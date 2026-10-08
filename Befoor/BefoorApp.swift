import SwiftUI
import UIKit

@main
struct BefoorApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Register background task handler before the app finishes launching.
        // NotificationService.shared is also initialized here, which sets it as
        // the UNUserNotificationCenter delegate and registers alarm actions.
        AlarmScheduler.shared.registerBackgroundTasks()
        _ = NotificationService.shared
        return true
    }
}
