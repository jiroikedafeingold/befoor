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
        Keys.lastAlert, Keys.skippedMeetings,
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

    /// The distinct alert times, earliest alert (most minutes before) first.
    var alertMinutes: [Int] {
        Array(Set([leadTimeMinutes, lastAlertMinutes])).sorted(by: >)
    }

    /// Minutes before the meeting that its first alert rings.
    var earliestAlertMinutes: Int { alertMinutes.first ?? leadTimeMinutes }

    static let firstAlertRange = 1...60
    static let laterAlertRange = 0...60

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
        excludedCalendarIdentifiers = Set(defaults.stringArray(forKey: Keys.excludedCalendars) ?? [])
        ignoredKeywords           = Self.deduped(defaults.stringArray(forKey: Keys.ignoredKeywords) ?? ["lunch"])
        skippedMeetings           = Set(defaults.stringArray(forKey: Keys.skippedMeetings) ?? [])
        skipWeekends              = defaults.object(forKey: Keys.skipWeekends) as? Bool ?? false
        isEnabled                 = defaults.object(forKey: Keys.isEnabled) as? Bool ?? true
        selectedSound             = BefoorSound(rawValue: defaults.string(forKey: Keys.selectedSound) ?? "") ?? .pebble
        lookAheadDays             = defaults.object(forKey: Keys.lookAheadDays) as? Int ?? 7
        backgroundCheckIntervalMinutes = defaults.object(forKey: Keys.checkInterval) as? Int ?? 15
        snoozeDurationMinutes     = defaults.object(forKey: Keys.snoozeDuration) as? Int ?? 5
        soundEnabled              = defaults.object(forKey: Keys.soundEnabled) as? Bool ?? true
        liveActivityEnabled       = defaults.object(forKey: Keys.liveActivityEnabled) as? Bool ?? true
        hasCompletedOnboarding    = defaults.object(forKey: Keys.hasCompletedOnboarding) as? Bool ?? false

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
                case Keys.ignoredKeywords:
                    if let v = value as? [String] { ignoredKeywords = Self.deduped(v) }
                case Keys.skippedMeetings:
                    if let v = value as? [String] { skippedMeetings = Set(v) }
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
