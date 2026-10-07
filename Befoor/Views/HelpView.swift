import SwiftUI

struct HelpView: View {
    @ObservedObject private var settings = AppSettings.shared

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
                        detail: "Snooze rings the alarm again after your snooze time, and the meeting's later alerts still ring. Stop ends it and skips that meeting's remaining alerts."
                    )
                    HelpRow(
                        icon: "timer",
                        iconColor: .red,
                        title: "Countdown to Your Meeting",
                        detail: "When you stop an alarm, a countdown to the meeting appears in the Dynamic Island and on the Lock Screen, with its location, calendar and who it's with. Turn it off under Live Activity in Settings."
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
                        title: "Three Alerts",
                        detail: "Each meeting rings up to three times — by default 15, 7 and 1 minute before. Change any of them in Settings → Alarm Timing; set one to \"at start\" to ring when the meeting begins."
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

                // MARK: People & 1:1 Meetings
                if settings.peopleEnabled {
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
                }

                // MARK: Tips
                Section("Tips") {
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
                        detail: settings.peopleEnabled
                            ? "In iOS Settings → Notifications → Befoor, enable Time Sensitive Notifications so 1:1 reminders, and meeting notifications when alarms are off, can break through Focus modes."
                            : "In iOS Settings → Notifications → Befoor, enable Time Sensitive Notifications so meeting notifications can break through Focus modes when alarms are off."
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
