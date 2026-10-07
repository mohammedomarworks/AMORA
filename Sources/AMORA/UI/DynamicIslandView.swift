import SwiftUI
import Observation

enum IslandDisplayState: Int, CaseIterable, Equatable {
    case collapsed = 0
    case quick = 1
    case workspace = 2
}

/// Shared morph state for the single notch window. `expansion` is driven by
/// WindowManager's spring (0 = collapsed into the physical notch, 1 = compact
/// Quick Island, 2 = expanded Workspace) and read here to interpolate corner
/// radius, the collapsed eyes, and the expanded content — keeping AppKit's
/// window-frame morph and the SwiftUI surface in lockstep.
@Observable @MainActor
final class IslandModel {
    static let shared = IslandModel()

    /// 0.0 = collapsed into notch, 1.0 = compact quick island, 2.0 = expanded workspace
    var expansion: Double = 0
    var displayState: IslandDisplayState = .collapsed
    var targetState: IslandDisplayState = .collapsed

    /// Height of the physical notch; expanded content is inset by this so it
    /// clears the camera housing and never hides behind it.
    var topInset: CGFloat = 0
    var notchWidth: CGFloat = 200
    var collapsedBottomRadius: CGFloat = 10
    var quickBottomRadius: CGFloat = 30
    var workspaceBottomRadius: CGFloat = 36

    var isExpanded: Bool { expansion > 0.05 }
    var isWorkspace: Bool { expansion > 1.05 }

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
/// The single geometric source of truth for AMORA's Dynamic Island silhouette.
/// Top edge is flat/square (anchored flush against the physical top bezel and notch).
/// Bottom corners are rounded, interpolating smoothly between collapsed chin
/// and expanded island radius.
struct IslandShape: Shape {
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

    /// Open border path that traces ONLY the free perimeter:
    /// down the right edge, around the bottom-right corner, across the bottom,
    /// around the bottom-left corner, and up the left edge.
    /// Inset by half the line width so the entire stroke stays 100% inside the silhouette.
    func borderPath(in rect: CGRect, inset: CGFloat = 0.5) -> Path {
        let r = min(max(bottomRadius - inset, 0), min(rect.width - 2 * inset, rect.height - 2 * inset) / 2)
        let rightX = rect.maxX - inset
        let leftX = rect.minX + inset
        let bottomY = rect.maxY - inset
        let topY = rect.minY

        var p = Path()
        p.move(to: CGPoint(x: rightX, y: topY))
        p.addLine(to: CGPoint(x: rightX, y: bottomY - r))
        p.addArc(center: CGPoint(x: rightX - r, y: bottomY - r), radius: r,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: leftX + r, y: bottomY))
        p.addArc(center: CGPoint(x: leftX + r, y: bottomY - r), radius: r,
                 startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: leftX, y: topY))
        return p
    }
}

/// An open outline shape derived directly from IslandShape.borderPath.
/// The top edge (y = minY) is intentionally open and unstroked so it merges
/// seamlessly into the physical display bezel and camera notch with zero line or seam.
struct IslandBorderShape: Shape {
    var bottomRadius: CGFloat
    var inset: CGFloat = 0.5

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        IslandShape(bottomRadius: bottomRadius).borderPath(in: rect, inset: inset)
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
    @Bindable var coordinator = AmoraActionExecutionCoordinator.shared
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

    private func bottomRadius(for e: Double) -> CGFloat {
        if e <= 1.0 {
            let t = CGFloat(max(0.0, min(1.0, e)))
            return lerp(island.collapsedBottomRadius, island.quickBottomRadius, t)
        } else {
            let t = CGFloat(max(0.0, min(1.0, e - 1.0)))
            return lerp(island.quickBottomRadius, island.workspaceBottomRadius, t)
        }
    }

    @ViewBuilder
    private func content(expansion e: Double) -> some View {
        let radius = bottomRadius(for: e)
        let shape = IslandShape(bottomRadius: radius)

        ZStack(alignment: .top) {
            surface(shape: shape, bottomRadius: radius, e: e)

            if e < 0.25 {
                collapsedEyes(expansion: e)
            }

            if e > 0.10 && e < 1.70 {
                quickContent(expansion: e)
            }

            if e > 1.05 {
                workspaceContent(expansion: e)
            }
        }
        .clipShape(shape)
    }

