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

        var seen = Set<String>()
        var alarms: [UpcomingAlarm] = []
        for model in models {
            if seen.insert(model.eventIdentifier).inserted {
                alarms.append(UpcomingAlarm(id: model.eventIdentifier, title: model.eventTitle, startDate: model.eventStartDate))
            }
        }

        return AlarmEntry(date: now, alarms: alarms)
    }
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
    private let modelContainer: ModelContainer

    init() {
        let types: [any PersistentModel.Type] = [
            Person.self, Note.self, FollowUp.self, LongTermNote.self,
            Reminder.self, DetectionKeyword.self,
            TrackedAlarmModel.self, CalendarSyncRecord.self,
        ]

        do {
            let config = ModelConfiguration(
                groupContainer: .identifier("group.com.befoor.app"),
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
