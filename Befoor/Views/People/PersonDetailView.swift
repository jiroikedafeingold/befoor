import SwiftUI
import SwiftData

struct PersonDetailView: View {
    @Bindable var person: Person
    let syncCoordinator: SyncCoordinator
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Note> { $0.isGlobal == true },
           sort: \Note.meetingDate, order: .reverse)
    private var globalNotes: [Note]

    @Query private var allNotes: [Note]
    @Query private var allFollowUps: [FollowUp]
    @Query private var allLongTermNotes: [LongTermNote]
    @Query private var allReminders: [Reminder]

    @State private var showAddNote = false
    @State private var showAddFollowUp = false
    @State private var showAddLongTermNote = false
    @State private var showAddReminder = false
    @State private var completedExpanded = false

    private func belongsToPerson(_ personID: UUID?, _ relationship: Person?) -> Bool {
        personID == person.id || relationship?.id == person.id
    }

    private var activeFollowUps: [FollowUp] {
        allFollowUps.filter { belongsToPerson($0.personID, $0.person) && !$0.isCompleted }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    private var completedFollowUps: [FollowUp] {
        allFollowUps.filter { belongsToPerson($0.personID, $0.person) && $0.isCompleted }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var sortedNotes: [Note] {
        allNotes.filter { belongsToPerson($0.personID, $0.person) && !$0.isGlobal }
            .sorted { $0.meetingDate > $1.meetingDate }
    }

    private var sortedLongTermNotes: [LongTermNote] {
        allLongTermNotes.filter { belongsToPerson($0.personID, $0.person) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var activeReminders: [Reminder] {
        allReminders.filter { belongsToPerson($0.personID, $0.person) && !$0.isCompleted }
            .sorted { $0.fireDate < $1.fireDate }
    }

    var body: some View {
        List {
            // MARK: Info
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(person.name)
                        .font(.title3.weight(.semibold))
                    if let email = person.email {
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let lastMeeting = person.lastMeetingDate {
                        Text("Next meeting: \(lastMeeting, format: .dateTime.month().day().year())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // MARK: Follow-ups
            Section {
                if activeFollowUps.isEmpty && completedFollowUps.isEmpty {
                    Text("No follow-ups yet")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(activeFollowUps) { followUp in
                    FollowUpRowView(followUp: followUp) {
                        toggleFollowUp(followUp)
                    }
                }
                .onDelete { offsets in
                    for offset in offsets {
                        modelContext.delete(activeFollowUps[offset])
                    }
                    try? modelContext.save()
                }

                if !completedFollowUps.isEmpty {
                    DisclosureGroup("Completed (\(completedFollowUps.count))", isExpanded: $completedExpanded) {
                        ForEach(completedFollowUps) { followUp in
                            FollowUpRowView(followUp: followUp) {
                                toggleFollowUp(followUp)
                            }
                        }
                        .onDelete { offsets in
                            for offset in offsets {
                                modelContext.delete(completedFollowUps[offset])
                            }
                            try? modelContext.save()
                        }
                    }
                }

                Button {
                    showAddFollowUp = true
                } label: {
                    Label("Add Follow-up", systemImage: "plus.circle")
                }
            } header: {
                Text("Follow-ups")
            }

            // MARK: Notes
            Section {
                if sortedNotes.isEmpty {
                    Text("No notes yet")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(sortedNotes) { note in
                    NoteRowView(note: note)
                }
                .onDelete { offsets in
                    for offset in offsets {
                        modelContext.delete(sortedNotes[offset])
                    }
                    try? modelContext.save()
                }

                Button {
                    showAddNote = true
                } label: {
                    Label("Add Note", systemImage: "plus.circle")
                }
            } header: {
                Text("Meeting Notes")
            }

            // MARK: Global Notes
            if !globalNotes.isEmpty {
                Section {
                    ForEach(globalNotes) { note in
                        NoteRowView(note: note, showGlobalBadge: true)
                    }
                    .onDelete { offsets in
                        for offset in offsets {
                            modelContext.delete(globalNotes[offset])
                        }
                        try? modelContext.save()
                    }
                } header: {
                    Text("Notes for Everyone")
                }
            }

            // MARK: Long-term Notes
            Section {
                if sortedLongTermNotes.isEmpty {
                    Text("No long-term notes yet")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(sortedLongTermNotes) { note in
                    LongTermNoteRowView(note: note)
                }
                .onDelete { offsets in
                    for offset in offsets {
                        modelContext.delete(sortedLongTermNotes[offset])
                    }
                    try? modelContext.save()
                }

                Button {
                    showAddLongTermNote = true
                } label: {
                    Label("Add Long-term Note", systemImage: "plus.circle")
                }
            } header: {
                Text("Long-term Notes")
            }

            // MARK: Reminders
            Section {
                if activeReminders.isEmpty {
                    Text("No active reminders")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(activeReminders) { reminder in
                    ReminderRowView(reminder: reminder)
                }
                .onDelete { offsets in
                    for offset in offsets {
                        let reminder = activeReminders[offset]
                        if let notifID = reminder.notificationIdentifier {
                            NotificationService.shared.cancelNotification(identifier: notifID)
                        }
                        modelContext.delete(reminder)
                    }
                    try? modelContext.save()
                }

                Button {
                    showAddReminder = true
                } label: {
                    Label("Add Reminder", systemImage: "plus.circle")
                }
            } header: {
                Text("Reminders")
            }

            // MARK: Actions
            Section {
                Toggle("Pinned", isOn: $person.isPinned)
                    .tint(.orange)
                    .onChange(of: person.isPinned) {
                        try? modelContext.save()
                    }
            }
        }
        .navigationTitle(person.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddNote) {
            AddNoteView(person: person)
        }
        .sheet(isPresented: $showAddFollowUp) {
            AddFollowUpView(person: person)
        }
        .sheet(isPresented: $showAddLongTermNote) {
            AddLongTermNoteView(person: person)
        }
        .sheet(isPresented: $showAddReminder) {
            AddReminderView(person: person)
        }
    }

    private func toggleFollowUp(_ followUp: FollowUp) {
        followUp.isCompleted.toggle()
        followUp.lastModified = Date()

        // If recurring and just completed, create the next occurrence
        if followUp.isCompleted, followUp.isRecurring, let interval = followUp.recurrenceIntervalDays {
            let nextDue = Calendar.current.date(
                byAdding: .day,
                value: interval,
                to: followUp.dueDate ?? Date()
            )
            let newFollowUp = FollowUp(
                text: followUp.text,
                dueDate: nextDue,
                isRecurring: true,
                recurrenceIntervalDays: interval,
                person: person
            )
            modelContext.insert(newFollowUp)
        }

        try? modelContext.save()
    }

    private func sendTestNotification() {
        Task {
            let granted = await NotificationService.shared.requestPermission()
            guard granted else { return }

            let id = "test_person_\(UUID().uuidString)"
            await NotificationService.shared.scheduleAlarm(
                identifier: id,
                eventTitle: "Test 1:1 Meeting",
                calendarName: "Test Calendar",
                fireDate: Date().addingTimeInterval(5),
                eventStartDate: Date().addingTimeInterval(300),
                sound: AppSettings.shared.selectedSound,
                personName: person.name
            )
        }
    }
}
