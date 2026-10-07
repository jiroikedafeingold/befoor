import Foundation
import CryptoKit

#if !targetEnvironment(macCatalyst)
import ActivityKit
import AlarmKit
import AppIntents
import SwiftUI
#endif

// MARK: - Request

/// One alarm Befoor wants to exist.
struct MeetingAlarmRequest: Sendable {
    let meetingKey: String
    /// Which of the meeting's alerts this is: 1 is the earliest, 3 the latest.
    let slot: Int
    /// Minutes before the meeting this alert rings (0 = at the start).
    let minutesBefore: Int
    /// The intended ring time. May already be in the past for a meeting found
    /// inside its lead window; see MeetingAlarms.reconcile.
    let fireDate: Date
    let eventTitle: String
    let eventStart: Date
    let calendarName: String
    let location: String?
    let sound: BefoorSound
    let snoozeMinutes: Int

    var id: UUID { MeetingAlarms.alarmID(meetingKey: meetingKey, slot: slot) }

    /// Everything baked into a scheduled alarm. If it changes, the alarm is rescheduled.
    var fingerprint: String {
        "\(slot)|\(minutesBefore)|\(Int(fireDate.timeIntervalSince1970))|\(eventTitle)|\(location ?? "")|\(sound.rawValue)|\(snoozeMinutes)"
    }
}

// MARK: - MeetingAlarms

/// Schedules Befoor's meeting alarms with AlarmKit.
///
/// AlarmKit alarms are real system alarms: they ring through silent mode and
/// Focus, and the system rings them even when Befoor isn't running. That's what
/// lets Befoor stay suspended in the background instead of keeping itself alive.
@MainActor
final class MeetingAlarms {
    static let shared = MeetingAlarms()

    private init() {}

    /// Most alerts a meeting can have.
    nonisolated static let maxSlots = 3

    /// Stable alarm ID per meeting and alert slot, so every sync addresses the same alarm.
    nonisolated static func alarmID(meetingKey: String, slot: Int) -> UUID {
        var bytes = Array(Insecure.MD5.hash(data: Data("\(meetingKey)|alert\(slot)".utf8)))
        bytes[6] = (bytes[6] & 0x0F) | 0x30   // name-based UUID (version 3)
        bytes[8] = (bytes[8] & 0x3F) | 0x80   // RFC 4122 variant
        return bytes.withUnsafeBytes { UUID(uuid: $0.load(as: uuid_t.self)) }
    }

    #if targetEnvironment(macCatalyst)
    // AlarmKit isn't available on Mac; Befoor uses notifications there.
    var isAuthorized: Bool { false }
    var isDenied: Bool { false }
    var isUndetermined: Bool { false }
    func requestAuthorization() async -> Bool { false }
    func reconcile(_ requests: [MeetingAlarmRequest]) async -> [MeetingAlarmRequest] { requests }
    func cancelAll() {}
    #else

    private let manager = AlarmManager.shared

    /// Befoor's alarms as the system has them. Empty if they can't be read.
    private var currentAlarms: [Alarm] { (try? manager.alarms) ?? [] }

    var isAuthorized: Bool { manager.authorizationState == .authorized }
    var isDenied: Bool { manager.authorizationState == .denied }
    var isUndetermined: Bool { manager.authorizationState == .notDetermined }

    @discardableResult
    func requestAuthorization() async -> Bool {
        (try? await manager.requestAuthorization()) == .authorized
    }

    // MARK: Bookkeeping

    /// Fingerprint of each alarm as last scheduled, keyed by alarm ID.
    private static let fingerprintsKey = "MeetingAlarmFingerprints"
    /// Alarm ID → intended fire date, for every alarm ever scheduled or suppressed.
    /// Stops an alarm whose time has already passed from being rescheduled (and
    /// ringing again) after it rang and went away.
    private static let historyKey = "MeetingAlarmHistory"
    /// Alarm IDs the person cancelled indirectly — a meeting's remaining alerts
    /// after they stopped an earlier one. Never rescheduled.
    private static let suppressedKey = "MeetingAlarmSuppressed"

