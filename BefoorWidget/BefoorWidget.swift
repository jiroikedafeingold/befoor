import WidgetKit
import SwiftUI

// MARK: - Data

struct UpcomingAlarm: Identifiable {
    let id: String
    let title: String
    let startDate: Date
}

struct AlarmEntry: TimelineEntry {
    let date: Date
    let alarms: [UpcomingAlarm]
}

// MARK: - Provider

struct AlarmTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> AlarmEntry {
        AlarmEntry(date: .now, alarms: [
            UpcomingAlarm(id: "placeholder", title: "Meeting", startDate: Date().addingTimeInterval(3600))
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (AlarmEntry) -> Void) {
        completion(fetchEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AlarmEntry>) -> Void) {
        let entry = fetchEntry()

        let nextRefresh: Date
        if let nextEvent = entry.alarms.first {
            nextRefresh = nextEvent.startDate
        } else {
            nextRefresh = Date().addingTimeInterval(900)
        }

        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func fetchEntry() -> AlarmEntry {
        let now = Date()
        let cutoff = now.addingTimeInterval(7200)

        guard let url = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: "group.com.befoor.app")?
                .appendingPathComponent("tracked_alarms.json"),
              let data = try? Data(contentsOf: url),
              let models = try? JSONDecoder().decode([WidgetAlarmModel].self, from: data) else {
            return AlarmEntry(date: now, alarms: [])
        }

        var seen = Set<String>()
        var alarms: [UpcomingAlarm] = []
        for model in models.sorted(by: { $0.eventStartDate < $1.eventStartDate }) {
            guard model.eventStartDate >= now && model.eventStartDate <= cutoff else { continue }
            if seen.insert(model.eventTitle).inserted {
                alarms.append(UpcomingAlarm(
                    id: model.eventIdentifier,
                    title: model.eventTitle,
                    startDate: model.eventStartDate
                ))
            }
        }

        return AlarmEntry(date: now, alarms: alarms)
    }
}

/// Mirrors the main app's TrackedAlarmModel for JSON decoding.
private struct WidgetAlarmModel: Codable {
    let eventIdentifier: String
    let eventTitle: String
    let eventStartDate: Date
}

// MARK: - Views

struct BefoorWidgetEntryView: View {
    var entry: AlarmEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryRectangular:
            rectangularView
        case .accessoryInline:
            inlineView
        default:
            rectangularView
        }
    }

    @ViewBuilder
    private var rectangularView: some View {
        if entry.alarms.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(entry.alarms.prefix(3))) { alarm in
                    HStack(spacing: 4) {
                        Text(alarm.startDate, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(alarm.title)
                            .font(.caption)
                            .fontWeight(.medium)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var inlineView: some View {
        if let next = entry.alarms.first {
            Text("\(next.title) at \(next.startDate, style: .time)")
        } else {
            EmptyView()
        }
    }
}

// MARK: - Widget

@main
struct BefoorWidget: Widget {
    let kind = "BefoorUpcomingAlarms"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: AlarmTimelineProvider()
        ) { entry in
            BefoorWidgetEntryView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Upcoming Events")
        .description("Shows events coming up in the next two hours.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}
