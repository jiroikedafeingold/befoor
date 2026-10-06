import Foundation
import CoreGraphics

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
/// alarm goes off until the meeting starts.
///
/// ActivityKit only lets an app start a Live Activity from the foreground or from
/// a Live Activity intent. Befoor uses both:
/// - Stopping a meeting alarm runs MeetingAlarmIntent, which starts the countdown
///   even though Befoor is in the background.
/// - Opening the app inside a meeting's alarm window starts it directly.
///
/// An activity already on screen is moved on to the following meeting when one
/// starts (back-to-back meetings) and ended otherwise. That needs Befoor to run,
/// which happens on the next alarm action, background refresh or app open; until
/// then a finished meeting's activity shows "Now" via its stale date.
///
/// Battery: the countdown is rendered by the system from the start date, so the
/// activity is only updated when the meeting itself changes.
@MainActor
final class MeetingLiveActivityManager {
    static let shared = MeetingLiveActivityManager()

    /// When a meeting's countdown may appear: the moment its first alert rings.
    private static func showAt(_ meeting: TrackedAlarmModel) -> Date {
        meeting.eventStartDate.addingTimeInterval(-Double(AppSettings.shared.earliestAlertMinutes) * 60)
    }

    private var advanceTimer: Timer?
    private var advanceDate: Date?

    private init() {}

    /// Brings the Live Activity in line with the upcoming meetings.
    /// - Parameters:
    ///   - fromSync: AlarmScheduler passes true. Other callers are ignored while a
    ///     sync is rebuilding the alarm store, because a half-built store would
    ///     look like "no meetings" and end the activity.
    ///   - allowStart: true when called from a Live Activity intent, which may
    ///     start an activity even though the app isn't in the foreground.
    func refresh(fromSync: Bool = false, allowStart: Bool = false) async {
        #if !targetEnvironment(macCatalyst)
        if !fromSync && AlarmScheduler.shared.syncInProgress { return }

        let settings = AppSettings.shared
        let activities = Activity<NextMeetingAttributes>.activities

        guard settings.isEnabled,
              settings.liveActivityEnabled,
              ActivityAuthorizationInfo().areActivitiesEnabled else {
            cancelAdvance()
            for activity in activities { await activity.end(nil, dismissalPolicy: .immediate) }
            return
        }

        let now = Date()
        let meetings = upcomingMeetings(after: now)

        if let current = meetings.first, Self.showAt(current) <= now {
            let content = self.content(for: current, following: meetings.dropFirst().first)
            if let activity = activities.first {
                if activity.content.state != content.state { await activity.update(content) }
                for extra in activities.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
            } else if allowStart || UIApplication.shared.applicationState == .active {
                do {
                    _ = try Activity.request(attributes: NextMeetingAttributes(), content: content)
                } catch {
                    print("[Befoor] Live Activity request failed: \(error)")
                }
            }
        } else {
            for activity in activities { await activity.end(nil, dismissalPolicy: .immediate) }
        }

        // While Befoor happens to be running, move on at the next transition: the
        // current meeting starting, or the next one's alarm ringing.
        let transitions = meetings.prefix(2).flatMap { [Self.showAt($0), $0.eventStartDate] }
        if let next = transitions.filter({ $0 > now }).min() {
            armAdvance(at: next)
        } else {
            cancelAdvance()
        }
        #endif
    }

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
            meetingID: meeting.notificationIdentifier,
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
        // Goes stale at the start, so the countdown switches to "Now" on time even
        // if Befoor isn't running to move it on.
        return ActivityContent(state: state, staleDate: meeting.eventStartDate)
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
