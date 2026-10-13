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

/// The Live Activity AlarmKit shows for a meeting alarm while it rings, is
/// snoozed, or counts down to the meeting's next alert. It's the meeting's
/// countdown during that time (Befoor's own one stays away so there's only one
/// per meeting), so it looks like it: the meeting, time left until it starts in
/// the calendar's color, and when the alarm rings next.
struct MeetingAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<MeetingAlarmMetadata>.self) { context in
            AlarmLockScreenView(attributes: context.attributes, state: context.state)
                .activitySystemActionForegroundColor(context.attributes.calendarColor)
        } dynamicIsland: { context in
            let color = context.attributes.calendarColor
            let metadata = context.attributes.metadata
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        IconView(size: 24, asset: "BefoorIslandIcon")
                        if let metadata {
                            Text(metadata.startDate, style: .time)
                                .monospacedDigit()
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    MeetingCountdown(metadata: metadata)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(color)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let metadata {
                            Text(metadata.meetingTitle)
                                .font(.headline)
                                .lineLimit(1)
                        }
                        AlarmDetails(metadata: metadata, state: context.state)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                IconView(size: 20, asset: "BefoorIslandIcon")
            } compactTrailing: {
                MeetingCountdown(metadata: metadata)
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

/// Befoor's alarm-clock icon, from the small cut-out copy in the widget's assets.
private struct IconView: View {
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

/// Time left until the meeting starts; the system animates it.
private struct MeetingCountdown: View {
    let metadata: MeetingAlarmMetadata?

    var body: some View {
        if let start = metadata?.startDate, start > .now {
            Text(timerInterval: Date.now...start, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        } else {
            Text("Now")
        }
    }
}

/// Where the meeting is and what the alarm does next.
private struct AlarmDetails: View {
    let metadata: MeetingAlarmMetadata?
    let state: AlarmPresentationState

    var body: some View {
        HStack(spacing: 10) {
            switch state.mode {
            case .countdown(let countdown):
                Label {
                    Text("Rings at \(countdown.fireDate, style: .time)")
                } icon: {
                    Image(systemName: "alarm")
                }
            case .paused:
                Label("Paused", systemImage: "pause")
            default:
                Label("Ringing", systemImage: "alarm.waves.left.and.right")
            }
            if let location = metadata?.location {
                Label(location, systemImage: "mappin.and.ellipse")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

private struct AlarmLockScreenView: View {
    let attributes: AlarmAttributes<MeetingAlarmMetadata>
    let state: AlarmPresentationState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                IconView(size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    if let metadata = attributes.metadata {
                        Text("Next meeting · \(metadata.startDate, style: .time)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(attributes.calendarColor)
                        Text(metadata.meetingTitle)
                            .font(.headline)
                            .lineLimit(1)
                    }
                }
                Spacer()
                MeetingCountdown(metadata: attributes.metadata)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(attributes.calendarColor)
                    .frame(maxWidth: 110, alignment: .trailing)
            }
            AlarmDetails(metadata: attributes.metadata, state: state)
        }
        .padding(16)
    }
}
#endif
