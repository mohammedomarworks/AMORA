import SwiftUI

struct NotchView: View {
    @Bindable var robot = AMORARobot.shared
    private var appState: AppState { AppState.shared }

    var body: some View {
        HStack(spacing: 8) {
            // AMORA Robot Character
            AMORARobotView(robot: robot, compact: true)
                .padding(.leading, 6)

            // Dynamic Island companion text or status indicator
            if robot.isHovering || appState.stateManager.currentState == .hover {
                Text("Hi!")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.88))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.25),
                                    Color.white.opacity(0.05)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.8
                        )
                )
                .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 3)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                robot.isHovering = hovering
                if hovering {
                    appState.stateManager.transition(to: .hover)
                    robot.updateExpression(for: .hover)
                } else {
                    appState.stateManager.transition(to: .idle)
                    robot.updateExpression(for: .idle)
                }
            }
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                robot.updateExpression(for: .happy)
                WindowManager.shared.toggleQuickPanel()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cursorMoved)) { notification in
            guard let userInfo = notification.userInfo,
                  let normX = userInfo["normalizedX"] as? Double,
                  let normY = userInfo["normalizedY"] as? Double else { return }
            robot.setEyeDirection(x: normX, y: normY)
        }
        .onChange(of: appState.stateManager.currentState) { _, newState in
            robot.updateExpression(for: newState)
        }
    }
}
