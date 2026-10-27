import SwiftUI
import Observation

/// The primary panoramic Dynamic Island content when expanded.
/// Features a compact top navigation strip, a left-side AMORA companion card,
/// and a right-side active page panel supporting Home, AI Talk, Timer, Clipboard,
/// Notes, File Shelf, Automations, and GitHub Activity.
@MainActor
struct WideDynamicIslandContentView: View {
    var topInset: CGFloat = 0
    @Bindable var nav = IslandNavigationModel.shared
    @Bindable var robot = AMORARobot.shared
    @Bindable var assistant = AssistantManager.shared
    @Bindable var coordinator = AmoraActionExecutionCoordinator.shared
    @Bindable var timer = TimerService.shared
    @Bindable var music = MusicService.shared
    private var personality = PersonalityEngine.shared
    private var palette: ThemePalette { AppState.shared.settings.palette }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 4) {
                // Top Navigation Strip (in the ears flanking the physical notch)
                IslandNavBar(topInset: topInset)

                // Main Content Card (below the notch)
                HStack(spacing: 12) {
                    // LEFT: AMORA Companion Panel
                    AmoraCompanionPanel()
                        .frame(width: 220)

                    // Subtle Vertical Separator
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 1)
                        .padding(.vertical, 4)

                    // RIGHT: Active Page Content
                    ActivePageContent()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(red: 0.10, green: 0.11, blue: 0.13))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            // Quick Actions Floating Menu Overlay
            if nav.isQuickMenuOpen {
                Color.black.opacity(0.001)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                            nav.isQuickMenuOpen = false
                        }
                    }

                IslandQuickMenu()
                    .padding(.top, max(topInset, 34) + 4)
                    .padding(.leading, 64)
                    .zIndex(100)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .amoraPageSwipe)) { note in
            guard let direction = note.userInfo?[AMORAPageSwipe.directionKey] as? AMORAPageSwipe else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                if direction == .next {
                    nav.nextPage()
                } else {
                    nav.previousPage()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .amoraPageKeyboard)) { note in
            guard let direction = note.userInfo?[AMORAPageSwipe.directionKey] as? AMORAPageSwipe else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                if direction == .next {
                    nav.nextPage()
                } else {
                    nav.previousPage()
                }
            }
        }
        .onChange(of: assistant.state) { _, newState in
            if newState == .thinking || newState == .responding {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    nav.navigateTo(.aiTalk)
                }
            }
        }
    }
}

/// Left column companion panel: displays the AMORA mascot, contextual status badges,
/// and concise companion message/task summary.
@MainActor
struct AmoraCompanionPanel: View {
    @Bindable var robot = AMORARobot.shared
    @Bindable var assistant = AssistantManager.shared
    @Bindable var coordinator = AmoraActionExecutionCoordinator.shared
    @Bindable var timer = TimerService.shared
    @Bindable var music = MusicService.shared
    @Bindable var gitHub = GitHubService.shared
    @Bindable var nav = IslandNavigationModel.shared
    @Bindable var proactive = AmoraProactiveService.shared
    @Bindable var automation = AmoraAutomationService.shared
    private var personality = PersonalityEngine.shared
    private var palette: ThemePalette { AppState.shared.settings.palette }

