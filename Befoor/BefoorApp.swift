import SwiftUI
import SwiftData
import BackgroundTasks
import UIKit
import CoreData
import CloudKit

@main
struct BefoorApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    static var storageMode: String = "unknown"
    let modelContainer: ModelContainer

    init() {
        let cloudTypes: [any PersistentModel.Type] = [
            Person.self, Note.self, FollowUp.self, LongTermNote.self,
            Reminder.self, DetectionKeyword.self, AlarmListSnapshot.self,
        ]

        // Only CloudKit-synced models live in the SwiftData container.
        // TrackedAlarmModel and CalendarSyncRecord now use file-based storage
        // so their reads/writes never touch the persistent store coordinator
        // and cannot interfere with CloudKit exports.
        do {
            let cloudConfig = ModelConfiguration(
                "CloudStore",
                schema: Schema(cloudTypes),
                groupContainer: .identifier("group.com.befoor.app"),
                cloudKitDatabase: .private("iCloud.com.jirofeingold.Befoor")
            )
            modelContainer = try ModelContainer(
                for: Schema(cloudTypes),
                configurations: cloudConfig
            )
            Self.storageMode = "CloudKit"
            print("[Befoor] CloudKit ModelContainer created successfully")
            Self.startCloudKitEventLogging()
        } catch {
            print("[Befoor] CloudKit ModelContainer failed: \(error)")
            Self.removeStoreFiles()
            do {
                let config = ModelConfiguration(
                    groupContainer: .identifier("group.com.befoor.app"),
                    cloudKitDatabase: .none
                )
                modelContainer = try ModelContainer(for: Schema(cloudTypes), configurations: config)
                Self.storageMode = "Local-only"
                print("[Befoor] Local-only ModelContainer created as fallback")
            } catch {
                print("[Befoor] Local-only ModelContainer also failed: \(error)")
                let config = ModelConfiguration(isStoredInMemoryOnly: true)
                modelContainer = try! ModelContainer(for: Schema(cloudTypes), configurations: config)
                Self.storageMode = "In-memory"
                print("[Befoor] In-memory ModelContainer created as last resort")
            }
        }
    }

    /// Removes all SwiftData/Core Data store files, CloudKit sync metadata,
    /// and related caches from Application Support and the App Group container.
    static func removeStoreFiles() {
        let directories: [URL?] = [
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.befoor.app")
        ]
        let fm = FileManager.default
        let storeExtensions: Set<String> = ["store", "store-shm", "store-wal",
                                             "sqlite", "sqlite-shm", "sqlite-wal"]
        for dir in directories.compactMap({ $0 }) {
            print("[Befoor] Scanning directory: \(dir.path)")
            guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: []) else { continue }
            var toRemove: [URL] = []
            while let url = enumerator.nextObject() as? URL {
                let name = url.lastPathComponent
                let ext = url.pathExtension
                let shouldRemove = storeExtensions.contains(ext)
                    || name.contains(".store")
                    || name.contains(".sqlite")
                    || name.hasPrefix("_cd_")
                    || name.hasPrefix("cloudkit-")
                    || name == "ckAssets"
                    || name == "CloudKit"
                    || name == "CoreDataCloudKitSupport"
                    || name.hasSuffix(".ckzone")
                    || name.hasSuffix(".cksubscription")
                if shouldRemove {
                    toRemove.append(url)
                    enumerator.skipDescendants()
                }
            }
            // Remove deepest paths first to handle nested items
            for url in toRemove.sorted(by: { $0.path.count > $1.path.count }) {
                try? fm.removeItem(at: url)
                print("[Befoor] Removed: \(url.path)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }

    private static func startCloudKitEventLogging() {
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            let type: String
            switch event.type {
            case .setup: type = "setup"
            case .import: type = "import"
            case .export: type = "export"
            @unknown default: type = "unknown"
            }
            let success = event.succeeded ? "✓" : "✗"
            let errorMsg = event.error.map { " error=\($0.localizedDescription)" } ?? ""
            let end = event.endDate as Date? ?? Date()
            print("[Befoor-CK] \(type) \(success) start=\(event.startDate) end=\(end)\(errorMsg)")

            let succeeded = event.succeeded
            var errorDesc: String? = nil
            if let err = event.error {
                let nsErr = err as NSError
                var parts = ["\(nsErr.domain) \(nsErr.code)"]
                if let underlying = nsErr.userInfo[NSUnderlyingErrorKey] as? NSError {
                    parts.append("underlying: \(underlying.domain) \(underlying.code)")
                }
                // Extract partial errors (CKError.partialFailure stores per-item errors)
                if let partialErrors = nsErr.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
                    for (key, partialErr) in partialErrors.prefix(3) {
                        let pNS = partialErr as NSError
                        parts.append("partial[\(key)]: \(pNS.domain) \(pNS.code)")
                    }
                    if partialErrors.count > 3 {
                        parts.append("+\(partialErrors.count - 3) more")
                    }
                }
                errorDesc = parts.joined(separator: " | ")
                print("[Befoor-CK] Full error: \(errorDesc!)")
            }
            let isSetup = event.type == .setup
            Task { @MainActor in
                CloudKitStatus.shared.lastEventType = type
                CloudKitStatus.shared.lastEventSucceeded = succeeded
                CloudKitStatus.shared.lastEventDate = end
                CloudKitStatus.shared.lastError = errorDesc
                CloudKitStatus.shared.lastEventTimestamp = end.formatted(.dateTime.hour().minute().second())
                if isSetup {
                    CloudKitStatus.shared.setupComplete = succeeded
                    if !succeeded { CloudKitStatus.shared.setupError = errorDesc }
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { _ in
            print("[Befoor-CK] Remote store change received")
            Task { @MainActor in
                CloudKitStatus.shared.remoteChangeCount += 1
            }
        }
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

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Wait for NSPersistentCloudKitContainer to finish importing before telling
        // the OS we're done. Otherwise the system suspends the app mid-import.
        let state = RemoteChangeWaiter()

        state.observer = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [state] _ in
            state.finish(with: completionHandler)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [state] in
            state.finish(with: completionHandler)
        }
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

// MARK: - CloudKit Status

@MainActor
final class CloudKitStatus: ObservableObject {
    static let shared = CloudKitStatus()
    @Published var setupComplete = false
    @Published var setupError: String?
    @Published var lastEventType: String?
    @Published var lastEventSucceeded = false
    @Published var lastEventDate: Date?
    @Published var lastError: String?
    @Published var remoteChangeCount = 0
    @Published var lastEventTimestamp: String?
    @Published var accountStatus: String = "unknown"
    @Published var iCloudDriveAvailable: Bool = FileManager.default.ubiquityIdentityToken != nil

    @Published var directTestResult: String?
    @Published var userRecordID: String = "unknown"

    func checkAccountStatus() {
        let container = CKContainer(identifier: "iCloud.com.jirofeingold.Befoor")
        container.accountStatus { status, error in
            let description: String
            switch status {
            case .available: description = "available"
            case .noAccount: description = "noAccount"
            case .restricted: description = "restricted"
            case .couldNotDetermine: description = "couldNotDetermine"
            case .temporarilyUnavailable: description = "temporarilyUnavailable"
            @unknown default: description = "unknown(\(status.rawValue))"
            }
            let errorSuffix = error.map { " (\($0.localizedDescription))" } ?? ""
            Task { @MainActor in
                self.accountStatus = description + errorSuffix
            }
        }
    }

    func testDirectCloudKit() {
        Task { @MainActor in
            self.directTestResult = "testing..."
        }
        let container = CKContainer(identifier: "iCloud.com.jirofeingold.Befoor")
        let db = container.privateCloudDatabase
        var parts: [String] = []

        container.fetchUserRecordID { userRecordID, userError in
            if let userRecordID {
                let fullID = userRecordID.recordName
                parts.append("user: \(fullID)")
                Task { @MainActor in
                    CloudKitStatus.shared.userRecordID = fullID
                }
            }
            if let userError {
                parts.append("userErr: \(self.detailedError(userError))")
            }

            let cdZoneID = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)
            let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            config.previousServerChangeToken = nil

            let op = CKFetchRecordZoneChangesOperation(recordZoneIDs: [cdZoneID], configurationsByRecordZoneID: [cdZoneID: config])
            var recordCount = 0
            var recordTypes = Set<String>()

            op.recordWasChangedBlock = { _, result in
                if case .success(let record) = result {
                    recordCount += 1
                    recordTypes.insert(record.recordType)
                }
            }

            op.recordZoneFetchResultBlock = { _, result in
                switch result {
                case .success:
                    parts.append("fetch: \(recordCount) records [\(recordTypes.sorted().joined(separator: ", "))]")
                case .failure(let fetchError):
                    parts.append("fetchErr: \(self.detailedError(fetchError))")
                }
            }

            op.fetchRecordZoneChangesResultBlock = { result in
                if case .failure(let err) = result {
                    parts.append("overallErr: \(self.detailedError(err))")
                }
                let output = parts.joined(separator: " | ")
                print("[Befoor-CK] Direct test: \(output)")
                Task { @MainActor in
                    CloudKitStatus.shared.directTestResult = output
                }
            }

            db.add(op)
        }
    }

    private nonisolated func detailedError(_ error: Error) -> String {
        let nsErr = error as NSError
        var msg = "\(nsErr.domain) \(nsErr.code)"
        if let underlying = nsErr.userInfo[NSUnderlyingErrorKey] as? NSError {
            msg += " (underlying: \(underlying.domain) \(underlying.code))"
        }
        return msg
    }
}

// MARK: - CloudKit Remote Change Waiter

private class RemoteChangeWaiter: @unchecked Sendable {
    var observer: NSObjectProtocol?
    private var completed = false

    func finish(with completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard !completed else { return }
        completed = true
        if let obs = observer {
            NotificationCenter.default.removeObserver(obs)
            observer = nil
        }
        completionHandler(.newData)
    }
}
