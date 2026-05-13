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

struct BeforeWidgetEntryView: View {
    var entry: AlarmEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryRectangular:
            rectangularView
        case .accessoryInline:
            inlineView
        case .systemMedium:
            mediumView
        default:
            mediumView
        }
    }

    @ViewBuilder
    private var mediumView: some View {
        if entry.alarms.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "alarm")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("No upcoming events")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Coming Up")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.indigo)

                ForEach(Array(entry.alarms.prefix(3))) { alarm in
                    HStack(spacing: 10) {
                        Text(alarm.startDate, style: .time)
                            .font(.body)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .frame(width: 72, alignment: .leading)
                        Text(alarm.title)
                            .font(.body)
                            .fontWeight(.bold)
                            .lineLimit(1)
                        Spacer()
                        Text(alarm.startDate, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var rectangularView: some View {
        if entry.alarms.isEmpty {
            EmptyView()
        } else {
            ZStack {
                AccessoryWidgetBackground()
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(entry.alarms.prefix(2))) { alarm in
                        HStack(spacing: 4) {
                            Text(alarm.startDate, style: .time)
                                .font(.footnote)
                                .fontWeight(.heavy)
                                .widgetAccentable()
                            Text(alarm.title)
                                .font(.footnote)
                                .fontWeight(.bold)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 6)
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

struct BeforeWidget: Widget {
    let kind = "BefoorUpcomingAlarms"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: AlarmTimelineProvider()
        ) { entry in
            BeforeWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(.systemBackground)
                }
        }
        .configurationDisplayName("Upcoming Events")
        .description("Shows events coming up in the next two hours.")
        .supportedFamilies([.systemMedium, .accessoryRectangular, .accessoryInline])
    }
}
