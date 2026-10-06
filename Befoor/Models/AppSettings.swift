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
        case .systemDefault: return "System Default"
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
        Keys.secondAlert, Keys.thirdAlert,
        Keys.mainDeviceID, Keys.peopleEnabled,
    ]

    // Each meeting gets up to three alerts. These are the minutes before the
    // meeting for each one (defaults 15, 7 and 1). 0 means "at the start".
    // The first keeps the old lead-time key so existing values carry over.
    @Published var leadTimeMinutes: Int {
        didSet { save(leadTimeMinutes, forKey: Keys.leadTime) }
    }

    @Published var secondAlertMinutes: Int {
        didSet { save(secondAlertMinutes, forKey: Keys.secondAlert) }
    }

    @Published var thirdAlertMinutes: Int {
        didSet { save(thirdAlertMinutes, forKey: Keys.thirdAlert) }
    }

    /// The distinct alert times, earliest alert (most minutes before) first.
    var alertMinutes: [Int] {
        Array(Set([leadTimeMinutes, secondAlertMinutes, thirdAlertMinutes])).sorted(by: >)
    }

    /// Minutes before the meeting that its first alert rings.
    var earliestAlertMinutes: Int { alertMinutes.first ?? leadTimeMinutes }

    static let firstAlertRange = 1...60
    static let laterAlertRange = 0...60

    // EventKit calendar identifiers the user wants monitored.
    // Empty set = all calendars. (Device-specific — NOT synced)
    @Published var selectedCalendarIdentifiers: Set<String> {
        didSet { defaults.set(Array(selectedCalendarIdentifiers), forKey: Keys.selectedCalendars) }
    }

    // Event title substrings to ignore (case-insensitive)
    @Published var ignoredKeywords: [String] {
        didSet { save(ignoredKeywords, forKey: Keys.ignoredKeywords) }
    }

    // Do not create alarms for events on Saturday or Sunday
    @Published var skipWeekends: Bool {
        didSet { save(skipWeekends, forKey: Keys.skipWeekends) }
    }

    // Master on/off switch
    @Published var isEnabled: Bool {
        didSet { save(isEnabled, forKey: Keys.isEnabled) }
    }

    // Enables the People tab and all 1:1 meeting features. Off by default.
    @Published var peopleEnabled: Bool {
        didSet { save(peopleEnabled, forKey: Keys.peopleEnabled) }
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

    // The device ID that owns calendar syncing — synced to iCloud so all devices know
    @Published var mainDeviceID: String {
        didSet { save(mainDeviceID, forKey: Keys.mainDeviceID) }
    }

    var isMainDevice: Bool {
        mainDeviceID == DeviceID.current
    }

    func claimAsMainDevice() {
        mainDeviceID = DeviceID.current
    }

    @Published var showDebugInfo: Bool {
        didSet { defaults.set(showDebugInfo, forKey: Keys.showDebugInfo) }
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
        secondAlertMinutes        = Self.clamp(defaults.object(forKey: Keys.secondAlert) as? Int ?? 7, Self.laterAlertRange)
        thirdAlertMinutes         = Self.clamp(defaults.object(forKey: Keys.thirdAlert) as? Int ?? 1, Self.laterAlertRange)
        selectedCalendarIdentifiers = Set(defaults.stringArray(forKey: Keys.selectedCalendars) ?? [])
        ignoredKeywords           = defaults.stringArray(forKey: Keys.ignoredKeywords) ?? ["lunch", "Lunch"]
        skipWeekends              = defaults.object(forKey: Keys.skipWeekends) as? Bool ?? false
        isEnabled                 = defaults.object(forKey: Keys.isEnabled) as? Bool ?? true
        peopleEnabled             = defaults.object(forKey: Keys.peopleEnabled) as? Bool ?? false
        selectedSound             = BefoorSound(rawValue: defaults.string(forKey: Keys.selectedSound) ?? "") ?? .pebble
        lookAheadDays             = defaults.object(forKey: Keys.lookAheadDays) as? Int ?? 7
        backgroundCheckIntervalMinutes = defaults.object(forKey: Keys.checkInterval) as? Int ?? 15
        snoozeDurationMinutes     = defaults.object(forKey: Keys.snoozeDuration) as? Int ?? 5
        soundEnabled              = defaults.object(forKey: Keys.soundEnabled) as? Bool ?? true
        mainDeviceID              = defaults.string(forKey: Keys.mainDeviceID) ?? ""
        showDebugInfo             = defaults.object(forKey: Keys.showDebugInfo) as? Bool ?? false
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
                case Keys.secondAlert:
                    if let v = value as? Int { secondAlertMinutes = Self.clamp(v, Self.laterAlertRange) }
                case Keys.thirdAlert:
                    if let v = value as? Int { thirdAlertMinutes = Self.clamp(v, Self.laterAlertRange) }
                case Keys.ignoredKeywords:
                    if let v = value as? [String] { ignoredKeywords = v }
                case Keys.skipWeekends:
                    if let v = value as? Bool { skipWeekends = v }
                case Keys.isEnabled:
                    if let v = value as? Bool { isEnabled = v }
                case Keys.peopleEnabled:
                    if let v = value as? Bool { peopleEnabled = v }
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
                case Keys.mainDeviceID:
                    if let v = value as? String { mainDeviceID = v }
                default:
                    break
                }
            }
        }
    }

    private enum Keys {
        static let leadTime           = "bf_leadTimeMinutes"
        static let selectedCalendars  = "bf_selectedCalendarIdentifiers"
        static let ignoredKeywords    = "bf_ignoredKeywords"
        static let skipWeekends       = "bf_skipWeekends"
        static let isEnabled          = "bf_isEnabled"
        static let peopleEnabled      = "bf_peopleEnabled"
        static let selectedSound      = "bf_selectedSound"
        static let lookAheadDays      = "bf_lookAheadDays"
        static let checkInterval      = "bf_checkIntervalMinutes"
        static let snoozeDuration     = "bf_snoozeDurationMinutes"
        static let soundEnabled           = "bf_soundEnabled"
        static let secondAlert            = "bf_secondAlertMinutes"
        static let thirdAlert             = "bf_thirdAlertMinutes"
        static let alertsMigratedV3       = "bf_alertsMigratedV3"
        static let mainDeviceID           = "bf_mainDeviceID"
        static let showDebugInfo          = "bf_showDebugInfo"
        static let hasCompletedOnboarding = "bf_hasCompletedOnboarding"
        static let liveActivityEnabled    = "bf_liveActivityEnabled"
    }
}
