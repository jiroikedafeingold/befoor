import Foundation
import Combine
import UserNotifications

// MARK: - Sound Options

enum BefoorSound: String, CaseIterable, Codable, Identifiable {
    case pebble        = "pebble"
    case brush         = "brush"
    case shaman        = "shaman"
    case zenCute       = "zen_cute"
    case gozaimasu     = "gozaimasu"
    case jfk           = "jfk"
    case narita        = "narita"
    case accessGranted = "access_granted"
    case positiveID    = "positive_id"
    case openChannel   = "open_channel"
    case systemDefault = "default"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pebble:        return "Pebble"
        case .brush:         return "Brush"
        case .shaman:        return "Shaman"
        case .zenCute:       return "Zen Cute"
        case .gozaimasu:     return "Gozaimasu"
        case .jfk:           return "JFK"
        case .narita:        return "Narita"
        case .accessGranted: return "Access Granted"
        case .positiveID:    return "Positive ID"
        case .openChannel:   return "Open Channel"
        case .systemDefault: return String(localized: "System Default")
        }
    }

    #if !os(watchOS)
    var notificationSound: UNNotificationSound {
        switch self {
        case .systemDefault:
            return .default
        default:
            return UNNotificationSound(named: UNNotificationSoundName(rawValue: rawValue + ".caf"))
        }
    }

    /// Critical variant at maximum volume — plays even when the ringer is off.
    var criticalNotificationSound: UNNotificationSound {
        switch self {
        case .systemDefault:
            return .defaultCriticalSound(withAudioVolume: 1.0)
        default:
            return UNNotificationSound.criticalSoundNamed(
                UNNotificationSoundName(rawValue: rawValue + ".caf"),
                withAudioVolume: 1.0
            )
        }
    }
    #endif
}

