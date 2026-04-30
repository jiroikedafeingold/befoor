import SwiftUI

struct WatchContentView: View {
    var body: some View {
        TabView {
            NavigationStack {
                WatchAlarmsView()
            }
            .tabItem {
                Label("Alarms", systemImage: "alarm")
            }

            NavigationStack {
                WatchPeopleListView()
            }
            .tabItem {
                Label("People", systemImage: "person.2")
            }
        }
    }
}