    /// One continuous pure-black surface that represents the hardware notch when
    /// collapsed and morphs fluidly downward into the Dynamic Island when expanded.
    private func surface(shape: IslandShape, bottomRadius: CGFloat, e: Double) -> some View {
        let border = IslandBorderShape(bottomRadius: bottomRadius)
        let tD = min(1.0, max(0.0, e))

        // Apple-style razor-thin glass border: completely transparent near the top bezel
        // and physical notch (y <= topInset), emerging subtly down the lateral edges and
        // chin. Zero opacity when collapsed (tD = 0) so the notch chin merges into the bezel.
        let borderGradient = LinearGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .clear, location: 0.08),
                .init(color: Color.white.opacity(0.18 * tD), location: 0.28),
                .init(color: Color.white.opacity(0.08 * tD), location: 0.82),
                .init(color: Color.white.opacity(0.04 * tD), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )

        return ZStack {
            // Base fill is 100% OLED pitch black (#000000).
            // Mini-LED local dimming zones turn completely off, matching the physical camera housing.
            shape.fill(Color.black)

            // Inner hairline border tracing the exact curved silhouette
            border.stroke(borderGradient, lineWidth: 1.0)
        }
        .contentShape(shape)
        .onTapGesture {
            if island.displayState == .collapsed {
                WindowManager.shared.expandIsland()
            }
        }
    }

    private func collapsedEyes(expansion e: Double) -> some View {
        // Eyes smoothly fade out as the notch starts expanding downward (0.0 -> 0.22)
        // and fade back in smoothly as the island tucks back into the notch (0.22 -> 0.0)
        let eyeProgress = min(1.0, max(0.0, e / 0.22))
        let eyeOpacity = 1.0 - eyeProgress
        let eyeScale = 1.0 - 0.15 * eyeProgress

        return NotchEyesView(robot: robot)
            .opacity(eyeOpacity)
            .scaleEffect(eyeScale, anchor: .bottom)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 4)
            .allowsHitTesting(false)
    }

    private func quickContent(expansion e: Double) -> some View {
        // When e is 0.12..0.72: unfolds and fades in (0 -> 1)
        // When e is 1.0..1.50: dissolves out (1 -> 0) as it morphs into workspace
        let fadeIn = min(1.0, max(0.0, (e - 0.12) / 0.60))
        let fadeOut = e > 1.0 ? max(0.0, 1.0 - (e - 1.0) / 0.40) : 1.0
        let opacity = fadeIn * fadeOut

        let translateY = e <= 1.0 ? -10.0 * (1.0 - fadeIn) : 0.0
        let scale = e <= 1.0 ? (0.96 + 0.04 * fadeIn) : (1.0 + 0.04 * (e - 1.0))

        return Group {
            if assistant.state == .thinking || assistant.state == .responding || assistant.state == .failed || coordinator.state != .idle {
                AIResponseView(embedded: true, topInset: island.topInset)
            } else {
                QuickPanelView(embedded: true, topInset: island.topInset)
            }
        }
        .opacity(opacity)
        .offset(y: translateY)
        .scaleEffect(scale, anchor: .top)
        .allowsHitTesting(island.displayState == .quick && e >= 0.85 && e <= 1.15)
    }

    private func workspaceContent(expansion e: Double) -> some View {
        // Content smoothly emerges between e = 1.15 and 1.85 with subtle scale and parallax
        let contentProgress = min(1.0, max(0.0, (e - 1.15) / 0.70))
        let translateY = -12.0 * (1.0 - contentProgress)
        let scale = 0.96 + 0.04 * contentProgress

        return DashboardView(
            viewModel: WindowManager.shared.dashboardViewModel,
            embedded: true,
            topInset: island.topInset
        )
        .opacity(contentProgress)
        .offset(y: translateY)
        .scaleEffect(scale, anchor: .top)
        .allowsHitTesting((island.displayState == .workspace || island.targetState == .workspace) && e >= 1.5)
    }
}

/// AI output is persistent content, unlike the short-lived personality text in
/// the ordinary quick panel. The response is scrollable rather than truncated.
struct AIResponseView: View {
    var embedded = false
    var topInset: CGFloat = 0
    @Bindable private var assistant = AssistantManager.shared
    @Bindable private var coordinator = AmoraActionExecutionCoordinator.shared
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
                Button { WindowManager.shared.showWorkspace() } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .buttonStyle(.plain)
                .help("Expand to Workspace")
                Button {
                    coordinator.reset()
                    WindowManager.shared.collapseIsland()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close AI response")
            }

            if coordinator.state != .idle {
                ActionExecutionView(compact: false)
            } else if assistant.state == .thinking {
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
                    Button("Close") {
                        coordinator.reset()
                        WindowManager.shared.collapseIsland()
                    }
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
