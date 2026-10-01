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
/// user sees essentially the normal notch, with a hint of life.
struct NotchEyesView: View {
    @Bindable var robot: AMORARobot

    var body: some View {
        HStack(spacing: 7) {
            eye
            eye
        }
    }

    private var eye: some View {
        let openHeight: CGFloat = 7
        let height = max(1.2, openHeight * CGFloat(1 - robot.blinkPhase * 0.92))
        return Capsule(style: .continuous)
            .fill(Color(red: 0.93, green: 0.99, blue: 1.0))
            .frame(width: 5, height: height)
            .shadow(color: Color(red: 0.25, green: 0.85, blue: 1.0).opacity(0.9), radius: 2.5)
            .offset(x: robot.eyeDirection.x, y: -robot.eyeDirection.y)
    }
}

/// The single window's content. It fills whatever size WindowManager animates the
/// window to, drawing one continuous black surface that is the notch when collapsed
/// and the Dynamic Island when expanded. Hover is subtle awareness only; a click on
/// the collapsed notch triggers the downward morph.
struct DynamicIslandView: View {
    @Bindable var robot = AMORARobot.shared
    @Bindable var island = IslandModel.shared
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
        let filled = shape.fill(Color.black)
        let bordered = filled.overlay(shape.stroke(stroke, lineWidth: 1))
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
        QuickPanelView(embedded: true, topInset: island.topInset)
            .opacity(max(0, min(1, (e - 0.4) / 0.6)))
            .scaleEffect(0.94 + 0.06 * t, anchor: .top)
            .allowsHitTesting(island.isExpanded && e > 0.85)
    }
}
