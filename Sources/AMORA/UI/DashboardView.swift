import SwiftUI
import Observation

@Observable @MainActor
final class DashboardViewModel {
    var commandInput: String = ""
    var assistantFeedback: String? = nil
    var selectedSection: DashboardView.DashboardSection = .overview
    var suggestions: [String] = []
}

@MainActor
struct DashboardView: View {
    var embedded: Bool = false
    var topInset: CGFloat = 0
    @Bindable var vm: DashboardViewModel
    @FocusState private var isInputFocused: Bool
    @State private var isDashboardFileShelfDropTargeted = false
    private var robot: AMORARobot { AMORARobot.shared }
    private var battery: BatteryService { BatteryService.shared }
    private var timer: TimerService { TimerService.shared }
    private var music: MusicService { MusicService.shared }
    private var systemMonitor: SystemMonitorService { SystemMonitorService.shared }
    private var clipboard: ClipboardService { ClipboardService.shared }
    private var notes: NotesService { NotesService.shared }
    private var fileShelf: FileShelfService { FileShelfService.shared }
    private var commandRouter: AMORACommandRouter { AMORACommandRouter.shared }
    private var commandHistory: AMORACommandHistory { AMORACommandHistory.shared }
    private var assistant: AssistantManager { AssistantManager.shared }
    private var coordinator: AmoraActionExecutionCoordinator { AmoraActionExecutionCoordinator.shared }
    private var gateway: AMORACommandGateway { AMORACommandGateway() }
    private var parser: AMORACommandParser { AMORACommandParser() }
    private var settings: SettingsStore { AppState.shared.settings }
    private var palette: ThemePalette { settings.palette }

    init(initialSection: DashboardSection = .overview, embedded: Bool = false, topInset: CGFloat = 0) {
        let model = DashboardViewModel()
        model.selectedSection = initialSection
        _vm = Bindable(wrappedValue: model)
        self.embedded = embedded
        self.topInset = topInset
    }

    init(viewModel: DashboardViewModel, embedded: Bool = true, topInset: CGFloat = 0) {
        _vm = Bindable(wrappedValue: viewModel)
        self.embedded = embedded
        self.topInset = topInset
    }

