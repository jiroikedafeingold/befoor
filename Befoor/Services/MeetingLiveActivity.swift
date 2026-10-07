import Foundation
import CoreGraphics
import OSLog

#if !targetEnvironment(macCatalyst)
import ActivityKit
import UIKit

// MARK: - Attributes

/// Data for the "next meeting" Live Activity (Dynamic Island + Lock Screen).
///
/// IMPORTANT: an identical copy lives in BeforeWidget/BeforeWidgetLiveActivity.swift.
/// ActivityKit matches the two by type name and Codable shape, so any change here
/// must be made there too.
struct NextMeetingAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// The meeting's notification identifier (event id + start time).
        var meetingID: String
        var title: String
        var startDate: Date
        var endDate: Date?
        /// When Befoor's alarm rings. Nil for 1:1s handled by the People tab.
        var alarmDate: Date?
        var calendarName: String?
        /// sRGB components of the calendar color.
        var calendarRGB: [Double]?
        var location: String?
        var personName: String?
        var followUp: String?
        var attendeeCount: Int
        var nextTitle: String?
        var nextStartDate: Date?
    }
}
#endif

// MARK: - Manager

/// Shows a countdown to the next meeting in a Live Activity, from the moment its
/// first alert rings until 10 minutes after the meeting starts.
///
/// Befoor doesn't run in the background, so the activity has to start without it:
/// - Whenever Befoor runs (app open, alarm Stop/Snooze, background refresh where
///   allowed), it books an activity for each of the next few meetings that iOS
///   starts by itself at the first alert. iOS requires an alert when a booked
///   activity starts; it uses the alarm sound and fires together with the alarm.
/// - Opening the app, or stopping an alarm, inside a meeting's window starts one
///   directly if it isn't already showing.
///
/// Ending: the content goes stale 10 minutes after the start (showing "Now"), and
/// Befoor removes it the next time it runs after that — a timer if the app is
/// open, otherwise the next background refresh, app open or alarm action.
///
/// Battery: the countdown is rendered by the system from the start date, so the
/// activity is only updated when the meeting itself changes.
@MainActor
final class MeetingLiveActivityManager {
    static let shared = MeetingLiveActivityManager()

    /// Decisions are logged so a countdown that didn't show (or vanished) can be
    /// traced from the device log.
    private let log = Logger(subsystem: "com.befoor.app", category: "LiveActivity")

    /// How long a meeting's activity stays up after the meeting starts.
    static let linger: TimeInterval = 10 * 60

    /// Booked activities count toward the system's per-app limit, so only book a few.
    private static let maxScheduled = 3

    /// When a meeting's countdown appears: the moment its first alert rings.
    private static func showAt(_ meeting: TrackedAlarmModel) -> Date {
        meeting.eventStartDate.addingTimeInterval(-Double(AppSettings.shared.earliestAlertMinutes) * 60)
    }

    private var advanceTimer: Timer?
    private var advanceDate: Date?

    private init() {}

