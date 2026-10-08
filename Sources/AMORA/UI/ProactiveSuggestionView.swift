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
                        .padding(6)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
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

            // Footer with Dismiss and optional Safe Action
            HStack(spacing: 12) {
                Button("Dismiss") {
                    proactive.dismissCurrentSuggestion()
                }
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss suggestion")

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
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(palette.accent)
                        )
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
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
