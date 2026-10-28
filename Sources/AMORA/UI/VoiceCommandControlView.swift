import SwiftUI

// MARK: - Mini Audio Waveform Visualizer

struct AudioWaveformVisualizer: View {
    let level: Float
    let accentColor: Color

    init(level: Float, accentColor: Color) {
        self.level = level
        self.accentColor = accentColor
    }

    private let barCount = 4

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(accentColor)
                    .frame(width: 3, height: barHeight(for: index))
                    .animation(.spring(response: 0.15, dampingFraction: 0.6), value: level)
            }
        }
        .frame(height: 16)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let baseHeight: CGFloat = 3.5
        let maxHeight: CGFloat = 16.0
        let multipliers: [Float] = [0.8, 1.2, 1.0, 0.7]
        let factor = multipliers[index % multipliers.count]
        let scaled = CGFloat(level * factor) * (maxHeight - baseHeight)
        return min(maxHeight, max(baseHeight, baseHeight + scaled))
    }
}

// MARK: - Voice Command Button

struct VoiceCommandButton: View {
    @Bindable private var voice = VoiceCommandService.shared
    private var palette: ThemePalette { AppState.shared.settings.palette }

    init() {}

    var body: some View {
        Button {
            handleTap()
        } label: {
            ZStack {
                switch voice.state {
                case .listening(let audioLevel, _):
                    HStack(spacing: 3) {
                        AudioWaveformVisualizer(level: audioLevel, accentColor: .white)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.red.opacity(0.85)))
                    .shadow(color: Color.red.opacity(0.5), radius: 6, x: 0, y: 0)

                case .processing:
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 20, height: 20)

                case .completed:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.green)

                case .permissionDenied:
                    Image(systemName: "mic.slash.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.orange)

                case .unavailable, .failed:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.orange)

                default:
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.accent)
                }
            }
            .frame(height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(buttonHelpText)
        .accessibilityLabel(buttonAccessibilityLabel)
    }

    private var buttonHelpText: String {
        switch voice.state {
        case .listening:
            return "Listening… Click to finish and send, or click cancel."
        case .processing:
            return "Processing voice command…"
        case .completed:
            return "Voice command completed!"
        case .permissionDenied:
            return "Microphone or Speech Recognition permission required. Click to open System Settings."
        case .unavailable:
            return "Speech recognition unavailable: \(voice.lastErrorMessage ?? "Unknown reason")"
        case .failed:
            return "Voice recognition failed: \(voice.lastErrorMessage ?? "Unknown error"). Click to retry."
        default:
            return "Voice Command (Click to speak)"
        }
    }

    private var buttonAccessibilityLabel: String {
        switch voice.state {
        case .listening:
            return "Stop listening and submit"
        case .processing:
            return "Processing speech"
        case .completed:
            return "Voice command finished"
        case .permissionDenied:
            return "Microphone permission required"
        case .unavailable, .failed:
            return "Speech recognition error"
        default:
            return "Start voice command"
        }
    }

    private func handleTap() {
        if voice.isListening {
            voice.stopAndSubmit()
        } else if case .permissionDenied = voice.state {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        } else {
            Task {
                await voice.startListening()
            }
        }
    }
}

// MARK: - Voice Command Live Listening Banner

struct VoiceCommandListeningBanner: View {
    @Bindable private var voice = VoiceCommandService.shared
    private var palette: ThemePalette { AppState.shared.settings.palette }

    init() {}

    var body: some View {
        if voice.isListening {
            HStack(spacing: 8) {
                AudioWaveformVisualizer(level: voice.audioLevel, accentColor: palette.accent)
                    .frame(width: 24, height: 14)

                Text(voice.currentTranscript.isEmpty ? "Listening for command…" : voice.currentTranscript)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(voice.currentTranscript.isEmpty ? .white.opacity(0.6) : .white)
                    .lineLimit(1)

                Spacer()

                Text(voice.isEngineOnDevice ? "On-Device" : "Apple Speech")
                    .font(.system(size: 8, weight: .semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
                    .foregroundStyle(.white.opacity(0.8))

                Button {
                    voice.cancelListening()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
                .help("Cancel voice command")
                .accessibilityLabel("Cancel voice command")

                Button {
                    voice.stopAndSubmit()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(palette.accent)
                }
                .buttonStyle(.plain)
                .help("Submit spoken command")
                .accessibilityLabel("Submit spoken command")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.65)))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(palette.accent.opacity(0.3), lineWidth: 1))
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if let error = voice.lastErrorMessage, case .failed = voice.state {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.15)))
            .transition(.opacity)
        }
    }
}
