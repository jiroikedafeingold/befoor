import WidgetKit
import SwiftUI
import SwiftData

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
    let modelContainer: ModelContainer

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
        let context = ModelContext(modelContainer)
        let now = Date()
        let cutoff = now.addingTimeInterval(7200)

        let descriptor = FetchDescriptor<TrackedAlarmModel>(
            predicate: #Predicate<TrackedAlarmModel> { alarm in
                alarm.eventStartDate >= now && alarm.eventStartDate <= cutoff
            },
            sortBy: [SortDescriptor(\.eventStartDate)]
        )

        let models = (try? context.fetch(descriptor)) ?? []
        let alarms = models.map {
            UpcomingAlarm(id: $0.eventIdentifier, title: $0.eventTitle, startDate: $0.eventStartDate)
        }

        return AlarmEntry(date: now, alarms: alarms)
    }
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
    private let modelContainer: ModelContainer

    init() {
        let types: [any PersistentModel.Type] = [
            Person.self, Note.self, FollowUp.self, LongTermNote.self,
            Reminder.self, DetectionKeyword.self,
            TrackedAlarmModel.self, CalendarSyncRecord.self,
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

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: AlarmTimelineProvider(modelContainer: modelContainer)
        ) { entry in
            BefoorWidgetEntryView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Upcoming Events")
        .description("Shows events coming up in the next two hours.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}
