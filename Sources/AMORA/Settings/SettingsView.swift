import SwiftUI

struct SettingsView: View {
    @Bindable var settings = AppState.shared.settings
    @Bindable var chromeBridge = ChromeMessageBridge.shared
    @State private var memoryService = AmoraMemoryService.shared
    @State private var showClearAllConfirmation = false
    private var palette: ThemePalette { settings.palette }

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
            soundsTab.tabItem { Label("Sounds", systemImage: "speaker.wave.2") }
            modulesTab.tabItem { Label("Modules", systemImage: "square.grid.2x2") }
            aiTab.tabItem { Label("AI Assistant", systemImage: "sparkles") }
            aboutTab.tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 460, height: 420)
        .padding()
        .onAppear { Task { await memoryService.refresh() } }
        // Persist when the window closes so preferences survive relaunch.
        .onDisappear { settings.save() }
        .confirmationDialog(
            "Clear All Memories?",
            isPresented: $showClearAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                Task { await memoryService.clearAll() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all stored memories. This action cannot be undone.")
        }
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
            Section("Desktop Music") {
                LabeledContent("Active Provider", value: music.source.displayName)
                LabeledContent("Spotify Desktop", value: spotifyStatusDescription)
                if !SpotifyProvider.shared.isInstalled {
                    Text("Spotify is not installed on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if SpotifyProvider.shared.hasPermissionDenied {
                    HStack {
                        Text("Automation permission is required to control Spotify.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Open Settings") {
                            SpotifyProvider.openAutomationSettings()
                        }
                        .font(.caption)
                    }
                }
                LabeledContent("Apple Music", value: appleMusicStatusDescription)
                if music.isAvailable {
                    LabeledContent("Current Track", value: "\(music.trackTitle) — \(music.artist)")
                }
            }
            Section("Browser media") {
                LabeledContent("Chrome", value: chromeBridge.status.rawValue)
                LabeledContent("Safari", value: "Not Connected")
                LabeledContent("YouTube", value: youtubeStatus)
                if let media = chromeBridge.state {
                    LabeledContent("Current media", value: media.title)
                    LabeledContent("Source", value: "YouTube — Chrome")
                    LabeledContent("Tracked media tabs", value: "\(media.trackedMediaTabCount)")
                    if let tabId = media.tabId {
                        LabeledContent("Current target", value: "Tab \(tabId)")
                    }
                }
                Text("AMORA tracks minimal YouTube player metadata for open Chrome video tabs. Playback remains available when the video tab or Chrome is in the background; no page contents or browsing history are stored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Chrome stays Connected independently of YouTube detection. Play and pause are sent to AMORA's selected tracked media tab and update only after Chrome acknowledges the action.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                DisclosureGroup("Diagnostics") {
                    diagnosticRow("Native Host", connected: chromeBridge.status == .connected)
                    diagnosticRow("Service Worker", connected: chromeBridge.status == .connected)
                    LabeledContent("Tracked Media Tabs", value: "\(chromeBridge.state?.trackedMediaTabCount ?? 0)")
                    LabeledContent("Current Media Target", value: currentMediaTargetDescription)
                    LabeledContent("Provider", value: chromeBridge.state == nil ? "None" : "YouTube")
                    LabeledContent("Playing", value: chromeBridge.state.map { $0.isPlaying ? "Yes" : "No" } ?? "No")
                    diagnosticRow("YouTube Content Script", connected: chromeBridge.contentDiagnostic?.success == true)
                    diagnosticRow("Video Element", connected: chromeBridge.contentDiagnostic?.hasVideo == true)
                    Button(chromeBridge.contentPingPending ? "Pinging…" : "Run Content Script Ping") {
                        chromeBridge.runContentPing()
                    }
                    .disabled(chromeBridge.contentPingPending || chromeBridge.status != .connected)
                    if let reason = chromeBridge.contentDiagnostic?.reason {
                        Text(Self.diagnosticReason(reason))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var music: MusicService { MusicService.shared }

    private var spotifyStatusDescription: String {
        let provider = SpotifyProvider.shared
        guard provider.isInstalled else { return "Not Installed" }
        if provider.hasPermissionDenied { return "Permission Required" }
        if provider.isRunning {
            if let track = provider.currentTrack {
                return track.isPlaying ? "Playing" : "Paused"
            }
            return "Running"
        }
        return "Not Running"
    }

    private var appleMusicStatusDescription: String {
        let isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty
        return isRunning ? "Running" : "Not Running"
    }

    private var youtubeStatus: String {
        guard let media = chromeBridge.state else { return "Not Detected" }
        if media.isPlaying { return media.isInBackground ? "Playing in background" : "Playing" }
        return "Paused"
    }

    private var currentMediaTargetDescription: String {
        guard let tabId = chromeBridge.state?.tabId else { return "None" }
        return "Tab \(tabId)"
    }

    private func diagnosticRow(_ title: String, connected: Bool) -> some View {
        LabeledContent(title) {
            Label(connected ? "Connected" : "Unavailable", systemImage: connected ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(connected ? .green : .secondary)
        }
    }

    private static func diagnosticReason(_ reason: String) -> String {
        switch reason {
        case "content_script_unavailable": return "Content script unavailable. Reload the extension or YouTube tab."
        case "content_video_unavailable": return "Video unavailable on the active YouTube page."
        case "youtube_tab_unavailable": return "The active tab is not a supported YouTube page."
        default: return reason
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

            Section("Context Awareness") {
                Toggle("Context Awareness", isOn: $settings.contextAwarenessEnabled)
                Text("AMORA can use current Mac state such as the active app, media, timer, and battery to give more helpful answers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Memory") {
                Toggle("Memory", isOn: $settings.memoryEnabled)
                Text("Memories are stored locally and can be reviewed or deleted at any time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                DisclosureGroup("Stored Memories (\(memoryService.memories.count))") {
                    if memoryService.memories.isEmpty {
                        Text("No memories stored yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(memoryService.memories) { item in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.key)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Text(item.value)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    Task { await memoryService.delete(id: item.id) }
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.vertical, 2)
                        }

                        Button("Clear All Memories", role: .destructive) {
                            showClearAllConfirmation = true
                        }
                        .font(.caption)
                        .padding(.top, 4)
                    }
                }
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
