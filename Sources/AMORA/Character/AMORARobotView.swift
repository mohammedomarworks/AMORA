import SwiftUI

/// AMORA's full character: antenna, glass-visor pod, and the digital face. All
/// color comes from the active theme palette so a theme switch recolors the whole
/// character in one place; nothing here hard-codes brand colors.
struct AMORARobotView: View {
    let robot: AMORARobot
    var compact: Bool = true

    private var palette: ThemePalette { AppState.shared.settings.palette }

    var body: some View {
        let baseHeight: CGFloat = compact ? 26 : 38
        let baseWidth: CGFloat = compact ? 34 : 50

        VStack(spacing: 0) {
            AntennaView(
                pulse: robot.isDancing ? robot.danceAntennaPhase : robot.antennaPhase,
                tint: antennaTint,
                compact: compact
            )

            ZStack {
                // Audio glow aura beneath chassis when dancing, matching dance reference
                if robot.isDancing {
                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.42, blue: 0.30).opacity(0.55 * robot.danceGlowPulse),
                                    Color(red: 1.0, green: 0.25, blue: 0.15).opacity(0.20 * robot.danceGlowPulse),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 2,
                                endRadius: compact ? 22 : 32
                            )
                        )
                        .frame(width: compact ? 44 : 64, height: compact ? 16 : 24)
                        .offset(y: compact ? 13 : 20)
                        .allowsHitTesting(false)
                }

                // Floating music notes matching dance reference
                if robot.isDancing && AppState.shared.settings.motionScale > 0 {
                    MusicNotesFloatingView(pulse: robot.danceAntennaPhase, compact: compact)
                        .offset(y: compact ? -12 : -18)
                }

                // Outer pod shell — themed body gradient with a soft top sheen.
                RoundedRectangle(cornerRadius: compact ? 9 : 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [palette.shellTop, palette.shellBottom],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: compact ? 9 : 14, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [palette.highlight.opacity(0.35), palette.highlight.opacity(0.08)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.black.opacity(0.35), radius: 3, x: 0, y: 1.5)
                // Face visor glass.
                RoundedRectangle(cornerRadius: compact ? 7 : 11, style: .continuous)
                    .fill(palette.visor)
                    .padding(compact ? 2.5 : 3.5)
                    .overlay(
                        RoundedRectangle(cornerRadius: compact ? 7 : 11, style: .continuous)
                            .strokeBorder(palette.accent.opacity(0.2), lineWidth: 0.5)
                            .padding(compact ? 2.5 : 3.5)
                    )

                // Digital face: eyes + optional mouth.
                VStack(spacing: compact ? 1.5 : 2.5) {
                    HStack(spacing: compact ? 5 : 8) {
                        eye(isLeft: true)
                        eye(isLeft: false)
                    }
                    if robot.expression.mouth != .neutral {
                        MouthView(shape: robot.expression.mouth, tint: palette.accent, compact: compact)
                    }
                }
                .offset(y: -robot.eyeDirection.y * 0.3)
            }
            .frame(width: baseWidth, height: baseHeight)
            .scaleEffect(1 + (robot.bouncePhase + (robot.isDancing ? robot.danceBouncePhase * 0.03 : 0)) * 0.12, anchor: .center)
            .offset(y: (robot.breathingPhase - 0.5) * (compact ? 1.0 : 1.8) - robot.bouncePhase * 2 - (robot.isDancing ? robot.danceBouncePhase : 0))
            .rotationEffect(.radians(robot.headMovementPhase * (compact ? 0.04 : 0.08) + robot.wigglePhase + (robot.isDancing ? robot.danceTiltPhase : 0)))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            robot.reactToClick()
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                if robot.recordPettingMovement(at: location) {
                    robot.pet()
                }
            case .ended:
                robot.resetPetting()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("AMORA")
        .accessibilityValue(accessibilityDescription)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Click to interact with AMORA")
        .accessibilityAction {
            robot.reactToClick()
        }
    }

    private var antennaTint: Color {
        if robot.state == .alert {
            return Color.red
        } else if robot.activeReaction == .affection {
            return Color.pink
        } else if robot.activeReaction == .grumpy {
            return Color.orange
        } else if robot.activeReaction == .sad || robot.state == .sad {
            return Color(red: 0.45, green: 0.65, blue: 0.95)
        } else if robot.isDancing {
            return Color(red: 1.0, green: 0.45, blue: 0.32)
        } else if robot.state == .concerned || robot.state == .aiError {
            return Color.orange.opacity(0.85)
        } else {
            return palette.accent
        }
    }

    private func eye(isLeft: Bool) -> some View {
        let isHeart = robot.expression.eyes == .heart
        return AMORAEyeView(
            shape: robot.expression.eyes,
            direction: robot.eyeDirection,
            blink: max(robot.blinkPhase, robot.expression.blinkProgress),
            width: compact ? 5.5 : 8.5,
            height: compact ? 7.5 : 12,
            core: isHeart ? Color.pink : palette.eyeCore,
            glow: isHeart ? Color.pink : palette.eyeGlow,
            lineWidth: compact ? 1.8 : 2.5,
            glowRadius: compact ? 2 : 4,
            isLeft: isLeft
        )
    }

    private var accessibilityDescription: String {
        if let reaction = robot.activeReaction {
            return reaction.accessibilityDescription
        }
        return Self.accessibilityDescription(for: robot.state)
    }

    /// A short VoiceOver value describing AMORA's current mood.
    private static func accessibilityDescription(for state: AMORAState) -> String {
        switch state {
        case .idle, .watching, .expanded: return "resting"
        case .hover, .happy: return "happy"
        case .thinking, .focused: return "focused"
        case .curious: return "curious"
        case .excited: return "excited"
        case .affection: return "feeling affectionate"
        case .grumpy: return "playfully grumpy"
        case .sad: return "feeling soft sadness"
        case .concerned: return "concerned"
        case .surprised: return "surprised"
        case .sleepy: return "sleeping"
        case .alert: return "alert"
        case .music: return "enjoying music"
        case .speaking: return "speaking"
        case .error: return "something went wrong"
        case .aiThinking: return "focused"
        case .aiResponse: return "happy"
        case .aiError: return "something went wrong"
        }
    }
}

