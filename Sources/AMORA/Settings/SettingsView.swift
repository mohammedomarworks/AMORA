import SwiftUI
import AppKit

// MARK: - Navigation State & Sections

@Observable @MainActor
public final class SettingsViewState {
    public static let shared = SettingsViewState()
    public var selectedSection: SettingsSection = .appearance
    public var filterQuery: String = ""
}

public enum SettingsSection: String, CaseIterable, Identifiable {
    case appearance = "Appearance"
    case behavior = "Behavior"
    case sounds = "Sounds"
    case aiAssistant = "AI Assistant"
    case contextAwareness = "Context & Proactive"
    case memory = "Memory"
    case modules = "Modules & Media"
    case automations = "Automations"
    case about = "About"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .appearance: return "paintpalette.fill"
        case .behavior: return "cursorarrow.rays"
        case .sounds: return "speaker.wave.2.fill"
        case .aiAssistant: return "sparkles"
        case .contextAwareness: return "eye.fill"
        case .memory: return "brain.head.profile"
        case .modules: return "square.grid.2x2.fill"
        case .automations: return "bolt.badge.clock.fill"
        case .about: return "info.circle.fill"
        }
    }

    public var badgeColor: Color {
        switch self {
        case .appearance: return Color.purple
        case .behavior: return Color.blue
        case .sounds: return Color.pink
        case .aiAssistant: return Color.indigo
        case .contextAwareness: return Color.teal
        case .memory: return Color.green
        case .modules: return Color.orange
        case .automations: return Color(red: 0.95, green: 0.70, blue: 0.10)
        case .about: return Color.gray
        }
    }

    public var subtitle: String {
        switch self {
        case .appearance: return "Visual themes, character sizing, surface opacity, and motion effects."
        case .behavior: return "Dynamic Island notch interaction, idle sleep, and auto-collapse timing."
        case .sounds: return "Tactile audio feedback, volume controls, and sound preview."
        case .aiAssistant: return "Intelligence provider configuration and offline Local Brain model runtime."
        case .contextAwareness: return "Mac situational context, proactive Dynamic Island prompts, and safety rules."
        case .memory: return "Review, inspect, and manage locally stored preferences and facts."
        case .modules: return "Active companion modules, Spotify, Apple Music, and Chrome browser bridge."
        case .automations: return "Scheduled background routines, battery triggers, and timer automations."
        case .about: return "AMORA version information, system health, and companion status."
        }
    }
}

// MARK: - Reusable Settings Components

struct SettingsCard<Content: View>: View {
    let title: String?
    let description: String?
    @ViewBuilder let content: () -> Content

    init(title: String? = nil, description: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.description = description
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            if let description {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.65))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.5)
                    )
            )
        }
    }
}

struct SettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var iconColor: Color? = nil
    @ViewBuilder let trailing: () -> Trailing

    init(
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        iconColor: Color? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.iconColor = iconColor
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(iconColor ?? .secondary)
                    .frame(width: 22, height: 22)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            trailing()
        }
    }
}

// MARK: - Main Settings View

public struct SettingsView: View {
    @Bindable var settings = AppState.shared.settings
    @Bindable var chromeBridge = ChromeMessageBridge.shared
    @Bindable var navState = SettingsViewState.shared
    @State private var memoryService = AmoraMemoryService.shared
    @State private var modelManager = AmoraModelManager.shared
    @State private var showClearAllConfirmation = false
    @State private var showDeleteModelConfirmation = false
    @State private var memoryFilter = ""
    @State private var editingMemoryId: UUID? = nil
    @State private var editingKey = ""
    @State private var editingValue = ""

