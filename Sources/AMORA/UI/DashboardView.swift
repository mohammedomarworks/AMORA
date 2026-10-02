import SwiftUI
import Observation

@Observable @MainActor
final class DashboardViewModel {
    var commandInput: String = ""
    var assistantFeedback: String? = nil
    var selectedSection: DashboardView.DashboardSection = .overview
    var suggestions: [String] = []
}

struct DashboardView: View {
    @Bindable var vm = DashboardViewModel()
    private var robot = AMORARobot.shared
    private var battery = BatteryService.shared
    private var timer = TimerService.shared
    private var music = MusicService.shared
    private var systemMonitor = SystemMonitorService.shared
    private var clipboard = ClipboardService.shared
    private var notes = NotesService.shared
    private var fileShelf = FileShelfService.shared
    private var commandRouter = AMORACommandRouter.shared
    private var commandHistory = AMORACommandHistory.shared
    private let parser = AMORACommandParser()

    init(initialSection: DashboardSection = .overview) {
        let model = DashboardViewModel()
        model.selectedSection = initialSection
        _vm = Bindable(wrappedValue: model)
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

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack(spacing: 14) {
                AMORARobotView(robot: robot, compact: false)
                    .frame(width: 48, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("AMORA")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text("ONLINE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.cyan)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.cyan.opacity(0.15)))
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
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(8)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help("Settings")

                Button {
                    WindowManager.shared.closeDashboard()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(8)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)

            // Primary Stat Cards 2x2 Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                // Music Card
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "music.note")
                            .foregroundStyle(.pink)
                        Spacer()
                        Button {
                            music.togglePlayPause()
                        } label: {
                            Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                    Text(music.trackTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(.white)
                    Text(music.artist.isEmpty ? "Music" : music.artist)
                        .font(.system(size: 10))
                        .lineLimit(1)
                        .foregroundStyle(.white.opacity(0.6))
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
                    Text(battery.timeRemainingFormatted)
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

                // System Load Card
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "cpu")
                            .foregroundStyle(.purple)
                        Spacer()
                        Text(String(format: "%.0f%% CPU", systemMonitor.cpuUsagePercent))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    Text(String(format: "%.1f GB of %.1f GB RAM", systemMonitor.memoryUsedGB, systemMonitor.memoryTotalGB))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(String(format: "%.0f GB Free Disk", systemMonitor.diskFreeGB))
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
            }
            .padding(.horizontal, 18)

            // Section Switcher
            Picker("", selection: $vm.selectedSection) {
                ForEach(DashboardSection.allCases, id: \.self) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 18)

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
            .padding(.horizontal, 18)
            .frame(maxHeight: 180)

            Spacer(minLength: 4)

            // Bottom Command Bar / Assistant Input
            VStack(spacing: 6) {
                if let feedback = vm.assistantFeedback {
                    Text(feedback)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.cyan)
                        .transition(.opacity)
                }

                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.cyan)
                        .font(.system(size: 13))

                    TextField("Try ‘start a 25 minute timer’…", text: $vm.commandInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
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
                        setFeedback("Battery is at \(battery.level)% (\(battery.timeRemainingFormatted))")
                    }
                    quickPromptChip("Toggle Music") {
                        music.togglePlayPause()
                        setFeedback("Toggled playback")
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
        .frame(width: 480, height: 600)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 0.07, green: 0.09, blue: 0.13).opacity(0.96))
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
        let command = parser.parse(trimmed, context: commandRouter.currentContext())
        let result = commandRouter.execute(command)
        switch result {
        case let .success(message), let .failure(message), let .needsInformation(message), let .needsConfirmation(message), let .unsupported(message):
            setFeedback(message)
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
            Text("Upcoming & Status")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Today")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(Date().formatted(date: .complete, time: .omitted))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Image(systemName: "calendar")
                    .font(.system(size: 20))
                    .foregroundStyle(.cyan.opacity(0.8))
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
        }
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
                Text("No items copied yet.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
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
                Text("No notes saved yet.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
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
            Text("File Shelf")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))

            VStack(spacing: 6) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.4))
                Text("Drag files here to pin for quick access")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 8).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4])).fill(Color.white.opacity(0.15)))
        }
    }
}
