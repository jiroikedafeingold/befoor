import Foundation
import AVFoundation
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
    /// One key per start time: meetings that start together share their alarms.
    let meetingKey: String
    /// Which of the meeting's alerts this is: 1 is the first, 2 the last.
    let slot: Int
    /// Minutes before the meeting this alert rings (0 = at the start).
    let minutesBefore: Int
    /// The intended ring time. May already be in the past for a meeting found
    /// inside its lead window; see MeetingAlarms.reconcile.
    let fireDate: Date
    let eventTitle: String
    let eventStart: Date
    let calendarName: String
    /// sRGB components of the calendar color.
    let calendarRGB: [Double]?
    let location: String?
    /// Video-call link, for the Join button on the alarm's Live Activity.
    let joinURL: URL?
    /// "removed" or "changed" if the meeting's link changed (see LinkWatch).
    let linkChange: String?
    let sound: BefoorSound
    /// Rings while another meeting is under way: the alarm vibrates first and
    /// its sound comes in after AlarmTones.quietLead.
    let quiet: Bool
    let snoozeMinutes: Int

    var id: UUID { MeetingAlarms.alarmID(meetingKey: meetingKey, slot: slot) }

    /// Everything baked into a scheduled alarm. If it changes, the alarm is rescheduled.
    var fingerprint: String {
        "\(slot)|\(minutesBefore)|\(Int(fireDate.timeIntervalSince1970))|\(eventTitle)|\(location ?? "")|\(joinURL?.absoluteString ?? "")|\(linkChange ?? "")|\(calendarRGB ?? [])|\(sound.rawValue)|\(quiet)|\(AlarmTones.isReady(sound, quiet: quiet))|\(snoozeMinutes)"
    }
}

// MARK: - Ring-once tones

/// AlarmKit loops an alarm's sound until it's stopped, for up to 15 minutes.
/// To have an alert sound just once, each tone gets a copy in Library/Sounds
/// (where the system also looks for alert sounds) followed by enough silence
/// that the loop never comes back around.
///
/// A second, quiet copy starts with `quietLead` of silence, for alerts that
/// land during another meeting: the alarm vibrates first and the sound only
/// comes in if it hasn't been stopped by then.
enum AlarmTones {
    /// AlarmKit's longest ring, plus a margin.
    private static let paddedLength: TimeInterval = 905

    /// Silence before the sound in the quiet copy.
    static let quietLead: TimeInterval = 15

    static func fileName(for sound: BefoorSound, quiet: Bool = false) -> String {
        sound.rawValue + (quiet ? "_quiet.caf" : "_once.caf")
    }

    private static var directory: URL {
        URL.libraryDirectory.appending(path: "Sounds", directoryHint: .isDirectory)
    }

    private static func url(for sound: BefoorSound, quiet: Bool) -> URL {
        directory.appending(path: fileName(for: sound, quiet: quiet))
    }

    static func isReady(_ sound: BefoorSound, quiet: Bool = false) -> Bool {
        sound != .systemDefault && FileManager.default.fileExists(atPath: url(for: sound, quiet: quiet).path)
    }

    /// Builds the padded copies of `sound` if they don't exist yet.
    static func prepare(_ sound: BefoorSound) async {
        guard sound != .systemDefault else { return }
        for quiet in [false, true] where !isReady(sound, quiet: quiet) {
            await Task.detached(priority: .utility) {
                do {
                    try build(sound, quiet: quiet)
                } catch {
                    print("[Befoor] Building ring-once tone failed: \(error)")
                }
            }.value
        }
    }

    private static func build(_ sound: BefoorSound, quiet: Bool) throws {
        guard let source = Bundle.main.url(forResource: sound.rawValue, withExtension: "caf") else { return }
        let input = try AVAudioFile(forReading: source)
        let format = input.processingFormat
        guard let tone = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(input.length)) else { return }
        try input.read(into: tone)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temp = directory.appending(path: UUID().uuidString + ".caf")
        defer { try? FileManager.default.removeItem(at: temp) }

