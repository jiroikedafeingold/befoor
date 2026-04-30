import SwiftUI

struct ContentView: View {
    @ObservedObject private var scheduler  = AlarmScheduler.shared
    @ObservedObject private var store      = TrackedAlarmsStore.shared
    @ObservedObject private var settings   = AppSettings.shared
    @ObservedObject private var calService = CalendarService.shared
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            alarmsTab
                .tabItem {
                    Label("Alarms", systemImage: "alarm")
                }
                .tag(0)

            PeopleTabView()
                .tabItem {
                    Label("People", systemImage: "person.2")
                }
                .tag(1)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(2)

            HelpView()
                .tabItem {
                    Label("Help", systemImage: "questionmark.circle")
                }
                .tag(3)
        }
        .tint(.indigo)
        .onReceive(NotificationCenter.default.publisher(for: .navigateToPerson)) { _ in
            // Switch to the People tab; PeopleTabView handles the rest
            selectedTab = 1
        }
        .task {
            // Configure TrackedAlarmsStore and AlarmScheduler with SwiftData context
            TrackedAlarmsStore.shared.configure(with: modelContext)
            AlarmScheduler.shared.modelContext = modelContext

            // Onboarding handles first-launch permissions; just sync on subsequent launches.
            if settings.hasCompletedOnboarding {
                await AlarmScheduler.shared.sync()
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { !settings.hasCompletedOnboarding },
            set: { if !$0 { settings.hasCompletedOnboarding = true } }
        )) {
            OnboardingView()
        }
    }

    // MARK: - Alarms Tab

    private var alarmsTab: some View {
        NavigationStack {
            Group {
                if store.alarms.isEmpty {
                    emptyState
                } else {
                    alarmsList
                }
            }
            .navigationTitle("Befoor")
            .toolbar { toolbarContent }
            .refreshable { await AlarmScheduler.shared.sync() }
        }
    }

    private var alarmsList: some View {
        List {
            if !settings.isEnabled {
                Section {
                    Label("Befoor is paused. Enable it in Settings.", systemImage: "pause.circle")
                        .foregroundStyle(.orange)
                        .font(.footnote)
                }
                .listRowBackground(Color.orange.opacity(0.1))
            }

            Section("Today's Alarms") {
                ForEach(sortedAlarms) { alarm in
                    AlarmRow(alarm: alarm)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "alarm")
                .font(.system(size: 64))
                .foregroundStyle(.indigo.opacity(0.5))

            Text("No alarms today")
                .font(.title3.weight(.semibold))

            Text(settings.isEnabled
                 ? "No appointments found for today in your selected calendars."
                 : "Befoor is paused. Enable it in Settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Sync Calendar") {
                Task { await AlarmScheduler.shared.sync() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
            .disabled(scheduler.syncInProgress)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            if scheduler.syncInProgress {
                ProgressView()
                    .tint(.indigo)
            } else {
                Button {
                    Task { await AlarmScheduler.shared.sync() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }

        ToolbarItem(placement: .navigationBarLeading) {
            Image(systemName: settings.isEnabled ? "checkmark.circle.fill" : "pause.circle.fill")
                .foregroundStyle(settings.isEnabled ? .green : .secondary)
                .accessibilityLabel(settings.isEnabled ? "Active" : "Paused")
        }
    }

    // MARK: - Helpers

    private var sortedAlarms: [TrackedAlarmModel] {
        let calendar = Calendar.current
        return store.alarms.values
            .filter { calendar.isDateInToday($0.eventStartDate) }
            .sorted { $0.eventStartDate < $1.eventStartDate }
    }

}

// MARK: - Alarm Row

private struct AlarmRow: View {
    let alarm: TrackedAlarmModel
    @ObservedObject private var calService = CalendarService.shared

    private var calendarColor: Color {
        if let cal = calService.calendar(for: alarm.calendarIdentifier) {
            return Color(cgColor: cal.cgColor)
        }
        return .indigo
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(alarm.eventTitle)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Circle()
                        .fill(calendarColor)
                        .frame(width: 8, height: 8)

                    Text(alarm.eventStartDate, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("·")
                        .foregroundStyle(.secondary)

                    Text(alarm.eventStartDate, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "alarm.fill")
                .foregroundStyle(.indigo.opacity(0.7))
                .font(.caption)
        }
        .padding(.vertical, 2)
    }
}


#Preview {
    ContentView()
}
