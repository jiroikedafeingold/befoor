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
                        title: "Fires Before Each Event",
                        detail: "You'll get a notification the configured number of minutes before each appointment — so you're never caught off guard."
                    )
                    HelpRow(
                        icon: "arrow.clockwise",
                        iconColor: .indigo,
                        title: "Stays in Sync",
                        detail: "Alarms are updated automatically whenever your calendar changes. You can also pull to refresh or tap the sync button on the Alarms tab."
                    )
                }

                // MARK: Notifications
                Section("Notifications") {
                    HelpRow(
                        icon: "bell.badge.fill",
                        iconColor: .orange,
                        title: "Up to Four Alerts Per Event",
                        detail: "Befoor sends up to four alerts per event: the first (at your lead time) and the last (at the event start) play a sound and bypass silent mode. The two middle alerts are silent banners — a gentle nudge without a second full alarm."
                    )
                    HelpRow(
                        icon: "moon.zzz.fill",
                        iconColor: .purple,
                        title: "Snooze or Dismiss",
                        detail: "Tap Snooze to be reminded again after your configured snooze duration. Tap Dismiss — or swipe the notification away — to cancel all remaining alerts for that event."
                    )
                    HelpRow(
                        icon: "hand.tap.fill",
                        iconColor: .pink,
                        title: "Tapping the Banner Snoozes",
                        detail: "Tapping the notification banner itself acts as a snooze, giving you a little more time."
                    )
                }

                // MARK: Settings
                Section("Settings") {
                    HelpRow(
                        icon: "slider.horizontal.3",
                        iconColor: .indigo,
                        title: "Lead Time",
                        detail: "Control how many minutes before each appointment the first alarm fires. Default is 7 minutes."
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
                        detail: "Pick specific calendars to watch, or leave the selection empty to monitor all calendars."
                    )
                    HelpRow(
                        icon: "speaker.wave.2.fill",
                        iconColor: .indigo,
                        title: "Alert Sound & Haptics",
                        detail: "Choose from a selection of alert sounds and toggle sound or haptics independently. Sounds play even in silent mode when the app is foregrounded."
                    )
                    HelpRow(
                        icon: "alarm.waves.left.and.right",
                        iconColor: .indigo,
                        title: "Alarm at Event Start",
                        detail: "When enabled, an additional alarm fires at the exact event start time — but only if you haven't already dismissed the earlier reminders."
                    )
                    HelpRow(
                        icon: "moon.fill",
                        iconColor: .indigo,
                        title: "Skip Weekends",
                        detail: "Turn this on to suppress alarms for events on Saturdays and Sundays."
                    )
                }

                // MARK: People & 1:1 Meetings
                Section("People & 1:1 Meetings") {
                    HelpRow(
                        icon: "person.2.fill",
                        iconColor: .indigo,
                        title: "People Tab",
                        detail: "Befoor automatically detects people from your 1:1 meetings and creates profiles for them. You can also add people manually."
                    )
                    HelpRow(
                        icon: "bell.badge.fill",
                        iconColor: .blue,
                        title: "Pre-Meeting Reminders",
                        detail: "30 minutes before a detected 1:1, you'll get a reminder to review your notes and follow-ups for that person."
                    )
                    HelpRow(
                        icon: "checklist",
                        iconColor: .orange,
                        title: "Follow-ups & Recurrence",
                        detail: "Track action items for each person. Mark them as recurring to automatically create the next occurrence when you complete one."
                    )
                    HelpRow(
                        icon: "note.text",
                        iconColor: .purple,
                        title: "Long-term Notes",
                        detail: "Store persistent notes about a person — career goals, preferences, or ongoing topics — that carry across meetings."
                    )
                    HelpRow(
                        icon: "magnifyingglass",
                        iconColor: .green,
                        title: "Detection Keywords",
                        detail: "Customize which calendar events are detected as 1:1 meetings by editing keywords in Settings. Default keywords include '1:1', 'one on one', 'catch up', and more."
                    )
                }

                // MARK: Tips
                Section("Tips") {
                    HelpRow(
                        icon: "bolt.fill",
                        iconColor: .yellow,
                        title: "Grant Time Sensitive Notifications",
                        detail: "In iOS Settings → Notifications → Befoor, enable Time Sensitive Notifications so alarms can break through Focus modes."
                    )
                    HelpRow(
                        icon: "iphone.radiowaves.left.and.right",
                        iconColor: .yellow,
                        title: "Allow Background App Refresh",
                        detail: "Enable Background App Refresh for Befoor in iOS Settings so alarms stay up to date even when you're not using the app."
                    )
                    HelpRow(
                        icon: "square.stack.3d.up.fill",
                        iconColor: .yellow,
                        title: "64 Notification Limit",
                        detail: "iOS allows a maximum of 64 pending local notifications. Befoor splits the budget between alarm notifications (~40 slots) and 1:1 meeting reminders (~20 slots), with a few reserved for snoozes."
                    )
                    HelpRow(
                        icon: "xmark.app.fill",
                        iconColor: .red,
                        title: "Don't Force-Quit the App",
                        detail: "Befoor plays alarm audio through a background audio session, which lets it bypass silent mode. If you swipe the app away in the app switcher, iOS ends that session and alarms will fall back to standard notification sounds that respect silent mode."
                    )
                    HelpRow(
                        icon: "shortcuts",
                        iconColor: .yellow,
                        title: "Auto-Launch with Shortcuts",
                        detail: "Create a Shortcuts automation to open Befoor every morning so it's always running in the background. Open the Shortcuts app → Automation → New Automation → Time of Day. Set a time (e.g. 7:00 AM), choose \"Run Immediately\", then add an \"Open App\" action and select Befoor. Add in a final step which is \"Go to Home Screen\". This ensures your alarms and calendar sync stay up to date each day without you having to remember to open the app."
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
    let title: String
    let detail: String

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
