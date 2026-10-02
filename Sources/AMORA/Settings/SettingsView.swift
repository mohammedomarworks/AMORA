import SwiftUI

struct SettingsView: View {
    @Bindable var settings = AppState.shared.settings
    private var palette: ThemePalette { settings.palette }

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
            soundsTab.tabItem { Label("Sounds", systemImage: "speaker.wave.2") }
            modulesTab.tabItem { Label("Modules", systemImage: "square.grid.2x2") }
            aiTab.tabItem { Label("AI Assistant", systemImage: "sparkles") }
            aboutTab.tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 460, height: 400)
        .padding()
        // Persist when the window closes so preferences survive relaunch.
        .onDisappear { settings.save() }
    }

    // MARK: - General (Appearance + Behavior)
    private var generalTab: some View {
        Form {
            Section("Appearance") {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Theme", selection: $settings.theme) {
                        ForEach(Theme.allCases, id: \.self) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }
                    HStack(spacing: 8) {
                        Circle().fill(palette.accent).frame(width: 18, height: 18)
                        Text(themeDescription(settings.theme))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Live preview")
                            .font(.caption2)
                            .foregroundStyle(palette.accent)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(palette.accent.opacity(0.12)))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Slider(value: $settings.animationIntensity, in: 0.0...1.0) {
                        Text("Animation intensity")
                    }
                    if MotionConfig.reduceMotion {
                        Text("System Reduce Motion is on — non-essential animation is minimized.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Slider(value: $settings.amoraSize, in: 24...44) {
                    Text("AMORA size")
                }

                VStack(alignment: .leading, spacing: 2) {
                    Slider(value: $settings.transparency, in: 0.3...1.0) {
                        Text("Opacity")
                    }
                    Text("Controls the transparency of AMORA's expanded surfaces.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Behavior") {
                Toggle("Hover notch to expand", isOn: $settings.hoverToExpand)
                Toggle("Click notch to expand", isOn: $settings.clickToExpand)
                Toggle("Sleep mode when idle", isOn: $settings.sleepMode)
                HStack {
                    Text("Auto-collapse delay")
                    Spacer()
                    Text("\(Int(settings.autoCollapseDelay))s")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $settings.autoCollapseDelay, in: 1...10, step: 1)
            }
        }
    }

    private func themeDescription(_ theme: Theme) -> String {
        switch theme {
        case .midnight: return "Deep violet accent"
        case .ocean: return "Cool blue accent"
        case .bubblegum: return "Soft pink accent"
        case .matrix: return "Terminal green accent"
        case .minimal: return "Monochrome"
        }
    }

    // MARK: - Sounds
    private var soundsTab: some View {
        Form {
            Section("Sound Effects") {
                Toggle("Enable sounds", isOn: $settings.soundEnabled)
                Slider(value: $settings.soundVolume, in: 0.0...1.0) {
                    Text("Volume")
                }
                .disabled(!settings.soundEnabled)
                Button("Preview") { SoundService.shared.play(.success) }
                    .disabled(!settings.soundEnabled)
            }
            Section {
                Text("AMORA uses subtle built-in macOS sounds for meaningful moments only — never on every poll.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Modules
    private var modulesTab: some View {
        Form {
            Section("Enabled Modules") {
                Toggle("Battery Monitor", isOn: $settings.batteryEnabled)
                Toggle("Focus Timer", isOn: $settings.timerEnabled)
                Toggle("Music Controller", isOn: $settings.musicEnabled)
                Toggle("Clipboard History", isOn: $settings.clipboardEnabled)
                Toggle("Quick Notes", isOn: $settings.notesEnabled)
                Toggle("System Monitor", isOn: $settings.systemMonitorEnabled)
            }
            Section("Browser media") {
                Text("AMORA can identify a YouTube tab in Safari or Chrome using macOS Automation. Playback controls and progress stay unavailable unless the browser exposes them safely.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("If macOS asks, allow AMORA to control Safari or Google Chrome. If permission is denied, Apple Music and other local modules continue to work normally.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - AI Assistant
    private var aiTab: some View {
        Form {
            Section("AI Assistant") {
                Toggle("Enable AI Assistant", isOn: $settings.aiEnabled)
                Picker("Provider", selection: $settings.aiProvider) {
                    Text("Apple On-Device").tag(AIProviderKind.appleOnDevice.rawValue)
                    Text("Anthropic (Claude)").tag("anthropic")
                    Text("OpenAI").tag("openai")
                    Text("Unavailable / None").tag(AIProviderKind.none.rawValue)
                }
                if settings.aiProvider == AIProviderKind.appleOnDevice.rawValue {
                    Text("Apple On-Device keeps Foundation Model processing on this Mac and requires no API key.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    let appleSettings = AISettingsSnapshot(enabled: true, provider: .appleOnDevice, model: "apple-on-device", apiKey: nil)
                    let availability = AIProviderFactory.make(for: appleSettings).availability
                    LabeledContent("Availability", value: availability.displayName)
                } else if settings.aiProvider != AIProviderKind.none.rawValue {
                    SecureField("API Key", text: $settings.aiApiKey)
                }
                Text("Keys are stored locally on this Mac and never shown in plain text elsewhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - About
    private var aboutTab: some View {
        VStack(spacing: 12) {
            Image(systemName: "circle.hexagongrid.fill")
                .font(.system(size: 48))
                .foregroundStyle(palette.accent)

            Text("AMORA")
                .font(.system(size: 18, weight: .bold, design: .rounded))

            Text("Your little Mac companion.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text("Version 1.0.0")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
