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
        // Do not deactivate the shared AVAudioSession — BackgroundAudioKeepAlive
        // depends on it staying active to keep the process alive in the background.
    }

    // MARK: AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully _: Bool) {
        DispatchQueue.main.async {
            self.playingSound = nil
        }
    }
}
