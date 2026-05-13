import SwiftUI

// MARK: - OnboardingView

struct OnboardingView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var pageIndex = 0
    @State private var calendarGranted = false
    @State private var contactsGranted = false
    @State private var notifGranted    = false
    @State private var roleChosen      = false

    private enum Page: Hashable {
        case welcome, howItWorks, people, deviceRole
        case calendarPermission, contactsPermission
        case notificationPermission, allSet
    }

    private var pages: [Page] {
        var p: [Page] = [.welcome, .howItWorks, .people, .deviceRole]
        if settings.isMainDevice {
            p.append(contentsOf: [.calendarPermission, .contactsPermission])
        }
        p.append(contentsOf: [.notificationPermission, .allSet])
        return p
    }

    private var currentPage: Page {
        pages[min(pageIndex, pages.count - 1)]
    }

    var body: some View {
        TabView(selection: $pageIndex) {
            ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                pageView(for: page).tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(.easeInOut, value: pageIndex)
        .ignoresSafeArea(edges: .top)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 16) {
                if currentPage != .allSet {
                    Button(action: advance) {
                        Text(primaryButtonTitle)
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(buttonEnabled ? Color.indigo : Color.secondary.opacity(0.3))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .disabled(!buttonEnabled)
                    .animation(.easeInOut(duration: 0.2), value: buttonEnabled)
                }

                PageDots(current: pageIndex, total: pages.count)
            }
            .frame(maxWidth: 600)
            .padding(.horizontal, 32)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .background(.clear)
        }
        .task {
            calendarGranted = CalendarService.shared.isAuthorized
            contactsGranted = CalendarService.shared.isContactsAuthorized
            let status = await NotificationService.shared.checkPermission()
            notifGranted = (status == .authorized)
        }
    }

    // MARK: Helpers

    @ViewBuilder
    private func pageView(for page: Page) -> some View {
        switch page {
        case .welcome:                WelcomePage()
        case .howItWorks:             HowItWorksPage()
        case .people:                 PeoplePage()
        case .deviceRole:             DeviceRolePage(roleChosen: $roleChosen)
        case .calendarPermission:     CalendarPermissionPage(granted: $calendarGranted)
        case .contactsPermission:     ContactsPermissionPage(granted: $contactsGranted)
        case .notificationPermission: NotificationPermissionPage(granted: $notifGranted)
        case .allSet:                 AllSetPage(onFinish: finish)
        }
    }

    private var primaryButtonTitle: String {
        switch currentPage {
        case .welcome:                return "Get Started"
        case .deviceRole:             return roleChosen ? "Next" : "Choose a Role"
        case .calendarPermission:     return calendarGranted ? "Next" : "Continue"
        case .contactsPermission:     return contactsGranted ? "Next" : "Continue"
        case .notificationPermission: return notifGranted ? "Next" : "Continue"
        default:                      return "Next"
        }
    }

    private var buttonEnabled: Bool {
        switch currentPage {
        case .deviceRole:             return roleChosen
        case .calendarPermission:     return calendarGranted
        case .contactsPermission:     return true
        case .notificationPermission: return notifGranted
        default:                      return true
        }
    }

    private func advance() {
        if currentPage == .contactsPermission, !contactsGranted {
            Task {
                contactsGranted = await CalendarService.shared.requestContactsAccess()
                withAnimation { pageIndex = min(pageIndex + 1, pages.count - 1) }
            }
            return
        }
        withAnimation { pageIndex = min(pageIndex + 1, pages.count - 1) }
    }

    private func finish() {
        settings.hasCompletedOnboarding = true
        if settings.isMainDevice {
            Task { await AlarmScheduler.shared.sync() }
        }
    }
}

// MARK: - Page Dots

private struct PageDots: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i == current ? Color.indigo : Color.secondary.opacity(0.3))
                    .frame(width: i == current ? 20 : 8, height: 8)
                    .animation(.spring(response: 0.3), value: current)
            }
        }
    }
}

// MARK: - Page 1: Welcome

