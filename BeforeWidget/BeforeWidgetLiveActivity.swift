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
        var personName: String?
        var followUp: String?
        var attendeeCount: Int
        var nextTitle: String?
        var nextStartDate: Date?
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
                .activitySystemActionForegroundColor(.indigo)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .foregroundStyle(state.calendarColor)
                        Text(state.startDate, style: .time)
                            .monospacedDigit()
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CountdownText(startDate: state.startDate, isStale: context.isStale)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.indigo)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(state.title)
                            .font(.headline)
                            .lineLimit(1)
                        MeetingDetailsView(state: state)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: "calendar")
                    .foregroundStyle(state.calendarColor)
            } compactTrailing: {
                CountdownText(startDate: state.startDate, isStale: context.isStale)
                    .frame(maxWidth: 64)
                    .foregroundStyle(.indigo)
            } minimal: {
                ProgressView(timerInterval: state.countdownRange, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    Image(systemName: "calendar")
                        .font(.caption2)
                }
                .progressViewStyle(.circular)
                .tint(.indigo)
            }
            .keylineTint(.indigo)
        }
    }
}

// MARK: - Views

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

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let location = state.location {
                Label(location, systemImage: "mappin.and.ellipse")
            }

            if let person = state.personName {
                Label("1:1 with \(person)", systemImage: "person.fill")
                if let followUp = state.followUp {
                    Label(followUp, systemImage: "checklist")
                }
            } else if state.attendeeCount > 0 {
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

            if let nextTitle = state.nextTitle, let nextStart = state.nextStartDate {
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
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next meeting · \(state.startDate, style: .time)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.indigo)
                    Text(state.title)
                        .font(.headline)
                        .lineLimit(1)
                }
                Spacer()
                CountdownText(startDate: state.startDate, isStale: isStale)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.indigo)
                    .frame(maxWidth: 110, alignment: .trailing)
            }
            MeetingDetailsView(state: state)
        }
        .padding(16)
    }
}

#Preview("Island expanded", as: .dynamicIsland(.expanded), using: NextMeetingAttributes()) {
    NextMeetingLiveActivity()
} contentStates: {
    NextMeetingAttributes.ContentState(
        meetingID: "preview",
        title: "1:1 with Maya Chen",
        startDate: .now.addingTimeInterval(1500),
        endDate: .now.addingTimeInterval(3300),
        alarmDate: nil,
        calendarName: "Work",
        calendarRGB: [0.2, 0.5, 0.9],
        location: "Room 4B",
        personName: "Maya Chen",
        followUp: "Share Q4 roadmap draft",
        attendeeCount: 2,
        nextTitle: "Product Sync",
        nextStartDate: .now.addingTimeInterval(7200)
    )
}
#endif
