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
    private var personality = PersonalityEngine.shared
    private var palette: ThemePalette { AppState.shared.settings.palette }

    private var statusMessage: String {
        if coordinator.state != .idle {
            return "Executing action…"
        } else if assistant.state == .thinking {
            return "Thinking…"
        } else if assistant.state == .responding, let resp = assistant.response, !resp.isEmpty {
            return "Assistant response ready"
        } else if timer.isRunning {
            return "Focus timer (\(timer.formattedTime))"
        } else if music.isPlaying && !music.trackTitle.isEmpty {
            return "Playing: \(music.trackTitle)"
        } else if let msg = personality.message, !msg.isEmpty {
            return msg
        } else {
            return "Hey, what should we do next?"
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            // Mascot
            AMORARobotView(robot: robot, compact: false)
                .frame(width: 50, height: 42)
                .padding(.top, 4)

            // Contextual status badge
            if assistant.state == .thinking {
                AmoraAccessibleStatusBadge(text: "Thinking", systemImage: "sparkles", tintColor: palette.accent)
            } else if coordinator.state != .idle {
                AmoraAccessibleStatusBadge(text: "Action", systemImage: "bolt.fill", tintColor: .orange)
            } else if timer.isRunning {
                AmoraAccessibleStatusBadge(text: timer.formattedTime, systemImage: "timer", tintColor: .orange)
            } else if music.isPlaying {
                AmoraAccessibleStatusBadge(text: "Music", systemImage: "music.note", tintColor: .green)
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
