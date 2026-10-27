import SwiftUI

/// Background visual effect displayed behind AMORA while music playback is actively
/// dancing. Recreates the reference design: a radiant warm coral under-chassis glow aura,
/// subtle sound vibration arcs, floating musical notes in orange, coral, and white, and
/// a bottom equalizer waveform spectrum visualizer.
///
/// Designed as a strictly separate background visual layer that does not resize, stretch,
/// or alter the mascot's foreground body geometry.
struct MusicDanceBackgroundView: View {
    let robot: AMORARobot
    var compact: Bool = false

    private var motion: Double { AppState.shared.settings.motionScale }

    var body: some View {
        ZStack {
            // 1. Warm coral under-chassis glow aura
            chassisGlowAura

            // 2. Chassis motion vibration arcs
            chassisVibrationArcs

            // 3. Antenna sound vibe waves
            antennaVibeWaves

            // 4. Floating musical notes on left and right
            floatingMusicNotes

            // 5. Audio waveform / equalizer spectrum bars beneath chassis
            equalizerSpectrumBars
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - 1. Chassis Glow Aura

    private var chassisGlowAura: some View {
        let auraWidth: CGFloat = compact ? 52 : 78
        let auraHeight: CGFloat = compact ? 18 : 28
        let pulse = robot.danceGlowPulse

        return Ellipse()
            .fill(
                RadialGradient(
                    colors: [
                        Color(red: 1.0, green: 0.35, blue: 0.40).opacity(0.70 * (0.6 + 0.4 * pulse)),
                        Color(red: 1.0, green: 0.22, blue: 0.28).opacity(0.40 * (0.6 + 0.4 * pulse)),
                        Color(red: 0.95, green: 0.15, blue: 0.20).opacity(0.12 * (0.6 + 0.4 * pulse)),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 2,
                    endRadius: compact ? 26 : 39
                )
            )
            .frame(width: auraWidth, height: auraHeight)
            .offset(y: compact ? 13 : 19)
            .blur(radius: compact ? 2.5 : 4.5)
    }

    // MARK: - 2. Chassis Vibration Arcs

    private var chassisVibrationArcs: some View {
        let pulse = robot.danceGlowPulse
        let arcWidth: CGFloat = compact ? 5 : 7
        let arcHeight: CGFloat = compact ? 10 : 15
        let strokeColor = Color(red: 1.0, green: 0.44, blue: 0.48).opacity(0.65 * (0.5 + 0.5 * pulse))
        let lineWidth: CGFloat = compact ? 1.4 : 1.8

        return Group {
            // Left flanking arc
            VibrationArcShape(bowsLeft: true)
                .stroke(strokeColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .frame(width: arcWidth, height: arcHeight)
                .offset(x: compact ? -22 : -32, y: compact ? 10 : 15)

            // Right flanking arc
            VibrationArcShape(bowsLeft: false)
                .stroke(strokeColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .frame(width: arcWidth, height: arcHeight)
                .offset(x: compact ? 22 : 32, y: compact ? 10 : 15)
        }
    }

    // MARK: - 3. Antenna Audio Waves

    private var antennaVibeWaves: some View {
        let pulse = robot.danceAntennaPhase
        let strokeColor = Color(red: 1.0, green: 0.52, blue: 0.44).opacity(0.60 * (0.4 + 0.6 * pulse))
        let lineWidth: CGFloat = compact ? 1.1 : 1.4

        return Group {
            // Inner small wave arc
            VibrationArcShape(bowsLeft: false)
                .stroke(strokeColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .frame(width: compact ? 3.5 : 5, height: compact ? 6 : 9)
                .offset(x: compact ? 6 : 9, y: compact ? -15 : -22)

            // Outer wave arc
            VibrationArcShape(bowsLeft: false)
                .stroke(strokeColor.opacity(0.75), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .frame(width: compact ? 4.5 : 6.5, height: compact ? 8 : 12)
                .offset(x: compact ? 9.5 : 14, y: compact ? -16 : -23)
        }
    }

    // MARK: - 4. Floating Music Notes

    private var floatingMusicNotes: some View {
        let pulse = robot.danceAntennaPhase
        let orangeColor = Color(red: 1.0, green: 0.56, blue: 0.22)
        let coralColor = Color(red: 1.0, green: 0.38, blue: 0.42)
        let whiteColor = Color.white.opacity(0.88)

        let bigSize: CGFloat = compact ? 9 : 13
        let midSize: CGFloat = compact ? 8 : 11
        let smallSize: CGFloat = compact ? 6.5 : 9

        return Group {
            // --- Left Side Notes ---
            // Upper Left: Orange double note ♫
            Text("♫")
                .font(.system(size: bigSize, weight: .bold))
                .foregroundStyle(orangeColor)
                .offset(x: compact ? -23 : -33, y: (compact ? -9 : -13) - pulse * (compact ? 3.0 : 4.5) * motion)
                .opacity(0.5 + pulse * 0.5)

            // Mid Left: Coral single note ♪
            Text("♪")
                .font(.system(size: midSize, weight: .bold))
                .foregroundStyle(coralColor)
                .offset(x: compact ? -19 : -27, y: (compact ? 2 : 3) - (1.0 - pulse) * (compact ? 2.5 : 4.0) * motion)
                .opacity(0.5 + (1.0 - pulse) * 0.5)

            // Lower Left: White single note ♪
            Text("♪")
                .font(.system(size: smallSize, weight: .bold))
                .foregroundStyle(whiteColor)
                .offset(x: compact ? -22 : -31, y: (compact ? 12 : 17) - pulse * (compact ? 2.0 : 3.0) * motion)
                .opacity(0.4 + pulse * 0.5)

            // --- Right Side Notes ---
            // Upper Right: Coral single note ♪
            Text("♪")
                .font(.system(size: midSize, weight: .bold))
                .foregroundStyle(coralColor)
                .offset(x: compact ? 19 : 27, y: (compact ? -11 : -16) - (1.0 - pulse) * (compact ? 2.5 : 4.0) * motion)
                .opacity(0.5 + (1.0 - pulse) * 0.5)

            // Mid Right: Orange double note ♫
            Text("♫")
                .font(.system(size: bigSize, weight: .bold))
                .foregroundStyle(orangeColor)
                .offset(x: compact ? 23 : 33, y: (compact ? 0 : 1) - pulse * (compact ? 3.0 : 4.5) * motion)
                .opacity(0.5 + pulse * 0.5)

            // Lower Right: White single note ♪
            Text("♪")
                .font(.system(size: smallSize, weight: .bold))
                .foregroundStyle(whiteColor)
                .offset(x: compact ? 18 : 26, y: (compact ? 11 : 16) - (1.0 - pulse) * (compact ? 2.0 : 3.0) * motion)
                .opacity(0.4 + (1.0 - pulse) * 0.5)
        }
    }

    // MARK: - 5. Equalizer Waveform Spectrum Bars

    private var equalizerSpectrumBars: some View {
        let barCount = 15
        let barWidth: CGFloat = compact ? 1.6 : 2.2
        let barSpacing: CGFloat = compact ? 1.8 : 2.6
        let minHeight: CGFloat = compact ? 2.5 : 3.5
        let maxHeight: CGFloat = compact ? 9.0 : 13.0
        let phase = robot.danceAntennaPhase * .pi * 2

        // Parabolic profile: taller at center (index 7), tapering at edges (0 and 14)
        return HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { i in
                let normDist = abs(Double(i) - 7.0) / 7.0 // 0.0 at center, 1.0 at edges
                let profile = 1.0 - (normDist * normDist * 0.72) // 1.0 at center, ~0.28 at edges
                let dynamicFactor: Double = motion > 0
                    ? 0.65 + 0.35 * sin(phase + Double(i) * 0.62)
                    : 0.85
                let h = minHeight + (maxHeight - minHeight) * profile * dynamicFactor

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.44, blue: 0.38),
                                Color(red: 1.0, green: 0.28, blue: 0.30)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: barWidth, height: h)
            }
        }
        .offset(y: compact ? 22 : 31)
    }
}

// MARK: - Vibration Arc Shape

/// A single quadratic curve bowing toward the left or right, used for chassis and antenna vibes.
private struct VibrationArcShape: Shape {
    let bowsLeft: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if bowsLeft {
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY),
                control: CGPoint(x: rect.minX, y: rect.midY)
            )
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY),
                control: CGPoint(x: rect.maxX, y: rect.midY)
            )
        }
        return path
    }
}
