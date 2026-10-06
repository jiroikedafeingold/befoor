import SwiftUI
import SwiftData

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var scheduler = AlarmScheduler.shared
    @ObservedObject private var soundPlayer = SoundPlayer.shared
    @ObservedObject private var ckStatus = CloudKitStatus.shared
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \DetectionKeyword.keyword) private var detectionKeywords: [DetectionKeyword]
    @State private var newKeyword = ""
    @State private var showAddKeyword = false
    @State private var newDetectionKeyword = ""
    @State private var showAddDetectionKeyword = false
    @State private var showPermissionPrompt = false
    @State private var showResetConfirm = false
    @State private var calendarGranted = false
    @State private var contactsGranted = false
    @State private var alarmsAllowed = false
    @Query private var allPeople: [Person]
    @Query private var allNotes: [Note]
    @Query private var allFollowUps: [FollowUp]
    @Query private var allLongTermNotes: [LongTermNote]
    @Query private var allReminders: [Reminder]
    @Query private var alarmSnapshots: [AlarmListSnapshot]

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Device Role
                Section {
                    if settings.isMainDevice {
                        HStack {
                            Label("Main Device", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Spacer()
                            Text("This device")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button {
                            settings.claimAsMainDevice()
                            showPermissionPrompt = true
                        } label: {
                            Label("Set as Main Device", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                } footer: {
                    Text("The main device syncs calendars and detects 1:1 meetings. Other devices receive people and meeting data via iCloud and can create notes and follow-ups.")
                }

                // MARK: Master switch
                Section {
                    Toggle("Enable Befoor", isOn: $settings.isEnabled)
                        .tint(.indigo)
                } footer: {
                    Text("When disabled, all scheduled alarms are cancelled.")
                }

                // MARK: People feature
                Section {
                    Toggle("People & 1:1 Meetings", isOn: $settings.peopleEnabled)
                        .tint(.indigo)
                } footer: {
                    Text("Adds a People tab that detects 1:1 meetings, tracks notes and follow-ups, and sends pre-meeting reminders. When off, Befoor is a pure calendar alarm. On the main device this also turns the feature off on your other devices.")
                }

                // MARK: Timing
                Section {
                    Stepper(
                        "First alert: \(alertLabel(settings.leadTimeMinutes))",
                        value: $settings.leadTimeMinutes,
                        in: AppSettings.firstAlertRange
                    )
                    Stepper(
                        "Second alert: \(alertLabel(settings.secondAlertMinutes))",
                        value: $settings.secondAlertMinutes,
                        in: AppSettings.laterAlertRange
                    )
                    Stepper(
                        "Third alert: \(alertLabel(settings.thirdAlertMinutes))",
                        value: $settings.thirdAlertMinutes,
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
                    Text("Each meeting rings up to three times. Stop on any alert skips that meeting's remaining alerts; Snooze keeps them.")
                }

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
                    Text("When a meeting's alarm goes off, shows a countdown to it in the Dynamic Island and on the Lock Screen, with its location, calendar and who it's with. Press and hold the Dynamic Island for details. iPhone only.")
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
                    Text("Befoor rings a real alarm before each meeting, so it sounds even when your iPhone is on silent or in a Focus, and works even if Befoor isn't open. With Sound off, or if alarms aren't allowed, you get notifications instead, which follow your ringer switch.")
                }

                // MARK: Detection Keywords
                if settings.peopleEnabled {
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

                // MARK: Debug
                Section("Debug") {
                    Toggle("Show Debug Info", isOn: $settings.showDebugInfo)
                        .tint(.indigo)

                    if settings.showDebugInfo {
                        LabeledContent("Storage", value: BefoorApp.storageMode)
                        LabeledContent("Device ID", value: String(DeviceID.current.prefix(8)) + "…")
                        LabeledContent("Main Device ID", value: settings.mainDeviceID.isEmpty ? "none" : String(settings.mainDeviceID.prefix(8)) + "…")
                        LabeledContent("Is Main", value: settings.isMainDevice ? "Yes" : "No")
                        LabeledContent("Alarms in Store", value: "\(TrackedAlarmsStore.shared.alarms.count)")
                        if let snapshot = alarmSnapshots.first {
                            let count = (try? JSONDecoder().decode([TrackedAlarmModel].self, from: snapshot.alarmsJSON))?.count ?? 0
                            LabeledContent("Snapshot Alarms", value: "\(count)")
                            LabeledContent("Snapshot Updated", value: snapshot.lastUpdated.formatted(.dateTime.hour().minute().second()))
                        } else {
                            LabeledContent("Snapshot", value: "none")
                        }
                        LabeledContent("iCloud Drive", value: ckStatus.iCloudDriveAvailable ? "Yes" : "No")
                            .foregroundStyle(ckStatus.iCloudDriveAvailable ? Color.primary : Color.red)
                        LabeledContent("CK Account", value: ckStatus.accountStatus)
                            .foregroundStyle(ckStatus.accountStatus == "available" ? Color.primary : Color.red)
                        HStack {
                            Text("CK User: \(ckStatus.userRecordID)")
                                .font(.caption2)
                                .lineLimit(1)
                            Spacer()
                            Button { UIPasteboard.general.string = ckStatus.userRecordID } label: {
                                Image(systemName: "doc.on.doc").font(.caption2)
                            }
                            .buttonStyle(.plain)
                        }
                        LabeledContent("CK Setup", value: ckStatus.setupComplete ? "OK" : (ckStatus.setupError ?? "pending"))
                            .foregroundStyle(ckStatus.setupComplete ? Color.primary : Color.orange)
                        if let lastType = ckStatus.lastEventType {
                            let time = ckStatus.lastEventTimestamp ?? ""
                            LabeledContent("CK Last Event", value: "\(lastType) \(ckStatus.lastEventSucceeded ? "✓" : "✗") \(time)")
                        }
                        if let error = ckStatus.lastError {
                            HStack {
                                Text("CK Error: \(error)")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                                Spacer()
                                Button { UIPasteboard.general.string = error } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.caption2)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        LabeledContent("Remote Changes", value: "\(ckStatus.remoteChangeCount)")
                        Button {
                            ckStatus.checkAccountStatus()
                        } label: {
                            Label("Check CK Account", systemImage: "icloud.and.arrow.down")
                        }
                        Button {
                            ckStatus.testDirectCloudKit()
                        } label: {
                            Label("Test CloudKit Directly", systemImage: "icloud.and.arrow.up")
                        }
                        if let testResult = ckStatus.directTestResult {
                            HStack {
                                Text("CK Test: \(testResult)")
                                    .font(.caption2)
                                    .foregroundStyle(testResult.hasPrefix("zones") ? Color.primary : Color.red)
                                Spacer()
                                Button { UIPasteboard.general.string = testResult } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.caption2)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        LabeledContent("People", value: "\(allPeople.count)")
                        LabeledContent("Notes", value: "\(allNotes.count)")
                        LabeledContent("Follow-ups", value: "\(allFollowUps.count)")
                        LabeledContent("Long-term Notes", value: "\(allLongTermNotes.count)")
                        LabeledContent("Reminders", value: "\(allReminders.count)")

                        let orphanedNotes = allNotes.filter { $0.person == nil && !$0.isGlobal }
                        if !orphanedNotes.isEmpty {
                            LabeledContent("Orphaned Notes", value: "\(orphanedNotes.count)")
                                .foregroundStyle(.red)
                        }

                        let nilPersonIDNotes = allNotes.filter { $0.personID == nil && !$0.isGlobal }
                        if !nilPersonIDNotes.isEmpty {
                            LabeledContent("Notes w/o personID", value: "\(nilPersonIDNotes.count)")
                                .foregroundStyle(.orange)
                        }

                        let orphanedFollowUps = allFollowUps.filter { $0.person == nil }
                        if !orphanedFollowUps.isEmpty {
                            LabeledContent("Orphaned Follow-ups", value: "\(orphanedFollowUps.count)")
                                .foregroundStyle(.red)
                        }

                        let nilPersonIDFollowUps = allFollowUps.filter { $0.personID == nil }
                        if !nilPersonIDFollowUps.isEmpty {
                            LabeledContent("Follow-ups w/o personID", value: "\(nilPersonIDFollowUps.count)")
                                .foregroundStyle(.orange)
                        }

                        if !settings.isMainDevice {
                            Button(role: .destructive) {
                                showResetConfirm = true
                            } label: {
                                Label("Reset Local Data", systemImage: "arrow.counterclockwise.circle")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            // These are baked into the scheduled alarms, so reschedule after a change.
            .onChange(of: settings.leadTimeMinutes) { _, _ in AlarmScheduler.shared.requestResync() }
            .onChange(of: settings.selectedSound) { _, _ in AlarmScheduler.shared.requestResync() }
            .onChange(of: settings.soundEnabled) { _, _ in AlarmScheduler.shared.requestResync() }
            .onChange(of: settings.secondAlertMinutes) { _, _ in AlarmScheduler.shared.requestResync() }
            .onChange(of: settings.thirdAlertMinutes) { _, _ in AlarmScheduler.shared.requestResync() }
            .onChange(of: settings.snoozeDurationMinutes) { _, _ in AlarmScheduler.shared.requestResync() }
            .onAppear { alarmsAllowed = MeetingAlarms.shared.isAuthorized }
            // Picks up a change made in iOS Settings while Befoor was in the background.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { alarmsAllowed = MeetingAlarms.shared.isAuthorized }
            }
            .alert("Reset Local Data?", isPresented: $showResetConfirm) {
                Button("Reset & Restart", role: .destructive) {
                    BefoorApp.removeStoreFiles()
                    exit(0)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes all local data and restarts the app. CloudKit will re-import everything from iCloud. Only use this on secondary devices.")
            }
            .onAppear { ckStatus.checkAccountStatus() }
            .sheet(isPresented: $showPermissionPrompt) {
                MainDevicePermissionsView(
                    calendarGranted: $calendarGranted,
                    contactsGranted: $contactsGranted
                )
            }
        }
    }

    // MARK: Helpers

    private func alertLabel(_ minutes: Int) -> String {
        switch minutes {
        case 0:  return "at start"
        case 1:  return "1 minute before"
        default: return "\(minutes) minutes before"
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

// MARK: - MainDevicePermissionsView

private struct MainDevicePermissionsView: View {
    @Binding var calendarGranted: Bool
    @Binding var contactsGranted: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.indigo)
                    Text("Main Device Setup")
                        .font(.title2.bold())
                    Text("As the main device, Befoor needs access to your calendar and contacts to detect 1:1 meetings.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 32)

                VStack(spacing: 16) {
                    PermissionRow(
                        icon: "calendar",
                        iconColor: .green,
                        title: "Calendar Access",
                        subtitle: "Read your events to detect meetings",
                        granted: calendarGranted
                    ) {
                        Task { calendarGranted = await CalendarService.shared.requestAccess() }
                    }

                    PermissionRow(
                        icon: "person.crop.circle",
                        iconColor: .blue,
                        title: "Contacts Access",
                        subtitle: "Better name resolution (optional)",
                        granted: contactsGranted
                    ) {
                        Task { contactsGranted = await CalendarService.shared.requestContactsAccess() }
                    }
                }

                Spacer()

                Button {
                    dismiss()
                    Task { await AlarmScheduler.shared.sync() }
                } label: {
                    Text("Done")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(calendarGranted ? Color.indigo : Color.secondary.opacity(0.3))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!calendarGranted)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 32)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        AppSettings.shared.mainDeviceID = ""
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct PermissionRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let granted: Bool
    let onRequest: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
            } else {
                Button(action: onRequest) {
                    Text("Allow")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(iconColor)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

#Preview {
    SettingsView()
}
