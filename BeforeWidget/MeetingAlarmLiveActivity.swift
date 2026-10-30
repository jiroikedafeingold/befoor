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
    var joinURL: URL?
    var linkChange: String?
    var note: String?
    var participants: String?
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
                    NarrowIsland {
                        HStack(spacing: 6) {
                            IconView(size: 24, asset: "BefoorIslandIcon")
                            if let metadata {
                                Text(metadata.startDate, style: .time)
                                    .monospacedDigit()
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.leading, 4)
                    } narrow: {
                        IconView(size: 24, asset: "BefoorIslandIcon")
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    NarrowIsland {
                        HStack(spacing: 8) {
                            if let joinURL = metadata?.joinURL {
                                JoinButton(url: joinURL, color: color, compact: true)
                            }
                            MeetingCountdown(metadata: metadata)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(color)
                        }
                        .padding(.trailing, 4)
                    } narrow: {
                        MeetingCountdown(metadata: metadata)
                            .font(.headline)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                            .foregroundStyle(color)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    NarrowIsland {
                        VStack(alignment: .leading, spacing: 6) {
                            if let note = metadata?.note {
                                NoteBanner(note: note, compact: true)
                                    .lineLimit(1)
                            }
                            if let metadata {
                                Text(metadata.meetingTitle)
                                    .font(.headline)
                                    .lineLimit(1)
                            }
                            AlarmDetails(metadata: metadata, state: context.state)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                    } narrow: {
                        // A narrow island runs top to bottom: one item per line, wrapping.
                        VStack(alignment: .leading, spacing: 4) {
                            if let metadata {
                                Text(metadata.meetingTitle)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(3)
                                Text(metadata.startDate, style: .time)
                                    .font(.caption.weight(.semibold))
                                    .monospacedDigit()
                            }
                            if let note = metadata?.note {
                                NoteBanner(note: note, compact: true)
                                    .lineLimit(3)
                            }
                            if let joinURL = metadata?.joinURL {
                                JoinButton(url: joinURL, color: color, compact: true)
                            }
                            AlarmDetails(metadata: metadata, state: context.state, stacked: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } compactLeading: {
                IconView(size: 20, asset: "BefoorIslandIcon")
            } compactTrailing: {
                MeetingCountdown(metadata: metadata)
                    .frame(maxWidth: 64)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
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
    /// One item per line, for a narrow Dynamic Island.
    var stacked = false

    var body: some View {
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 3))
                             : AnyLayout(HStackLayout(spacing: 10))
        VStack(alignment: .leading, spacing: 3) {
            if let participants = metadata?.participants {
                Label("With \(participants)", systemImage: "person.2")
            }
            layout {
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
                if metadata?.linkChange != nil {
                    LinkChangeNotice(change: metadata?.linkChange)
                } else if let location = metadata?.location {
                    Label(location, systemImage: "mappin.and.ellipse")
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(stacked ? 2 : 1)
    }
}

private struct AlarmLockScreenView: View {
    let attributes: AlarmAttributes<MeetingAlarmMetadata>
    let state: AlarmPresentationState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let note = attributes.metadata?.note {
                NoteBanner(note: note)
            }
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
            HStack(alignment: .bottom) {
                AlarmDetails(metadata: attributes.metadata, state: state)
                Spacer(minLength: 8)
                if let joinURL = attributes.metadata?.joinURL {
                    JoinButton(url: joinURL, color: attributes.calendarColor)
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
#endif