    enum DashboardSection: String, CaseIterable {
        case overview = "Overview"
        case clipboard = "Clipboard"
        case notes = "Notes"
        case fileShelf = "File Shelf"
    }

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning!" }
        if hour < 18 { return "Good afternoon!" }
        return "Good evening!"
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(palette.accent.opacity(0.08), lineWidth: 0.5)
            )
    }

    var body: some View {
        let content = VStack(spacing: 14) {
            // Header
            HStack(spacing: 14) {
                AMORARobotView(robot: robot, compact: false)
                    .frame(width: 44, height: 40)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("AMORA")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text("ONLINE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(palette.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(palette.accent.opacity(0.15)))
                    }

                    Text(greeting)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }

                Spacer()

                Button {
                    WindowManager.shared.showSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .buttonStyle(.amoraHeaderCircle)
                .help("Settings")
                .accessibilityLabel("Settings")

                Button {
                    WindowManager.shared.contractToQuickIsland()
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .buttonStyle(.amoraHeaderCircle)
                .help("Collapse to Quick Island")
                .accessibilityLabel("Collapse to quick island")

                Button {
                    WindowManager.shared.closeDashboard()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .buttonStyle(.amoraHeaderCircle)
                .help("Close")
                .accessibilityLabel("Close workspace")
            }
            .padding(.horizontal, embedded ? 20 : 18)
            .padding(.top, embedded ? (topInset + 10) : 18)

            // Primary Stat Cards
            LazyVGrid(columns: embedded ? [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ] : [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 10) {
                // Music Card
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: music.source == .spotify ? "waveform" : (music.source == .youtube ? "play.rectangle.fill" : "music.note"))
                            .foregroundStyle(music.source == .spotify ? Color.green : (music.source == .youtube ? Color.red : Color.pink))
                        if music.source == .spotify {
                            Text("SPOTIFY")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.green.opacity(0.15)))
                        } else if music.source == .youtube {
                            Text("YOUTUBE")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.red.opacity(0.15)))
                        }
                        Spacer()
                        HStack(spacing: 8) {
                            Button {
                                music.previousTrack()
                            } label: {
                                Image(systemName: "backward.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Previous track")
                            .help("Previous track")
                            .disabled(!music.capabilities.supportsPrevious || music.controlPending || !music.isAvailable)
                            .opacity((!music.capabilities.supportsPrevious || music.controlPending || !music.isAvailable) ? 0.35 : 1.0)

                            Button {
                                music.togglePlayPause()
                            } label: {
                                Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(music.isPlaying ? "Pause" : "Play")
                            .help(music.isPlaying ? "Pause" : "Play")
                            .disabled(!music.capabilities.supportsPlay || music.controlPending || (!music.isAvailable && music.source == .none))
                            .opacity((!music.capabilities.supportsPlay || music.controlPending || (!music.isAvailable && music.source == .none)) ? 0.35 : 1.0)

                            Button {
                                music.nextTrack()
                            } label: {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Next track")
                            .help("Next track")
                            .disabled(!music.capabilities.supportsNext || music.controlPending || !music.isAvailable)
                            .opacity((!music.capabilities.supportsNext || music.controlPending || !music.isAvailable) ? 0.35 : 1.0)
                        }
                    }
                    Text(music.trackTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(.white)
                    Text(music.artist.isEmpty ? (music.source == .spotify ? "Spotify" : "Music") : music.artist)
                        .font(.system(size: 10))
                        .lineLimit(1)
                        .foregroundStyle(.white.opacity(0.6))
                    if let status = music.controlStatus ?? music.controlError {
                        Text(status)
                            .font(.system(size: 9))
                            .foregroundStyle(music.controlError == nil ? Color.secondary : Color.orange)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))

                // Battery Card
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: battery.isCharging ? "battery.100.bolt" : "battery.100")
                            .foregroundStyle(battery.level > 20 ? .green : .red)
                        Spacer()
                        Text("\(battery.level)%")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    Text(battery.timeRemainingDescription.replacingOccurrences(of: "\n", with: " "))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(battery.isPluggedIn ? "Power connected" : "On Battery")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))

                // Timer Card
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "timer")
                            .foregroundStyle(.cyan)
                        Spacer()
                        Text(timer.isRunning ? timer.formattedTime : "Off")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    if timer.isRunning {
                        HStack(spacing: 8) {
                            Button(timer.isPaused ? "Resume" : "Pause") {
                                timer.isPaused ? timer.resumeTimer() : timer.pauseTimer()
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.cyan)

                            Button("Stop") {
                                timer.stopTimer()
                            }
                            .font(.system(size: 10))
                            .foregroundStyle(.red.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    } else {
                        HStack(spacing: 6) {
                            Button("5m") { timer.startTimer(minutes: 5) }
                            Button("25m") { timer.startTimer(minutes: 25) }
                            Button("45m") { timer.startTimer(minutes: 45) }
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.cyan)
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))

                // System metrics card
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "cpu")
                            .foregroundStyle(.purple)
                        Spacer()
                        Text(String(format: "%.0f%% CPU", systemMonitor.cpuUsagePercent))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    Text(String(format: "%.1f GB of %.1f GB Memory", systemMonitor.memoryUsedGB, systemMonitor.memoryTotalGB))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(String(format: "%.0f GB Free Disk", systemMonitor.diskFreeGB))
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
            }
            .padding(.horizontal, embedded ? 20 : 18)

            // Section Switcher
            Picker("", selection: $vm.selectedSection) {
                ForEach(DashboardSection.allCases, id: \.self) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, embedded ? 20 : 18)

            // Section Detail View
            VStack {
                switch vm.selectedSection {
                case .overview:
                    overviewSection
                case .clipboard:
                    clipboardSection
                case .notes:
                    notesSection
                case .fileShelf:
                    fileShelfSection
                }
            }
            .padding(.horizontal, embedded ? 20 : 18)
            .frame(minHeight: embedded ? 180 : nil, maxHeight: embedded ? 220 : 180)

            Spacer(minLength: 4)

            // Bottom Command Bar / Assistant Input
            VStack(spacing: 6) {
                if coordinator.state != .idle {
                    ActionExecutionView(compact: true)
                } else if let feedback = vm.assistantFeedback {
                    Text(feedback)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.cyan)
                        .transition(.opacity)
                }

                if coordinator.state == .idle && assistant.state == .thinking {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small).tint(.cyan)
                        Text("Thinking…").font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.65))
                        Spacer()
                        Button("Stop") { assistant.cancel() }
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.cyan)
                            .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.cyan)
                        .font(.system(size: 13))

                    TextField("Try ‘start a 25 minute timer’…", text: $vm.commandInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($isInputFocused)
                        .onChange(of: vm.commandInput) { _, value in
                            vm.suggestions = suggestions(for: value)
                        }
                        .onSubmit {
                            handleCommand(vm.commandInput)
                        }

                    if !vm.commandInput.isEmpty {
                        Button {
                            handleCommand(vm.commandInput)
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.cyan)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
                .contentShape(Rectangle())
                .onTapGesture {
                    isInputFocused = true
                }

                if !vm.suggestions.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(vm.suggestions.prefix(3), id: \.self) { suggestion in
                            Button(suggestion) { handleCommand(suggestion) }
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.75))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.white.opacity(0.06)))
                                .buttonStyle(.plain)
                        }
                    }
                }

                if !commandHistory.items.isEmpty && vm.commandInput.isEmpty {
                    HStack(spacing: 6) {
                        Text("Recent")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.4))
                        ForEach(commandHistory.items.prefix(2), id: \.self) { item in
                            Button(item) { handleCommand(item) }
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(1)
                                .buttonStyle(.plain)
                        }
                        Spacer()
                        Button("Clear") { commandHistory.clear() }
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.4))
                            .buttonStyle(.plain)
                    }
                }

                // Quick Prompt Chips
                HStack(spacing: 6) {
                    quickPromptChip("Start 25m Focus") {
                        timer.startTimer(minutes: 25)
                        setFeedback("Started 25m Focus Timer!")
                    }
                    quickPromptChip("Battery Status") {
                        setFeedback("Battery is at \(battery.level)% (\(battery.timeRemainingDescription.replacingOccurrences(of: "\n", with: " ")))")
                    }
                    quickPromptChip("Toggle Music") {
                        music.togglePlayPause()
                        setFeedback("Toggled playback")
                    }
                }
            }
            .padding(.horizontal, embedded ? 20 : 18)
            .padding(.bottom, 16)
        }

        if embedded {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .onAppear {
                    fileShelf.refreshItemStates()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        isInputFocused = true
                    }
                }
        } else {
            content
                .frame(width: 480, height: 600)
                .background {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(red: 0.07, green: 0.09, blue: 0.13).opacity(AppState.shared.settings.transparency))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.2), Color.white.opacity(0.05)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: .black.opacity(0.6), radius: 24, x: 0, y: 12)
                }
                .onAppear {
                    fileShelf.refreshItemStates()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        isInputFocused = true
                    }
                }
        }
    }

    private func quickPromptChip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    private func setFeedback(_ msg: String) {
        withAnimation {
            vm.assistantFeedback = msg
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation {
                if vm.assistantFeedback == msg {
                    vm.assistantFeedback = nil
                }
            }
        }
    }

    private func handleCommand(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        vm.commandInput = ""
        guard !trimmed.isEmpty else { return }
        commandHistory.add(trimmed)
        Task { @MainActor in
            let result = await gateway.submit(trimmed, settings: AppState.shared.settings.aiSettingsSnapshot)
            switch result {
            case let .success(message), let .failure(message), let .needsInformation(message), let .needsConfirmation(message), let .unsupported(message):
                setFeedback(message)
            }
        }
    }

    private func suggestions(for input: String) -> [String] {
        let prefix = AMORACommandParser.normalize(input)
        if prefix.isEmpty {
            if timer.isRunning { return timer.isPaused ? ["Resume timer", "Add 5 minutes", "Stop timer"] : ["Pause timer", "Add 5 minutes", "Stop timer"] }
            if music.isPlaying { return ["Pause music", "Next track"] }
            return ["Start a timer", "Play music", "Check battery", "Add a note", "Open Downloads"]
        }
        let all = ["Start a timer", "Battery status", "Open Dashboard", "Open Downloads", "Open Settings", "Play music", "Show clipboard", "Show notes"]
        return all.filter { AMORACommandParser.normalize($0).hasPrefix(prefix) }
    }

    // MARK: - Sections
    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WORKSPACE")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("FOCUS")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(timer.isRunning ? (timer.isPaused ? "Paused \(timer.formattedTime)" : timer.formattedTime) : "Nothing queued")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Image(systemName: timer.isRunning ? "timer" : "checkmark.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(.cyan.opacity(0.8))
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))

            HStack(spacing: 8) {
                workspaceValue(title: "RECENT NOTE", value: notes.notes.first?.text ?? "No notes yet", icon: "note.text")
                workspaceValue(title: "RECENT FILES", value: fileShelf.items.first?.name ?? "No files pinned", icon: "doc")
            }
        }
    }

    private func workspaceValue(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: icon)
                .foregroundStyle(.cyan.opacity(0.8))
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.55))
            Text(value)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
    }

    private var clipboardSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Clipboard History")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                if !clipboard.history.isEmpty {
                    Button("Clear All") { clipboard.clearHistory() }
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                        .buttonStyle(.plain)
                }
            }

            if clipboard.history.isEmpty {
                AmoraEmptyStateView(
                    iconName: "doc.on.clipboard",
                    title: "No Copied Items",
                    subtitle: "Copied snippets will appear here automatically."
                )
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(clipboard.history) { item in
                            HStack {
                                Text(item.preview)
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                                    .foregroundStyle(.white.opacity(0.9))
                                Spacer()
                                Button {
                                    clipboard.copyToClipboard(item)
                                    setFeedback("Copied to clipboard!")
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.cyan)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.04)))
                        }
                    }
                }
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quick Notes")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))

            if notes.notes.isEmpty {
                AmoraEmptyStateView(
                    iconName: "note.text",
                    title: "No Notes Yet",
                    subtitle: "Ask AMORA to save a note anytime."
                )
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(notes.notes) { note in
                            HStack {
                                Text(note.text)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.9))
                                Spacer()
                                Button {
                                    notes.deleteNote(id: note.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.red.opacity(0.7))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.04)))
                        }
                    }
                }
            }
        }
    }

    private var fileShelfSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Pinned Files")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                if !fileShelf.items.isEmpty {
                    Text("(\(fileShelf.items.count))")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.cyan.opacity(0.85))
                }
                Spacer()
                if !fileShelf.items.isEmpty {
                    Button("Clear All") {
                        fileShelf.clearShelf()
                        setFeedback("Cleared all pinned files")
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear all pinned files")
                }
            }

            if fileShelf.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: isDashboardFileShelfDropTargeted ? "arrow.down.doc.fill" : "tray.and.arrow.down")
                        .font(.system(size: 22))
                        .foregroundStyle(isDashboardFileShelfDropTargeted ? .cyan : .white.opacity(0.35))
                        .scaleEffect(isDashboardFileShelfDropTargeted ? 1.15 : 1.0)
                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDashboardFileShelfDropTargeted)

                    Text(isDashboardFileShelfDropTargeted ? "Drop files to pin" : "Drop files here to keep them handy")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isDashboardFileShelfDropTargeted ? .cyan : .white.opacity(0.6))

                    Text("Drag any file from Finder to pin for quick access")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            isDashboardFileShelfDropTargeted ? Color.cyan : Color.white.opacity(0.12),
                            style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                        )
                )
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(fileShelf.items) { item in
                            HStack(spacing: 8) {
                                Image(systemName: item.isMissing ? "exclamationmark.triangle.fill" : "doc.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(item.isMissing ? Color.orange : Color.cyan)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.name)
                                        .font(.system(size: 11, weight: .medium))
                                        .lineLimit(1)
                                        .foregroundStyle(item.isMissing ? .white.opacity(0.55) : .white.opacity(0.9))

                                    if item.isMissing {
                                        Text("Missing file")
                                            .font(.system(size: 9))
                                            .foregroundStyle(Color.orange.opacity(0.85))
                                    }
                                }

                                Spacer()

                                Button {
                                    if !fileShelf.openFile(item) {
                                        setFeedback("Could not open: \(item.name)")
                                    }
                                } label: {
                                    Image(systemName: "arrow.up.forward.app")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.cyan)
                                }
                                .buttonStyle(.plain)
                                .help("Open file")
                                .accessibilityLabel("Open \(item.name)")
                                .disabled(item.isMissing)

                                Button {
                                    if !fileShelf.revealFile(item) {
                                        setFeedback("Could not reveal: \(item.name)")
                                    }
                                } label: {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                                .buttonStyle(.plain)
                                .help("Reveal in Finder")
                                .accessibilityLabel("Reveal \(item.name) in Finder")
                                .disabled(item.isMissing)

                                Button {
                                    fileShelf.removeItem(id: item.id)
                                    setFeedback("Removed \(item.name)")
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.red.opacity(0.7))
                                }
                                .buttonStyle(.plain)
                                .help("Remove from shelf")
                                .accessibilityLabel("Remove \(item.name)")
                            }
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.04)))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if !fileShelf.openFile(item) {
                                    setFeedback("Could not open: \(item.name)")
                                }
                            }
                        }
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isDashboardFileShelfDropTargeted ? Color.cyan : Color.clear, lineWidth: 1.5)
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL, .item], isTargeted: $isDashboardFileShelfDropTargeted) { providers in
            let accepted = fileShelf.handleDrop(providers: providers) { url in
                setFeedback("File added to shelf: \(url.lastPathComponent)")
            }
            return accepted
        }
    }
}
