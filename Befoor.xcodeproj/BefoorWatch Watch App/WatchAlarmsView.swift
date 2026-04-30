import SwiftUI
import SwiftData

struct WatchAlarmsView: View {
    @Query(sort: \TrackedAlarmModel.eventStartDate) private var allAlarms: [TrackedAlarmModel]

    private var todayAlarms: [TrackedAlarmModel] {
        allAlarms.filter { Calendar.current.isDateInToday($0.eventStartDate) }
    }

    var body: some View {
        List {
            if todayAlarms.isEmpty {
                ContentUnavailableView("No Alarms", systemImage: "alarm",
                                       description: Text("No alarms scheduled for today."))
            } else {
                ForEach(todayAlarms, id: \.eventIdentifier) { alarm in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(alarm.eventTitle)
                            .font(.headline)
                            .lineLimit(2)

                        HStack(spacing: 4) {
                            Text(alarm.eventStartDate, style: .time)
                            if alarm.eventStartDate > Date() {
                                Text("·")
                                Text(alarm.eventStartDate, style: .relative)
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Alarms")
    }
}
