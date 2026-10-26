#if !targetEnvironment(macCatalyst)
import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Attributes

/// IMPORTANT: identical copy of the type in Befoor/Services/MeetingLiveActivity.swift.
/// ActivityKit matches the two by type name and Codable shape — keep them in sync.
struct NextMeetingAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var meetingID: String
        var title: String
        var startDate: Date
        var endDate: Date?
        var alarmDate: Date?
        var calendarName: String?
        var calendarRGB: [Double]?
        var location: String?
        var attendeeCount: Int
        var nextTitle: String?
        var nextStartDate: Date?
        var joinURL: URL?
        var linkChange: String?
        var note: String?
    }
}

private extension NextMeetingAttributes.ContentState {
    var calendarColor: Color {
        guard let rgb = calendarRGB, rgb.count == 3 else { return .indigo }
        return Color(.sRGB, red: rgb[0], green: rgb[1], blue: rgb[2])
    }

    /// The window the minimal gauge drains over: from the alarm (or 15 min before) to the start.
    var countdownRange: ClosedRange<Date> {
        let lower = min(alarmDate ?? startDate.addingTimeInterval(-900),
                        startDate.addingTimeInterval(-60))
        return lower...startDate
    }
}

// MARK: - Live Activity

struct NextMeetingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NextMeetingAttributes.self) { context in
            LockScreenMeetingView(state: context.state, isStale: context.isStale)
                .activitySystemActionForegroundColor(context.state.calendarColor)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        AppIconView(size: 24, asset: "BefoorIslandIcon")
                        Text(state.startDate, style: .time)
                            .monospacedDigit()
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 8) {
                        if let joinURL = state.joinURL {
                            JoinButton(url: joinURL, color: state.calendarColor, compact: true)
                        }
                        CountdownText(startDate: state.startDate, isStale: context.isStale)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(state.calendarColor)
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let note = state.note {
                            NoteBanner(note: note, compact: true)
                                .lineLimit(1)
                        }
                        Text(state.title)
                            .font(.headline)
                            .lineLimit(1)
                        // The island has a fixed height: with a note, drop the extras.
                        MeetingDetailsView(state: state, showExtras: state.note == nil)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                AppIconView(size: 20, asset: "BefoorIslandIcon")
            } compactTrailing: {
                CountdownText(startDate: state.startDate, isStale: context.isStale)
                    .frame(maxWidth: 64)
                    .foregroundStyle(state.calendarColor)
            } minimal: {
                ProgressView(timerInterval: state.countdownRange, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    Image(systemName: "calendar")
                        .font(.caption2)
                }
                .progressViewStyle(.circular)
                .tint(state.calendarColor)
            }
            .keylineTint(state.calendarColor)
        }
    }
}

// MARK: - Views

/// Befoor's alarm-clock icon, a small cut-out copy in the widget's assets (a Live
/// Activity may fail to start if an image is larger than where it's shown).
private struct AppIconView: View {
    let size: CGFloat
    /// The Dynamic Island uses a pixel-art clock; the Lock Screen the smooth one.
    var asset = "BefoorIcon"

