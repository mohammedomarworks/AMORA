import SwiftUI

struct AMORARobotView: View {
    let robot: AMORARobot
    var compact: Bool = true

    // Visual theme colors
    private let visorColor = Color(red: 0.05, green: 0.07, blue: 0.12)
    private let eyeGlowColor = Color(red: 0.25, green: 0.85, blue: 1.0)
    private let eyeCoreColor = Color(red: 0.9, green: 0.98, blue: 1.0)
    private let bodyGradStart = Color(red: 0.18, green: 0.20, blue: 0.26)
    private let bodyGradEnd = Color(red: 0.10, green: 0.12, blue: 0.16)
    private let accentColor = Color(red: 0.3, green: 0.8, blue: 1.0)

    var body: some View {
        let baseHeight: CGFloat = compact ? 26 : 38
        let baseWidth: CGFloat = compact ? 34 : 50

        VStack(spacing: 0) {
            // Antenna
            AntennaView(
                pulse: robot.antennaPhase,
                alert: robot.state == .alert,
                compact: compact
            )

            // Robot Head/Body Pod
            ZStack {
                // Outer Pod Shell
                RoundedRectangle(cornerRadius: compact ? 9 : 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [bodyGradStart, bodyGradEnd],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: compact ? 9 : 14, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.35),
                                        Color.white.opacity(0.08)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.black.opacity(0.35), radius: 3, x: 0, y: 1.5)

                // Face Visor Screen
                RoundedRectangle(cornerRadius: compact ? 7 : 11, style: .continuous)
                    .fill(visorColor)
                    .padding(compact ? 2.5 : 3.5)
                    .overlay(
                        RoundedRectangle(cornerRadius: compact ? 7 : 11, style: .continuous)
                            .strokeBorder(Color.cyan.opacity(0.2), lineWidth: 0.5)
                            .padding(compact ? 2.5 : 3.5)
                    )

                // Digital Face: Eyes & Mouth
                VStack(spacing: compact ? 1.5 : 2.5) {
                    HStack(spacing: compact ? 5 : 8) {
                        // Left Eye
                        SingleEyeView(
                            shape: robot.expression.eyes,
                            direction: robot.eyeDirection,
                            blink: max(robot.blinkPhase, robot.expression.blinkProgress),
                            compact: compact
                        )

                        // Right Eye
                        SingleEyeView(
                            shape: robot.expression.eyes,
                            direction: robot.eyeDirection,
                            blink: max(robot.blinkPhase, robot.expression.blinkProgress),
                            compact: compact
                        )
                    }

                    // Tiny Digital Mouth (if open or speaking)
                    if robot.expression.mouth != .neutral {
                        MouthView(
                            shape: robot.expression.mouth,
                            compact: compact
                        )
                    }
                }
                .offset(y: -robot.eyeDirection.y * 0.3)
            }
            .frame(width: baseWidth, height: baseHeight)
            .offset(y: (robot.breathingPhase - 0.5) * (compact ? 1.0 : 1.8))
            .rotationEffect(.radians(robot.headMovementPhase * (compact ? 0.04 : 0.08)))
        }
    }
}

// MARK: - Antenna View
private struct AntennaView: View {
    let pulse: Double
    let alert: Bool
    let compact: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Glowing antenna tip
            Circle()
                .fill(alert ? Color.red : Color.cyan)
                .frame(width: compact ? 3.5 : 5, height: compact ? 3.5 : 5)
                .shadow(
                    color: (alert ? Color.red : Color.cyan).opacity(0.6 + pulse * 0.4),
                    radius: compact ? 3 : 5
                )

            // Stem
            Rectangle()
                .fill(Color.gray.opacity(0.7))
                .frame(width: compact ? 1 : 1.5, height: compact ? 3 : 5)
        }
    }
}

// MARK: - Single Eye View
private struct SingleEyeView: View {
    let shape: Expression.EyeShape
    let direction: CGPoint
    let blink: Double
    let compact: Bool

    private let eyeGlowColor = Color(red: 0.25, green: 0.85, blue: 1.0)
    private let eyeCoreColor = Color(red: 0.95, green: 0.99, blue: 1.0)

    var body: some View {
        let eyeWidth: CGFloat = compact ? 5.5 : 8.5
        let eyeHeight: CGFloat = compact ? 7.5 : 12

        Group {
            switch shape {
            case .normal, .wide:
                Capsule(style: .continuous)
                    .fill(eyeCoreColor)
                    .frame(
                        width: shape == .wide ? eyeWidth * 1.2 : eyeWidth,
                        height: max(1.0, eyeHeight * (1.0 - blink * 0.9))
                    )
            case .happy:
                // Cute happy arc `^`
                HappyEyePath()
                    .stroke(eyeCoreColor, style: StrokeStyle(lineWidth: compact ? 1.8 : 2.5, lineCap: .round))
                    .frame(width: eyeWidth, height: eyeHeight * 0.6)
            case .sad:
                // Downward arc
                SadEyePath()
                    .stroke(eyeCoreColor, style: StrokeStyle(lineWidth: compact ? 1.8 : 2.5, lineCap: .round))
                    .frame(width: eyeWidth, height: eyeHeight * 0.6)
            case .narrow:
                Capsule(style: .continuous)
                    .fill(eyeCoreColor)
                    .frame(width: eyeWidth, height: eyeHeight * 0.35)
            case .halfClosed:
                Capsule(style: .continuous)
                    .fill(eyeCoreColor)
                    .frame(width: eyeWidth, height: max(1.0, eyeHeight * 0.45 * (1.0 - blink * 0.8)))
            }
        }
        .shadow(color: eyeGlowColor.opacity(0.85), radius: compact ? 2 : 4)
        .offset(x: direction.x, y: -direction.y)
    }
}

// MARK: - Mouth View
private struct MouthView: View {
    let shape: Expression.MouthShape
    let compact: Bool

    var body: some View {
        Group {
            switch shape {
            case .smile:
                HappyEyePath()
                    .stroke(Color.cyan.opacity(0.9), style: StrokeStyle(lineWidth: compact ? 1.2 : 1.8, lineCap: .round))
                    .frame(width: compact ? 6 : 9, height: compact ? 2.5 : 4)
                    .rotationEffect(.degrees(180))
            case .open:
                Capsule()
                    .fill(Color.cyan.opacity(0.85))
                    .frame(width: compact ? 4 : 6, height: compact ? 2.5 : 4)
            case .sad:
                SadEyePath()
                    .stroke(Color.cyan.opacity(0.8), style: StrokeStyle(lineWidth: compact ? 1.2 : 1.8, lineCap: .round))
                    .frame(width: compact ? 6 : 9, height: compact ? 2.5 : 4)
            case .neutral:
                EmptyView()
            }
        }
    }
}

// MARK: - Shapes
private struct HappyEyePath: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.midX, y: rect.minY)
        )
        return path
    }
}

private struct SadEyePath: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.maxY)
        )
        return path
    }
}
