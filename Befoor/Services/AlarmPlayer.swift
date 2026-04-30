import AVFoundation
import Foundation

/// Fires alarm audio at scheduled times, bypassing the silent switch.
///
/// Works alongside UNUserNotificationCenter: notifications provide the visual popup
/// and Snooze/Dismiss actions; AlarmPlayer provides the audio that ignores silent mode.
///
/// Requires the app to have an active AVAudioSession (.playback) so it can run
/// while backgrounded — BackgroundAudioKeepAlive handles that.
@MainActor
final class AlarmPlayer {
    static let shared = AlarmPlayer()

    // MARK: - Types

    struct Entry: Codable {
        let identifier: String   // base notification ID (no suffix)
        let fireDates: [Date]    // all ring dates: initial, +2 min, +4 min, final
        let sound: BefoorSound
    }

    // MARK: - Persistence

    private static let storageKey = "AlarmPlayerEntries"

    private func persistEntries() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private static func loadEntries() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }

        // Only keep entries that still have future fire dates
        let now = Date()
        return saved.compactMap { entry in
            let futureDates = entry.fireDates.filter { $0 > now }
            guard !futureDates.isEmpty else { return nil }
            return Entry(identifier: entry.identifier, fireDates: futureDates, sound: entry.sound)
        }
    }

    // MARK: - State

    private var entries: [Entry] = []
    private var firedTimestamps: Set<Int> = []   // rounded fire-date timestamps already played
    private var timer: Timer?
    private var player: AVAudioPlayer?
    private var stopWork: DispatchWorkItem?

    var isPlaying: Bool { player?.isPlaying == true }

    private init() {
        entries = Self.loadEntries()
        if !entries.isEmpty {
            print("[Befoor] AlarmPlayer restored \(entries.count) entries from disk")
            startTimerIfNeeded()
        }
    }

    // MARK: - Public API

    /// Replace the full alarm schedule. Called after every sync().
    func setSchedule(_ newEntries: [Entry]) {
        entries = newEntries
        pruneOldTimestamps()
        persistEntries()
        startTimerIfNeeded()
    }

    /// Add a snooze entry (called when user snoozes a notification).
    func addSnooze(identifier: String, at fireDate: Date, sound: BefoorSound) {
        let snoozeID = identifier + "_snooze"
        entries.removeAll { $0.identifier == snoozeID }
        entries.append(Entry(identifier: snoozeID, fireDates: [fireDate], sound: sound))
        persistEntries()
        startTimerIfNeeded()
    }

    /// Stop current playback and remove all entries for this alarm.
    func dismiss(identifier: String) {
        stopPlayback()
        entries.removeAll {
            $0.identifier == identifier || $0.identifier == identifier + "_snooze"
        }
        persistEntries()
    }

    /// Stop current playback (the snooze notification will re-fire later).
    func stopForSnooze(identifier: String) {
        stopPlayback()
        // Remove follow-up entries so only the snooze remains
        entries.removeAll {
            $0.identifier != identifier + "_snooze" &&
            ($0.identifier == identifier ||
             $0.identifier == identifier + "_r1" ||
             $0.identifier == identifier + "_r2" ||
             $0.identifier == identifier + "_final")
        }
        persistEntries()
    }

    // MARK: - Timer

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let now = Date()

        for entry in entries {
            for fireDate in entry.fireDates {
                let age = now.timeIntervalSince(fireDate)
                guard age >= 0, age < 5 else { continue }   // within 5-second window

                let stamp = Int(fireDate.timeIntervalSince1970)
                guard !firedTimestamps.contains(stamp) else { continue }

                firedTimestamps.insert(stamp)
                playSound(entry.sound)
                if AppSettings.shared.hapticsEnabled {
                    NotificationService.shared.playAlarmHaptics()
                }
            }
        }

        stopTimerIfIdle()
    }

    private func stopTimerIfIdle() {
        let now = Date()
        let hasUpcoming = entries.contains { entry in
            entry.fireDates.contains { $0 > now }
        }
        if !hasUpcoming && !isPlaying {
            timer?.invalidate()
            timer = nil
        }
    }

    // MARK: - Playback

    private func playSound(_ sound: BefoorSound) {
        guard AppSettings.shared.soundEnabled else { return }
        stopPlayback()

        let fileName = sound == .systemDefault ? "pebble" : sound.rawValue
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "caf") else {
            print("[Befoor] AlarmPlayer: sound file not found: \(fileName).caf")
            return
        }

        do {
            // Ensure session is active and in .playback mode, which bypasses the
            // silent switch. mixWithOthers keeps the keep-alive stream alive alongside.
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)

            player = try AVAudioPlayer(contentsOf: url)
            player?.volume = 1.0
            player?.play()
        } catch {
            print("[Befoor] AlarmPlayer playback error: \(error)")
            return
        }

        // Auto-stop after 60 seconds if the user takes no action
        let work = DispatchWorkItem { [weak self] in self?.stopPlayback() }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: work)
    }

    private func stopPlayback() {
        stopWork?.cancel()
        stopWork = nil
        player?.stop()
        player = nil
    }

    // MARK: - Helpers

    private func pruneOldTimestamps() {
        let cutoff = Int(Date().timeIntervalSince1970) - 600   // keep last 10 minutes
        firedTimestamps = firedTimestamps.filter { $0 > cutoff }
    }
}
