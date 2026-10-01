import SwiftUI
import Observation

@Observable @MainActor
final class QuickPanelViewModel {
    var newNoteText: String = ""
    var selectedTab: QuickPanelView.QuickTab = .controls
}

struct QuickPanelView: View {
    @Bindable var vm = QuickPanelViewModel()
    private var robot = AMORARobot.shared
    private var battery = BatteryService.shared
    private var timer = TimerService.shared
    private var music = MusicService.shared
    private var clipboard = ClipboardService.shared
    private var notes = NotesService.shared

    enum QuickTab: String, CaseIterable {
        case controls = "Controls"
        case clipboard = "Clipboard"
        case notes = "Notes"
    }

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack(spacing: 10) {
                AMORARobotView(robot: robot, compact: true)
                    .frame(width: 32, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text("AMORA")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("What are we doing?")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                }

                Spacer()

                Button {
                    WindowManager.shared.showDashboard()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(6)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .help("Open Full Dashboard")

                Button {
                    WindowManager.shared.toggleQuickPanel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(6)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)

            // Segmented Picker
            Picker("", selection: $vm.selectedTab) {
                ForEach(QuickTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14)

            // Content Area based on tab
            Group {
                switch vm.selectedTab {
                case .controls:
                    controlsView
                case .clipboard:
                    clipboardView
                case .notes:
                    notesView
                }
            }
            .padding(.horizontal, 14)

            Spacer(minLength: 4)

            // Footer
            HStack {
                Text(battery.timeRemainingFormatted)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))

                Spacer()

                Button {
                    WindowManager.shared.showDashboard()
                } label: {
                    Text("Open Dashboard →")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.cyan)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(width: 320, height: 420)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(red: 0.08, green: 0.10, blue: 0.14).opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.2), Color.white.opacity(0.04)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(0.5), radius: 16, x: 0, y: 8)
        }
    }

    // MARK: - Controls View
    private var controlsView: some View {
        VStack(spacing: 10) {
            // Music Card
            HStack(spacing: 10) {
                Image(systemName: "music.note")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.pink)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.pink.opacity(0.15)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(music.trackTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(.white)
                    if !music.artist.isEmpty {
                        Text(music.artist)
                            .font(.system(size: 10))
                            .lineLimit(1)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                Spacer()

                HStack(spacing: 6) {
                    Button {
                        music.previousTrack()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)

                    Button {
                        music.togglePlayPause()
                    } label: {
                        Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)

                    Button {
                        music.nextTrack()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.white.opacity(0.85))
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))

            // Battery & Timer in grid
            HStack(spacing: 10) {
                // Battery Card
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: battery.isCharging ? "battery.100.bolt" : "battery.100")
                            .foregroundStyle(battery.level > 20 ? Color.green : Color.red)
                        Spacer()
                        Text("\(battery.level)%")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    Text(battery.isPluggedIn ? "Power Connected" : "Battery")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))

                // Timer Card
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "timer")
                            .foregroundStyle(Color.cyan)
                        Spacer()
                        Text(timer.isRunning ? timer.formattedTime : "Timer")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }

                    if timer.isRunning {
                        HStack(spacing: 8) {
                            Button(timer.isPaused ? "Resume" : "Pause") {
                                if timer.isPaused {
                                    timer.resumeTimer()
                                } else {
                                    timer.pauseTimer()
                                }
                            }
                            .font(.system(size: 10, weight: .semibold))
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
                            Button("15m") { timer.startTimer(minutes: 15) }
                            Button("25m") { timer.startTimer(minutes: 25) }
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
            }

            // System Quick Status Card
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("System Load")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(String(format: "CPU: %.0f%% • RAM: %.1f GB", SystemMonitorService.shared.cpuUsagePercent, SystemMonitorService.shared.memoryUsedGB))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Circle()
                    .fill(SystemMonitorService.shared.cpuUsagePercent > 80 ? Color.red : Color.green)
                    .frame(width: 8, height: 8)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
        }
    }

    // MARK: - Clipboard View
    private var clipboardView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent Snippets")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                if !clipboard.history.isEmpty {
                    Button("Clear") {
                        clipboard.clearHistory()
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                    .buttonStyle(.plain)
                }
            }

            if clipboard.history.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("Clipboard is empty")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(clipboard.history.prefix(5)) { item in
                            HStack {
                                Text(item.preview)
                                    .font(.system(size: 11))
                                    .lineLimit(2)
                                    .foregroundStyle(.white.opacity(0.9))

                                Spacer()

                                Button {
                                    clipboard.copyToClipboard(item)
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.cyan)
                                }
                                .buttonStyle(.plain)
                                .help("Copy back to clipboard")
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
                        }
                    }
                }
                .frame(height: 180)
            }
        }
    }

    // MARK: - Notes View
    private var notesView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Add a quick note…", text: $vm.newNoteText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                    .onSubmit {
                        if !vm.newNoteText.isEmpty {
                            notes.addNote(vm.newNoteText)
                            vm.newNoteText = ""
                        }
                    }

                Button {
                    if !vm.newNoteText.isEmpty {
                        notes.addNote(vm.newNoteText)
                        vm.newNoteText = ""
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.cyan.opacity(0.8)))
                }
                .buttonStyle(.plain)
            }

            if notes.notes.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "note.text")
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("No notes yet")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(notes.notes.prefix(5)) { note in
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
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
                        }
                    }
                }
                .frame(height: 160)
            }
        }
    }
}
