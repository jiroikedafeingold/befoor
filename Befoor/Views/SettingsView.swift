import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var scheduler = AlarmScheduler.shared
    @ObservedObject private var soundPlayer = SoundPlayer.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var newKeyword = ""
    @State private var showAddKeyword = false
    @State private var newAlertKeyword = ""
    @State private var newAlertMinutes = 30
    @State private var showAddAlertKeyword = false
    @State private var alarmsAllowed = false
    @State private var testPending = false

    /// How long after tapping Test Alert it rings.
    private static let testDelay: TimeInterval = 10

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Master switch
                Section {
                    Toggle("Enable Dingly", isOn: $settings.isEnabled)
                        .tint(.indigo)
                } footer: {
                    Text("When disabled, all scheduled alarms are cancelled.")
                }

                // MARK: Timing
                Section {
                    Stepper(
                        "First alert: \(alertLabel(settings.leadTimeMinutes))",
                        value: $settings.leadTimeMinutes,
                        in: AppSettings.firstAlertRange
                    )
                    Stepper(
                        "Last alert: \(alertLabel(settings.lastAlertMinutes))",
                        value: $settings.lastAlertMinutes,
                        in: AppSettings.laterAlertRange
                    )

                    Stepper(
                        "Snooze \(settings.snoozeDurationMinutes) minutes",
                        value: $settings.snoozeDurationMinutes,
                        in: 1...30
                    )

                    Stepper(
                        "Look ahead \(settings.lookAheadDays) days",
                        value: $settings.lookAheadDays,
                        in: 1...30
                    )

                    Toggle("Skip weekends", isOn: $settings.skipWeekends)
                        .tint(.indigo)
                } header: {
                    Text("Alarm Timing")
                } footer: {
                    Text("Each meeting rings at the first alert, when its countdown appears, and again at the last alert. Meetings that start at the same time share one alarm.")
                }

                // MARK: Pause
                Section {
                    Toggle("Pause Until", isOn: Binding(
                        get: { settings.pausedUntil != nil },
                        set: { settings.pausedUntil = $0 ? Self.defaultPauseEnd : nil }
                    ))
                    .tint(.indigo)
                    if let until = settings.pausedUntil {
                        DatePicker("Resume", selection: Binding(
                            get: { until },
                            set: { settings.pausedUntil = $0 }
                        ), in: Date()...)
                    }
                } header: {
                    Text("Pause")
                } footer: {
                    Text("No alarms for meetings before this date, for a vacation or a day off. Alarms come back on their own afterwards.")
                }
                .onChange(of: settings.pausedUntil) { _, _ in
                    Task { await AlarmScheduler.shared.sync(force: true) }
                }

                // MARK: Morning summary
                Section {
                    Toggle("Morning Summary", isOn: $settings.morningSummaryEnabled)
                        .tint(.indigo)
                    if settings.morningSummaryEnabled {
                        DatePicker("Time", selection: Binding(
                            get: { Calendar.current.startOfDay(for: .now).addingTimeInterval(Double(settings.morningSummaryMinutes) * 60) },
                            set: {
                                let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
                                settings.morningSummaryMinutes = (parts.hour ?? 7) * 60 + (parts.minute ?? 30)
                            }
                        ), displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    Text("A quiet notification each morning with how many meetings you have and when the first one starts.")
                }
                .onChange(of: settings.morningSummaryEnabled) { _, on in
                    if on { Task { await NotificationService.shared.requestPermission() } }
                    AlarmScheduler.shared.requestResync()
                }
                .onChange(of: settings.morningSummaryMinutes) { _, _ in AlarmScheduler.shared.requestResync() }

                // MARK: Live Activity
                Section {
                    Toggle("Next Meeting Countdown", isOn: $settings.liveActivityEnabled)
                        .tint(.indigo)
                        .onChange(of: settings.liveActivityEnabled) { _, _ in
                            Task { await MeetingLiveActivityManager.shared.refresh() }
                        }
                } header: {
                    Text("Live Activity")
                } footer: {
                    Text("Pops up by itself when a meeting's first alert rings: a countdown in the Dynamic Island and on the Lock Screen, with its location and calendar. It keeps counting down after you stop the alert and goes away when you stop the last one. Press and hold the Dynamic Island for details. iPhone only.")
                }

                // MARK: Calendars
                Section("Calendars") {
                    NavigationLink {
                        CalendarPickerView()
                    } label: {
                        HStack {
                            Text("Monitored Calendars")
                            Spacer()
                            Text(settings.excludedCalendarIdentifiers.isEmpty
                                 ? String(localized: "All")
                                 : String(localized: "\(settings.excludedCalendarIdentifiers.count) off"))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // MARK: Ignored keywords
                Section {
                    ForEach(settings.ignoredKeywords, id: \.self) { keyword in
                        HStack {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                                .onTapGesture { remove(keyword: keyword) }
                            Text(keyword)
                        }
                    }

                    if showAddKeyword {
                        HStack {
                            TextField("e.g. lunch", text: $newKeyword)
                                .autocorrectionDisabled()
                            Button("Add") { addKeyword() }
                                .disabled(newKeyword.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    } else {
                        Button {
                            showAddKeyword = true
                        } label: {
                            Label("Add Keyword", systemImage: "plus.circle")
                        }
                    }
                } header: {
                    Text("Ignored Keywords")
                } footer: {
                    Text("Events whose titles contain any of these words (case-insensitive) will be skipped.")
                }

                // MARK: Sound
                Section {
                    alarmPermissionRow

                    Toggle("Sound", isOn: $settings.soundEnabled)
                        .tint(.indigo)

                    ForEach(BefoorSound.allCases) { sound in
                        SoundRow(
                            sound: sound,
                            isSelected: settings.selectedSound == sound,
                            isPlaying: soundPlayer.playingSound == sound
                        ) {
                            settings.selectedSound = sound
                        } onPreview: {
                            if soundPlayer.playingSound == sound {
                                soundPlayer.stop()
                            } else {
                                soundPlayer.preview(sound)
                            }
                        }
                    }
                } header: {
                    Text("Alarm Sound")
                } footer: {
                    Text("Dingly rings a real alarm before each meeting, so it sounds even when your iPhone is on silent or in a Focus, and works even if Dingly isn't open. With Sound off, or if alarms aren't allowed, you get notifications instead, which follow your ringer switch.")
                }

                // MARK: Keyword alerts
                Section {
                    ForEach(settings.keywordFirstAlerts.keys.sorted(), id: \.self) { keyword in
                        HStack {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                                .onTapGesture { settings.keywordFirstAlerts[keyword] = nil }
                            Text(keyword)
                            Spacer()
                            Text("\(settings.keywordFirstAlerts[keyword] ?? 0) min before")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if showAddAlertKeyword {
                        TextField("e.g. kid pickup", text: $newAlertKeyword)
                            .autocorrectionDisabled()
                        Picker("First alert", selection: $newAlertMinutes) {
                            ForEach(keywordAlertChoices, id: \.self) { minutes in
                                Text("\(minutes) min before").tag(minutes)
                            }
                        }
                        Button("Add") { addKeywordAlert() }
                            .disabled(newAlertKeyword.trimmingCharacters(in: .whitespaces).isEmpty)
                    } else {
                        Button {
                            showAddAlertKeyword = true
                        } label: {
                            Label("Add Keyword Alert", systemImage: "plus.circle")
                        }
                    }
                } header: {
                    Text("Keyword Alerts")
                } footer: {
                    Text("Meetings whose titles contain one of these words (case-insensitive) get their first alert at the time you set, instead of First Alert.")
                }

                // MARK: Background refresh
                Section {
                    Picker("Check interval", selection: $settings.backgroundCheckIntervalMinutes) {
                        Text("15 min").tag(15)
                        Text("30 min").tag(30)
                        Text("1 hour").tag(60)
                        Text("2 hours").tag(120)
                    }
                } header: {
                    Text("Background Sync")
                } footer: {
                    Text("iOS may delay or batch background checks to preserve battery. To catch meetings added while Dingly is closed, add a Shortcuts automation, such as \"When Calendar is closed\", that runs Sync Dingly.")
                }

                // MARK: Manual sync
                Section {
                    Button {
                        Task { await AlarmScheduler.shared.sync(force: true) }
                    } label: {
                        HStack {
                            Label("Sync Now", systemImage: "arrow.clockwise")
                            Spacer()
                            if scheduler.syncInProgress {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(scheduler.syncInProgress)

                    if let date = scheduler.lastSyncDate {
                        HStack {
                            Text("Last sync")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(date, style: .relative)
                                .foregroundStyle(.secondary)
                                .font(.footnote)
                        }
                    }

                    Button {
                        settings.hasCompletedOnboarding = false
                    } label: {
                        Label("Restart Onboarding", systemImage: "arrow.counterclockwise")
                    }
                }

                // MARK: Test
                Section {
                    Button {
                        Task { await testAlert() }
                    } label: {
                        HStack {
                            Label("Test Alert", systemImage: "bell.badge")
                            Spacer()
                            if testPending {
                                Text("Rings in 10 seconds")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(testPending)
                } footer: {
                    Text("Rings a test alert in 10 seconds with your current sound and settings. Lock your iPhone or switch it to silent to check that alerts get through.")
                }
            }
            .navigationTitle("Settings")
            // These are baked into the scheduled alarms, so reschedule after a change.
            .onChange(of: settings.leadTimeMinutes) { _, _ in AlarmScheduler.shared.requestResync() }
            .onChange(of: settings.selectedSound) { _, _ in AlarmScheduler.shared.requestResync() }
            .onChange(of: settings.soundEnabled) { _, _ in AlarmScheduler.shared.requestResync() }
            .onChange(of: settings.lastAlertMinutes) { _, _ in AlarmScheduler.shared.requestResync() }
            .onChange(of: settings.snoozeDurationMinutes) { _, _ in AlarmScheduler.shared.requestResync() }
            .onChange(of: settings.keywordFirstAlerts) { _, _ in AlarmScheduler.shared.requestResync() }
            .onAppear { alarmsAllowed = MeetingAlarms.shared.isAuthorized }
            // Picks up a change made in iOS Settings while Befoor was in the background.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { alarmsAllowed = MeetingAlarms.shared.isAuthorized }
            }
        }
    }

    // MARK: Helpers

    /// A real alarm when alarms are in use, otherwise the notification a
    /// meeting would get.
    private func testAlert() async {
        testPending = true
        var rang = false
        if settings.soundEnabled && MeetingAlarms.shared.isAuthorized {
            rang = await MeetingAlarms.shared.scheduleTest(in: Self.testDelay)
        }
        if !rang {
            NotificationService.shared.sendTest(in: Self.testDelay)
        }
        try? await Task.sleep(for: .seconds(Self.testDelay + 2))
        testPending = false
    }

    /// A pause starts out ending tomorrow at 8 AM.
    private static var defaultPauseEnd: Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) ?? .now
        return calendar.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    private func alertLabel(_ minutes: Int) -> String {
        switch minutes {
        case 0:  return String(localized: "at start")
        case 1:  return String(localized: "1 minute before")
        default: return String(localized: "\(minutes) minutes before")
        }
    }

    /// Shows whether Befoor may schedule system alarms, with a way to fix it.
    @ViewBuilder
    private var alarmPermissionRow: some View {
        if alarmsAllowed {
            Label("Alarms Allowed", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else if MeetingAlarms.shared.isDenied {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Alarms Are Off — Open Settings", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        } else {
            Button {
                Task {
                    alarmsAllowed = await MeetingAlarms.shared.requestAuthorization()
                    AlarmScheduler.shared.requestResync()
                }
            } label: {
                Label("Allow Alarms", systemImage: "alarm")
            }
        }
    }

    private func addKeyword() {
        let trimmed = newKeyword.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              !settings.ignoredKeywords.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame })
        else { return }
        settings.ignoredKeywords.append(trimmed)
        newKeyword = ""
        showAddKeyword = false
    }

    /// Keyword alert times, all before the last alert so they stay the first.
    private var keywordAlertChoices: [Int] {
        AppSettings.meetingFirstAlertChoices.filter { $0 > settings.lastAlertMinutes }
    }

    private func addKeywordAlert() {
        let trimmed = newAlertKeyword.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        // Re-adding a keyword (in any case) replaces its time.
        for key in settings.keywordFirstAlerts.keys where key.caseInsensitiveCompare(trimmed) == .orderedSame {
            settings.keywordFirstAlerts[key] = nil
        }
        settings.keywordFirstAlerts[trimmed] = newAlertMinutes
        newAlertKeyword = ""
        showAddAlertKeyword = false
    }

    private func remove(keyword: String) {
        settings.ignoredKeywords.removeAll { $0 == keyword }
    }
}

// MARK: - SoundRow

private struct SoundRow: View {
    let sound: BefoorSound
    let isSelected: Bool
    let isPlaying: Bool
    let onSelect: () -> Void
    let onPreview: () -> Void

    var body: some View {
        HStack {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? .indigo : .secondary)
                        .font(.title3)

                    Text(sound.displayName)
                        .foregroundStyle(.primary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: onPreview) {
                Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle")
                    .font(.title3)
                    .foregroundStyle(isPlaying ? .indigo : .secondary)
                    .symbolEffect(.pulse, isActive: isPlaying)
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    SettingsView()
}