private struct WelcomePage: View {
    var body: some View {
        OnboardingPageShell(
            iconName: "alarm.fill",
            iconColor: .indigo,
            backgroundGradient: [Color.indigo.opacity(0.08), Color.clear],
            title: "Welcome to Befoor",
            subtitle: "The alarm clock for your calendar",
            description: "Befoor reads your upcoming meetings and sets alarms in advance — so you're never scrambling to join at the last second. It also detects your 1:1 meetings and helps you keep track of notes, follow-ups, and reminders for each person."
        )
    }
}

// MARK: - Page 2: How It Works

private struct HowItWorksPage: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Hero icon — gradient spans full width
                ZStack {
                    LinearGradient(
                        colors: [Color.purple.opacity(0.12), Color.clear],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)

                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.purple.opacity(0.15))
                                .frame(width: 120, height: 120)
                            Image(systemName: "sparkles")
                                .font(.system(size: 52, weight: .medium))
                                .foregroundStyle(Color.purple)
                        }
                        .padding(.top, 60)

                        Text("How Befoor Works")
                            .font(.title.bold())
                    }
                }

                VStack(alignment: .leading, spacing: 20) {
                    FeatureRow(
                        icon: "calendar",
                        iconColor: .green,
                        title: "Reads your calendar",
                        detail: "Befoor watches all your calendars and keeps your alarms in sync automatically."
                    )
                    FeatureRow(
                        icon: "alarm",
                        iconColor: .indigo,
                        title: "Rings before each meeting",
                        detail: "The first alert rings at your lead time, with two silent follow-up banners in between, and a final ring at the event start. Dismiss any alert to cancel the rest."
                    )
                    FeatureRow(
                        icon: "arrow.clockwise",
                        iconColor: .orange,
                        title: "Always up to date",
                        detail: "Add, reschedule, or cancel a meeting and Befoor updates your alarms in the background."
                    )
                    FeatureRow(
                        icon: "moon.zzz.fill",
                        iconColor: .purple,
                        title: "Snooze or dismiss",
                        detail: "Tap Snooze to delay a reminder, or Dismiss to silence the entire sequence for that event."
                    )
                    FeatureRow(
                        icon: "xmark.app.fill",
                        iconColor: .red,
                        title: "Keep the app running",
                        detail: "Befoor uses a background audio session to play alarms through silent mode. Force-quitting the app ends that session, so alarms will fall back to standard notification sounds."
                    )
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: 600, alignment: .leading)
                .padding(.vertical, 28)

                Spacer(minLength: 140)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Page 3: People & 1:1 Meetings

private struct PeoplePage: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Hero area — gradient spans full width, content centered in 600pt column
                ZStack {
                    LinearGradient(
                        colors: [Color.blue.opacity(0.12), Color.clear],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)

                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.15))
                                .frame(width: 120, height: 120)
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 52, weight: .medium))
                                .foregroundStyle(Color.blue)
                        }
                        .padding(.top, 60)

                        Text("People & 1:1s")
                            .font(.title.bold())
                    }
                }

                VStack(alignment: .leading, spacing: 20) {
                    FeatureRow(
                        icon: "person.crop.circle.badge.plus",
                        iconColor: .blue,
                        title: "Track your 1:1s",
                        detail: "Befoor detects 1:1 meetings on your calendar and automatically builds a People list so you always know who you're meeting."
                    )
                    FeatureRow(
                        icon: "note.text",
                        iconColor: .indigo,
                        title: "Meeting notes",
                        detail: "Jot down notes during or after each meeting. They're saved by date so you can look back at past conversations."
                    )
                    FeatureRow(
                        icon: "arrow.uturn.forward",
                        iconColor: .orange,
                        title: "Follow-ups",
                        detail: "Create follow-up items with due dates and optional recurrence. Mark them complete when done — they carry forward until you do."
                    )
                    FeatureRow(
                        icon: "pin.fill",
                        iconColor: .purple,
                        title: "Long-term notes",
                        detail: "Pin important context about a person — preferences, ongoing topics, or anything you want to remember across meetings."
                    )
                    FeatureRow(
                        icon: "bell.fill",
                        iconColor: .red,
                        title: "Reminders",
                        detail: "Set a reminder for a specific person and get notified at the time you choose — great for birthday wishes or check-ins."
                    )
                    FeatureRow(
                        icon: "icloud.fill",
                        iconColor: .teal,
                        title: "Synced via iCloud",
                        detail: "Your People data syncs across all your devices through iCloud, so your notes and follow-ups are always with you."
                    )
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: 600, alignment: .leading)
                .padding(.vertical, 28)

                Spacer(minLength: 140)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Page 4: Device Role