    private var palette: ThemePalette { settings.palette }

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.55))

            Divider()

            detailView
                .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .underPageBackgroundColor).opacity(0.35))
        }
        .frame(minWidth: 700, minHeight: 520)
        .onAppear {
            Task {
                await memoryService.refresh()
                await AmoraAutomationService.shared.refresh()
                _ = await modelManager.checkStatus()
                chromeBridge.probeConnectionIfChromeRunning()
            }
        }
        .onDisappear {
            settings.save()
        }
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
        .confirmationDialog(
            "Delete Offline Brain Model?",
            isPresented: $showDeleteModelConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Model", role: .destructive) {
                Task {
                    await AmoraLocalBrainProvider.shared.runtime.unloadModel()
                    try? await modelManager.deleteModel()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete the downloaded model file (~\(modelManager.descriptor.formattedExpectedSize)). You can download it again whenever you want.")
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            // App Header
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(palette.accent.opacity(0.2))
                        .frame(width: 32, height: 32)
                    Image(systemName: "circle.hexagongrid.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(palette.accent)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("AMORA")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("Settings")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 12)

            // Section List
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 3) {
                    ForEach(SettingsSection.allCases) { section in
                        sidebarItem(section)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            }

            Spacer()

            Divider()
                .padding(.horizontal, 12)

            // Sidebar Footer status
            HStack(spacing: 8) {
                Circle()
                    .fill(palette.accent)
                    .frame(width: 8, height: 8)
                Text(settings.theme.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(modelManager.status.displayName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func sidebarItem(_ section: SettingsSection) -> some View {
        let isSelected = navState.selectedSection == section
        return Button {
            withAnimation(.easeInOut(duration: 0.12)) {
                navState.selectedSection = section
            }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(section.badgeColor.opacity(isSelected ? 0.9 : 0.8))
                        .frame(width: 22, height: 22)
                    Image(systemName: section.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                }

                Text(section.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : Color.primary.opacity(0.85))

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? palette.accent.opacity(0.16) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail View

    private var detailView: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(navState.selectedSection.rawValue)
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(navState.selectedSection.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Divider()

            // Scrollable Content
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    switch navState.selectedSection {
                    case .appearance:
                        appearanceSection
                    case .behavior:
                        behaviorSection
                    case .sounds:
                        soundsSection
                    case .aiAssistant:
                        aiAssistantSection
                    case .contextAwareness:
                        contextAwarenessSection
                    case .memory:
                        memorySection
                    case .modules:
                        modulesSection
                    case .automations:
                        automationsSection
                    case .about:
                        aboutSection
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }
        }
    }

    // MARK: - Appearance Section

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard(
                title: "Theme & Accent",
                description: "Select AMORA's color scheme. All Dynamic Island surfaces and character eyes update instantly."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    // Swatch grid
                    HStack(spacing: 10) {
                        ForEach(Theme.allCases, id: \.self) { theme in
                            let isThemeSelected = settings.theme == theme
                            Button {
                                settings.theme = theme
                            } label: {
                                VStack(spacing: 6) {
                                    Circle()
                                        .fill(theme.palette.accent)
                                        .frame(width: 24, height: 24)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color.white.opacity(0.8), lineWidth: isThemeSelected ? 2 : 0)
                                        )
                                    Text(theme.rawValue)
                                        .font(.system(size: 11, weight: isThemeSelected ? .semibold : .regular))
                                        .foregroundStyle(isThemeSelected ? .primary : .secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(isThemeSelected ? theme.palette.accent.opacity(0.18) : Color(nsColor: .controlBackgroundColor))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .strokeBorder(isThemeSelected ? theme.palette.accent : Color.clear, lineWidth: 1.5)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Live preview banner
                    HStack(spacing: 12) {
                        Circle()
                            .fill(palette.accent)
                            .frame(width: 14, height: 14)
                        Text(themeDescription(settings.theme))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Active Theme")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(palette.accent)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(palette.accent.opacity(0.10))
                    )
                }
            }

            SettingsCard(
                title: "Sizing & Transparency",
                description: "Fine-tune AMORA's notch character proportions and backdrop intensity."
            ) {
                VStack(spacing: 14) {
                    SettingsRow(
                        title: "AMORA Size",
                        subtitle: "Scales the robot eyes within the notch.",
                        icon: "arrow.up.left.and.arrow.down.right"
                    ) {
                        HStack(spacing: 10) {
                            Slider(value: $settings.amoraSize, in: 24...44)
                                .frame(width: 160)
                            Text("\(Int(settings.amoraSize)) pt")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }

                    Divider()

                    SettingsRow(
                        title: "Surface Opacity",
                        subtitle: "Background translucency of AMORA's expanded Dynamic Island.",
                        icon: "circle.lefthalf.filled"
                    ) {
                        HStack(spacing: 10) {
                            Slider(value: $settings.transparency, in: 0.3...1.0)
                                .frame(width: 160)
                            Text("\(Int(settings.transparency * 100))%")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
            }

            SettingsCard(
                title: "Motion & Animation",
                description: "Adjust dynamic spring velocity and transition responsiveness."
            ) {
                VStack(spacing: 12) {
                    SettingsRow(
                        title: "Animation Intensity",
                        subtitle: "Scales transition velocity and eyelid bounce.",
                        icon: "sparkles"
                    ) {
                        HStack(spacing: 10) {
                            Slider(value: $settings.animationIntensity, in: 0.0...1.0)
                                .frame(width: 160)
                            Text("\(Int(settings.animationIntensity * 100))%")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }

                    if MotionConfig.reduceMotion {
                        HStack(spacing: 8) {
                            Image(systemName: "figure.walk.motion")
                                .foregroundStyle(.orange)
                            Text("System Reduce Motion is enabled — non-essential animations are automatically subdued.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.orange.opacity(0.12))
                        )
                    }
                }
            }
        }
    }

    private func themeDescription(_ theme: Theme) -> String {
        switch theme {
        case .midnight: return "Deep violet accent with dark space-gray chassis"
        case .ocean: return "Cool teal-cyan accent with slate blue surfaces"
        case .bubblegum: return "Soft pink accent with warm purple tones"
        case .matrix: return "Phosphor terminal green with high-contrast chassis"
        case .minimal: return "Clean monochrome with subtle cool-gray highlights"
        }
    }

    // MARK: - Behavior Section

    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard(
                title: "Notch Expansion Triggers",
                description: "Configure mouse interactions that trigger AMORA to unfold from the MacBook notch."
            ) {
                VStack(spacing: 14) {
                    SettingsRow(
                        title: "Hover notch to expand",
                        subtitle: "Expand the Dynamic Island when the mouse pointer moves over the notch.",
                        icon: "hand.point.up.left"
                    ) {
                        Toggle("", isOn: $settings.hoverToExpand)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    Divider()

                    SettingsRow(
                        title: "Click notch to expand",
                        subtitle: "Expand to Quick Controls immediately when clicking the notch surface.",
                        icon: "cursorarrow.click.2"
                    ) {
                        Toggle("", isOn: $settings.clickToExpand)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }
            }

            SettingsCard(
                title: "Power & Auto-Collapse",
                description: "Manage idle dormant behavior and collapse timing."
            ) {
                VStack(spacing: 14) {
                    SettingsRow(
                        title: "Sleep mode when idle",
                        subtitle: "Dormant eyes and lower refresh rate during periods of user inactivity.",
                        icon: "moon.stars"
                    ) {
                        Toggle("", isOn: $settings.sleepMode)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    Divider()

                    SettingsRow(
                        title: "Auto-collapse delay",
                        subtitle: "How long AMORA waits before contracting back after cursor leaves the island.",
                        icon: "timer"
                    ) {
                        HStack(spacing: 10) {
                            Slider(value: $settings.autoCollapseDelay, in: 1...10, step: 1)
                                .frame(width: 160)
                            Text("\(Int(settings.autoCollapseDelay))s")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sounds Section

    private var soundsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard(
                title: "Audio Feedback",
                description: "Subtle system audio cues for meaningful events, timer completions, and errors."
            ) {
                VStack(spacing: 14) {
                    SettingsRow(
                        title: "Enable sound effects",
                        subtitle: "Play tactile clicks and completion chimes.",
                        icon: "speaker.wave.2"
                    ) {
                        Toggle("", isOn: $settings.soundEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    Divider()

                    SettingsRow(
                        title: "Sound volume",
                        subtitle: "Volume level for all AMORA audio notifications.",
                        icon: "speaker.wave.1"
                    ) {
                        HStack(spacing: 10) {
                            Slider(value: $settings.soundVolume, in: 0.0...1.0)
                                .frame(width: 160)
                                .disabled(!settings.soundEnabled)
                            Text("\(Int(settings.soundVolume * 100))%")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(settings.soundEnabled ? .secondary : .tertiary)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }

                    Divider()

                    SettingsRow(
                        title: "Preview Sound",
                        subtitle: "Test the primary success notification chime.",
                        icon: "play.circle"
                    ) {
                        Button {
                            SoundService.shared.play(.success)
                        } label: {
                            Label("Play Sample", systemImage: "play.fill")
                        }
                        .disabled(!settings.soundEnabled)
                    }
                }
            }

            SettingsCard(
                title: "Character Emotion Sounds",
                description: "Original synthesized audio for expressive mascot emotion states."
            ) {
                VStack(spacing: 12) {
                    emotionSoundRow(
                        title: "Love & Affection",
                        subtitle: "Warm, sweet major arpeggio chime played during petting.",
                        icon: "heart.fill",
                        sound: .love
                    )

                    Divider()

                    emotionSoundRow(
                        title: "Playfully Grumpy",
                        subtitle: "Short, playful descending robo-grumble when poked rapidly.",
                        icon: "face.dashed",
                        sound: .grumpy
                    )

                    Divider()

                    emotionSoundRow(
                        title: "Excitement",
                        subtitle: "Energetic, cheerful rising chirp and celebratory chime.",
                        icon: "sparkles",
                        sound: .excited
                    )

                    Divider()

                    emotionSoundRow(
                        title: "Gentle Sadness",
                        subtitle: "Soft, gentle melancholy descending sigh on cancellation.",
                        icon: "cloud.rain.fill",
                        sound: .sad
                    )
                }
            }

            SettingsCard(
                title: "Audio Policy",
                description: "AMORA strictly limits audio feedback to user-facing events. Sound is never triggered during background checks or background polling."
            ) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 18))
                        .foregroundStyle(.green)
                    Text("Only meaningful moments trigger audio: completed timers, manual action triggers, and explicit user commands.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func emotionSoundRow(title: String, subtitle: String, icon: String, sound: AMORASound) -> some View {
        SettingsRow(
            title: title,
            subtitle: subtitle,
            icon: icon
        ) {
            Button {
                SoundService.shared.resetCooldownsForTesting()
                SoundService.shared.play(sound)
            } label: {
                Label("Preview", systemImage: "play.fill")
            }
            .disabled(!settings.soundEnabled)
        }
    }

    // MARK: - AI Assistant Section

    private var aiAssistantSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard(
                title: "Intelligence Engine",
                description: "Select which model powers natural language parsing and conversational assistance."
            ) {
                VStack(spacing: 14) {
                    SettingsRow(
                        title: "Enable AI Assistant",
                        subtitle: "Enables conversational questions and natural language actions.",
                        icon: "sparkles"
                    ) {
                        Toggle("", isOn: $settings.aiEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    Divider()

                    SettingsRow(
                        title: "AI Provider",
                        subtitle: "Choose between on-device privacy, offline LLM, or cloud models.",
                        icon: "cpu"
                    ) {
                        Picker("", selection: $settings.aiProvider) {
                            Text("Apple On-Device").tag(AIProviderKind.appleOnDevice.rawValue)
                            Text("Local Brain (Offline)").tag(AIProviderKind.local.rawValue)
                            Text("Anthropic (Claude)").tag("anthropic")
                            Text("OpenAI").tag("openai")
                            Text("Unavailable / None").tag(AIProviderKind.none.rawValue)
                        }
                        .labelsHidden()
                        .frame(width: 190)
                    }
                }
            }

            // Provider-specific details
            if settings.aiProvider == AIProviderKind.appleOnDevice.rawValue {
                SettingsCard(
                    title: "Apple On-Device Foundation Model",
                    description: "Processes prompt inputs directly on Apple Silicon with hardware security."
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        let appleSettings = AISettingsSnapshot(enabled: true, provider: .appleOnDevice, model: "apple-on-device", apiKey: nil)
                        let availability = AIProviderFactory.make(for: appleSettings).availability

                        HStack {
                            Text("Runtime Availability")
                                .font(.subheadline)
                            Spacer()
                            Label(
                                availability.displayName,
                                systemImage: availability == .available ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                            )
                            .foregroundStyle(availability == .available ? Color.green : Color.secondary)
                            .font(.subheadline)
                        }

                        if availability != .available {
                            HStack {
                                Text("Apple on-device AI is unsupported on this macOS version. Switch to Local Brain to run offline models directly on this Mac.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Switch to Local Brain") {
                                    settings.aiProvider = AIProviderKind.local.rawValue
                                    settings.aiModel = AmoraModelDescriptor.defaultModel.id
                                    settings.save()
                                }
                                .font(.caption)
                                .buttonStyle(.borderedProminent)
                            }
                            .padding(.top, 4)
                        }

                        Text("Apple On-Device models run 100% locally on your Mac. No network calls are made and no API key is required.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if settings.aiProvider == AIProviderKind.local.rawValue {
                offlineLocalBrainCard
            } else if settings.aiProvider != AIProviderKind.none.rawValue {
                SettingsCard(
                    title: "Cloud Provider Configuration",
                    description: "Configure your API authentication key for cloud models."
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        SettingsRow(
                            title: "API Key",
                            subtitle: "Encrypted securely in macOS Keychain / local application store.",
                            icon: "key"
                        ) {
                            SecureField("Enter API Key", text: $settings.aiApiKey)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 200)
                        }

                        Text("API keys are stored on this Mac and transmitted only to the designated provider endpoint. Never shared with third parties.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var offlineLocalBrainCard: some View {
        SettingsCard(
            title: "AMORA Local Brain (Offline LLM)",
            description: "Qwen 2.5 quantized local model running directly in-process via llama.cpp with Metal GPU acceleration."
        ) {
            VStack(spacing: 12) {
                let desc = modelManager.descriptor

                // Specs Grid
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                    GridRow {
                        Text("Model:").font(.caption).foregroundStyle(.secondary)
                        Text(desc.displayName).font(.caption).fontWeight(.semibold)
                        Text("Quantization:").font(.caption).foregroundStyle(.secondary)
                        Text(desc.quantization).font(.caption).fontWeight(.semibold)
                    }
                    GridRow {
                        Text("Size:").font(.caption).foregroundStyle(.secondary)
                        Text(desc.formattedExpectedSize).font(.caption)
                        Text("RAM:").font(.caption).foregroundStyle(.secondary)
                        Text(String(format: "~%d MB", desc.estimatedRAMBytes / (1024 * 1024))).font(.caption)
                    }
                    GridRow {
                        Text("Engine:").font(.caption).foregroundStyle(.secondary)
                        Text("llama.cpp (Metal GPU)").font(.caption)
                        Text("License:").font(.caption).foregroundStyle(.secondary)
                        Text(desc.license).font(.caption)
                    }
                }

                Divider()

                // Status Row
                HStack {
                    Text("Model Status")
                        .font(.subheadline)
                    Spacer()
                    Label(modelManager.status.displayName, systemImage: statusIcon(for: modelManager.status))
                        .foregroundStyle(statusColor(for: modelManager.status))
                        .font(.subheadline)
                }

                // Progress indicators
                if case .downloading(let progress, let downloaded, let total) = modelManager.status {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                        HStack {
                            Text(String(format: "%.1f / %.1f MB", Double(downloaded) / (1024 * 1024), Double(total) / (1024 * 1024)))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(progress * 100))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if case .verifying(let progress) = modelManager.status {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                        HStack {
                            Text("Verifying SHA-256 integrity…")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(progress * 100))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Action controls
                HStack(spacing: 10) {
                    if modelManager.status.isReady {
                        Button {
                            Task { await modelManager.verifyIntegrity() }
                        } label: {
                            Label("Verify Integrity", systemImage: "checkmark.seal")
                        }

                        Spacer()

                        Button(role: .destructive) {
                            showDeleteModelConfirmation = true
                        } label: {
                            Label("Delete Model", systemImage: "trash")
                        }
                    } else if case .downloading = modelManager.status {
                        Button("Cancel Download") {
                            modelManager.cancelDownload()
                        }
                    } else if case .verifying = modelManager.status {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Verifying checksum…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Button {
                            Task { try? await modelManager.startDownload() }
                        } label: {
                            let isReDownload: Bool = {
                                switch modelManager.status {
                                case .corrupt, .failed: return true
                                default: return false
                                }
                            }()
                            let actionTitle = isReDownload ? "Re-download" : "Download & Set Up"
                            Label("\(actionTitle) (\(desc.formattedExpectedSize))", systemImage: "arrow.down.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.top, 4)

                if case .verifying = modelManager.status {
                    // Suppress duplicate text during active verification
                } else {
                    Text(modelManager.status.detailedDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Voice Commands Card
            SettingsCard(
                title: "Voice Commands",
                description: "Speak natural language commands and questions directly to AMORA."
            ) {
                VStack(spacing: 14) {
                    SettingsRow(
                        title: "Enable Voice Commands",
                        subtitle: "Adds microphone controls to the Dynamic Island and Dashboard.",
                        icon: "mic.fill"
                    ) {
                        Toggle("", isOn: $settings.voiceCommandsEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    Divider()

                    SettingsRow(
                        title: "Prefer On-Device Recognition",
                        subtitle: "Transcribes speech locally on your Mac when available for maximum privacy.",
                        icon: "lock.shield.fill"
                    ) {
                        Toggle("", isOn: $settings.preferOnDeviceRecognition)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Recognition Mode")
                                .font(.subheadline)
                            Text(VoiceCommandService.shared.engine.recognitionModeDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if case .permissionDenied = VoiceCommandService.shared.state {
                            Button("Open System Settings") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .buttonStyle(.amoraPill)
                        }
                    }
                }
            }

            // Hands-Free Wake Word Card
            SettingsCard(
                title: "Hands-Free Wake Word",
                description: "Activate voice listening hands-free simply by saying \"AMORA\"."
            ) {
                VStack(spacing: 14) {
                    SettingsRow(
                        title: "Enable Wake Word (\"AMORA\")",
                        subtitle: "Listens for the keyword 'AMORA' to activate voice commands automatically.",
                        icon: "waveform.badge.mic"
                    ) {
                        Toggle("", isOn: $settings.wakeWordEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    if settings.wakeWordEnabled {
                        Divider()

                        // Status & Control Row
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Image(systemName: WakeWordService.shared.state.statusIcon)
                                        .foregroundStyle(WakeWordService.shared.state.statusColor)
                                    Text(WakeWordService.shared.state.statusTitle)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                                Text(WakeWordService.shared.state.userFacingDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()

                            if case .standby = WakeWordService.shared.state {
                                Button {
                                    WakeWordService.shared.pause()
                                } label: {
                                    Label("Pause", systemImage: "pause.fill")
                                }
                                .buttonStyle(.amoraPill)
                            } else if case .paused = WakeWordService.shared.state {
                                Button {
                                    WakeWordService.shared.resume()
                                } label: {
                                    Label("Resume", systemImage: "play.fill")
                                }
                                .buttonStyle(.amoraPill)
                            } else if case .unauthorized = WakeWordService.shared.state {
                                Button("System Settings") {
                                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                                .buttonStyle(.amoraPill)
                            }
                        }

                        Divider()

                        // Engine Selection
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Wake Word Engine")
                                .font(.subheadline)
                            Picker("", selection: $settings.wakeWordEngineKind) {
                                ForEach(WakeWordEngineKind.allCases, id: \.rawValue) { kind in
                                    Text(kind.displayName).tag(kind.rawValue)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)

                            if settings.wakeWordEngineKind == WakeWordEngineKind.nativeAcoustic.rawValue {
                                Text("Runs completely on-device using native acoustic processing. Zero network traffic and no third-party accounts required.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Uses Picovoice Porcupine keyword spotting. Requires a free AccessKey and trained .ppn keyword model.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Porcupine Configuration Fields
                        if settings.wakeWordEngineKind == WakeWordEngineKind.porcupine.rawValue {
                            Divider()

                            VStack(alignment: .leading, spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Picovoice AccessKey")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    SecureField("Paste Picovoice AccessKey", text: $settings.porcupineAccessKey)
                                        .textFieldStyle(.roundedBorder)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Custom Keyword Model Path (.ppn)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    TextField("/path/to/Amora_mac.ppn", text: $settings.porcupineKeywordPath)
                                        .textFieldStyle(.roundedBorder)
                                }

                                Button {
                                    if let url = URL(string: "https://console.picovoice.ai/") {
                                        NSWorkspace.shared.open(url)
                                    }
                                } label: {
                                    Label("Get Free AccessKey & Train 'AMORA' Model", systemImage: "arrow.up.right.square")
                                }
                                .buttonStyle(.amoraPill)
                            }
                        }

                        Divider()

                        // Sensitivity
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Detection Sensitivity")
                                    .font(.subheadline)
                                Spacer()
                                Text(String(format: "%.0f%%", settings.wakeWordSensitivity * 100))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $settings.wakeWordSensitivity, in: 0.1...1.0, step: 0.05)
                            Text("Higher sensitivity triggers more easily; lower sensitivity resists ambient background noise.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func statusIcon(for status: AmoraModelStatus) -> String {
        switch status {
        case .ready: return "checkmark.circle.fill"
        case .downloading, .loading, .verifying: return "arrow.down.circle"
        case .notInstalled, .readyToDownload: return "circle"
        case .cancelling, .cancelled: return "xmark.circle"
        case .outOfMemory, .corrupt, .failed: return "exclamationmark.triangle.fill"
        }
    }

    private func statusColor(for status: AmoraModelStatus) -> Color {
        switch status {
        case .ready: return .green
        case .downloading, .loading, .verifying: return palette.accent
        case .notInstalled, .readyToDownload, .cancelling, .cancelled: return .secondary
        case .outOfMemory, .corrupt, .failed: return .red
        }
    }

    // MARK: - Context & Proactive Section

    private var contextAwarenessSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard(
                title: "Context Awareness",
                description: "Permits AMORA to observe system context (frontmost app, active media, timer state, battery health) to deliver contextual assistance."
            ) {
                SettingsRow(
                    title: "Enable Context Awareness",
                    subtitle: "Provides situational awareness when answering questions and executing actions.",
                    icon: "eye"
                ) {
                    Toggle("", isOn: $settings.contextAwarenessEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }

            SettingsCard(
                title: "Proactive Dynamic Island Suggestions",
                description: "Allows AMORA to proactively offer safe, helpful actions right inside the Dynamic Island based on local triggers and strict cooldowns."
            ) {
                VStack(spacing: 12) {
                    SettingsRow(
                        title: "Enable Proactive AMORA",
                        subtitle: "Suggest actions automatically without waiting for a prompt.",
                        icon: "sparkle.magnifyingglass"
                    ) {
                        Toggle("", isOn: $settings.proactiveAmoraEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    if settings.proactiveAmoraEnabled {
                        Divider()

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Allowed Proactive Triggers")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)

                            SettingsRow(title: "Timer Completed", subtitle: "Suggest next focus session or reset", icon: "timer") {
                                Toggle("", isOn: $settings.proactiveTimerCompletedEnabled)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                            }
                            SettingsRow(title: "Timer Nearly Finished", subtitle: "Warn when focus timer reaches final 2 minutes", icon: "hourglass.bottomhalf.filled") {
                                Toggle("", isOn: $settings.proactiveTimerNearlyFinishedEnabled)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                            }
                            SettingsRow(title: "Music Playback Changes", subtitle: "Suggest playback options when track ends", icon: "music.note") {
                                Toggle("", isOn: $settings.proactiveMusicPlaybackEnabled)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                            }
                            SettingsRow(title: "Return After Inactivity", subtitle: "Welcome back and summarize current tasks", icon: "moon.zzz") {
                                Toggle("", isOn: $settings.proactiveInactivityReturnEnabled)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                            }
                            SettingsRow(title: "Critically Low Battery", subtitle: "Recommend low-power habits when battery drops below 20%", icon: "battery.25") {
                                Toggle("", isOn: $settings.proactiveBatteryCriticalEnabled)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                            }
                        }
                    }
                }
            }

            SettingsCard(
                title: "Privacy Guarantee",
                description: "AMORA strictly protects your privacy through local evaluation."
            ) {
                HStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.blue)
                    Text("AMORA never reads screen contents, keystrokes, clipboard text, or documents for proactive suggestions. Evaluation runs entirely on your Mac with conservative cooldowns.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Memory Section

    private var memorySection: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard(
                title: "Personal Memory",
                description: "AMORA can retain personal preferences and facts across restarts (e.g. 'I prefer dark mode' or 'My favorite language is Swift')."
            ) {
                SettingsRow(
                    title: "Enable Memory",
                    subtitle: "Allow storing and retrieving personal facts.",
                    icon: "brain.head.profile"
                ) {
                    Toggle("", isOn: $settings.memoryEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }

            SettingsCard(
                title: "Stored Memories (\(memoryService.memories.count))",
                description: "Review and manage all locally stored memories."
            ) {
                VStack(spacing: 10) {
                    if memoryService.memories.isEmpty {
                        AmoraEmptyStateView(
                            iconName: "brain.head.profile",
                            title: "No Memories Stored",
                            subtitle: "Tell AMORA “Remember that I prefer dark mode” to store a memory."
                        )
                    } else {
                        // Memory search filter
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField("Filter memories…", text: $memoryFilter)
                                .textFieldStyle(.plain)
                            if !memoryFilter.isEmpty {
                                Button {
                                    memoryFilter = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Clear filter")
                            }
                        }
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )

                        let filteredMemories = memoryService.memories.filter {
                            memoryFilter.isEmpty || $0.key.localizedCaseInsensitiveContains(memoryFilter) || $0.value.localizedCaseInsensitiveContains(memoryFilter)
                        }

                        if filteredMemories.isEmpty {
                            Text("No memories match '\(memoryFilter)'.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            VStack(spacing: 6) {
                            ForEach(filteredMemories) { item in
                                if editingMemoryId == item.id {
                                    VStack(alignment: .leading, spacing: 6) {
                                        TextField("Key / Topic", text: $editingKey)
                                            .textFieldStyle(.roundedBorder)
                                        TextField("Value / Content", text: $editingValue)
                                            .textFieldStyle(.roundedBorder)
                                        HStack {
                                            Spacer()
                                            Button("Cancel") {
                                                editingMemoryId = nil
                                            }
                                            .buttonStyle(.plain)
                                            .font(.caption)
                                            Button("Save") {
                                                let id = item.id
                                                let k = editingKey
                                                let v = editingValue
                                                Task {
                                                    _ = try? await memoryService.update(id: id, key: k, value: v)
                                                    editingMemoryId = nil
                                                }
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .font(.caption)
                                            .disabled(editingKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || editingValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                        }
                                    }
                                    .padding(8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color(nsColor: .controlBackgroundColor))
                                    )
                                } else {
                                    HStack(alignment: .center, spacing: 10) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.key)
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundStyle(.primary)
                                            Text(item.value)
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Button {
                                            editingMemoryId = item.id
                                            editingKey = item.key
                                            editingValue = item.value
                                        } label: {
                                            Image(systemName: "pencil")
                                                .font(.system(size: 12))
                                                .foregroundStyle(.secondary)
                                                .frame(width: 24, height: 24)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.borderless)
                                        .help("Edit this memory")
                                        .accessibilityLabel("Edit memory \(item.key)")

                                        Button(role: .destructive) {
                                            Task { await memoryService.delete(id: item.id) }
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.system(size: 12))
                                                .foregroundStyle(.red)
                                                .frame(width: 24, height: 24)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.borderless)
                                        .help("Delete this memory")
                                        .accessibilityLabel("Delete memory \(item.key)")
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                                    )
                                }
                            }
                        }
                    }

                        HStack {
                            Spacer()
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
    }

    // MARK: - Modules Section

    private var modulesSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard(
                title: "Built-In Modules",
                description: "Enable or disable AMORA's integrated tools and widgets."
            ) {
                VStack(spacing: 12) {
                    SettingsRow(title: "Battery Monitor", subtitle: "Battery state, time remaining, and charger indicators", icon: "battery.100") {
                        Toggle("", isOn: $settings.batteryEnabled).labelsHidden().toggleStyle(.switch)
                    }
                    Divider()
                    SettingsRow(title: "Focus Timer", subtitle: "Pomodoro sessions, focus timers, and break countdowns", icon: "timer") {
                        Toggle("", isOn: $settings.timerEnabled).labelsHidden().toggleStyle(.switch)
                    }
                    Divider()
                    SettingsRow(title: "Music Controller", subtitle: "Spotify desktop, Apple Music, and YouTube playback", icon: "music.note") {
                        Toggle("", isOn: $settings.musicEnabled).labelsHidden().toggleStyle(.switch)
                    }
                    Divider()
                    SettingsRow(title: "Clipboard History", subtitle: "Quick access to copied text snippets and history", icon: "doc.on.clipboard") {
                        Toggle("", isOn: $settings.clipboardEnabled).labelsHidden().toggleStyle(.switch)
                    }
                    Divider()
                    SettingsRow(title: "Quick Notes", subtitle: "Lightweight scratchpad for instant thoughts and reminders", icon: "note.text") {
                        Toggle("", isOn: $settings.notesEnabled).labelsHidden().toggleStyle(.switch)
                    }
                    Divider()
                    SettingsRow(title: "System Monitor", subtitle: "CPU load, memory consumption, and disk status", icon: "cpu") {
                        Toggle("", isOn: $settings.systemMonitorEnabled).labelsHidden().toggleStyle(.switch)
                    }
                }
            }

            SettingsCard(
                title: "Desktop Music Players",
                description: "Integrations with native macOS audio applications."
            ) {
                VStack(spacing: 10) {
                    SettingsRow(title: "Active Provider", icon: "music.note.list") {
                        Text(music.source.displayName).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Divider()
                    SettingsRow(title: "Spotify Desktop", icon: "play.circle") {
                        Text(spotifyStatusDescription).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if !SpotifyProvider.shared.isInstalled {
                        Text("Spotify is not installed on this Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if SpotifyProvider.shared.hasPermissionDenied {
                        HStack {
                            Text("Automation permission required to control Spotify.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Spacer()
                            Button("Open Automation Settings") {
                                SpotifyProvider.openAutomationSettings()
                            }
                            .font(.caption)
                        }
                    }
                    Divider()
                    SettingsRow(title: "Apple Music", icon: "apple.logo") {
                        Text(appleMusicStatusDescription).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if music.isAvailable {
                        Divider()
                        SettingsRow(title: "Current Track", icon: "waveform") {
                            Text("\(music.trackTitle) — \(music.artist)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            SettingsCard(
                title: "Browser Media (Chrome Extension)",
                description: "Track and control video playback from open Chrome tabs."
            ) {
                VStack(spacing: 10) {
                    SettingsRow(title: "Chrome Extension Bridge", icon: "network") {
                        Text(chromeBridge.status.rawValue).font(.subheadline).foregroundStyle(chromeBridge.status == .connected ? .green : .secondary)
                    }
                    Divider()
                    SettingsRow(title: "YouTube Video Player", icon: "play.rectangle") {
                        Text(youtubeStatus).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let media = chromeBridge.state {
                        Divider()
                        SettingsRow(title: "Tracked Video", icon: "film") {
                            Text(media.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }

                    Text("AMORA tracks minimal YouTube player metadata for open Chrome video tabs. No browsing history or page content is ever stored.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    DisclosureGroup("Diagnostics & Diagnostic Pings") {
                        VStack(spacing: 8) {
                            diagnosticRow("Native Messaging Host", connected: chromeBridge.status == .connected)
                            diagnosticRow("Chrome Service Worker", connected: chromeBridge.status == .connected)
                            diagnosticRow("YouTube Content Script", connected: chromeBridge.contentDiagnostic?.success == true)
                            diagnosticRow("Video Element Detected", connected: chromeBridge.contentDiagnostic?.hasVideo == true)

                            HStack {
                                Text("Tracked Tabs: \(chromeBridge.state?.trackedMediaTabCount ?? 0)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button(chromeBridge.contentPingPending ? "Pinging…" : "Run Content Script Ping") {
                                    chromeBridge.runContentPing()
                                }
                                .font(.caption)
                                .disabled(chromeBridge.contentPingPending || chromeBridge.status != .connected)
                            }

                            if let reason = chromeBridge.contentDiagnostic?.reason {
                                Text(Self.diagnosticReason(reason))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 6)
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

    private func diagnosticRow(_ title: String, connected: Bool) -> some View {
        HStack {
            Text(title).font(.caption).foregroundStyle(.primary)
            Spacer()
            Label(connected ? "Connected" : "Unavailable", systemImage: connected ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.caption)
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

    // MARK: - Automations Section

    private var automationsSection: some View {
        AmoraAutomationSettingsView()
    }

    // MARK: - About Section

    private var aboutSection: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(palette.accent.opacity(0.18))
                        .frame(width: 80, height: 80)
                    Image(systemName: "circle.hexagongrid.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(palette.accent)
                }

                Text("AMORA")
                    .font(.system(size: 26, weight: .bold, design: .rounded))

                Text("Your Little Mac Companion")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)

                Text("Living seamlessly right around your MacBook notch.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)

                Text(AppVersion.fullDisplay)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(Color(nsColor: .controlBackgroundColor))
                    )
            }
            .padding(.top, 10)

            SettingsCard(
                title: "System & Architecture Overview"
            ) {
                VStack(spacing: 8) {
                    HStack {
                        Text("Active Theme")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(settings.theme.rawValue)
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    Divider()
                    HStack {
                        Text("AI Provider")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(settings.aiProvider)
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    Divider()
                    HStack {
                        Text("Local Brain Runtime")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(modelManager.status.displayName)
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    Divider()
                    HStack {
                        Text("Stored Memories")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(memoryService.memories.count)")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    Divider()
                    HStack {
                        Text("Active Automations")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(AmoraAutomationService.shared.automations.count)")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                }
            }

            Text("AMORA is designed with local-first privacy. No user keystrokes, personal files, or private browsing history are stored or uploaded.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }
}
