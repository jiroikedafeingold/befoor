import SwiftUI
import SwiftData

struct WatchAlarmsView: View {
    @Query(sort: \TrackedAlarmModel.eventStartDate) private var allAlarms: [TrackedAlarmModel]

    private var upcomingAlarms: [TrackedAlarmModel] {
        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: Date())) else {
            return []
        }
        return allAlarms.filter { $0.eventStartDate >= Date() && $0.eventStartDate < cutoff }
    }

    private var todayAlarms: [TrackedAlarmModel] {
        upcomingAlarms.filter { Calendar.current.isDateInToday($0.eventStartDate) }
    }

    private var tomorrowAlarms: [TrackedAlarmModel] {
        upcomingAlarms.filter { Calendar.current.isDateInTomorrow($0.eventStartDate) }
    }

    var body: some View {
        List {
            if upcomingAlarms.isEmpty {
                ContentUnavailableView("No Alarms", systemImage: "alarm",
                                       description: Text("No alarms in the next two days."))
            } else {
                if !todayAlarms.isEmpty {
                    Section("Today") {
                        ForEach(todayAlarms, id: \.eventIdentifier) { alarm in
                            WatchAlarmRow(alarm: alarm, showRelative: true)
                        }
                    }
                }

                if !tomorrowAlarms.isEmpty {
                    Section("Tomorrow") {
                        ForEach(tomorrowAlarms, id: \.eventIdentifier) { alarm in
                            WatchAlarmRow(alarm: alarm, showRelative: false)
                        }
                    }
                }
            }
        }
        .navigationTitle("Alarms")
    }
}

private struct WatchAlarmRow: View {
    let alarm: TrackedAlarmModel
    var showRelative: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(alarm.eventTitle)
                .font(.headline)
                .lineLimit(2)

            HStack(spacing: 4) {
                Text(alarm.eventStartDate, style: .time)
                if showRelative && alarm.eventStartDate > Date() {
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
