import SwiftUI
import SwiftData

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var scheduler = AlarmScheduler.shared
    @ObservedObject private var soundPlayer = SoundPlayer.shared
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DetectionKeyword.keyword) private var detectionKeywords: [DetectionKeyword]
    @State private var newKeyword = ""
    @State private var showAddKeyword = false
    @State private var newDetectionKeyword = ""
    @State private var showAddDetectionKeyword = false

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Master switch
                Section {
                    Toggle("Enable Befoor", isOn: $settings.isEnabled)
                        .tint(.indigo)
                } footer: {
                    Text("When disabled, all scheduled alarms are cancelled.")
                }

                // MARK: Timing
                Section("Alarm Timing") {
                    Stepper(
                        "\(settings.leadTimeMinutes) minutes before",
                        value: $settings.leadTimeMinutes,
                        in: 5...60
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
                }

                // MARK: Calendars
                Section("Calendars") {
                    NavigationLink {
                        CalendarPickerView()
                    } label: {
                        HStack {
                            Text("Monitored Calendars")
                            Spacer()
                            Text(settings.selectedCalendarIdentifiers.isEmpty
                                 ? "All"
                                 : "\(settings.selectedCalendarIdentifiers.count) selected")
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
                Section("Alert Sound") {
                    Toggle("Sound", isOn: $settings.soundEnabled)
                        .tint(.indigo)
                    Toggle("Haptics", isOn: $settings.hapticsEnabled)
                        .tint(.indigo)
                    Toggle("Alarm at Event Start", isOn: $settings.finalAlarmEnabled)
                        .tint(.indigo)

                    Picker("Audible Alerts", selection: $settings.audibleAlertsMode) {
                        ForEach(AudibleAlertsMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }

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
                }

                // MARK: Detection Keywords
                Section {
                    ForEach(detectionKeywords) { keyword in
                        HStack {
                            Toggle(keyword.keyword, isOn: Bindable(keyword).isEnabled)
                                .tint(.indigo)
                            Button {
                                modelContext.delete(keyword)
                                try? modelContext.save()
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if showAddDetectionKeyword {
                        HStack {
                            TextField("e.g. 1:1", text: $newDetectionKeyword)
                                .autocorrectionDisabled()
                            Button("Add") { addDetectionKeyword() }
                                .disabled(newDetectionKeyword.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    } else {
                        Button {
                            showAddDetectionKeyword = true
                        } label: {
                            Label("Add Keyword", systemImage: "plus.circle")
                        }
                    }
                } header: {
                    Text("1:1 Detection Keywords")
                } footer: {
                    Text("Calendar events whose titles contain any of these keywords (case-insensitive) will be detected as 1:1 meetings.")
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
                    Text("iOS may delay or batch background checks to preserve battery.")
                }

                // MARK: Manual sync
                Section {
                    Button {
                        Task { await AlarmScheduler.shared.sync() }
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
            }
            .navigationTitle("Settings")
        }
    }

    // MARK: Helpers

    private func addKeyword() {
        let trimmed = newKeyword.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !settings.ignoredKeywords.contains(trimmed) else { return }
        settings.ignoredKeywords.append(trimmed)
        newKeyword = ""
        showAddKeyword = false
    }

    private func remove(keyword: String) {
        settings.ignoredKeywords.removeAll { $0 == keyword }
    }

    private func addDetectionKeyword() {
        let trimmed = newDetectionKeyword.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard !detectionKeywords.contains(where: { $0.keyword.lowercased() == trimmed.lowercased() }) else { return }
        let keyword = DetectionKeyword(keyword: trimmed)
        modelContext.insert(keyword)
        try? modelContext.save()
        newDetectionKeyword = ""
        showAddDetectionKeyword = false
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
