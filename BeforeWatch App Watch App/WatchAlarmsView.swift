import SwiftUI

struct WatchAlarmsView: View {
    var body: some View {
        ContentUnavailableView(
            "Alarms on iPhone",
            systemImage: "alarm",
            description: Text("Alarm scheduling is managed on your iPhone.")
        )
        .navigationTitle("Alarms")
    }
}