// MARK: - AppSettings

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard
    private let cloud = NSUbiquitousKeyValueStore.default

    /// Keys that sync to iCloud. Device-specific keys (onboarding, selected calendars) are excluded.
    private static let syncedKeys: Set<String> = [
        Keys.leadTime, Keys.ignoredKeywords, Keys.skipWeekends,
        Keys.isEnabled, Keys.selectedSound, Keys.lookAheadDays,
        Keys.checkInterval, Keys.snoozeDuration, Keys.soundEnabled,
        Keys.lastAlert, Keys.skippedMeetings, Keys.pausedUntil, Keys.meetingNotes, Keys.meetingFirstAlerts, Keys.seriesFirstAlerts, Keys.keywordFirstAlerts,
        Keys.morningSummary, Keys.morningSummaryMinutes, Keys.firstMeetingAlert,
    ]

    // Each meeting rings twice: at the first alert, when its countdown appears,
    // and again at the last alert. These are the minutes before the meeting for
    // each (defaults 15 and 1). 0 means "at the start".
    // The first keeps the old lead-time key so existing values carry over.
    @Published var leadTimeMinutes: Int {
        didSet { save(leadTimeMinutes, forKey: Keys.leadTime) }
    }

    @Published var lastAlertMinutes: Int {
        didSet { save(lastAlertMinutes, forKey: Keys.lastAlert) }
    }

    static let firstAlertRange = 1...60
    static let laterAlertRange = 0...60

    // First-alert time for the day's first meeting (minutes before), to leave
    // time to get ready in the morning. 0 means First Alert, like any other
    // meeting. Synced.
    @Published var firstMeetingAlertMinutes: Int {
        didSet { save(firstMeetingAlertMinutes, forKey: Keys.firstMeetingAlert) }
    }

    // EventKit calendar identifiers the user has turned OFF. Every other calendar
    // is watched, so a calendar added later (or one whose identifier changes when
    // an account is re-added) is picked up automatically. (Device-specific — NOT synced)
    @Published var excludedCalendarIdentifiers: Set<String> {
        didSet { defaults.set(Array(excludedCalendarIdentifiers), forKey: Keys.excludedCalendars) }
    }

    /// Converts the pre-3.1 setting, which listed the calendars to watch, into the
    /// list of calendars to skip. Needs the calendars that exist right now, so it
    /// runs from the first sync with calendar access rather than at launch.
    func migrateCalendarSelectionIfNeeded(allCalendarIdentifiers: Set<String>) {
        guard let legacy = defaults.stringArray(forKey: Keys.selectedCalendars),
              !allCalendarIdentifiers.isEmpty else { return }   // wait for calendar access
        // An empty list meant "all calendars", which is now simply nothing excluded.
        // If none of the old picks exist any more (their identifiers changed), the
        // old setting was silently watching nothing; start over with everything.
        if !legacy.isEmpty, !allCalendarIdentifiers.isDisjoint(with: legacy) {
            excludedCalendarIdentifiers = allCalendarIdentifiers.subtracting(legacy)
        }
        defaults.removeObject(forKey: Keys.selectedCalendars)
    }

    // Event title substrings to ignore (case-insensitive)
    @Published var ignoredKeywords: [String] {
        didSet { save(ignoredKeywords, forKey: Keys.ignoredKeywords) }
    }

    // Meetings the person skipped from the list, as "event identifier|start" keys.
    // Synced, so a meeting skipped on one device doesn't ring on the others.
    @Published private(set) var skippedMeetings: Set<String> {
        didSet { save(Array(skippedMeetings), forKey: Keys.skippedMeetings) }
    }

    static func skipKey(eventIdentifier: String, start: Date) -> String {
        "\(eventIdentifier)|\(Int(start.timeIntervalSince1970))"
    }

    func isSkipped(eventIdentifier: String, start: Date) -> Bool {
        skippedMeetings.contains(Self.skipKey(eventIdentifier: eventIdentifier, start: start))
    }

    /// Skips (or un-skips) one occurrence of a meeting, and forgets skips for
    /// meetings that are long over.
    func setSkipped(_ skipped: Bool, eventIdentifier: String, start: Date) {
        let cutoff = Date().addingTimeInterval(-86_400).timeIntervalSince1970
        var keys = skippedMeetings.filter { key in
            guard let seconds = key.split(separator: "|").last.flatMap({ Double($0) }) else { return false }
            return seconds > cutoff
        }
        let key = Self.skipKey(eventIdentifier: eventIdentifier, start: start)
        if skipped { keys.insert(key) } else { keys.remove(key) }
        skippedMeetings = keys
    }

    /// Phrases that mark calendar blocks rather than meetings. Kept specific:
    /// matching is by substring, so a word like "busy" would also catch "business".
    static let defaultIgnoredKeywords = [
        "lunch", "OOO", "Out of office", "Focus time", "Do not book", "Commute", "Travel time",
    ]

    // No alarms for meetings that start before this date (vacation, a day off).
    // Meetings after it keep their alarms, so nothing depends on Befoor running
    // when the pause ends. Synced.
    @Published var pausedUntil: Date? {
        didSet { save(pausedUntil?.timeIntervalSince1970 ?? 0, forKey: Keys.pausedUntil) }
    }

    /// Whether `start` falls inside the pause.
    func isPaused(at start: Date) -> Bool {
        guard let pausedUntil else { return false }
        return start < pausedUntil
    }

    /// Paused right now.
    var isPausedNow: Bool { pausedUntil.map { $0 > Date() } ?? false }

    // A quiet notification each morning listing the day's meetings.
    @Published var morningSummaryEnabled: Bool {
        didSet { save(morningSummaryEnabled, forKey: Keys.morningSummary) }
    }

    // When the morning summary arrives, in minutes after midnight (default 7:30).
    @Published var morningSummaryMinutes: Int {
        didSet { save(morningSummaryMinutes, forKey: Keys.morningSummaryMinutes) }
    }

    // Short notes for single meetings ("event identifier|start" → note), shown
    // on the meeting's alarm, countdown and list row. Synced.
    @Published private(set) var meetingNotes: [String: String] {
        didSet { save(meetingNotes, forKey: Keys.meetingNotes) }
    }

    static let maxNoteLength = 120

    func note(eventIdentifier: String, start: Date) -> String? {
        meetingNotes[Self.skipKey(eventIdentifier: eventIdentifier, start: start)]
    }

    /// Sets (or, when empty, removes) a meeting's note, and forgets notes for
    /// meetings that are long over.
    func setNote(_ note: String, eventIdentifier: String, start: Date) {
        let cutoff = Date().addingTimeInterval(-86_400).timeIntervalSince1970
        var notes = meetingNotes.filter { key, _ in
            (key.split(separator: "|").last.flatMap { Double($0) } ?? 0) > cutoff
        }
        let key = Self.skipKey(eventIdentifier: eventIdentifier, start: start)
        let trimmed = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxNoteLength))
        notes[key] = trimmed.isEmpty ? nil : trimmed
        meetingNotes = notes
    }

    // First-alert times chosen for single meetings ("event identifier|start" →
    // minutes before), replacing First Alert for that meeting. 0 means "the
    // usual time", overriding the series' or a keyword's time. Synced.
    @Published private(set) var meetingFirstAlerts: [String: Int] {
        didSet { save(meetingFirstAlerts, forKey: Keys.meetingFirstAlerts) }
    }

    // First-alert times chosen for every meeting of a repeating series (event
    // identifier, which its occurrences share → minutes before; 0 as above). Synced.
    @Published private(set) var seriesFirstAlerts: [String: Int] {
        didSet { save(seriesFirstAlerts, forKey: Keys.seriesFirstAlerts) }
    }

    // First-alert times for meetings whose titles contain a keyword (keyword →
    // minutes before), e.g. "kid pickup" → 45. Synced.
    @Published var keywordFirstAlerts: [String: Int] {
        didSet { save(keywordFirstAlerts, forKey: Keys.keywordFirstAlerts) }
    }

    /// The choices offered for a meeting's or keyword's first alert.
    static let meetingFirstAlertChoices = [5, 10, 15, 30, 45, 60, 90, 120]

    /// The earliest first-alert time among the keywords in `title`, if any.
    func keywordFirstAlert(for title: String) -> Int? {
        keywordFirstAlerts
            .filter { title.localizedCaseInsensitiveContains($0.key) }
            .values.max()
    }

    /// This meeting's own first-alert time: chosen for just this meeting, else
    /// for its series, else from a keyword in its title. Nil means First Alert.
    func chosenFirstAlert(eventIdentifier: String, start: Date, title: String) -> Int? {
        let chosen = meetingFirstAlerts[Self.skipKey(eventIdentifier: eventIdentifier, start: start)]
            ?? seriesFirstAlerts[eventIdentifier]
        if let chosen { return chosen == 0 ? nil : chosen }
        return keywordFirstAlert(for: title)
    }

    /// Sets (or, when nil, goes back to the usual) first-alert time for one
    /// meeting or for its whole series, and forgets choices for meetings that
    /// are long over.
    func setFirstAlert(_ minutes: Int?, eventIdentifier: String, start: Date, title: String, wholeSeries: Bool) {
        let cutoff = Date().addingTimeInterval(-86_400).timeIntervalSince1970
        var choices = meetingFirstAlerts.filter { key, _ in
            (key.split(separator: "|").last.flatMap { Double($0) } ?? 0) > cutoff
        }
        let keywordTime = keywordFirstAlert(for: title) != nil
        if wholeSeries {
            // The series' time replaces choices made for single meetings in it.
            choices = choices.filter { !$0.key.hasPrefix("\(eventIdentifier)|") }
            seriesFirstAlerts[eventIdentifier] = minutes ?? (keywordTime ? 0 : nil)
        } else {
            let otherTime = keywordTime || seriesFirstAlerts[eventIdentifier].map { $0 != 0 } == true
            choices[Self.skipKey(eventIdentifier: eventIdentifier, start: start)] = minutes ?? (otherTime ? 0 : nil)
        }
        meetingFirstAlerts = choices
    }

    /// Minutes before a meeting time its first alert rings. Meetings at the same
    /// time share one alarm, so the earliest time among them (skipped ones
    /// aside) wins; with none, the first-meeting time for the day's first
    /// meeting, else First Alert.
    func firstAlertMinutes(start: Date, meetings: [(eventIdentifier: String, title: String)], firstOfDay: Bool) -> Int {
        meetings
            .filter { !isSkipped(eventIdentifier: $0.eventIdentifier, start: start) }
            .compactMap { chosenFirstAlert(eventIdentifier: $0.eventIdentifier, start: start, title: $0.title) }
            .max() ?? usualFirstAlert(firstOfDay: firstOfDay)
    }

    /// First Alert, or the first-meeting time for the day's first meeting.
    func usualFirstAlert(firstOfDay: Bool) -> Int {
        firstOfDay && firstMeetingAlertMinutes > 0 ? firstMeetingAlertMinutes : leadTimeMinutes
    }

    /// The distinct alert times for a meeting time, earliest alert (most
    /// minutes before) first.
    func alertMinutes(start: Date, meetings: [(eventIdentifier: String, title: String)], firstOfDay: Bool) -> [Int] {
        Array(Set([firstAlertMinutes(start: start, meetings: meetings, firstOfDay: firstOfDay), lastAlertMinutes]))
            .sorted(by: >)
    }

    // Do not create alarms for events on Saturday or Sunday
    @Published var skipWeekends: Bool {
        didSet { save(skipWeekends, forKey: Keys.skipWeekends) }
    }

    // Master on/off switch
    @Published var isEnabled: Bool {
        didSet { save(isEnabled, forKey: Keys.isEnabled) }
    }

    // Which soothing sound to use
    @Published var selectedSound: BefoorSound {
        didSet { save(selectedSound.rawValue, forKey: Keys.selectedSound) }
    }

    // How many days ahead to schedule alarms (keeps the 64-notification limit in check)
    @Published var lookAheadDays: Int {
        didSet { save(lookAheadDays, forKey: Keys.lookAheadDays) }
    }

    // How often (minutes) to poll for calendar changes when the app is in the background
    @Published var backgroundCheckIntervalMinutes: Int {
        didSet { save(backgroundCheckIntervalMinutes, forKey: Keys.checkInterval) }
    }

    // How long to snooze when the Snooze action is tapped
    @Published var snoozeDurationMinutes: Int {
        didSet { save(snoozeDurationMinutes, forKey: Keys.snoozeDuration) }
    }

    @Published var soundEnabled: Bool {
        didSet { save(soundEnabled, forKey: Keys.soundEnabled) }
    }

    // Live Activity counting down to the next meeting (Dynamic Island + Lock Screen).
    // Device-specific — NOT synced
    @Published var liveActivityEnabled: Bool {
        didSet { defaults.set(liveActivityEnabled, forKey: Keys.liveActivityEnabled) }
    }

    // Device-specific — NOT synced
    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    private init() {
        // 3.0 moved the first alert's default from 7 to 15 minutes. A stored 7 is
        // the old default, so drop it once and let everyone start at 15; any
        // other stored value was a real choice and is kept.
        if !defaults.bool(forKey: Keys.alertsMigratedV3) {
            if defaults.object(forKey: Keys.leadTime) as? Int == 7 {
                defaults.removeObject(forKey: Keys.leadTime)
            }
            defaults.set(true, forKey: Keys.alertsMigratedV3)
        }
        leadTimeMinutes           = Self.clamp(defaults.object(forKey: Keys.leadTime) as? Int ?? 15, Self.firstAlertRange)
        lastAlertMinutes          = Self.clamp(defaults.object(forKey: Keys.lastAlert) as? Int ?? 1, Self.laterAlertRange)
        firstMeetingAlertMinutes  = defaults.object(forKey: Keys.firstMeetingAlert) as? Int ?? 0
        excludedCalendarIdentifiers = Set(defaults.stringArray(forKey: Keys.excludedCalendars) ?? [])
        var keywords = defaults.stringArray(forKey: Keys.ignoredKeywords) ?? Self.defaultIgnoredKeywords
        // 4.4 added more default phrases; give them to existing lists once.
        if !defaults.bool(forKey: Keys.keywordsMigratedV2) {
            let have = Set(keywords.map { $0.lowercased() })
            keywords += Self.defaultIgnoredKeywords.filter { $0 != "lunch" && !have.contains($0.lowercased()) }
            defaults.set(true, forKey: Keys.keywordsMigratedV2)
        }
        ignoredKeywords           = Self.deduped(keywords)
        skippedMeetings           = Set(defaults.stringArray(forKey: Keys.skippedMeetings) ?? [])
        meetingNotes              = defaults.dictionary(forKey: Keys.meetingNotes) as? [String: String] ?? [:]
        meetingFirstAlerts        = defaults.dictionary(forKey: Keys.meetingFirstAlerts) as? [String: Int] ?? [:]
        seriesFirstAlerts         = defaults.dictionary(forKey: Keys.seriesFirstAlerts) as? [String: Int] ?? [:]
        keywordFirstAlerts        = defaults.dictionary(forKey: Keys.keywordFirstAlerts) as? [String: Int] ?? [:]
        skipWeekends              = defaults.object(forKey: Keys.skipWeekends) as? Bool ?? false
        pausedUntil               = Self.date(defaults.double(forKey: Keys.pausedUntil))
        morningSummaryEnabled     = defaults.object(forKey: Keys.morningSummary) as? Bool ?? false
        morningSummaryMinutes     = defaults.object(forKey: Keys.morningSummaryMinutes) as? Int ?? 7 * 60 + 30
        isEnabled                 = defaults.object(forKey: Keys.isEnabled) as? Bool ?? true
        selectedSound             = BefoorSound(rawValue: defaults.string(forKey: Keys.selectedSound) ?? "") ?? .pebble
        lookAheadDays             = defaults.object(forKey: Keys.lookAheadDays) as? Int ?? 7
        backgroundCheckIntervalMinutes = defaults.object(forKey: Keys.checkInterval) as? Int ?? 15
        snoozeDurationMinutes     = defaults.object(forKey: Keys.snoozeDuration) as? Int ?? 5
        soundEnabled              = defaults.object(forKey: Keys.soundEnabled) as? Bool ?? true
        liveActivityEnabled       = defaults.object(forKey: Keys.liveActivityEnabled) as? Bool ?? true
        hasCompletedOnboarding    = defaults.object(forKey: Keys.hasCompletedOnboarding) as? Bool ?? false
        if defaults.object(forKey: Keys.firstUseDate) == nil {
            defaults.set(Date(), forKey: Keys.firstUseDate)
        }

        // Start observing iCloud KV store changes from other devices
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(iCloudStoreDidChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud
        )
        cloud.synchronize()
    }

    /// Keyword matching ignores case, so "lunch" and "Lunch" are the same keyword.
    /// Keeps the first spelling of each (older versions defaulted to both).
    private static func deduped(_ keywords: [String]) -> [String] {
        var seen = Set<String>()
        return keywords.filter { seen.insert($0.lowercased()).inserted }
    }

    /// Stored pause dates; 0 (or one in the past) means not paused.
    private static func date(_ seconds: Double) -> Date? {
        seconds > Date().timeIntervalSince1970 ? Date(timeIntervalSince1970: seconds) : nil
    }

    // MARK: Review prompt (device-specific — NOT synced)

    /// Ask for an App Store rating once someone has relied on Befoor for a
    /// while: at least this many alarms stopped…
    private static let reviewAfterAlarms = 10
    /// …and at least this long since first use. Once per app version.
    private static let reviewAfterDays: TimeInterval = 7 * 86_400

    func recordAlarmStopped() {
        defaults.set(defaults.integer(forKey: Keys.alarmsStopped) + 1, forKey: Keys.alarmsStopped)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var shouldAskForReview: Bool {
        guard defaults.integer(forKey: Keys.alarmsStopped) >= Self.reviewAfterAlarms,
              let firstUse = defaults.object(forKey: Keys.firstUseDate) as? Date,
              Date().timeIntervalSince(firstUse) >= Self.reviewAfterDays else { return false }
        return defaults.string(forKey: Keys.reviewPromptVersion) != appVersion
    }

    func markReviewAsked() {
        defaults.set(appVersion, forKey: Keys.reviewPromptVersion)
    }

    private static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    // MARK: - iCloud KV Store Sync

    /// Save a value to both UserDefaults and iCloud KV store (if synced).
    private func save(_ value: Any, forKey key: String) {
        defaults.set(value, forKey: key)
        if Self.syncedKeys.contains(key) {
            cloud.set(value, forKey: key)
        }
    }

    /// Called when another device changes a value in the iCloud KV store.
    @objc private func iCloudStoreDidChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let changeReason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int,
              changeReason == NSUbiquitousKeyValueStoreServerChange ||
              changeReason == NSUbiquitousKeyValueStoreInitialSyncChange,
              let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
        else { return }

        DispatchQueue.main.async { [self] in
            for key in changedKeys {
                guard Self.syncedKeys.contains(key) else { continue }
                let value = cloud.object(forKey: key)

                // Mirror the remote value into UserDefaults
                if let value {
                    defaults.set(value, forKey: key)
                }

                // Update the corresponding @Published property
                switch key {
                case Keys.leadTime:
                    if let v = value as? Int { leadTimeMinutes = Self.clamp(v, Self.firstAlertRange) }
                case Keys.lastAlert:
                    if let v = value as? Int { lastAlertMinutes = Self.clamp(v, Self.laterAlertRange) }
                case Keys.firstMeetingAlert:
                    if let v = value as? Int { firstMeetingAlertMinutes = v }
                case Keys.ignoredKeywords:
                    if let v = value as? [String] { ignoredKeywords = Self.deduped(v) }
                case Keys.meetingNotes:
                    if let v = value as? [String: String] { meetingNotes = v }
                case Keys.meetingFirstAlerts:
                    if let v = value as? [String: Int] { meetingFirstAlerts = v }
                case Keys.seriesFirstAlerts:
                    if let v = value as? [String: Int] { seriesFirstAlerts = v }
                case Keys.keywordFirstAlerts:
                    if let v = value as? [String: Int] { keywordFirstAlerts = v }
                case Keys.skippedMeetings:
                    if let v = value as? [String] { skippedMeetings = Set(v) }
                case Keys.pausedUntil:
                    if let v = value as? Double { pausedUntil = Self.date(v) }
                case Keys.morningSummary:
                    if let v = value as? Bool { morningSummaryEnabled = v }
                case Keys.morningSummaryMinutes:
                    if let v = value as? Int { morningSummaryMinutes = v }
                case Keys.skipWeekends:
                    if let v = value as? Bool { skipWeekends = v }
                case Keys.isEnabled:
                    if let v = value as? Bool { isEnabled = v }
                case Keys.selectedSound:
                    if let v = value as? String, let s = BefoorSound(rawValue: v) { selectedSound = s }
                case Keys.lookAheadDays:
                    if let v = value as? Int { lookAheadDays = v }
                case Keys.checkInterval:
                    if let v = value as? Int { backgroundCheckIntervalMinutes = v }
                case Keys.snoozeDuration:
                    if let v = value as? Int { snoozeDurationMinutes = v }
                case Keys.soundEnabled:
                    if let v = value as? Bool { soundEnabled = v }
                default:
                    break
                }
            }
        }
    }

    private enum Keys {
        static let leadTime           = "bf_leadTimeMinutes"
        static let selectedCalendars  = "bf_selectedCalendarIdentifiers"   // legacy, pre-3.1
        static let excludedCalendars  = "bf_excludedCalendarIdentifiers"
        static let ignoredKeywords    = "bf_ignoredKeywords"
        static let skipWeekends       = "bf_skipWeekends"
        static let skippedMeetings    = "bf_skippedMeetings"
        static let keywordsMigratedV2 = "bf_keywordsMigratedV2"
        static let meetingNotes       = "bf_meetingNotes"
        static let meetingFirstAlerts = "bf_meetingFirstAlerts"
        static let seriesFirstAlerts  = "bf_seriesFirstAlerts"
        static let keywordFirstAlerts = "bf_keywordFirstAlerts"
        static let firstMeetingAlert  = "bf_firstMeetingAlertMinutes"
        static let alarmsStopped      = "bf_alarmsStopped"
        static let firstUseDate       = "bf_firstUseDate"
        static let reviewPromptVersion = "bf_reviewPromptVersion"
        static let pausedUntil        = "bf_pausedUntil"
        static let morningSummary     = "bf_morningSummary"
        static let morningSummaryMinutes = "bf_morningSummaryMinutes"
        static let isEnabled          = "bf_isEnabled"
        static let selectedSound      = "bf_selectedSound"
        static let lookAheadDays      = "bf_lookAheadDays"
        static let checkInterval      = "bf_checkIntervalMinutes"
        static let snoozeDuration     = "bf_snoozeDurationMinutes"
        static let soundEnabled           = "bf_soundEnabled"
        // The last alert was the third of three before 4.0; keeps its key so the value carries over.
        static let lastAlert              = "bf_thirdAlertMinutes"
        static let alertsMigratedV3       = "bf_alertsMigratedV3"
        static let hasCompletedOnboarding = "bf_hasCompletedOnboarding"
        static let liveActivityEnabled    = "bf_liveActivityEnabled"
    }
}