    var body: some View {
        Image(asset)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

/// Counts down to the start; the system animates it, so no updates are needed.
private struct CountdownText: View {
    let startDate: Date
    let isStale: Bool

    var body: some View {
        if isStale || startDate <= .now {
            Text("Now")
        } else {
            Text(timerInterval: Date.now...startDate, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }
}

/// The "quick information" rows shared by the expanded island and the Lock Screen.
private struct MeetingDetailsView: View {
    let state: NextMeetingAttributes.ContentState
    /// Attendee count and the following meeting; left out when space is short.
    var showExtras = true

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            LinkChangeNotice(change: state.linkChange)

            if let location = state.location {
                Label(location, systemImage: "mappin.and.ellipse")
            }

            if showExtras && state.attendeeCount > 0 {
                Label("\(state.attendeeCount) attendees", systemImage: "person.2")
            }

            HStack(spacing: 10) {
                if let calendar = state.calendarName {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(state.calendarColor)
                            .frame(width: 7, height: 7)
                        Text(calendar)
                    }
                }
                if let end = state.endDate {
                    Text("until \(end, style: .time)")
                }
                if let alarm = state.alarmDate {
                    Label {
                        Text(alarm, style: .time)
                    } icon: {
                        Image(systemName: "alarm")
                    }
                }
            }

            if showExtras, let nextTitle = state.nextTitle, let nextStart = state.nextStartDate {
                Text("Then \(nextTitle) at \(nextStart, style: .time)")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

private struct LockScreenMeetingView: View {
    let state: NextMeetingAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let note = state.note {
                NoteBanner(note: note)
            }
            HStack(alignment: .center, spacing: 10) {
                AppIconView(size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next meeting · \(state.startDate, style: .time)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(state.calendarColor)
                    Text(state.title)
                        .font(.headline)
                        .lineLimit(1)
                }
                Spacer()
                CountdownText(startDate: state.startDate, isStale: isStale)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(state.calendarColor)
                    .frame(maxWidth: 110, alignment: .trailing)
            }
            HStack(alignment: .bottom) {
                // Live Activities are cut off past ~160 pt: with a note, drop the extras.
                MeetingDetailsView(state: state, showExtras: state.note == nil)
                Spacer(minLength: 8)
                if let joinURL = state.joinURL {
                    JoinButton(url: joinURL, color: state.calendarColor)
                }
            }
        }
        .padding(16)
    }
}

/// Warns that the meeting's video-call link was removed or replaced since
/// Befoor first saw it — check the invite before joining.
private struct LinkChangeNotice: View {
    let change: String?

    var body: some View {
        if let change {
            Label(change == "removed" ? "Link removed" : "Link changed",
                  systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}

/// The person's note for the meeting, highlighted like a sticky note.
private struct NoteBanner: View {
    let note: String
    /// Smaller, for the Dynamic Island's fixed height.
    var compact = false

    var body: some View {
        Label {
            Text(note)
                .lineLimit(2)
        } icon: {
            Text(verbatim: "👉🏽")
        }
        .font((compact ? Font.caption : .subheadline).weight(.semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 3 : 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Join

/// A Live Activity's links can only open its own app, so Join opens Befoor,
/// which opens the call (see ContentView's onOpenURL).
private func joinLink(_ url: URL) -> URL {
    var components = URLComponents()
    components.scheme = "befoor"
    components.host = "join"
    components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
    return components.url ?? url
}

private struct JoinLabelStyle: LabelStyle {
    let iconOnly: Bool

    func makeBody(configuration: Configuration) -> some View {
        if iconOnly {
            configuration.icon
        } else {
            Label(configuration)
        }
    }
}

private struct JoinButton: View {
    let url: URL
    let color: Color
    /// Icon only and no taller than a line of text, for the Dynamic Island.
    var compact = false

    var body: some View {
        Link(destination: joinLink(url)) {
            Label("Join", systemImage: "video.fill")
                .labelStyle(JoinLabelStyle(iconOnly: compact))
                .font((compact ? Font.caption2 : .caption).weight(.semibold))
                .padding(.horizontal, compact ? 8 : 10)
                .padding(.vertical, compact ? 1 : 4)
                .background(color.opacity(0.2), in: Capsule())
                .foregroundStyle(color)
                .fixedSize()
        }
        .accessibilityLabel("Join")
    }
}

#Preview("Island expanded", as: .dynamicIsland(.expanded), using: NextMeetingAttributes()) {
    NextMeetingLiveActivity()
} contentStates: {
    NextMeetingAttributes.ContentState(
        meetingID: "preview",
        title: "Design Review",
        startDate: .now.addingTimeInterval(1500),
        endDate: .now.addingTimeInterval(3300),
        alarmDate: .now.addingTimeInterval(600),
        calendarName: "Work",
        calendarRGB: [0.2, 0.5, 0.9],
        location: "Room 4B",
        attendeeCount: 4,
        nextTitle: "Product Sync",
        nextStartDate: .now.addingTimeInterval(7200),
        joinURL: URL(string: "https://zoom.us/j/123456789"),
        note: "Ask about the Q3 budget"
    )
}
#endif
