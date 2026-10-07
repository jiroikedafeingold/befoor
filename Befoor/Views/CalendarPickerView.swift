import SwiftUI
import EventKit

struct CalendarPickerView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var calendarService = CalendarService.shared

    var body: some View {
        List {
            Section {
                Text("Befoor watches every checked calendar. Uncheck any you want it to ignore. Calendars you add later are watched automatically.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color.clear)

            Section("Calendars") {
                ForEach(calendarService.availableCalendars, id: \.calendarIdentifier) { cal in
                    CalendarRow(calendar: cal, isSelected: !settings.excludedCalendarIdentifiers.contains(cal.calendarIdentifier)) {
                        toggle(cal)
                    }
                }
            }
        }
        .navigationTitle("Calendars")
        .onAppear {
            // Convert an old-style selection before showing checkmarks for it.
            settings.migrateCalendarSelectionIfNeeded(allCalendarIdentifiers: calendarService.allCalendarIdentifiers)
            calendarService.refreshCalendars()
        }
        // Reschedule alarms for the new set of calendars.
        .onChange(of: settings.excludedCalendarIdentifiers) { _, _ in
            AlarmScheduler.shared.requestResync()
        }
    }

    private func toggle(_ cal: EKCalendar) {
        if settings.excludedCalendarIdentifiers.contains(cal.calendarIdentifier) {
            settings.excludedCalendarIdentifiers.remove(cal.calendarIdentifier)
        } else {
            settings.excludedCalendarIdentifiers.insert(cal.calendarIdentifier)
        }
    }
}

private struct CalendarRow: View {
    let calendar: EKCalendar
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(cgColor: calendar.cgColor))
                    .frame(width: 14, height: 14)

                Text(calendar.title)
                    .foregroundStyle(.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}