private struct DeviceRolePage: View {
    @Binding var roleChosen: Bool
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ZStack {
                    LinearGradient(
                        colors: [Color.cyan.opacity(0.12), Color.clear],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)

                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.cyan.opacity(0.15))
                                .frame(width: 120, height: 120)
                            Image(systemName: "iphone.and.ipad")
                                .font(.system(size: 48, weight: .medium))
                                .foregroundStyle(Color.cyan)
                        }
                        .padding(.top, 60)

                        Text("Device Role")
                            .font(.title.bold())
                    }
                }

                VStack(spacing: 16) {
                    Text("Is this your primary device?")
                        .font(.headline)

                    Text("Your primary device syncs with your calendar to detect 1:1 meetings and create people. Other devices receive that data via iCloud and let you add notes and follow-ups.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    VStack(spacing: 12) {
                        Button {
                            settings.claimAsMainDevice()
                            roleChosen = true
                        } label: {
                            HStack {
                                Image(systemName: "star.fill")
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Primary Device")
                                        .font(.body.weight(.semibold))
                                    Text("Syncs calendar & detects 1:1s")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.8))
                                }
                                Spacer()
                                if settings.isMainDevice {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title3)
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(settings.isMainDevice ? Color.indigo : Color.indigo.opacity(0.7))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }

                        Button {
                            roleChosen = true
                        } label: {
                            HStack {
                                Image(systemName: "icloud.and.arrow.down")
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Secondary Device")
                                        .font(.body.weight(.semibold))
                                    Text("Reads from iCloud, adds notes")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if roleChosen && !settings.isMainDevice {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.green)
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color(uiColor: .secondarySystemBackground))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: 600)
                .padding(.top, 28)

                Spacer(minLength: 140)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Page 5: Calendar Permission

private struct CalendarPermissionPage: View {
    @Binding var granted: Bool

    var body: some View {
        OnboardingPageShell(
            iconName: "calendar.badge.checkmark",
            iconColor: .green,
            backgroundGradient: [Color.green.opacity(0.10), Color.clear],
            title: "Connect Your Calendar",
            subtitle: granted ? "Access granted!" : "Befoor needs to read your events",
            description: "Your calendar data stays private on your device. Befoor only reads event titles, times, and calendars — nothing is sent anywhere.\n\nTapping Continue will show a system dialog asking for calendar access."
        ) {
            if !granted {
                PermissionButton(label: "Continue", color: .green) {
                    Task {
                        granted = await CalendarService.shared.requestAccess()
                    }
                }
            } else {
                GrantedBadge()
            }
        }
    }
}

// MARK: - Page 6: Contacts Permission (optional)

private struct ContactsPermissionPage: View {
    @Binding var granted: Bool

    var body: some View {
        OnboardingPageShell(
            iconName: "person.crop.circle.badge.checkmark",
            iconColor: .blue,
            backgroundGradient: [Color.blue.opacity(0.10), Color.clear],
            title: "Connect Contacts",
            subtitle: granted ? "Access granted!" : "Better name resolution (optional)",
            description: "Befoor can look up attendee names from your Contacts to better identify people in your 1:1 meetings. This is optional — you can skip this step.\n\nTapping Continue will show a system dialog asking for contacts access."
        ) {
            if !granted {
                PermissionButton(label: "Continue", color: .blue) {
                    Task {
                        granted = await CalendarService.shared.requestContactsAccess()
                    }
                }
            } else {
                GrantedBadge()
            }
        }
    }
}

// MARK: - Page 7: Notification Permission

private struct NotificationPermissionPage: View {
    @Binding var granted: Bool

