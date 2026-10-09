import SwiftUI

/// User-facing feedback view displaying action execution status, sequential progress,
/// confirmation prompts, and cancellation controls in the Dynamic Island and Workspace.
struct ActionExecutionView: View {
    var compact: Bool = false
    @Bindable private var coordinator = AmoraActionExecutionCoordinator.shared
    @Bindable private var settings = AppState.shared.settings
    private var palette: ThemePalette { settings.palette }

    var body: some View {
        if compact {
            compactContent
        } else {
            expandedContent
        }
    }

    // MARK: - Compact Content (for Workspace / Dashboard bottom bar)

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                statusIcon
                Text(headerTitle)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                if coordinator.state == .executing {
                    Button("Stop") {
                        coordinator.cancelExecution()
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .buttonStyle(.amoraPill(fill: Color.red.opacity(0.15), foreground: .red.opacity(0.9)))
                    .accessibilityLabel("Stop action execution")
                } else if coordinator.state == .completed || coordinator.state == .failed {
                    Button {
                        coordinator.reset()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .buttonStyle(.amoraHeaderCircle)
                    .accessibilityLabel("Dismiss action notice")
                }
            }

            if coordinator.state == .awaitingConfirmation, let pending = coordinator.pendingConfirmation {
                VStack(alignment: .leading, spacing: 6) {
                    Text(pending.prompt)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))

                    HStack(spacing: 8) {
                        Button("Cancel") {
                            coordinator.cancelPendingAction()
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .buttonStyle(.amoraPill(fill: Color.white.opacity(0.12), foreground: .white.opacity(0.75)))
                        .accessibilityLabel("Cancel action")

                        Button("Confirm") {
                            coordinator.confirmPendingAction()
                        }
                        .font(.system(size: 10, weight: .bold))
                        .buttonStyle(.amoraPill(fill: palette.accent, foreground: .white))
                        .accessibilityLabel("Confirm action")
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
            } else if !coordinator.items.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(coordinator.items) { item in
                        HStack(spacing: 6) {
                            itemStatusIcon(for: item)
                            Text(item.title)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(itemTextColor(for: item))
                            Spacer()
                            if let msg = item.message, item.status == .completed || item.status == .failed {
                                Text(msg)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.white.opacity(0.55))
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }

            if let summary = coordinator.summaryMessage, (coordinator.state == .completed || coordinator.state == .failed) {
                Text(summary)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.top, 2)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
    }

    // MARK: - Expanded Content (for Dynamic Island AIResponseView)

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header status
            HStack(spacing: 8) {
                statusIcon
                Text(headerTitle)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                if coordinator.state == .executing {
                    Button("Stop") {
                        coordinator.cancelExecution()
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.amoraPill(fill: Color.red.opacity(0.15), foreground: .red.opacity(0.9)))
                    .accessibilityLabel("Stop action execution")
                }
            }

            // Action Items
            if !coordinator.items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(coordinator.items) { item in
                        HStack(spacing: 8) {
                            actionGlyph(for: item.action)
                                .frame(width: 16)
                            Text(item.title)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(itemTextColor(for: item))

                            Spacer()

                            itemStatusIcon(for: item)
                        }
                        if let msg = item.message, !msg.isEmpty {
                            Text(msg)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.6))
                                .padding(.leading, 24)
                        }
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
            }

            // Confirmation Prompt Box
            if coordinator.state == .awaitingConfirmation, let pending = coordinator.pendingConfirmation {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .foregroundStyle(.orange)
                        Text("Confirmation Required")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.orange)
                    }

                    Text(pending.prompt)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineSpacing(2)

                    HStack(spacing: 12) {
                        Spacer()

                        Button("Cancel") {
                            coordinator.cancelPendingAction()
                        }
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .buttonStyle(.amoraPill(fill: Color.white.opacity(0.12), foreground: .white.opacity(0.8)))
                        .accessibilityLabel("Cancel action")

                        Button("Confirm") {
                            coordinator.confirmPendingAction()
                        }
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .buttonStyle(.amoraPill(fill: palette.accent, foreground: .white))
                        .accessibilityLabel("Confirm action")
                    }
                    .padding(.top, 4)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.15)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.orange.opacity(0.3), lineWidth: 1))
            }

            // Final Summary Message
            if let summary = coordinator.summaryMessage, (coordinator.state == .completed || coordinator.state == .failed) {
                Text(summary)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineSpacing(3)
                    .padding(.vertical, 4)
            }

            if coordinator.state == .completed || coordinator.state == .failed {
                HStack {
                    Spacer()
                    Button("Close") {
                        coordinator.reset()
                        WindowManager.shared.collapseIsland()
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .buttonStyle(.amoraPill(fill: Color.white.opacity(0.12), foreground: .white.opacity(0.85)))
                    .accessibilityLabel("Close action view")
                }
            }
        }
    }

    // MARK: - Helpers

    private var headerTitle: String {
        switch coordinator.state {
        case .idle: return "Ready"
        case .thinking: return "Thinking…"
        case .executing:
            if coordinator.totalCount > 1 {
                return "Working (\(coordinator.currentIndex + 1)/\(coordinator.totalCount))…"
            }
            return "Working…"
        case .awaitingConfirmation: return "Confirmation Needed"
        case .completed: return "Done"
        case .failed: return coordinator.isCancelled ? "Stopped" : "Action Completed with Notices"
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch coordinator.state {
        case .idle:
            Image(systemName: "sparkles").foregroundStyle(palette.accent)
        case .thinking, .executing:
            ProgressView().controlSize(.small).tint(palette.accent)
        case .awaitingConfirmation:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            if coordinator.isCancelled {
                Image(systemName: "slash.circle.fill").foregroundStyle(.secondary)
            } else {
                Image(systemName: "info.circle.fill").foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func itemStatusIcon(for item: AmoraActionExecutionItem) -> some View {
        switch item.status {
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.3))
        case .executing:
            ProgressView()
                .controlSize(.small)
                .tint(palette.accent)
        case .awaitingConfirmation:
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "slash.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func actionGlyph(for action: AmoraAction) -> some View {
        switch action {
        case .playMusic, .pauseMusic, .nextTrack, .previousTrack:
            Image(systemName: "music.note").font(.system(size: 11)).foregroundStyle(.pink)
        case .openApplication:
            Image(systemName: "app.badge").font(.system(size: 11)).foregroundStyle(.blue)
        case .openFolder:
            Image(systemName: "folder.fill").font(.system(size: 11)).foregroundStyle(.cyan)
        case .openWorkspace:
            Image(systemName: "macwindow").font(.system(size: 11)).foregroundStyle(.purple)
        case .startTimer, .cancelTimer, .pauseTimer, .resumeTimer:
            Image(systemName: "timer").font(.system(size: 11)).foregroundStyle(.orange)
        case .confirmTest:
            Image(systemName: "shield.lefthalf.filled").font(.system(size: 11)).foregroundStyle(.yellow)
        case .showNotification:
            Image(systemName: "bell.fill").font(.system(size: 11)).foregroundStyle(.indigo)
        }
    }

    private func itemTextColor(for item: AmoraActionExecutionItem) -> Color {
        switch item.status {
        case .pending: return .white.opacity(0.4)
        case .executing: return .white
        case .awaitingConfirmation: return .orange
        case .completed: return .white.opacity(0.9)
        case .failed: return .white.opacity(0.7)
        case .cancelled: return .white.opacity(0.4)
        }
    }
}