    private var idleCompanionGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            return "Good morning! Ready when you are."
        case 12..<17:
            return "Good afternoon. Here if you need me."
        case 17..<22:
            return "Good evening. What's on your mind?"
        default:
            return "Working late? I'm here with you."
        }
    }

    private var statusMessage: String {
        if let reactionMessage = robot.activeReactionMessage {
            return reactionMessage
        } else if let notification = automation.currentNotification {
            return notification.message
        } else if let suggestion = proactive.currentSuggestion {
            return suggestion.message
        } else if coordinator.state != .idle {
            switch coordinator.state {
            case .awaitingConfirmation:
                return "Needs your confirmation"
            case .executing:
                if let activeItem = coordinator.items.first(where: { $0.status == .executing }) {
                    return "\(activeItem.title)…"
                }
                return "Taking care of that…"
            case .completed:
                return "All set!"
            case .failed:
                return coordinator.isCancelled ? "Action cancelled" : "Couldn't complete that action"
            case .idle, .thinking:
                return "Taking care of that…"
            }
        } else if assistant.state == .thinking {
            return "Thinking it through…"
        } else if assistant.state == .responding, let resp = assistant.response, !resp.isEmpty {
            let firstLine = resp.split(whereSeparator: \.isNewline).first.map(String.init) ?? resp
            if firstLine.count <= 42 {
                return firstLine
            }
            return "Here is what I found:"
        } else if assistant.state == .failed {
            return "Something got in the way."
        } else if assistant.state == .cancelled {
            return "Request stopped."
        } else if timer.isRunning {
            return "Focus timer (\(timer.formattedTime))"
        } else if music.isPlaying && !music.trackTitle.isEmpty {
            return "Listening to \(music.trackTitle)"
        } else {
            let battery = BatteryService.shared
            if battery.hasBattery && !battery.isCharging && battery.level <= 20 {
                return "Battery at \(battery.level)% — let's plug in soon."
            } else if battery.hasBattery && battery.isCharging {
                return "Charging up nicely (\(battery.level)%)."
            } else if nav.selectedPage == .github && gitHub.authState.isConnected {
                if let cal = gitHub.contributionCalendar, cal.totalContributions > 0 {
                    let plural = cal.totalContributions == 1 ? "contribution" : "contributions"
                    return "\(cal.totalContributions) \(plural) in past year"
                } else if let user = gitHub.user {
                    return "@\(user.login) activity synced"
                } else {
                    return "GitHub connected"
                }
            } else if let msg = personality.message, !msg.isEmpty {
                return msg
            } else {
                return idleCompanionGreeting
            }
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            // Mascot
            AMORARobotView(robot: robot, compact: false)
                .frame(width: 56, height: 48)
                .padding(.top, 4)
                .padding(.bottom, robot.isDancing ? 12 : 0)
                .animation(.easeInOut(duration: 0.35), value: robot.isDancing)

            // Contextual status badge
            if let reaction = robot.activeReaction {
                AmoraAccessibleStatusBadge(
                    text: reaction.badgeText,
                    systemImage: reaction.badgeIcon,
                    tintColor: reaction == .affection ? .pink : (reaction == .grumpy ? .orange : (reaction == .sad ? .blue : palette.accent))
                )
            } else if let notification = automation.currentNotification {
                AmoraAccessibleStatusBadge(
                    text: notification.triggerName,
                    systemImage: notification.triggerIcon,
                    tintColor: palette.accent
                )
            } else if let suggestion = proactive.currentSuggestion {
                AmoraAccessibleStatusBadge(text: suggestion.trigger.displayName, systemImage: "sparkles", tintColor: palette.accent)
            } else if assistant.state == .thinking {
                AmoraAccessibleStatusBadge(text: "Thinking", systemImage: "sparkles", tintColor: palette.accent)
            } else if coordinator.state != .idle {
                AmoraAccessibleStatusBadge(text: "Action", systemImage: "bolt.fill", tintColor: .orange)
            } else if timer.isRunning {
                AmoraAccessibleStatusBadge(text: timer.formattedTime, systemImage: "timer", tintColor: .orange)
            } else if music.isPlaying {
                AmoraAccessibleStatusBadge(text: "Music", systemImage: "music.note", tintColor: .green)
            } else if BatteryService.shared.hasBattery && !BatteryService.shared.isCharging && BatteryService.shared.level <= 20 {
                AmoraAccessibleStatusBadge(text: "\(BatteryService.shared.level)%", systemImage: "battery.25", tintColor: .orange)
            } else if BatteryService.shared.hasBattery && BatteryService.shared.isCharging {
                AmoraAccessibleStatusBadge(text: "Charging", systemImage: "battery.100.bolt", tintColor: .green)
            } else if nav.selectedPage == .github && gitHub.authState.isConnected {
                AmoraAccessibleStatusBadge(text: "GitHub", systemImage: "chevron.left.forwardslash.chevron.right", tintColor: .green)
            } else {
                AmoraAccessibleStatusBadge(text: "Online", systemImage: "circle.fill", tintColor: palette.accentSoft)
            }

            // Concise message / task summary
            Text(statusMessage)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 8)
                .animation(.easeInOut(duration: 0.2), value: statusMessage)

            if let notification = automation.currentNotification {
                VStack(spacing: 5) {
                    if let action = notification.action {
                        Button {
                            Task {
                                await automation.executeCurrentNotificationAction()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(notification.actionTitle ?? action.humanReadableName)
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .lineLimit(1)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.amoraPill(fill: palette.accent, foreground: .white))
                        .accessibilityLabel(notification.actionTitle ?? action.humanReadableName)
                    }

                    Button("Dismiss") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            automation.dismissNotification()
                        }
                    }
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .buttonStyle(.amoraPill(fill: Color.white.opacity(0.12), foreground: .white.opacity(0.85)))
                    .accessibilityLabel("Dismiss notification")
                }
                .padding(.horizontal, 8)
                .padding(.top, 2)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else if let suggestion = proactive.currentSuggestion {
                VStack(spacing: 5) {
                    if let action = suggestion.action {
                        Button {
                            Task {
                                await proactive.executeCurrentAction()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(suggestion.actionTitle ?? action.humanReadableName)
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .lineLimit(1)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.amoraPill(fill: palette.accent, foreground: .white))
                        .accessibilityLabel(suggestion.actionTitle ?? action.humanReadableName)
                    }

                    HStack(spacing: 6) {
                        Button("Snooze") {
                            proactive.snoozeCurrentSuggestion()
                        }
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .buttonStyle(.amoraPill(fill: Color.white.opacity(0.12), foreground: .white.opacity(0.85)))
                        .accessibilityLabel("Snooze suggestion")

                        Button("Dismiss") {
                            proactive.dismissCurrentSuggestion()
                        }
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .buttonStyle(.amoraPill(fill: Color.white.opacity(0.12), foreground: .white.opacity(0.85)))
                        .accessibilityLabel("Dismiss suggestion")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}

/// Right column active page content: switches seamlessly based on `selectedPage`.
@MainActor
struct ActivePageContent: View {
    @Bindable var nav = IslandNavigationModel.shared

    var body: some View {
        Group {
            switch nav.selectedPage {
            case .home:
                IslandHomePage()
            case .aiTalk:
                IslandAITalkPage()
            case .timer:
                IslandTimerPage()
            case .clipboard:
                IslandClipboardPage()
            case .notes:
                IslandNotesPage()
            case .fileShelf:
                IslandFileShelfPage()
            case .automations:
                IslandAutomationsPage()
            case .github:
                IslandGitHubPage()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.18), value: nav.selectedPage)
    }
}