// MARK: - Shared eye

/// AMORA's single eye, shared by the full face and the collapsed notch so the
/// character's expression reads the same everywhere: a glowing capsule that
/// squints, widens, and blinks, bending into an arc for happy and sad.
struct AMORAEyeView: View {
    let shape: Expression.EyeShape
    let direction: CGPoint
    let blink: Double
    let width: CGFloat
    let height: CGFloat
    let core: Color
    let glow: Color
    var lineWidth: CGFloat = 2
    var glowRadius: CGFloat = 2
    var isLeft: Bool = true

    var body: some View {
        Group {
            switch shape {
            case .normal:
                Capsule(style: .continuous)
                    .fill(core)
                    .frame(width: width, height: max(1.0, height * (1.0 - blink * 0.9)))
            case .wide:
                Capsule(style: .continuous)
                    .fill(core)
                    .frame(width: width * 1.2, height: max(1.0, height * (1.0 - blink * 0.9)))
            case .happy:
                AMORAArc(up: true)
                    .stroke(core, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .frame(width: width, height: height * 0.6)
            case .sad:
                AMORAArc(up: false)
                    .stroke(core, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .frame(width: width, height: height * 0.6)
            case .narrow:
                Capsule(style: .continuous)
                    .fill(core)
                    .frame(width: width, height: max(1.0, height * 0.35))
            case .halfClosed:
                Capsule(style: .continuous)
                    .fill(core)
                    .frame(width: width, height: max(1.0, height * 0.45 * (1.0 - blink * 0.8)))
            case .heart:
                Image(systemName: "heart.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.pink)
                    .frame(width: width * 1.35, height: height * 0.95)
            case .grumpy:
                Capsule(style: .continuous)
                    .fill(core)
                    .frame(width: width * 1.1, height: max(1.0, height * 0.35))
                    .rotationEffect(.degrees(isLeft ? 18 : -18))
            }
        }
        .shadow(color: glow.opacity(0.85), radius: glowRadius)
        .offset(x: direction.x, y: -direction.y)
    }
}
// MARK: - Antenna

private struct AntennaView: View {
    let pulse: Double
    let tint: Color
    let compact: Bool

    var body: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(tint)
                .frame(width: compact ? 3.5 : 5, height: compact ? 3.5 : 5)
                .shadow(color: tint.opacity(0.6 + pulse * 0.4), radius: compact ? 3 : 5)
            Rectangle()
                .fill(Color.gray.opacity(0.7))
                .frame(width: compact ? 1 : 1.5, height: compact ? 3 : 5)
        }
    }
}

// MARK: - Mouth

private struct MouthView: View {
    let shape: Expression.MouthShape
    let tint: Color
    let compact: Bool

    var body: some View {
        Group {
            switch shape {
            case .smile:
                AMORAArc(up: true)
                    .stroke(tint.opacity(0.9), style: StrokeStyle(lineWidth: compact ? 1.2 : 1.8, lineCap: .round))
                    .frame(width: compact ? 6 : 9, height: compact ? 2.5 : 4)
                    .rotationEffect(.degrees(180))
            case .open:
                Capsule()
                    .fill(tint.opacity(0.85))
                    .frame(width: compact ? 4 : 6, height: compact ? 2.5 : 4)
            case .sad:
                AMORAArc(up: false)
                    .stroke(tint.opacity(0.8), style: StrokeStyle(lineWidth: compact ? 1.2 : 1.8, lineCap: .round))
                    .frame(width: compact ? 6 : 9, height: compact ? 2.5 : 4)
            case .flat:
                Capsule()
                    .fill(tint.opacity(0.85))
                    .frame(width: compact ? 5 : 7.5, height: compact ? 1.5 : 2.0)
            case .neutral:
                EmptyView()
            }
        }
    }
}

// MARK: - Arc shape

/// A single quadratic arc. `up` bows toward the top (happy `^`, or a smile when
/// rotated 180°); otherwise it bows toward the bottom (sad).
private struct AMORAArc: Shape {
    let up: Bool
    func path(in rect: CGRect) -> Path {
        var path = Path()
        if up {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                              control: CGPoint(x: rect.midX, y: rect.minY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                              control: CGPoint(x: rect.midX, y: rect.maxY))
        }
        return path
    }
}

// MARK: - Floating Music Notes (for dance animation)

private struct MusicNotesFloatingView: View {
    let pulse: Double
    let compact: Bool

    var body: some View {
        let noteSize: CGFloat = compact ? 8 : 11
        HStack(spacing: compact ? 20 : 32) {
            Text("♪")
                .font(.system(size: noteSize, weight: .bold))
                .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.35))
                .offset(y: -pulse * (compact ? 5 : 8))
                .opacity(0.4 + pulse * 0.6)

            Text("♫")
                .font(.system(size: noteSize + 1, weight: .bold))
                .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.40))
                .offset(y: -(1.0 - pulse) * (compact ? 6 : 9))
                .opacity(0.4 + (1.0 - pulse) * 0.6)
        }
        .allowsHitTesting(false)
    }
}