        // AAC keeps the silence tiny: about 170 KB per tone instead of 150 MB as PCM.
        do {
            let output = try AVAudioFile(
                forWriting: temp,
                settings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: format.sampleRate,
                    AVNumberOfChannelsKey: format.channelCount,
                ],
                commonFormat: format.commonFormat,
                interleaved: format.isInterleaved
            )
            func silence(seconds: TimeInterval) -> AVAudioPCMBuffer? {
                let frames = AVAudioFrameCount(format.sampleRate * seconds)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
                buffer.frameLength = frames
                for channel in UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList) {
                    if let data = channel.mData { memset(data, 0, Int(channel.mDataByteSize)) }
                }
                return buffer
            }

            if quiet, let lead = silence(seconds: quietLead) {
                try output.write(from: lead)
            }
            try output.write(from: tone)

            guard let chunk = silence(seconds: 10) else { return }
            var remaining = paddedLength - Double(input.length) / format.sampleRate - (quiet ? quietLead : 0)
            while remaining > 0 {
                try output.write(from: chunk)
                remaining -= 10
            }
        } // Closing the file finishes the AAC stream before it's moved into place.

        try FileManager.default.moveItem(at: temp, to: url(for: sound, quiet: quiet))
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
    func hasActiveAlarm(meetingKey: String) -> Bool { false }
    func scheduleTest(in seconds: TimeInterval) async -> Bool { false }
    #else

    private let manager = AlarmManager.shared

    /// Befoor's alarms as the system has them. Empty if they can't be read.
    private var currentAlarms: [Alarm] { (try? manager.alarms) ?? [] }

    var isAuthorized: Bool { manager.authorizationState == .authorized }
    var isDenied: Bool { manager.authorizationState == .denied }
    var isUndetermined: Bool { manager.authorizationState == .notDetermined }

    /// The alarms the last sync asked for, so Stop can turn a meeting's next
    /// alert into a countdown without rebuilding them from the calendar.
    private var lastRequests: [MeetingAlarmRequest] = []

    /// Whether one of the meeting's alarms is ringing, snoozed or counting down.
    /// AlarmKit shows its own Live Activity for it then, so Befoor's countdown
    /// stays out of the way to keep one per meeting.
    func hasActiveAlarm(meetingKey: String) -> Bool {
        let ids = Set((1...2).map { Self.alarmID(meetingKey: meetingKey, slot: $0) })
        return currentAlarms.contains { ids.contains($0.id) && $0.state != .scheduled }
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        (try? await manager.requestAuthorization()) == .authorized
    }

    // MARK: Bookkeeping

    /// Fingerprint of each alarm as last scheduled, keyed by alarm ID.
    private static let fingerprintsKey = "MeetingAlarmFingerprints"
    /// Alarm ID → intended fire date, for every alarm ever scheduled.
    /// Stops an alarm whose time has already passed from being rescheduled (and
    /// ringing again) after it rang and went away.
    private static let historyKey = "MeetingAlarmHistory"
    /// Alarm ID → start of the meeting it's for. Lets a sync recognise a ringing
    /// or snoozed alarm whose meeting has since moved or been cancelled.
    private static let startsKey = "MeetingAlarmStarts"
    /// Alarm ID → ring time of a countdown Befoor started itself (Stop on the
    /// first alert), so it can be rebuilt if the meeting's details change.
    private static let chainsKey = "MeetingAlarmChains"

    private var fingerprints: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: Self.fingerprintsKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Self.fingerprintsKey) }
    }
    private var history: [String: Double] {
        get { UserDefaults.standard.dictionary(forKey: Self.historyKey) as? [String: Double] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Self.historyKey) }
    }
    private var starts: [String: Double] {
        get { UserDefaults.standard.dictionary(forKey: Self.startsKey) as? [String: Double] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Self.startsKey) }
    }
    private var chains: [String: Double] {
        get { UserDefaults.standard.dictionary(forKey: Self.chainsKey) as? [String: Double] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Self.chainsKey) }
    }

    // MARK: Scheduling

    /// Makes the scheduled alarms match `requests`.
    ///
    /// Alarms that are ringing or snoozed are left alone, so a resync can't cut
    /// off an alarm in progress — unless their meeting has moved or been
    /// cancelled, when they're taken down along with their Live Activity so they
    /// don't count down (and ring again) for the old time. Returns the requests that couldn't be scheduled
    /// (for example when the system's alarm limit is reached) so the caller can
    /// fall back to a notification.
    func reconcile(_ requests: [MeetingAlarmRequest]) async -> [MeetingAlarmRequest] {
        let now = Date()
        lastRequests = requests
        var fingerprints = self.fingerprints
        var history = self.history
        var starts = self.starts

        for sound in Set(requests.map(\.sound)) {
            await AlarmTones.prepare(sound)
        }

        let existing = Dictionary(currentAlarms.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let wantedByID = Dictionary(requests.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        // Copies of one alarm left by overlapping syncs (4.1 and earlier): cancel
        // every copy, and the one that's still wanted is rescheduled below.
        let scheduledCopies = Dictionary(grouping: currentAlarms.filter { $0.state == .scheduled }, by: \.id)
        for (id, copies) in scheduledCopies where copies.count > 1 {
            for _ in copies { try? manager.cancel(id: id) }
            fingerprints[id.uuidString] = nil
        }

        // Cancel scheduled alarms that are no longer wanted or have changed.
        for (id, alarm) in existing where alarm.state == .scheduled {
            if id == Self.testAlarmID { continue }   // the test from Settings isn't a meeting
            let key = id.uuidString
            if let request = wantedByID[id], fingerprints[key] == request.fingerprint { continue }
            try? manager.cancel(id: id)
            fingerprints[key] = nil
        }

        // Ringing or snoozed alarms for a meeting time that no longer has a meeting.
        let wantedStarts = Set(requests.map(\.eventStart.timeIntervalSince1970))
        for (id, alarm) in existing where alarm.state != .scheduled && wantedByID[id] == nil {
            guard let start = starts[id.uuidString], start > now.timeIntervalSince1970,
                  !wantedStarts.contains(start) else { continue }
            print("[Befoor] Meeting moved; taking down its \(alarm.state) alarm")
            try? manager.cancel(id: id)
            fingerprints[id.uuidString] = nil
        }

        // Befoor's own countdowns whose meeting changed (a new title, location or
        // video link): rebuilt to the same ring time so the card shows it.
        let chains = self.chains
        for (id, alarm) in existing where alarm.state == .countdown {
            let key = id.uuidString
            guard let target = chains[key], let request = wantedByID[id],
                  target == request.fireDate.timeIntervalSince1970,
                  request.fireDate > now.addingTimeInterval(30),
                  fingerprints[key] != request.fingerprint else { continue }
            try? manager.cancel(id: id)
            if (try? await manager.schedule(id: id, configuration: configuration(for: request, at: request.fireDate,
                                                                                    countingDown: true))) != nil {
                fingerprints[key] = request.fingerprint
            }
        }

        var failed: [MeetingAlarmRequest] = []
        for request in requests {
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
                starts[key] = request.eventStart.timeIntervalSince1970
            } catch {
                print("[Befoor] Scheduling alarm failed: \(error)")
                failed.append(request)
            }
        }

        // Forget bookkeeping for alarms more than a day old.
        let cutoff = now.addingTimeInterval(-86_400).timeIntervalSince1970
        let liveIDs = Set(currentAlarms.map(\.id.uuidString))
        self.history = history.filter { $0.value > cutoff }
        self.starts = starts.filter { $0.value > cutoff }
        self.chains = chains.filter { $0.value > cutoff }
        self.fingerprints = fingerprints.filter { liveIDs.contains($0.key) }

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

    /// - Parameter countingDown: start counting down to `ringAt` right away, so
    ///   the alarm's Live Activity shows the countdown until it rings.
    private func configuration(
        for request: MeetingAlarmRequest,
        at ringAt: Date,
        countingDown: Bool = false
    ) -> AlarmManager.AlarmConfiguration<MeetingAlarmMetadata> {
        let title: String
        switch request.minutesBefore {
        case 0:  title = String(localized: "\(request.eventTitle) is starting")
        case 1:  title = String(localized: "\(request.eventTitle) in 1 minute")
        default: title = String(localized: "\(request.eventTitle) in \(request.minutesBefore) minutes")
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
                location: request.location,
                calendarRGB: request.calendarRGB,
                joinURL: request.joinURL,
                linkChange: request.linkChange
            ),
            tintColor: request.calendarRGB.map { Color(.sRGB, red: $0[0], green: $0[1], blue: $0[2]) } ?? .indigo
        )
        let sound: AlertConfiguration.AlertSound
        if request.sound == .systemDefault {
            sound = .default
        } else if AlarmTones.isReady(request.sound, quiet: request.quiet) {
            sound = .named(AlarmTones.fileName(for: request.sound, quiet: request.quiet))
        } else if AlarmTones.isReady(request.sound) {
            sound = .named(AlarmTones.fileName(for: request.sound))
        } else {
            sound = .named(request.sound.rawValue + ".caf")
        }

        return AlarmManager.AlarmConfiguration(
            // preAlert is the countdown before it rings; postAlert is the snooze length.
            countdownDuration: Alarm.CountdownDuration(
                preAlert: countingDown ? max(ringAt.timeIntervalSinceNow, 1) : nil,
                postAlert: Double(request.snoozeMinutes) * 60
            ),
            schedule: countingDown ? nil : .fixed(ringAt),
            attributes: attributes,
            stopIntent: MeetingAlarmIntent(meetingKey: request.meetingKey, slot: request.slot, action: "stop"),
            secondaryIntent: MeetingAlarmIntent(meetingKey: request.meetingKey, slot: request.slot, action: "snooze"),
            sound: sound
        )
    }

    // MARK: Alarm actions

    // MARK: Test alert

    /// The test alert from Settings; syncs leave it alone.
    private static let testAlarmID = alarmID(meetingKey: "befoor_test", slot: 1)

    /// Rings a real alarm in `seconds`, set up like a meeting's first alert
    /// (title, sound, snooze and countdown card), so the person can check it
    /// gets through on silent, in a Focus, or with the phone locked.
    func scheduleTest(in seconds: TimeInterval) async -> Bool {
        let settings = AppSettings.shared
        await AlarmTones.prepare(settings.selectedSound)
        let ringAt = Date().addingTimeInterval(seconds)
        let request = MeetingAlarmRequest(
            meetingKey: "befoor_test", slot: 1, minutesBefore: 5, fireDate: ringAt,
            eventTitle: String(localized: "Test meeting"), eventStart: ringAt.addingTimeInterval(5 * 60),
            calendarName: "", calendarRGB: nil, location: nil, joinURL: nil, linkChange: nil,
            sound: settings.selectedSound, quiet: false, snoozeMinutes: settings.snoozeDurationMinutes
        )
        try? manager.cancel(id: Self.testAlarmID)
        do {
            _ = try await manager.schedule(id: Self.testAlarmID, configuration: configuration(for: request, at: ringAt))
            return true
        } catch {
            print("[Befoor] Test alarm failed: \(error)")
            return false
        }
    }

    /// Called when the person taps Stop or Snooze on a ringing alarm. Either way
    /// the meeting's last alert still rings.
    func handleAction(meetingKey: String, slot: Int, stopped: Bool) async {
        // Befoor is awake anyway, so use the moment to pick up calendar changes
        // made since it last ran. Awaited so the system doesn't suspend the app
        // mid-sync once the intent returns. Ringing and snoozed alarms are left
        // alone by the sync.
        await AlarmScheduler.shared.sync()

        // Snooze already counts down in the alarm's own Live Activity.
        if stopped {
            await countDownToNextAlert(meetingKey: meetingKey, after: slot)
        }

        // Then tidy the countdown. Befoor is in the background here, which iOS
        // doesn't let start a Live Activity (not even from an alarm's intent), so
        // once the last alert is stopped the meeting has no card unless Befoor is open.
        await MeetingLiveActivityManager.shared.refresh()
    }

    /// After the person stops an alert, reschedules the meeting's next alert as a
    /// countdown that starts now. AlarmKit then shows the countdown in the
    /// alarm's Live Activity — the same one that was ringing — and rings the
    /// next alert from it, so the meeting only ever has one Live Activity.
    /// It keeps the same alarm ID, so syncs leave it alone while it counts down.
    private func countDownToNextAlert(meetingKey: String, after slot: Int) async {
        let now = Date()
        guard let next = lastRequests
            .filter({ $0.meetingKey == meetingKey && $0.slot > slot && $0.fireDate > now.addingTimeInterval(5) })
            .min(by: { $0.slot < $1.slot }),
              currentAlarms.first(where: { $0.id == next.id })?.state ?? .scheduled == .scheduled
        else { return }

        try? manager.cancel(id: next.id)
        do {
            _ = try await manager.schedule(id: next.id,
                                           configuration: configuration(for: next, at: next.fireDate, countingDown: true))
            chains[next.id.uuidString] = next.fireDate.timeIntervalSince1970
        } catch {
            // Never lose the alert: put it back as a plain alarm.
            print("[Befoor] Countdown to next alert failed: \(error)")
            _ = try? await manager.schedule(id: next.id, configuration: configuration(for: next, at: next.fireDate))
        }
        fingerprints[next.id.uuidString] = next.fingerprint
    }
    #endif
}

#if !targetEnvironment(macCatalyst)

// MARK: - Metadata

/// Meeting details shown in the alarm's Live Activity.
///
/// IMPORTANT: an identical copy lives in BeforeWidget/MeetingAlarmLiveActivity.swift.
/// ActivityKit matches the two by type name and Codable shape — keep them in sync.
struct MeetingAlarmMetadata: AlarmMetadata {
    var meetingTitle: String
    var startDate: Date
    var location: String?
    /// sRGB components of the calendar color.
    var calendarRGB: [Double]?
    /// Video-call link for the Join button.
    var joinURL: URL?
    /// "removed" or "changed" if the meeting's link changed.
    var linkChange: String?
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
