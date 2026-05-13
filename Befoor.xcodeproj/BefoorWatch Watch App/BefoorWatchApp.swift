import SwiftUI
import SwiftData

@main
struct BefoorWatchApp: App {
    let modelContainer: ModelContainer

    init() {
        let types: [any PersistentModel.Type] = [
            Person.self, Note.self, FollowUp.self, LongTermNote.self,
            Reminder.self, DetectionKeyword.self,
        ]

        do {
            let config = ModelConfiguration(
                cloudKitDatabase: .private("iCloud.com.jirofeingold.Befoor")
            )
            modelContainer = try ModelContainer(for: Schema(types), configurations: config)
        } catch {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            modelContainer = try! ModelContainer(for: Schema(types), configurations: config)
        }
    }

    var body: some Scene {
        WindowGroup {
            WatchContentView()
        }
        .modelContainer(modelContainer)
    }
}
