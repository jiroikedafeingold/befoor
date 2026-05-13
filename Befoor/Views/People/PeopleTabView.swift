import SwiftUI
import SwiftData

/// Wrapper view for the People tab. Initializes SyncCoordinator and handles deep linking.
struct PeopleTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.cloudRefreshToken) private var refreshToken
    @Query private var people: [Person]
    @State private var syncCoordinator = SyncCoordinator()
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            PeopleListView(syncCoordinator: syncCoordinator)
                .id(refreshToken)
                .navigationDestination(for: PersistentIdentifier.self) { personID in
                    PersonDetailFromID(personID: personID, syncCoordinator: syncCoordinator)
                }
        }
        .task {
            syncCoordinator.configure(with: modelContext)
            syncCoordinator.seedDefaultKeywords()
            await syncCoordinator.performFullSync(force: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToPerson)) { notification in
            if let personName = notification.userInfo?["personName"] as? String,
               let person = people.first(where: { $0.name == personName }) {
                navigationPath = NavigationPath()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    navigationPath.append(person.persistentModelID)
                }
            } else if let personIDString = notification.userInfo?["personID"] as? String,
                      let person = people.first(where: {
                          $0.persistentModelID.hashValue == personIDString.hashValue
                      }) {
                navigationPath = NavigationPath()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    navigationPath.append(person.persistentModelID)
                }
            }
        }
    }
}

/// Helper to resolve PersistentIdentifier → Person for navigation destinations.
private struct PersonDetailFromID: View {
    let personID: PersistentIdentifier
    let syncCoordinator: SyncCoordinator
    @Query private var people: [Person]

    var body: some View {
        if let person = people.first(where: { $0.persistentModelID == personID }) {
            PersonDetailView(person: person, syncCoordinator: syncCoordinator)
        } else {
            ContentUnavailableView("Person Not Found", systemImage: "person.slash")
        }
    }
}
