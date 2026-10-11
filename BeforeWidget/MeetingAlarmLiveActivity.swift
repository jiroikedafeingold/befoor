#if !targetEnvironment(macCatalyst)
import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

// MARK: - Metadata

/// IMPORTANT: identical copy of the type in Befoor/Services/MeetingAlarms.swift.
/// ActivityKit matches the two by type name and Codable shape — keep them in sync.
struct MeetingAlarmMetadata: AlarmMetadata {
    var meetingTitle: String
    var startDate: Date
    var location: String?
    /// sRGB components of the calendar color.
    var calendarRGB: [Double]?
}

private extension AlarmAttributes<MeetingAlarmMetadata> {
    var calendarColor: Color {
        guard let rgb = metadata?.calendarRGB, rgb.count == 3 else { return .indigo }
        return Color(.sRGB, red: rgb[0], green: rgb[1], blue: rgb[2])
    }
}

// MARK: - Live Activity

/// The Live Activity AlarmKit shows for a meeting alarm outside its ringing
/// screen — mainly while it's snoozed, counting down to the next ring.
struct MeetingAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<MeetingAlarmMetadata>.self) { context in
            AlarmLockScreenView(attributes: context.attributes, state: context.state)
                .activitySystemActionForegroundColor(context.attributes.calendarColor)
        } dynamicIsland: { context in
            let color = context.attributes.calendarColor
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Snoozed", systemImage: "zzz")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(color)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RingCountdown(state: context.state)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(color)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    MeetingSummary(metadata: context.attributes.metadata)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: "alarm")
                    .foregroundStyle(color)
            } compactTrailing: {
                RingCountdown(state: context.state)
                    .frame(maxWidth: 64)
                    .foregroundStyle(color)
            } minimal: {
                Image(systemName: "alarm")
                    .foregroundStyle(color)
            }
            .keylineTint(color)
        }
    }
}

// MARK: - Views

/// Time until the snoozed alarm rings again.
private struct RingCountdown: View {
    let state: AlarmPresentationState

    var body: some View {
        switch state.mode {
        case .countdown(let countdown) where countdown.fireDate > .now:
            Text(timerInterval: Date.now...countdown.fireDate, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        case .paused:
            Text("Paused")
        default:
            Image(systemName: "alarm.waves.left.and.right")
        }
    }
}

private struct MeetingSummary: View {
    let metadata: MeetingAlarmMetadata?

    var body: some View {
        if let metadata {
            VStack(alignment: .leading, spacing: 3) {
                Text(metadata.meetingTitle)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 10) {
                    Text("Starts \(metadata.startDate, style: .time)")
                    if let location = metadata.location {
                        Label(location, systemImage: "mappin.and.ellipse")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
    }
}

private struct AlarmLockScreenView: View {
    let attributes: AlarmAttributes<MeetingAlarmMetadata>
    let state: AlarmPresentationState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label("Snoozed", systemImage: "zzz")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(attributes.calendarColor)
                Spacer()
                RingCountdown(state: state)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(attributes.calendarColor)
                    .frame(maxWidth: 110, alignment: .trailing)
            }
            MeetingSummary(metadata: attributes.metadata)
        }
        .padding(16)
    }
}
#endif
