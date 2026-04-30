import AVFoundation

/// Plays a looping silent audio stream to keep the app process alive in the background.
///
/// As long as an AVAudioSession with category .playback is active, iOS will not
/// suspend the app, which lets AlarmPlayer's timer fire at the correct time even
/// when the device is locked and the ringer switch is off.
///
/// Call start() at app launch and leave it running. The overhead of a silent
/// audio loop is negligible for an alarm app.
final class BackgroundAudioKeepAlive {
    static let shared = BackgroundAudioKeepAlive()

    private var player: AVAudioPlayer?
    private var healthTimer: Timer?
    private(set) var isRunning = false

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMediaReset),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: nil
        )
    }

    func start() {
        #if targetEnvironment(macCatalyst)
        // Background audio keep-alive is not needed on Mac — the process stays alive.
        return
        #endif

        configureSession()

        if isRunning, player?.isPlaying == true {
            startHealthTimer()
            return
        }

        // Use a bundled sound at volume 0. A real audio stream is more reliably
        // recognised by iOS as "app is playing audio" than generated silence.
        let fileName = AppSettings.shared.selectedSound == .systemDefault
            ? "pebble"
            : AppSettings.shared.selectedSound.rawValue
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "caf") else {
            print("[Befoor] BackgroundAudioKeepAlive: sound file not found")
            return
        }

        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.volume = 0          // inaudible
            player?.numberOfLoops = -1  // loop forever
            player?.play()
            isRunning = true
            startHealthTimer()
        } catch {
            print("[Befoor] BackgroundAudioKeepAlive error: \(error)")
        }
    }

    func stop() {
        #if targetEnvironment(macCatalyst)
        return
        #endif

        healthTimer?.invalidate()
        healthTimer = nil
        player?.stop()
        player = nil
        isRunning = false
        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation
        )
    }

    // MARK: - Session configuration

    /// Sets category and activates session. Safe to call repeatedly.
    func configureSession() {
        #if targetEnvironment(macCatalyst)
        return
        #endif

        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                options: [.mixWithOthers]   // don't duck podcasts/music
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[Befoor] BackgroundAudioKeepAlive session error: \(error)")
        }
    }

    // MARK: - Health check

    /// Periodically verifies the silent player is still running. If it stopped
    /// for any reason (media reset, unexpected deallocation), restart it.
    private func startHealthTimer() {
        guard healthTimer == nil else { return }
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkHealth()
        }
        RunLoop.main.add(t, forMode: .common)
        healthTimer = t
    }

    private func checkHealth() {
        guard isRunning else { return }
        if player == nil || player?.isPlaying == false {
            print("[Befoor] BackgroundAudioKeepAlive: player stopped, restarting")
            isRunning = false
            start()
        }
    }

    // MARK: - Interruption handling

    @objc private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }

        if type == .ended {
            // Check if iOS suggests we should resume
            let optionsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
            if options.contains(.shouldResume) || isRunning {
                configureSession()
                player?.play()
            }
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        // After a route change (e.g. headphones unplugged) the player may pause.
        // Resume silently so the keep-alive continues.
        if isRunning, player?.isPlaying == false {
            configureSession()
            player?.play()
        }
    }

    /// Media services were completely reset by iOS (rare but happens).
    /// The old player and session are invalid — recreate everything.
    @objc private func handleMediaReset() {
        print("[Befoor] BackgroundAudioKeepAlive: media services reset, restarting")
        player = nil
        isRunning = false
        start()
    }
}
