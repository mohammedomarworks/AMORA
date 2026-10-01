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
                Picker("Theme", selection: $settings.theme) {
                    ForEach(Theme.allCases, id: \.self) { theme in
                        Text(theme.rawValue).tag(theme)
                    }
                }

                // Live palette swatches — tap to switch; the whole character and
                // panel recolor from the chosen theme's palette.
                HStack(spacing: 10) {
                    Text("Accent")
                    Spacer()
                    ForEach(Theme.allCases, id: \.self) { theme in
                        Circle()
                            .fill(theme.palette.accent)
                            .frame(width: 16, height: 16)
                            .overlay(
                                Circle().strokeBorder(
                                    .white.opacity(settings.theme == theme ? 0.9 : 0),
                                    lineWidth: 1.5
                                )
                            )
                            .onTapGesture { settings.theme = theme }
                            .accessibilityLabel("\(theme.rawValue) theme")
                    }
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

                Slider(value: $settings.transparency, in: 0.3...1.0) {
                    Text("Opacity")
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
        }
    }

    // MARK: - AI Assistant
    private var aiTab: some View {
        Form {
            Section("AI Assistant") {
                Toggle("Enable AI Assistant", isOn: $settings.aiEnabled)
                Picker("Provider", selection: $settings.aiProvider) {
                    Text("Anthropic (Claude)").tag("anthropic")
                    Text("OpenAI").tag("openai")
                    Text("Local (Offline)").tag("local")
                }
                SecureField("API Key", text: $settings.aiApiKey)
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
