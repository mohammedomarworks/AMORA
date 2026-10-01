import SwiftUI

struct SettingsView: View {
    @Bindable var settings = AppState.shared.settings

    var body: some View {
        TabView {
            // General Behavior
            Form {
                Section("Behavior") {
                    Toggle("Hover notch to expand", isOn: $settings.hoverToExpand)
                    Toggle("Click notch to expand", isOn: $settings.clickToExpand)
                    Toggle("Sleep mode when idle", isOn: $settings.sleepMode)
                }

                Section("Appearance") {
                    Picker("Theme", selection: $settings.theme) {
                        ForEach(Theme.allCases, id: \.self) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }

                    Slider(value: $settings.transparency, in: 0.3...1.0) {
                        Text("Opacity")
                    }
                }
            }
            .tabItem {
                Label("General", systemImage: "gearshape")
            }

            // Modules
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
            .tabItem {
                Label("Modules", systemImage: "square.grid.2x2")
            }

            // AI / Assistant
            Form {
                Section("AI Assistant") {
                    Toggle("Enable AI Assistant", isOn: $settings.aiEnabled)
                    Picker("Provider", selection: $settings.aiProvider) {
                        Text("Anthropic (Claude)").tag("anthropic")
                        Text("OpenAI").tag("openai")
                        Text("Local (Offline)").tag("local")
                    }
                    SecureField("API Key", text: $settings.aiApiKey)
                }
            }
            .tabItem {
                Label("AI Assistant", systemImage: "sparkles")
            }

            // About
            VStack(spacing: 12) {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.cyan)

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
            .tabItem {
                Label("About", systemImage: "info.circle")
            }
        }
        .frame(width: 440, height: 320)
        .padding()
    }
}
