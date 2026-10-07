import AVFoundation

final class SoundPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = SoundPlayer()

    @Published private(set) var playingSound: BefoorSound?

    private var player: AVAudioPlayer?

    private override init() {}

    func preview(_ sound: BefoorSound) {
        stop()

        let fileName = sound == .systemDefault ? "pebble" : sound.rawValue
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "caf") else {
            print("[Befoor] Sound file not found: \(fileName).caf")
            return
        }

        do {
            // The default session category is silenced by the ringer switch; alarms
            // ignore it, so the preview should too.
            try AVAudioSession.sharedInstance().setCategory(.playback, options: .duckOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.play()
            playingSound = sound
        } catch {
            print("[Befoor] SoundPlayer error: \(error)")
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playingSound = nil
        deactivateSession()
    }

    /// Hands audio back to whatever was playing before (music, podcasts).
    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully _: Bool) {
        DispatchQueue.main.async {
            self.playingSound = nil
            self.deactivateSession()
        }
    }
}
