import SwiftUI
import Observation

/// Shared morph state for the single notch window. `expansion` is driven by
/// WindowManager's spring (0 = collapsed into the physical notch, 1 = fully
/// expanded Dynamic Island) and read here to interpolate corner radius, the
/// collapsed eyes, and the expanded content — keeping AppKit's window-frame
/// morph and the SwiftUI surface in lockstep.
@Observable @MainActor
final class IslandModel {
    static let shared = IslandModel()

    var expansion: Double = 0
    var isExpanded: Bool = false

    /// Height of the physical notch; expanded content is inset by this so it
    /// clears the camera housing and never hides behind it.
    var topInset: CGFloat = 0
    var notchWidth: CGFloat = 200
    var collapsedBottomRadius: CGFloat = 10
    var expandedBottomRadius: CGFloat = 30

    private init() {}
}

@inline(__always)
private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
    a + (b - a) * t
}

/// A rectangle whose TOP edge is square (flush against the physical top bezel,
/// so it merges with the notch) and whose BOTTOM corners are rounded. The radius
/// animates with the morph, so the notch appears to grow a rounder chin as it
/// expands downward into the island.
struct BottomRoundedRectangle: Shape {
    var bottomRadius: CGFloat

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = min(max(bottomRadius, 0), min(rect.width, rect.height) / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r,
                 startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.closeSubpath()
        return p
    }
}
/// The tiny notch-integrated element shown when collapsed: just AMORA's eyes,
/// glowing at the lower lip of the notch. No pod, no antenna, no panel — so the
/// user sees essentially the normal notch, with a hint of life. Uses the shared
/// eye so expression + theme stay consistent with the full character.
struct NotchEyesView: View {
    @Bindable var robot: AMORARobot
    private var palette: ThemePalette { AppState.shared.settings.palette }

    var body: some View {
        HStack(spacing: 7) {
            eye
            eye
        }
    }

    private var eye: some View {
        AMORAEyeView(
            shape: robot.expression.eyes,
            direction: robot.eyeDirection,
            blink: max(robot.blinkPhase, robot.expression.blinkProgress),
            width: 5,
            height: 7,
            core: palette.eyeCore,
            glow: palette.eyeGlow,
            lineWidth: 1.6,
            glowRadius: 2.5
        )
    }
}

/// The single window's content. It fills whatever size WindowManager animates the
/// window to, drawing one continuous black surface that is the notch when collapsed
/// and the Dynamic Island when expanded. Hover is subtle awareness only; a click on
/// the collapsed notch triggers the downward morph.
struct DynamicIslandView: View {
    @Bindable var robot = AMORARobot.shared
    @Bindable var island = IslandModel.shared
    @Bindable var assistant = AssistantManager.shared
    private var appState: AppState { AppState.shared }

    var body: some View {
        content(expansion: island.expansion)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onHover { hovering in
                guard !island.isExpanded else { return }
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
            .onReceive(NotificationCenter.default.publisher(for: .cursorMoved)) { notification in
                guard let info = notification.userInfo,
                      let nx = info["normalizedX"] as? Double,
                      let ny = info["normalizedY"] as? Double else { return }
                robot.setEyeDirection(x: nx, y: ny)
            }
            .onChange(of: appState.stateManager.currentState) { _, newState in
                robot.updateExpression(for: newState)
            }
    }

    @ViewBuilder
    private func content(expansion e: Double) -> some View {
        let tD = max(0.0, min(1.0, e))
        let t = CGFloat(tD)
        let bottomRadius = lerp(island.collapsedBottomRadius, island.expandedBottomRadius, t)

        ZStack(alignment: .top) {
            surface(bottomRadius: bottomRadius, tD: tD, t: t)

            if e < 0.5 {
                collapsedEyes(expansion: e)
            }

            if e > 0.01 {
                expandedContent(expansion: e, t: t)
            }
        }
    }

    /// One continuous black surface — the notch when collapsed, the island when
    /// expanded. Tapping it (collapsed only) triggers the downward morph.
    private func surface(bottomRadius: CGFloat, tD: Double, t: CGFloat) -> some View {
        let shape = BottomRoundedRectangle(bottomRadius: bottomRadius)
        let stroke = LinearGradient(
            colors: [Color.white.opacity(0.22 * tD), Color.white.opacity(0.04 * tD)],
            startPoint: .top,
            endPoint: .bottom
        )
        // A faint top sheen that only appears as the island expands, giving the
        // chin a soft glassy highlight. At tD = 0 it is fully transparent, so the
        // collapsed notch stays pure black and merges with the bezel.
        let sheen = LinearGradient(
            colors: [Color.white.opacity(0.06 * tD), Color.clear],
            startPoint: .top,
            endPoint: .bottom
        )
        let filled = shape.fill(Color.black)
        let bordered = filled
            .overlay(shape.fill(sheen))
            .overlay(shape.stroke(stroke, lineWidth: 1))
        let shadowed = bordered.shadow(color: Color.black.opacity(0.55 * tD), radius: 20 * t, x: 0, y: 8 * t)
        return shadowed
            .contentShape(shape)
            .onTapGesture {
                if !island.isExpanded {
                    WindowManager.shared.toggleQuickPanel()
                }
            }
    }

    private func collapsedEyes(expansion e: Double) -> some View {
        NotchEyesView(robot: robot)
            .opacity(1 - min(1, e * 2))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 4)
            .allowsHitTesting(false)
    }

    private func expandedContent(expansion e: Double, t: CGFloat) -> some View {
        Group {
            if assistant.state == .thinking || assistant.state == .responding || assistant.state == .failed {
                AIResponseView(embedded: true, topInset: island.topInset)
            } else {
                QuickPanelView(embedded: true, topInset: island.topInset)
            }
        }
            .opacity(max(0, min(1, (e - 0.4) / 0.6)))
            .scaleEffect(0.94 + 0.06 * t, anchor: .top)
            .allowsHitTesting(island.isExpanded && e > 0.85)
    }
}

/// AI output is persistent content, unlike the short-lived personality text in
/// the ordinary quick panel. The response is scrollable rather than truncated.
struct AIResponseView: View {
    var embedded = false
    var topInset: CGFloat = 0
    @Bindable private var assistant = AssistantManager.shared
    private var palette: ThemePalette { AppState.shared.settings.palette }

    private var responseText: String { assistant.response ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AMORARobotView(robot: AMORARobot.shared, compact: true)
                    .frame(width: 32, height: 28)
                Text("AMORA")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Button { WindowManager.shared.showDashboard() } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .buttonStyle(.plain)
                .help("Open response in Dashboard")
                Button { WindowManager.shared.collapseIsland() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close AI response")
            }

            if assistant.state == .thinking {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(palette.accent)
                    Text("Thinking…")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 28)
            } else {
                ScrollView {
                    Text(responseText)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 270)
                .scrollIndicators(.hidden)

                HStack {
                    Spacer()
                    Button("Close") { WindowManager.shared.collapseIsland() }
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, topInset + 14)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