    private var fingerprints: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: Self.fingerprintsKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Self.fingerprintsKey) }
    }
    private var history: [String: Double] {
        get { UserDefaults.standard.dictionary(forKey: Self.historyKey) as? [String: Double] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Self.historyKey) }
    }
    private var suppressed: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.suppressedKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Self.suppressedKey) }
    }

    // MARK: Scheduling

    /// Makes the scheduled alarms match `requests`.
    ///
    /// Alarms that are ringing or snoozed are never touched, so a resync can't cut
    /// off an alarm in progress. Returns the requests that couldn't be scheduled
    /// (for example when the system's alarm limit is reached) so the caller can
    /// fall back to a notification.
    func reconcile(_ requests: [MeetingAlarmRequest]) async -> [MeetingAlarmRequest] {
        let now = Date()
        var fingerprints = self.fingerprints
        var history = self.history
        let suppressed = self.suppressed

        let existing = Dictionary(currentAlarms.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let wanted = requests.filter { !suppressed.contains($0.id.uuidString) }
        let wantedByID = Dictionary(wanted.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        // Cancel scheduled alarms that are no longer wanted or have changed.
        for (id, alarm) in existing where alarm.state == .scheduled {
            let key = id.uuidString
            if let request = wantedByID[id], fingerprints[key] == request.fingerprint { continue }
            try? manager.cancel(id: id)
            fingerprints[key] = nil
        }

        var failed: [MeetingAlarmRequest] = []
        for request in wanted {
            let key = request.id.uuidString
            if let alarm = existing[request.id] {
                if alarm.state != .scheduled { continue }              // ringing or snoozed
                if fingerprints[key] == request.fingerprint { continue } // unchanged
            }

            var ringAt = request.fireDate
            if ringAt <= now.addingTimeInterval(5) {
                // The ring time has passed. Only ring now for a meeting that just
                // appeared inside its window, never again after it already rang.
                guard history[key] == nil else { continue }
                ringAt = now.addingTimeInterval(5)
            }

            do {
                _ = try await manager.schedule(id: request.id, configuration: configuration(for: request, at: ringAt))
                fingerprints[key] = request.fingerprint
                history[key] = request.fireDate.timeIntervalSince1970
            } catch {
                print("[Befoor] Scheduling alarm failed: \(error)")
                failed.append(request)
            }
        }

        // Forget bookkeeping for alarms more than a day old.
        let cutoff = now.addingTimeInterval(-86_400).timeIntervalSince1970
        let liveIDs = Set(currentAlarms.map(\.id.uuidString))
        self.history = history.filter { $0.value > cutoff }
        self.fingerprints = fingerprints.filter { liveIDs.contains($0.key) }
        self.suppressed = suppressed.filter { self.history[$0] != nil }

        return failed
    }

    /// Cancels every scheduled Befoor alarm. Alarms ringing or snoozed right now
    /// are left alone.
    func cancelAll() {
        for alarm in currentAlarms where alarm.state == .scheduled {
            try? manager.cancel(id: alarm.id)
        }
        fingerprints = [:]
    }

    private func configuration(
        for request: MeetingAlarmRequest,
        at ringAt: Date
    ) -> AlarmManager.AlarmConfiguration<MeetingAlarmMetadata> {
        let title: String
        switch request.minutesBefore {
        case 0:  title = "\(request.eventTitle) is starting"
        case 1:  title = "\(request.eventTitle) in 1 minute"
        default: title = "\(request.eventTitle) in \(request.minutesBefore) minutes"
        }

        let snooze = AlarmButton(text: "Snooze", textColor: .white, systemImageName: "zzz")
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: title),
                secondaryButton: snooze,
                secondaryButtonBehavior: .countdown
            )
        } else {
            alert = AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: title),
                stopButton: AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill"),
                secondaryButton: snooze,
                secondaryButtonBehavior: .countdown
            )
        }
        let presentation = AlarmPresentation(
            alert: alert,
            countdown: AlarmPresentation.Countdown(title: LocalizedStringResource(stringLiteral: request.eventTitle))
        )
        let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: MeetingAlarmMetadata(
                meetingTitle: request.eventTitle,
                startDate: request.eventStart,
                location: request.location
            ),
            tintColor: .indigo
        )
        let sound: AlertConfiguration.AlertSound = request.sound == .systemDefault
            ? .default
            : .named(request.sound.rawValue + ".caf")

        return AlarmManager.AlarmConfiguration(
            // postAlert is the snooze length.
            countdownDuration: Alarm.CountdownDuration(preAlert: nil, postAlert: Double(request.snoozeMinutes) * 60),
            schedule: .fixed(ringAt),
            attributes: attributes,
            stopIntent: MeetingAlarmIntent(meetingKey: request.meetingKey, slot: request.slot, action: "stop"),
            secondaryIntent: MeetingAlarmIntent(meetingKey: request.meetingKey, slot: request.slot, action: "snooze"),
            sound: sound
        )
    }

    // MARK: Alarm actions

    /// Called when the person taps Stop or Snooze on a ringing alarm.
    func handleAction(meetingKey: String, slot: Int, stopped: Bool) async {
        // Stop means "I'm on it": skip the meeting's remaining alerts, the same
        // as dismissing the old notification. Snooze keeps them, so the later
        // alerts still ring on time.
        if stopped && slot < Self.maxSlots {
            let alarms = currentAlarms
            var suppressed = self.suppressed
            var history = self.history
            for later in (slot + 1)...Self.maxSlots {
                let id = Self.alarmID(meetingKey: meetingKey, slot: later)
                if alarms.first(where: { $0.id == id })?.state == .scheduled {
                    try? manager.cancel(id: id)
                }
                suppressed.insert(id.uuidString)
                history[id.uuidString] = Date().addingTimeInterval(86_400).timeIntervalSince1970
            }
            self.suppressed = suppressed
            self.history = history
        }
        // Befoor is awake anyway, so use the moment to pick up calendar changes
        // made since it last ran. Awaited so the system doesn't suspend the app
        // mid-sync once the intent returns. Ringing and snoozed alarms are left
        // alone by the sync, and alerts skipped above stay skipped.
        await AlarmScheduler.shared.sync()

        // Then refresh the countdown with intent rights, which (unlike the sync's
        // own background refresh) may start an activity and book upcoming ones.
        await MeetingLiveActivityManager.shared.refresh(allowStart: true)
    }
    #endif
}