    /// Brings the Live Activities in line with the upcoming meetings.
    /// - Parameters:
    ///   - fromSync: AlarmScheduler passes true. Other callers are ignored while a
    ///     sync is rebuilding the alarm store, because a half-built store would
    ///     look like "no meetings" and end the activity.
    ///   - allowStart: true when called from a Live Activity intent, which may
    ///     start or book an activity even though the app isn't in the foreground.
    func refresh(fromSync: Bool = false, allowStart: Bool = false) async {
        #if !targetEnvironment(macCatalyst)
        if !fromSync && AlarmScheduler.shared.syncInProgress { return }

        let settings = AppSettings.shared
        let all = Activity<NextMeetingAttributes>.activities
        let pending = all.filter(Self.isPending)
        let live = all.filter { !Self.isPending($0) }

        guard settings.isEnabled,
              settings.liveActivityEnabled,
              ActivityAuthorizationInfo().areActivitiesEnabled else {
            log.notice("refresh: disabled (enabled=\(settings.isEnabled), toggle=\(settings.liveActivityEnabled), system=\(ActivityAuthorizationInfo().areActivitiesEnabled)); ending \(all.count)")
            cancelAdvance()
            for activity in all { await activity.end(nil, dismissalPolicy: .immediate) }
            return
        }

        let now = Date()
        let meetings = upcomingMeetings(after: now)
        let canCreate = allowStart || UIApplication.shared.applicationState == .active
        log.notice("refresh: fromSync=\(fromSync) canCreate=\(canCreate) meetings=\(meetings.count) next=\(meetings.first?.eventTitle ?? "-", privacy: .private) live=\(live.map { $0.content.state.meetingID.suffix(12) }.joined(separator: ","), privacy: .public) pending=\(pending.count)")

        // 1. What should be on screen: the next meeting once its first alert has
        //    rung; otherwise a meeting that started less than 10 minutes ago.
        var keepID: String?
        if let next = meetings.first, Self.showAt(next) <= now {
            let content = self.content(for: next, following: meetings.dropFirst().first)
            keepID = content.state.meetingID
            // Prefer the activity already showing this meeting (a booked one that
            // started by itself), else repurpose whichever is up.
            if let activity = live.first(where: { $0.content.state.meetingID == keepID }) ?? live.first {
                if activity.content.state != content.state { await activity.update(content) }
            } else if pending.contains(where: { $0.content.state.meetingID == keepID }) {
                // Its booked activity is starting right now; the app can still see
                // it as pending for a moment. Leave it be.
            } else if canCreate {
                request(content)
            }
        } else if let started = live.first(where: {
            $0.content.state.startDate <= now && $0.content.state.startDate.addingTimeInterval(Self.linger) > now
        }) {
            keepID = started.content.state.meetingID
        }

        // Anything else on screen is finished or superseded.
        let showing = live.first { $0.content.state.meetingID == keepID } ?? (keepID == nil ? nil : live.first)
        for activity in live where activity.id != showing?.id {
            log.notice("refresh: ending \(activity.content.state.meetingID.suffix(12), privacy: .public) (keep=\(keepID?.suffix(12) ?? "none", privacy: .public))")
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        // 2. Book activities that start by themselves at later meetings' first alert.
        await reconcileScheduled(meetings: meetings, pending: pending, now: now,
                                 keepID: keepID, canCreate: canCreate)

        // 3. While Befoor happens to be running, act at the next transition: a
        //    first alert, or 10 minutes after a meeting started.
        var transitions = meetings.prefix(2).map { Self.showAt($0) }
        if let showing {
            transitions.append(showing.content.state.startDate.addingTimeInterval(Self.linger))
        }
        if let nextChange = transitions.filter({ $0 > now }).min() {
            armAdvance(at: nextChange)
        } else {
            cancelAdvance()
        }
        #endif
    }

    // MARK: - Booking

    #if !targetEnvironment(macCatalyst)
    private func reconcileScheduled(
        meetings: [TrackedAlarmModel],
        pending: [Activity<NextMeetingAttributes>],
        now: Date,
        keepID: String?,
        canCreate: Bool
    ) async {
        // The booked start needs an alert sound, so only book when alerts make a
        // sound anyway; it then rings in step with the meeting's first alarm.
        // 1:1s handled by the People tab have no alarm, so they're not booked.
        var targets: [(content: ActivityContent<NextMeetingAttributes.ContentState>, showAt: Date)] = []
        if AppSettings.shared.soundEnabled {
            for (index, meeting) in meetings.enumerated() {
                let showAt = Self.showAt(meeting)
                guard showAt > now else { continue }
                let following = index + 1 < meetings.count ? meetings[index + 1] : nil
                let content = self.content(for: meeting, following: following)
                guard content.state.alarmDate != nil else { continue }
                targets.append((content, showAt))
                if targets.count == Self.maxScheduled { break }
            }
        }

        // Never end the current meeting's activity: at its start time the app can
        // still see it as pending, and ending it then kills it the moment it appears.
        var keepIDs = Set(targets.map(\.content.state.meetingID))
        if let keepID { keepIDs.insert(keepID) }
        for activity in pending where !keepIDs.contains(activity.content.state.meetingID) {
            log.notice("booking: ending pending \(activity.content.state.meetingID.suffix(12), privacy: .public)")
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        for target in targets {
            if let existing = pending.first(where: { $0.content.state.meetingID == target.content.state.meetingID }) {
                if existing.content.state != target.content.state { await existing.update(target.content) }
            } else if canCreate {
                book(target.content, at: target.showAt)
            }
        }
    }

    private func book(_ content: ActivityContent<NextMeetingAttributes.ContentState>, at date: Date) {
        let state = content.state
        var body = "Starts at \(state.startDate.formatted(date: .omitted, time: .shortened))"
        if let location = state.location { body += " · \(location)" }
        let selected = AppSettings.shared.selectedSound
        let sound: AlertConfiguration.AlertSound = selected == .systemDefault
            ? .default
            : .named(selected.rawValue + ".caf")
        let alert = AlertConfiguration(
            title: LocalizedStringResource(stringLiteral: state.title),
            body: LocalizedStringResource(stringLiteral: body),
            sound: sound
        )
        do {
            _ = try Activity.request(attributes: NextMeetingAttributes(), content: content,
                                     pushType: nil, style: .standard,
                                     alertConfiguration: alert, start: date)
        } catch {
            print("[Befoor] Booking Live Activity failed: \(error)")
        }
    }

    private func request(_ content: ActivityContent<NextMeetingAttributes.ContentState>) {
        log.notice("refresh: starting \(content.state.meetingID.suffix(12), privacy: .public)")
        do {
            _ = try Activity.request(attributes: NextMeetingAttributes(), content: content)
        } catch {
            print("[Befoor] Live Activity request failed: \(error)")
        }
    }

    private static func isPending(_ activity: Activity<NextMeetingAttributes>) -> Bool {
        activity.activityState == .pending
    }
    #endif

    // MARK: - Advancing

    private func armAdvance(at date: Date) {
        guard advanceDate != date else { return }
        cancelAdvance()
        let timer = Timer(fire: date.addingTimeInterval(1), interval: 0, repeats: false) { _ in
            Task { @MainActor in
                MeetingLiveActivityManager.shared.advanceDate = nil
                await MeetingLiveActivityManager.shared.refresh()
            }
        }
        timer.tolerance = 15
        RunLoop.main.add(timer, forMode: .common)
        advanceTimer = timer
        advanceDate = date
    }

    private func cancelAdvance() {
        advanceTimer?.invalidate()
        advanceTimer = nil
        advanceDate = nil
    }

    // MARK: - Building the state

    /// Upcoming meetings in start order, without the duplicates the store can hold.
    private func upcomingMeetings(after now: Date) -> [TrackedAlarmModel] {
        var seen = Set<String>()
        return TrackedAlarmsStore.shared.alarms.values
            .filter { $0.eventStartDate > now }
            .sorted { $0.eventStartDate < $1.eventStartDate }
            .filter { seen.insert("\($0.eventTitle)|\(Int($0.eventStartDate.timeIntervalSince1970))").inserted }
    }

    #if !targetEnvironment(macCatalyst)
    private func content(
        for meeting: TrackedAlarmModel,
        following: TrackedAlarmModel?
    ) -> ActivityContent<NextMeetingAttributes.ContentState> {
        let settings = AppSettings.shared
        let calendarService = CalendarService.shared
        let event = calendarService.event(identifier: meeting.eventIdentifier,
                                          startingAt: meeting.eventStartDate)
        let calendar = calendarService.calendar(for: meeting.calendarIdentifier) ?? event?.calendar
        let person = settings.peopleEnabled
            ? event.flatMap { AlarmScheduler.shared.lookUpPersonInfo(for: $0) }
            : nil

        // Only mention the following meeting if it's the same day.
        let sameDayFollowing = following.flatMap {
            Calendar.current.isDate($0.eventStartDate, inSameDayAs: meeting.eventStartDate) ? $0 : nil
        }

        let state = NextMeetingAttributes.ContentState(
            // Includes the alert timing and sound, which are baked into a booked
            // activity's start time and alert; changing either rebooks it.
            meetingID: "\(meeting.notificationIdentifier)|\(settings.earliestAlertMinutes)|\(settings.selectedSound.rawValue)",
            title: meeting.eventTitle,
            startDate: meeting.eventStartDate,
            endDate: event?.endDate,
            // 1:1s with a tracked person don't get a Befoor alarm (see AlarmScheduler).
            alarmDate: person == nil
                ? meeting.eventStartDate.addingTimeInterval(-Double(settings.earliestAlertMinutes) * 60)
                : nil,
            calendarName: calendar?.title,
            calendarRGB: Self.rgb(calendar?.cgColor),
            location: Self.trimmed(event?.location),
            personName: person?.name,
            followUp: Self.trimmed(person?.followUps.first),
            attendeeCount: event?.attendees?.count ?? 0,
            nextTitle: sameDayFollowing?.eventTitle,
            nextStartDate: sameDayFollowing?.eventStartDate
        )
        // Goes stale 10 minutes after the start, when it's due to be removed, so it
        // reads as finished even if Befoor isn't running to remove it right then.
        return ActivityContent(state: state, staleDate: meeting.eventStartDate.addingTimeInterval(Self.linger))
    }
    #endif

    /// Keeps strings short — the whole activity payload must stay under 4 KB.
    private static func trimmed(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text.count > 80 ? String(text.prefix(77)) + "…" : text
    }

    private static func rgb(_ color: CGColor?) -> [Double]? {
        guard let color,
              let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
              let components = color.converted(to: sRGB, intent: .defaultIntent, options: nil)?.components,
              components.count >= 3 else { return nil }
        return components.prefix(3).map(Double.init)
    }
}
