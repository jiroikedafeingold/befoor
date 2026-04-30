import SwiftUI
import SwiftData
import BackgroundTasks
import UIKit

@main
struct BefoorApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    let modelContainer: ModelContainer

    init() {
        let types: [any PersistentModel.Type] = [
            Person.self, Note.self, FollowUp.self, LongTermNote.self,
            Reminder.self, DetectionKeyword.self,
            TrackedAlarmModel.self, CalendarSyncRecord.self,
        ]

        // Try CloudKit + App Group first, fall back gracefully.
        do {
            let config = ModelConfiguration(
                groupContainer: .identifier("group.com.befoor.app"),
                cloudKitDatabase: .private("iCloud.com.jirofeingold.Befoor")
            )
            modelContainer = try ModelContainer(for: Schema(types), configurations: config)
            print("[Befoor] CloudKit ModelContainer created successfully")
        } catch {
            print("[Befoor] CloudKit ModelContainer failed: \(error)")
            Self.removeStoreFiles()
            do {
                let config = ModelConfiguration(
                    groupContainer: .identifier("group.com.befoor.app"),
                    cloudKitDatabase: .none
                )
                modelContainer = try ModelContainer(for: Schema(types), configurations: config)
                print("[Befoor] Local-only ModelContainer created as fallback")
            } catch {
                print("[Befoor] Local-only ModelContainer also failed: \(error)")
                let config = ModelConfiguration(isStoredInMemoryOnly: true)
                modelContainer = try! ModelContainer(for: Schema(types), configurations: config)
                print("[Befoor] In-memory ModelContainer created as last resort")
            }
        }
    }

    /// Removes all SwiftData/Core Data store files from Application Support.
    private static func removeStoreFiles() {
        guard let dir = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        // Catch .store, .store-shm, .store-wal, .sqlite, .sqlite-shm, .sqlite-wal,
        // and CoreData ckAssets / _cd_* support files
        let storeExtensions: Set<String> = ["store", "store-shm", "store-wal",
                                             "sqlite", "sqlite-shm", "sqlite-wal"]
        for file in files {
            let ext = (file as NSString).pathExtension
            if storeExtensions.contains(ext)
                || file.contains(".store")
                || file.contains(".sqlite")
                || file.hasPrefix("_cd_")
                || file == "ckAssets" {
                try? fm.removeItem(at: dir.appendingPathComponent(file))
                print("[Befoor] Removed store file: \(file)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, UIApplicationDelegate {
    /// Set by BefoorApp after init so notification callbacks can access SwiftData.
    var modelContainer: ModelContainer?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Register background task handler before the app finishes launching.
        // NotificationService.shared is also initialized here, which sets it as
        // the UNUserNotificationCenter delegate and registers alarm actions.
        AlarmScheduler.shared.registerBackgroundTasks()
        _ = NotificationService.shared

        // Configure the audio session and start the silent keep-alive immediately.
        // This ensures the session is active before any sync or alarm scheduling,
        // and that the app can stay alive in the background for timer-based alarms.
        BackgroundAudioKeepAlive.shared.start()

        // Register for remote notifications (required for CloudKit sync push)
        application.registerForRemoteNotifications()

        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // CloudKit handles the token internally; nothing to do here.
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[Befoor] Failed to register for remote notifications: \(error)")
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        NotificationService.shared.clearBadge()
        BackgroundAudioKeepAlive.shared.start()
        Task { await AlarmScheduler.shared.sync() }
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Start silent audio loop so the process stays alive for timer-based alarms
        BackgroundAudioKeepAlive.shared.start()
        AlarmScheduler.shared.scheduleNextBackgroundRefresh()
    }
}