#if !targetEnvironment(macCatalyst)

// MARK: - Metadata

/// Meeting details shown in the alarm's Live Activity while it's snoozed.
///
/// IMPORTANT: an identical copy lives in BeforeWidget/MeetingAlarmLiveActivity.swift.
/// ActivityKit matches the two by type name and Codable shape — keep them in sync.
struct MeetingAlarmMetadata: AlarmMetadata {
    var meetingTitle: String
    var startDate: Date
    var location: String?
}

// MARK: - Intent

/// Runs in Befoor when the person taps Stop or Snooze on a meeting alarm.
struct MeetingAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Meeting Alarm Action"
    static let isDiscoverable = false

    @Parameter(title: "Meeting")
    var meetingKey: String

    @Parameter(title: "Alert")
    var slot: Int

    @Parameter(title: "Action")
    var action: String

    init() {}

    init(meetingKey: String, slot: Int, action: String) {
        self.meetingKey = meetingKey
        self.slot = slot
        self.action = action
    }

    func perform() async throws -> some IntentResult {
        let meetingKey = meetingKey
        let slot = slot
        let stopped = action == "stop"
        await MeetingAlarms.shared.handleAction(meetingKey: meetingKey, slot: slot, stopped: stopped)
        return .result()
    }
}
#endif
