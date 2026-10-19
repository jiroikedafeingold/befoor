import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Data

struct UpcomingAlarm: Identifiable {
    let id: String
    let title: String
    let startDate: Date
    var joinURL: URL?
    var isSkipped = false
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

    /// Events further out than this aren't shown.
    private static let window: TimeInterval = 7200

    /// Reload interval when nothing is on the horizon. The app reloads the timeline
    /// itself whenever the alarm set changes, so this only covers the app having
    /// been killed; it used to be 15 minutes, which woke the extension all night.
    private static let idleRefresh: TimeInterval = 6 * 3600

    func getSnapshot(in context: Context, completion: @escaping (AlarmEntry) -> Void) {
        completion(load().entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AlarmEntry>) -> Void) {
        let (entry, nextChange) = load()
        // Refresh exactly when the shown list would change, not on a fixed clock.
        let nextRefresh = nextChange ?? entry.date.addingTimeInterval(Self.idleRefresh)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    /// Reads the shared snapshot and returns the entry plus the next moment the
    /// visible list changes: the first shown event starting (it drops off) or a
    /// later event entering the two-hour window, whichever comes first.
    private func load() -> (entry: AlarmEntry, nextChange: Date?) {
        let now = Date()
        let cutoff = now.addingTimeInterval(Self.window)

        guard let url = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: "group.com.befoor.app")?
                .appendingPathComponent("tracked_alarms.json"),
              let data = try? Data(contentsOf: url),
              let models = try? JSONDecoder().decode([WidgetAlarmModel].self, from: data) else {
            return (AlarmEntry(date: now, alarms: []), nil)
        }

        var seen = Set<String>()
        var alarms: [UpcomingAlarm] = []
        var nextBeyondWindow: Date?
        for model in models.sorted(by: { $0.eventStartDate < $1.eventStartDate }) {
            guard model.eventStartDate >= now else { continue }
            if model.eventStartDate > cutoff {
                nextBeyondWindow = model.eventStartDate
                break
            }
            if seen.insert(model.eventTitle).inserted {
                alarms.append(UpcomingAlarm(
                    id: model.eventIdentifier,
                    title: model.eventTitle,
                    startDate: model.eventStartDate,
                    joinURL: model.joinURL,
                    isSkipped: model.isSkipped ?? false
                ))
            }
        }

        let candidates = [
            alarms.first?.startDate,
            nextBeyondWindow?.addingTimeInterval(-Self.window),
        ].compactMap { $0 }

        return (AlarmEntry(date: now, alarms: alarms), candidates.min())
    }
}

/// Mirrors the main app's TrackedAlarmModel for JSON decoding.
private struct WidgetAlarmModel: Codable {
    let eventIdentifier: String
    let eventTitle: String
    let eventStartDate: Date
    let joinURL: URL?
    let isSkipped: Bool?
}

// MARK: - Actions

/// IMPORTANT: copy of the intent in Befoor/Services/AlarmScheduler.swift, with
/// the same name and parameters, so the widget's buttons can create it. It's a
/// Live Activity intent, so the system runs Befoor's copy; this perform() isn't called.
struct SetMeetingSkippedIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Skip Meeting"
    static let isDiscoverable = false

    @Parameter(title: "Meeting")
    var eventIdentifier: String

    @Parameter(title: "Start")
    var start: Date

    @Parameter(title: "Skipped")
    var skipped: Bool

    init() {}

    init(eventIdentifier: String, start: Date, skipped: Bool) {
        self.eventIdentifier = eventIdentifier
        self.start = start
        self.skipped = skipped
    }

    func perform() async throws -> some IntentResult { .result() }
}

/// The widget's links can only open Befoor, which then opens the call.
private func joinLink(_ url: URL) -> URL {
    var components = URLComponents()
    components.scheme = "befoor"
    components.host = "join"
    components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
    return components.url ?? url
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
                            .strikethrough(alarm.isSkipped)
                            .lineLimit(1)
                        Spacer()
                        if alarm.isSkipped {
                            Text("Skipped")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(alarm.startDate, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let joinURL = alarm.joinURL, !alarm.isSkipped {
                            Link(destination: joinLink(joinURL)) {
                                Image(systemName: "video.fill")
                                    .font(.caption)
                                    .frame(width: 28, height: 24)
                                    .background(.indigo.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.indigo)
                            }
                            .accessibilityLabel("Join")
                        }
                        Button(intent: SetMeetingSkippedIntent(eventIdentifier: alarm.id, start: alarm.startDate,
                                                               skipped: !alarm.isSkipped)) {
                            Image(systemName: alarm.isSkipped ? "bell" : "bell.slash")
                                .font(.caption)
                                .frame(width: 28, height: 24)
                                .background(Color.secondary.opacity(0.15), in: Capsule())
                                .foregroundStyle(alarm.isSkipped ? Color.indigo : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(alarm.isSkipped ? Text("Ring") : Text("Skip"))
                    }
                    .opacity(alarm.isSkipped ? 0.6 : 1)
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
