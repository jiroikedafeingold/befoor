import SwiftUI
import EventKit

struct CalendarPickerView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var calendarService = CalendarService.shared

    var body: some View {
        List {
            Section {
                Text("Choose which calendars Befoor monitors. Leave all unchecked to watch every calendar.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color.clear)

            Section("Calendars") {
                ForEach(calendarService.availableCalendars, id: \.calendarIdentifier) { cal in
                    CalendarRow(calendar: cal, isSelected: settings.selectedCalendarIdentifiers.contains(cal.calendarIdentifier)) {
                        toggle(cal)
                    }
                }
            }
        }
        .navigationTitle("Calendars")
        .onAppear { calendarService.refreshCalendars() }
    }

    private func toggle(_ cal: EKCalendar) {
        if settings.selectedCalendarIdentifiers.contains(cal.calendarIdentifier) {
            settings.selectedCalendarIdentifiers.remove(cal.calendarIdentifier)
        } else {
            settings.selectedCalendarIdentifiers.insert(cal.calendarIdentifier)
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