    var body: some View {
        OnboardingPageShell(
            iconName: "bell.badge.fill",
            iconColor: .indigo,
            backgroundGradient: [Color.indigo.opacity(0.10), Color.clear],
            title: "Notifications",
            subtitle: granted ? "Notifications enabled!" : "How Befoor reaches you",
            description: "Befoor delivers alarms as notifications so you know when a meeting is coming up. For the best experience, also enable Time Sensitive Notifications in iOS Settings → Notifications → Befoor.\n\nTapping Continue will show a system dialog asking for notification access."
        ) {
            if !granted {
                PermissionButton(label: "Continue", color: .indigo) {
                    Task {
                        granted = await NotificationService.shared.requestPermission()
                    }
                }
            } else {
                GrantedBadge()
            }
        }
    }
}

// MARK: - Page 8: All Set

private struct AllSetPage: View {
    let onFinish: () -> Void
    @State private var animateCheck = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 160, height: 160)
                    .scaleEffect(animateCheck ? 1.0 : 0.5)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 90))
                    .foregroundStyle(Color.green)
                    .scaleEffect(animateCheck ? 1.0 : 0.3)
                    .opacity(animateCheck ? 1.0 : 0.0)
            }
            .animation(.spring(response: 0.6, dampingFraction: 0.65), value: animateCheck)
            .onAppear { animateCheck = true }

            VStack(spacing: 12) {
                Text("You're all set!")
                    .font(.largeTitle.bold())
                    .padding(.top, 32)

                Text("Befoor is ready to keep you on time.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            Spacer()

            Button(action: onFinish) {
                Text("Start Using Befoor")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.indigo)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .frame(maxWidth: 600)
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }
}

// MARK: - Shared Components

private struct OnboardingPageShell<ActionContent: View>: View {
    let iconName: String
    let iconColor: Color
    let backgroundGradient: [Color]
    let title: String
    let subtitle: String
    let description: String
    var actionContent: (() -> ActionContent)?

    init(
        iconName: String,
        iconColor: Color,
        backgroundGradient: [Color],
        title: String,
        subtitle: String,
        description: String,
        @ViewBuilder actionContent: @escaping () -> ActionContent
    ) {
        self.iconName = iconName
        self.iconColor = iconColor
        self.backgroundGradient = backgroundGradient
        self.title = title
        self.subtitle = subtitle
        self.description = description
        self.actionContent = actionContent
    }

    var body: some View {
        VStack(spacing: 0) {
            // Hero area — gradient spans full width, icon is centered
            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: backgroundGradient,
                    startPoint: .top, endPoint: .bottom
                )
                .frame(maxWidth: .infinity)
                .frame(height: 300)

                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(iconColor.opacity(0.15))
                            .frame(width: 120, height: 120)
                        Image(systemName: iconName)
                            .font(.system(size: 52, weight: .medium))
                            .foregroundStyle(iconColor)
                    }
                    .padding(.top, 60)
                }
                .padding(.bottom, 24)
            }

            // Text content — constrained width, left-aligned within centered column
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.title.bold())

                Text(subtitle)
                    .font(.headline)
                    .foregroundStyle(iconColor)

                Text(description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)

                if let actionContent {
                    actionContent()
                        .padding(.top, 12)
                }
            }
            .frame(maxWidth: 600, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 28)

            Spacer(minLength: 140)
        }
        .frame(maxWidth: .infinity)
    }
}

// Convenience init for pages with no action button
extension OnboardingPageShell where ActionContent == EmptyView {
    init(
        iconName: String,
        iconColor: Color,
        backgroundGradient: [Color],
        title: String,
        subtitle: String,
        description: String
    ) {
        self.init(
            iconName: iconName,
            iconColor: iconColor,
            backgroundGradient: backgroundGradient,
            title: title,
            subtitle: subtitle,
            description: description,
            actionContent: { EmptyView() }
        )
    }
}

private struct PermissionButton: View {
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(color)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}

private struct GrantedBadge: View {
    var body: some View {
        Label("Access Granted", systemImage: "checkmark.circle.fill")
            .font(.body.weight(.semibold))
            .foregroundStyle(.green)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.green.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

#Preview {
    OnboardingView()
}
