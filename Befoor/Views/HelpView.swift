import SwiftUI

struct HelpView: View {
    var body: some View {
        NavigationStack {
            List {
                // MARK: How it works
                Section("How It Works") {
                    HelpRow(
                        icon: "calendar",
                        iconColor: .indigo,
                        title: "Reads Your Calendar",
                        detail: "Befoor scans your calendars for upcoming appointments and automatically schedules alarms before each one."
                    )
                    HelpRow(
                        icon: "alarm.fill",
                        iconColor: .indigo,
                        title: "Rings Before Each Event",
                        detail: "An alarm rings the configured number of minutes before each appointment — so you're never caught off guard."
                    )
                    HelpRow(
                        icon: "arrow.clockwise",
                        iconColor: .indigo,
                        title: "Stays in Sync",
                        detail: "Alarms are updated whenever you open Befoor and periodically in the background. You can also pull to refresh or tap the sync button on the Alarms tab."
                    )
                }

                // MARK: Alarms
                Section("Alarms") {
                    HelpRow(
                        icon: "alarm.waves.left.and.right.fill",
                        iconColor: .orange,
                        title: "Real Alarms, Even on Silent",
                        detail: "Befoor's alarms are system alarms, like the Clock app's. They ring even when your iPhone is on silent or in a Focus, and even if Befoor isn't open or was swiped away."
                    )
                    HelpRow(
                        icon: "moon.zzz.fill",
                        iconColor: .purple,
                        title: "Snooze or Stop",
                        detail: "Snooze rings the alarm again after your snooze time. Stop ends it. Either way, the meeting's last alert still rings."
                    )
                    HelpRow(
                        icon: "timer",
                        iconColor: .red,
                        title: "Countdown to Your Meeting",
                        detail: "When a meeting's first alert rings, a countdown to it pops up in the Dynamic Island and on the Lock Screen, with its location and calendar. It keeps counting down after you stop the alert, rings again at the last alert, and goes away when you stop that one. There's only ever one per meeting."
                    )
                    HelpRow(
                        icon: "bell.badge.fill",
                        iconColor: .pink,
                        title: "When Alarms Are Off",
                        detail: "With Sound turned off, or if alarms aren't allowed, Befoor sends notifications instead. Those follow your ringer switch and Focus. Only the newest one stays in Notification Center, and it clears itself after 30 minutes."
                    )
                }

                // MARK: Settings
                Section("Settings") {
                    HelpRow(
                        icon: "slider.horizontal.3",
                        iconColor: .indigo,
                        title: "First and Last Alert",
                        detail: "Each meeting rings twice — by default 15 minutes and 1 minute before. Change either in Settings → Alarm Timing; set the last alert to \"at start\" to ring when the meeting begins. Meetings that start at the same time share one alarm."
                    )
                    HelpRow(
                        icon: "calendar.badge.minus",
                        iconColor: .indigo,
                        title: "Ignored Keywords",
                        detail: "Add words like \"lunch\" or \"OOO\" and any event whose title contains those words will be skipped."
                    )
                    HelpRow(
                        icon: "building.2",
                        iconColor: .indigo,
                        title: "Monitored Calendars",
                        detail: "Befoor watches all your calendars. Uncheck any you want it to ignore. Calendars you add later are watched automatically."
                    )
                    HelpRow(
                        icon: "speaker.wave.2.fill",
                        iconColor: .indigo,
                        title: "Alarm Sound",
                        detail: "Choose the sound your alarms ring with. Turn Sound off to get silent notifications instead of alarms."
                    )
                    HelpRow(
                        icon: "moon.fill",
                        iconColor: .indigo,
                        title: "Skip Weekends",
                        detail: "Turn this on to suppress alarms for events on Saturdays and Sundays."
                    )
                }

                // MARK: Tips
                Section("Tips") {
                    HelpRow(
                        icon: "bell.slash.fill",
                        iconColor: .orange,
                        title: "Skip a Meeting",
                        detail: "Swipe left on a meeting, or touch and hold it, and tap Skip. It won't ring on any of your devices. Tap Ring to undo."
                    )
                    HelpRow(
                        icon: "video.fill",
                        iconColor: .green,
                        title: "Join a Call",
                        detail: "Meetings with a Zoom, Google Meet, Teams or Webex link get a Join button, in the list and on the countdown."
                    )
                    HelpRow(
                        icon: "speaker.wave.1.fill",
                        iconColor: .indigo,
                        title: "Back-to-Back Meetings",
                        detail: "When an alert comes while another meeting is still going, it vibrates first and only plays its sound after 15 seconds, so you can stop it quietly."
                    )
                    HelpRow(
                        icon: "exclamationmark.triangle.fill",
                        iconColor: .orange,
                        title: "Video Link Warnings",
                        detail: "If a meeting's Zoom, Meet or Teams link is removed or changed, Befoor flags it in the list and on the countdown, and sends a notification when the meeting is less than two hours away."
                    )
                    HelpRow(
                        icon: "pause.circle.fill",
                        iconColor: .orange,
                        title: "Pause for a Vacation",
                        detail: "In Settings → Pause, choose when to resume. Meetings before then don't ring; alarms come back on their own afterwards."
                    )
                    HelpRow(
                        icon: "mic.fill",
                        iconColor: .purple,
                        title: "Ask Siri",
                        detail: "Say \"When's my next meeting in Befoor\", \"Join my next Befoor meeting\" or \"Skip my next meeting in Befoor\". The same actions are in the Shortcuts app."
                    )
                    HelpRow(
                        icon: "arrow.clockwise",
                        iconColor: .blue,
                        title: "Last-Minute Meetings",
                        detail: "iOS lets Befoor check your calendar only now and then while it's closed. To catch meetings added at the last minute, create a Shortcuts automation, such as \"When Calendar is closed\", that runs Sync Befoor."
                    )
                    HelpRow(
                        icon: "checkmark.shield.fill",
                        iconColor: .yellow,
                        title: "Allow Alarms",
                        detail: "If alarms aren't ringing, check Settings → Alarm Sound in Befoor. If it says alarms are off, turn them back on for Befoor in iOS Settings."
                    )
                    HelpRow(
                        icon: "iphone.radiowaves.left.and.right",
                        iconColor: .yellow,
                        title: "Allow Background App Refresh",
                        detail: "Enable Background App Refresh for Befoor in iOS Settings so calendar changes are picked up even when you haven't opened the app."
                    )
                    HelpRow(
                        icon: "bolt.fill",
                        iconColor: .yellow,
                        title: "Grant Time Sensitive Notifications",
                        detail: "In iOS Settings → Notifications → Befoor, enable Time Sensitive Notifications so meeting notifications can break through Focus modes when alarms are off."
                    )
                }

                // MARK: Credits
                Section("Credits") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Alert Sounds")
                            .font(.body.weight(.medium))
                        Text("The ringtone sounds included in Befoor were created by **Jeff Essex** and **Joel Hladecek**.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Link(destination: URL(string: "https://www.theinteractivist.com/free-ringtones-iringpro/")!) {
                            Label("theinteractivist.com", systemImage: "link")
                                .font(.footnote)
                        }
                        .tint(.indigo)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Help")
        }
    }
}

// MARK: - HelpRow

private struct HelpRow: View {
    let icon: String
    let iconColor: Color
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(iconColor)
                .frame(width: 28, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    HelpView()
}
