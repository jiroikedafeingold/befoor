import SwiftUI

// MARK: - OnboardingView

struct OnboardingView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var pageIndex = 0
    @State private var calendarGranted = false
    @State private var notifGranted    = false
    @State private var alarmsGranted   = false

    private enum Page: Hashable {
        case welcome, howItWorks
        case calendarPermission, alarmPermission
        case notificationPermission, allSet
    }

    private let pages: [Page] = [
        .welcome, .howItWorks, .calendarPermission, .alarmPermission,
        .notificationPermission, .allSet,
    ]

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
            alarmsGranted = MeetingAlarms.shared.isAuthorized
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
        case .calendarPermission:     CalendarPermissionPage(granted: $calendarGranted)
        case .alarmPermission:        AlarmPermissionPage(granted: $alarmsGranted)
        case .notificationPermission: NotificationPermissionPage(granted: $notifGranted)
        case .allSet:                 AllSetPage(onFinish: finish)
        }
    }

    private var primaryButtonTitle: String {
        switch currentPage {
        case .welcome:                return "Get Started"
        case .calendarPermission:     return calendarGranted ? "Next" : "Continue"
        case .alarmPermission:        return alarmsGranted ? "Next" : "Continue"
        case .notificationPermission: return notifGranted ? "Next" : "Continue"
        default:                      return "Next"
        }
    }

    private var buttonEnabled: Bool {
        switch currentPage {
        case .calendarPermission:     return calendarGranted
        case .alarmPermission:        return true
        case .notificationPermission: return notifGranted
        default:                      return true
        }
    }

    private func advance() {
        // Not required — without it Befoor falls back to notifications — so ask
        // once and move on either way.
        if currentPage == .alarmPermission, !alarmsGranted {
            Task {
                alarmsGranted = await MeetingAlarms.shared.requestAuthorization()
                withAnimation { pageIndex = min(pageIndex + 1, pages.count - 1) }
            }
            return
        }
        withAnimation { pageIndex = min(pageIndex + 1, pages.count - 1) }
    }

    private func finish() {
        settings.hasCompletedOnboarding = true
        Task { await AlarmScheduler.shared.sync() }
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
            description: "Befoor reads your upcoming meetings and sets alarms in advance — so you're never scrambling to join at the last second."
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
                        detail: "Befoor looks at your calendars and sets an alarm before each meeting."
                    )
                    FeatureRow(
                        icon: "alarm",
                        iconColor: .indigo,
                        title: "A real alarm, even on silent",
                        detail: "Befoor's alarms are system alarms, like the Clock app's. Each meeting rings three times — 15, 7 and 1 minute before, which you can change — even when your iPhone is on silent or in a Focus, and even if Befoor isn't open."
                    )
                    FeatureRow(
                        icon: "arrow.clockwise",
                        iconColor: .orange,
                        title: "Always up to date",
                        detail: "Add, move, or cancel a meeting and Befoor updates your alarms the next time it opens or checks in the background."
                    )
                    FeatureRow(
                        icon: "moon.zzz.fill",
                        iconColor: .purple,
                        title: "Snooze or stop",
                        detail: "Snooze rings again after your snooze time. Stop ends the alarm and skips that meeting's remaining alerts."
                    )
                    FeatureRow(
                        icon: "timer",
                        iconColor: .red,
                        title: "Countdown to your meeting",
                        detail: "When a meeting's first alert rings, a countdown to it pops up in the Dynamic Island and on the Lock Screen."
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

// MARK: - Page 3: Calendar Permission

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

// MARK: - Page 4: Alarm Permission

private struct AlarmPermissionPage: View {
    @Binding var granted: Bool

    var body: some View {
        OnboardingPageShell(
            iconName: "alarm.waves.left.and.right.fill",
            iconColor: .orange,
            backgroundGradient: [Color.orange.opacity(0.10), Color.clear],
            title: "Alarms",
            subtitle: granted ? "Alarms allowed!" : "Rings even on silent",
            description: "Befoor sets a real alarm before each meeting — the same kind the Clock app uses — so it rings even when your iPhone is on silent or in a Focus, and even if Befoor isn't open.\n\nIf you don't allow alarms, Befoor uses notifications instead, which follow your ringer switch.\n\nTapping Continue will show a system dialog asking to allow alarms."
        ) {
            if granted {
                GrantedBadge()
            }
        }
    }
}

// MARK: - Page 5: Notification Permission

private struct NotificationPermissionPage: View {
    @Binding var granted: Bool

    var body: some View {
        OnboardingPageShell(
            iconName: "bell.badge.fill",
            iconColor: .indigo,
            backgroundGradient: [Color.indigo.opacity(0.10), Color.clear],
            title: "Notifications",
            subtitle: granted ? "Notifications enabled!" : "How Befoor reaches you",
            description: "Befoor uses notifications for meeting alerts if alarms are off. For the best experience, also enable Time Sensitive Notifications in iOS Settings → Notifications → Befoor.\n\nTapping Continue will show a system dialog asking for notification access."
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

// MARK: - Page 6: All Set

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
