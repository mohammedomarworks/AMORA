import SwiftUI

/// View rendering proactive suggestions inside the Dynamic Island.
/// Provides a clear user-facing message, dismissal option, and optional safe action.
/// Never forcibly opens Workspace.
struct ProactiveSuggestionView: View {
    let suggestion: AmoraProactiveSuggestion
    var topInset: CGFloat = 0
    @Bindable private var proactive = AmoraProactiveService.shared
    private var palette: ThemePalette { AppState.shared.settings.palette }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 10) {
                AMORARobotView(robot: AMORARobot.shared, compact: true)
                    .frame(width: 32, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text("AMORA")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(suggestion.trigger.displayName)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(palette.accent.opacity(0.95))
                }

                Spacer()

                Button {
                    proactive.dismissCurrentSuggestion()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .buttonStyle(.amoraHeaderCircle)
                .help("Dismiss")
                .accessibilityLabel("Dismiss proactive suggestion")
            }

            // Message Body
            VStack(alignment: .leading, spacing: 8) {
                Text(suggestion.message)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)

            Spacer()

            // Footer with Dismiss, Snooze, and optional Safe Action
            HStack(spacing: 10) {
                Button("Dismiss") {
                    proactive.dismissCurrentSuggestion()
                }
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .buttonStyle(.amoraPill(fill: Color.white.opacity(0.12), foreground: .white.opacity(0.8)))
                .accessibilityLabel("Dismiss suggestion")

                Button("Snooze") {
                    proactive.snoozeCurrentSuggestion()
                }
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .buttonStyle(.amoraPill(fill: Color.white.opacity(0.12), foreground: .white.opacity(0.8)))
                .accessibilityLabel("Snooze suggestion")

                Spacer()

                if let action = suggestion.action {
                    Button {
                        Task {
                            await proactive.executeCurrentAction()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(suggestion.actionTitle ?? action.humanReadableName)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                    }
                    .buttonStyle(.amoraPill(fill: palette.accent, foreground: .white))
                    .accessibilityLabel(suggestion.actionTitle ?? action.humanReadableName)
                }
            }
        }
        .padding(.top, topInset + 14)
        .padding(.horizontal, 14)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Compact suggestion card/banner rendered inside the Dynamic Island Home page.
struct ProactiveSuggestionCard: View {
    let suggestion: AmoraProactiveSuggestion
    @Bindable private var proactive = AmoraProactiveService.shared
    private var palette: ThemePalette { AppState.shared.settings.palette }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(palette.accent)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(suggestion.trigger.displayName)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.accent)
                    Text("•")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("Suggestion")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }

                Text(suggestion.message)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                if let action = suggestion.action {
                    Button {
                        Task {
                            await proactive.executeCurrentAction()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(suggestion.actionTitle ?? action.humanReadableName)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 8, weight: .bold))
                        }
                    }
                    .buttonStyle(.amoraPill(fill: palette.accent, foreground: .white))
                    .accessibilityLabel(suggestion.actionTitle ?? action.humanReadableName)
                }

                Button("Snooze") {
                    proactive.snoozeCurrentSuggestion()
                }
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .buttonStyle(.amoraPill(fill: Color.white.opacity(0.12), foreground: .white.opacity(0.85)))
                .accessibilityLabel("Snooze suggestion")

                Button {
                    proactive.dismissCurrentSuggestion()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .buttonStyle(.amoraHeaderCircle)
                .help("Dismiss")
                .accessibilityLabel("Dismiss suggestion")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.12, green: 0.14, blue: 0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.accent.opacity(0.35), lineWidth: 1)
        )
    }
}

/// Compact automation notification card/banner rendered inside the Dynamic Island Home page.
struct AutomationNotificationCard: View {
    let notification: AmoraAutomationNotification
    @Bindable private var automation = AmoraAutomationService.shared
    private var palette: ThemePalette { AppState.shared.settings.palette }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: notification.triggerIcon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(palette.accent)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(notification.triggerName)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.accent)
                    Text("•")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("Automation")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }

                Text(notification.message)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                if let action = notification.action {
                    Button {
                        Task {
                            await automation.executeCurrentNotificationAction()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(notification.actionTitle ?? action.humanReadableName)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 8, weight: .bold))
                        }
                    }
                    .buttonStyle(.amoraPill(fill: palette.accent, foreground: .white))
                    .accessibilityLabel(notification.actionTitle ?? action.humanReadableName)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        automation.dismissNotification()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .buttonStyle(.amoraHeaderCircle)
                .help("Dismiss")
                .accessibilityLabel("Dismiss automation notification")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.12, green: 0.14, blue: 0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.accent.opacity(0.35), lineWidth: 1)
        )
    }
}
