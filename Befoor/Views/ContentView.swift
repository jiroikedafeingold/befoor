import SwiftUI
import StoreKit

struct ContentView: View {
    @ObservedObject private var scheduler  = AlarmScheduler.shared
    @ObservedObject private var store      = TrackedAlarmsStore.shared
    @ObservedObject private var settings   = AppSettings.shared
    @ObservedObject private var calService = CalendarService.shared
    @Environment(\.scenePhase) private var scenePhase

    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview

    @State private var selectedTab = 0
    @State private var alarmsAllowed = true
    @State private var alarmsDenied = false
    /// The meeting whose note is being edited, and the text so far.
    @State private var noteMeeting: TrackedAlarmModel?
    @State private var noteDraft = ""
    /// A First Alert pick for a repeating meeting, waiting on "this one or all?".
    @State private var pendingFirstAlert: PendingFirstAlert?

    var body: some View {
        TabView(selection: $selectedTab) {
            alarmsTab
                .tabItem {
                    Label("Alarms", systemImage: "alarm")
                }
                .tag(0)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(1)

            HelpView()
                .tabItem {
                    Label("Help", systemImage: "questionmark.circle")
                }
                .tag(2)
        }
        .tint(.indigo)
        // Befoor uses a scene, so UIKit never calls the app delegate's
        // didBecomeActive/didEnterBackground; the scene phase stands in for them.
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                refreshAlarmStatus()
                askForReviewIfEarned()
                NotificationService.shared.clearBadge()
                NotificationService.shared.tidyDeliveredNotifications()
                Task {
                    // People who updated from a pre-AlarmKit version finished onboarding
                    // before it asked for alarms, so ask here, once, while on screen.
                    if settings.hasCompletedOnboarding, MeetingAlarms.shared.isUndetermined {
                        await MeetingAlarms.shared.requestAuthorization()
                        refreshAlarmStatus()
                    }
                    await AlarmScheduler.shared.sync()
                    // Live Activities can only be started in the foreground, so check here
                    // even when sync was throttled.
                    await MeetingLiveActivityManager.shared.refresh()
                }
            case .background:
                AlarmScheduler.shared.scheduleNextBackgroundRefresh()
            default:
                break
            }
        }
        // The Join button on a Live Activity opens Befoor with befoor://join?url=…,
        // since a Live Activity's links can only open its own app.
        .onOpenURL { url in
            guard url.scheme == "befoor", url.host() == "join",
                  let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "url" })?.value,
                  let target = URL(string: value),
                  ["https", "http"].contains(target.scheme?.lowercased() ?? "") else { return }
            openURL(target)
        }
        .task {
            refreshAlarmStatus()
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
        // Onboarding asks for alarms after this screen first checked, so check
        // again when it finishes (else "Alarms are off" shows until a relaunch).
        .onChange(of: settings.hasCompletedOnboarding) { _, done in
            if done { refreshAlarmStatus() }
        }
    }

    // MARK: - Alarms Tab

    private var alarmsTab: some View {
        NavigationStack {
            Group {
                if scheduler.syncInProgress && store.alarms.isEmpty {
                    syncingState
                } else if store.alarms.isEmpty {
                    emptyState
                } else {
                    alarmsList
                }
            }
            .navigationTitle("Dingly")
            .toolbar { toolbarContent }
            .refreshable { await AlarmScheduler.shared.sync(force: true) }
        }
    }

    private var syncingState: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.indigo)

            Text("Syncing calendars…")
                .font(.title3.weight(.semibold))

            Text("Checking for upcoming appointments.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var alarmsList: some View {
        noteAlert(List {
            statusSections

            ForEach(meetingsByDay, id: \.day) { day in
                Section {
                    ForEach(day.meetings) { meeting in
                        let skipped = settings.isSkipped(eventIdentifier: meeting.eventIdentifier,
                                                         start: meeting.eventStartDate)
                        let note = settings.note(eventIdentifier: meeting.eventIdentifier, start: meeting.eventStartDate)
                        let firstAlert = settings.chosenFirstAlert(eventIdentifier: meeting.eventIdentifier,
                                                                   start: meeting.eventStartDate,
                                                                   title: meeting.eventTitle)
                        AlarmRow(alarm: meeting, isSkipped: skipped,
                                 isPaused: settings.isPaused(at: meeting.eventStartDate),
                                 note: note,
                                 firstAlert: firstAlert ?? morningFirstAlert(for: meeting))
                            .swipeActions(edge: .trailing) {
                                skipButton(for: meeting, skipped: skipped)
                            }
                            .contextMenu {
                                skipButton(for: meeting, skipped: skipped)
                                Button {
                                    noteDraft = note ?? ""
                                    noteMeeting = meeting
                                } label: {
                                    Label(note == nil ? "Add Note" : "Edit Note", systemImage: "note.text")
                                }
                                firstAlertMenu(for: meeting, chosen: firstAlert)
                            }
                    }
                } header: {
                    dayTitle(day.day)
                }
            }
        })
        .confirmationDialog("This is a repeating meeting.", isPresented: Binding(
            get: { pendingFirstAlert != nil },
            set: { if !$0 { pendingFirstAlert = nil } }
        ), titleVisibility: .visible, presenting: pendingFirstAlert) { pending in
            Button("Just This Meeting") { applyFirstAlert(pending, wholeSeries: false) }
            Button("All Meetings in the Series") { applyFirstAlert(pending, wholeSeries: true) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Change the first alert for just this meeting, or for every meeting in the series?")
        }
    }

    private struct PendingFirstAlert {
        let meeting: TrackedAlarmModel
        let minutes: Int?
    }

    private func applyFirstAlert(_ pending: PendingFirstAlert, wholeSeries: Bool) {
        settings.setFirstAlert(pending.minutes, eventIdentifier: pending.meeting.eventIdentifier,
                               start: pending.meeting.eventStartDate, title: pending.meeting.eventTitle,
                               wholeSeries: wholeSeries)
        Task { await AlarmScheduler.shared.sync(force: true) }
    }

    /// A short note for one meeting: shown on its row, alarm and countdown.
    private func noteAlert<Content: View>(_ content: Content) -> some View {
        content.alert("Meeting Note", isPresented: Binding(
            get: { noteMeeting != nil },
            set: { if !$0 { noteMeeting = nil } }
        ), presenting: noteMeeting) { meeting in
            TextField("e.g. Bring up the budget", text: $noteDraft)
            Button("Save") { saveNote(noteDraft, for: meeting) }
            if settings.note(eventIdentifier: meeting.eventIdentifier, start: meeting.eventStartDate) != nil {
                Button("Remove Note", role: .destructive) { saveNote("", for: meeting) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { meeting in
            Text("Shows on \(meeting.eventTitle)'s alarm and countdown.")
        }
    }

    /// Picks when this one meeting's first alert rings, instead of First Alert.
    private func firstAlertMenu(for meeting: TrackedAlarmModel, chosen: Int?) -> some View {
        Menu {
            Picker("First Alert", selection: Binding(
                get: { chosen },
                set: { minutes in
                    let pending = PendingFirstAlert(meeting: meeting, minutes: minutes)
                    let event = CalendarService.shared.event(identifier: meeting.eventIdentifier,
                                                             startingAt: meeting.eventStartDate)
                    // Repeating meetings ask whether the change is for this one or all.
                    if event?.hasRecurrenceRules == true {
                        pendingFirstAlert = pending
                    } else {
                        applyFirstAlert(pending, wholeSeries: false)
                    }
                }
            )) {
                Text("Usual (\(settings.leadTimeMinutes) min before)").tag(Int?.none)
                // Only times before the last alert, so this stays the first one.
                ForEach(AppSettings.meetingFirstAlertChoices.filter { $0 > settings.lastAlertMinutes }, id: \.self) { minutes in
                    Text("\(minutes) min before").tag(Int?.some(minutes))
                }
            }
        } label: {
            Label("First Alert", systemImage: "alarm")
        }
    }

    private func saveNote(_ note: String, for meeting: TrackedAlarmModel) {
        settings.setNote(note, eventIdentifier: meeting.eventIdentifier, start: meeting.eventStartDate)
        // The note is baked into the meeting's alarms and countdown.
        Task { await AlarmScheduler.shared.sync(force: true) }
    }

    /// Warnings that matter more than the list: Befoor paused, or meetings that
    /// won't ring on silent because they only get notifications.
    @ViewBuilder
    private var statusSections: some View {
        if !settings.isEnabled {
            Section {
                Label("Dingly is paused. Enable it in Settings.", systemImage: "pause.circle")
                    .foregroundStyle(.orange)
                    .font(.footnote)
            }
            .listRowBackground(Color.orange.opacity(0.1))
        } else if settings.isPausedNow, let until = settings.pausedUntil {
            Section {
                HStack {
                    Label {
                        Text("Paused until \(until.formatted(date: .abbreviated, time: .shortened))")
                    } icon: {
                        Image(systemName: "pause.circle")
                    }
                    .foregroundStyle(.orange)
                    .font(.footnote)
                    Spacer()
                    Button("Resume") {
                        settings.pausedUntil = nil
                        Task { await AlarmScheduler.shared.sync(force: true) }
                    }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderless)
                }
            }
            .listRowBackground(Color.orange.opacity(0.1))
        } else if settings.soundEnabled && !alarmsAllowed {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Alarms are off, so meetings won't ring on silent or in a Focus. You'll get notifications instead.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.footnote)
                    Button(alarmsDenied ? String(localized: "Open Settings") : String(localized: "Allow Alarms")) {
                        Task { await fixAlarms() }
                    }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderless)
                }
            }
            .listRowBackground(Color.orange.opacity(0.1))
        } else if scheduler.alarmFallbackCount > 0 {
            Section {
                Label("Some meetings are over iOS's alarm limit, so they get notifications instead, which don't ring on silent. Shorten Look Ahead in Settings to fix this.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.footnote)
            }
            .listRowBackground(Color.orange.opacity(0.1))
        }
    }

    private func skipButton(for meeting: TrackedAlarmModel, skipped: Bool) -> some View {
        Button {
            settings.setSkipped(!skipped, eventIdentifier: meeting.eventIdentifier, start: meeting.eventStartDate)
            Task { await AlarmScheduler.shared.sync(force: true) }
        } label: {
            if skipped {
                Label("Ring", systemImage: "bell")
            } else {
                Label("Skip", systemImage: "bell.slash")
            }
        }
        .tint(skipped ? .indigo : .orange)
    }

    private func dayTitle(_ day: Date) -> Text {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return Text("Today") }
        if calendar.isDateInTomorrow(day) { return Text("Tomorrow") }
        return Text(day, format: .dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            if settings.isEnabled && settings.soundEnabled && !alarmsAllowed {
                List { statusSections }
                    .frame(maxHeight: 160)
                    .scrollDisabled(true)
            }

            Image(systemName: "alarm")
                .font(.system(size: 64))
                .foregroundStyle(.indigo.opacity(0.5))

            Text("No upcoming meetings")
                .font(.title3.weight(.semibold))

            Text(settings.isEnabled
                 ? String(localized: "No appointments found in the next \(settings.lookAheadDays) days in your selected calendars.")
                 : String(localized: "Dingly is paused. Enable it in Settings."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Sync Calendar") {
                Task { await AlarmScheduler.shared.sync(force: true) }
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
                    Task { await AlarmScheduler.shared.sync(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Sync Calendar")
            }
        }

        ToolbarItem(placement: .navigationBarLeading) {
            Image(systemName: settings.isEnabled ? "checkmark.circle.fill" : "pause.circle.fill")
                .foregroundStyle(settings.isEnabled ? .green : .secondary)
                .accessibilityLabel(settings.isEnabled ? Text("Active") : Text("Paused"))
        }
    }

    // MARK: - Helpers

    /// The system rating prompt, once Befoor has proved itself (see
    /// AppSettings.shouldAskForReview). iOS decides whether it actually shows.
    private func askForReviewIfEarned() {
        guard settings.hasCompletedOnboarding, settings.shouldAskForReview else { return }
        settings.markReviewAsked()
        Task {
            // A moment after opening, so it doesn't interrupt.
            try? await Task.sleep(for: .seconds(2))
            requestReview()
        }
    }

    private func refreshAlarmStatus() {
        alarmsAllowed = MeetingAlarms.shared.isAuthorized
        alarmsDenied = MeetingAlarms.shared.isDenied
    }

    private func fixAlarms() async {
        if alarmsDenied {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        } else {
            await MeetingAlarms.shared.requestAuthorization()
            refreshAlarmStatus()
            await AlarmScheduler.shared.sync(force: true)
        }
    }

    /// The earlier first alert of the day's first meeting, shown on its row.
    private func morningFirstAlert(for meeting: TrackedAlarmModel) -> Int? {
        guard meeting.firstOfDay == true, settings.firstMeetingAlertMinutes > 0 else { return nil }
        return settings.firstMeetingAlertMinutes
    }

    /// Upcoming meetings in the look-ahead window, grouped by day, without the
    /// duplicates the store can hold (the same event in two calendars).
    private var meetingsByDay: [(day: Date, meetings: [TrackedAlarmModel])] {
        let calendar = Calendar.current
        var seen = Set<String>()
        let meetings = store.alarms.values
            .sorted { $0.eventStartDate < $1.eventStartDate }
            .filter { seen.insert($0.eventTitle + "_" + String(Int($0.eventStartDate.timeIntervalSince1970))).inserted }
        return Dictionary(grouping: meetings) { calendar.startOfDay(for: $0.eventStartDate) }
            .map { (day: $0.key, meetings: $0.value) }
            .sorted { $0.day < $1.day }
    }

}

// MARK: - Time Left

/// Time until a meeting, without seconds: "45 minutes" under an hour, the
/// nearest quarter hour up to 4 hours ("3.75 hours"), then one whole unit
/// ("5 hours", "2 days").
private struct TimeLeftText: View {
    let start: Date

    var body: some View {
        TimelineView(.everyMinute) { context in
            let left = start.timeIntervalSince(context.date)
            if left >= 3600 && left < 4 * 3600 {
                let hours = (left / 900).rounded() / 4
                Text(Measurement(value: hours, unit: UnitDuration.hours)
                    .formatted(.measurement(width: .wide, usage: .asProvided,
                                            numberFormatStyle: .number.precision(.fractionLength(0...2)))))
            } else {
                Text(.currentDate, format: .offset(to: start,
                                                   allowedFields: [.day, .hour, .minute],
                                                   maxFieldCount: 1,
                                                   sign: .never))
            }
        }
    }
}

// MARK: - Alarm Row

private struct AlarmRow: View {
    let alarm: TrackedAlarmModel
    let isSkipped: Bool
    var isPaused = false
    var note: String?
    /// This meeting's own first-alert time, if one was picked.
    var firstAlert: Int?
    @ObservedObject private var calService = CalendarService.shared

    private var isCancelled: Bool { alarm.cancellation != nil }
    private var silenced: Bool { isSkipped || isPaused || isCancelled }

    private var cancelledText: Text {
        alarm.cancellation == "declined" ? Text("Declined") : Text("Cancelled")
    }

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
                    .strikethrough(isSkipped || isCancelled)
                    .lineLimit(1)

                if let note {
                    Label {
                        Text(note)
                    } icon: {
                        Text(verbatim: "👉🏽")
                    }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.yellow.opacity(0.35), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }

                if let change = alarm.linkChange {
                    Label(change == "removed" ? "Video link removed" : "Video link changed",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(calendarColor)
                        .frame(width: 8, height: 8)

                    if isCancelled {
                        Label { cancelledText } icon: { Image(systemName: "xmark.circle.fill") }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                    } else if isSkipped {
                        Text("Skipped")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if isPaused {
                        Text("Paused")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        TimeLeftText(start: alarm.eventStartDate)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("·")
                        .foregroundStyle(.secondary)

                    Text(alarm.eventStartDate, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let firstAlert, !silenced {
                        Text("·")
                            .foregroundStyle(.secondary)
                        HStack(spacing: 2) {
                            Image(systemName: "alarm")
                            Text("\(firstAlert) min before")
                        }
                        .font(.caption)
                        .foregroundStyle(.indigo)
                    }
                }
            }

            Spacer()

            if let joinURL = alarm.joinURL, !isCancelled {
                Link(destination: joinURL) {
                    Label("Join", systemImage: "video.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(calendarColor)
            }

            Image(systemName: silenced ? "bell.slash" : "alarm.fill")
                .foregroundStyle(silenced ? AnyShapeStyle(.secondary) : AnyShapeStyle(.indigo.opacity(0.7)))
                .font(.caption)
                .accessibilityLabel(isCancelled ? cancelledText : isSkipped ? Text("Skipped") : isPaused ? Text("Paused") : Text("Alarm set"))
        }
        .padding(.vertical, 2)
        .opacity(silenced ? 0.6 : 1)
        // Otherwise a row with a Join button gets a separator that starts at the button.
        .alignmentGuide(.listRowSeparatorLeading) { dimensions in dimensions[.leading] }
    }
}


#Preview {
    ContentView()
}
