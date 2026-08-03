import SwiftUI

struct WatchContentView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        TabView {
            NavigationStack {
                WatchAlarmsView()
            }
            .tabItem {
                Label("Alarms", systemImage: "alarm")
            }

            if settings.peopleEnabled {
                NavigationStack {
                    WatchPeopleListView()
                }
                .tabItem {
                    Label("People", systemImage: "person.2")
                }
            }
        }
    }
}
