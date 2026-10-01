import SwiftUI
import Observation

@Observable @MainActor
final class QuickPanelViewModel {
    var newNoteText: String = ""
    var selectedTab: QuickPanelView.QuickTab = .controls
}

struct QuickPanelView: View {
    /// When embedded inside the Dynamic Island, drop the standalone panel's fixed
    /// frame + background (the island supplies the black surface) and inset the
    /// content below the physical notch.
    var embedded: Bool = false
    var topInset: CGFloat = 0
    @Bindable var vm = QuickPanelViewModel()
    @State private var celebrationActive = false
    private var robot = AMORARobot.shared
    private var battery = BatteryService.shared
    private var timer = TimerService.shared
    private var music = MusicService.shared
    private var clipboard = ClipboardService.shared
    private var notes = NotesService.shared
    private var personality = PersonalityEngine.shared
    private var settings = AppState.shared.settings
    private var palette: ThemePalette { settings.palette }

    enum QuickTab: String, CaseIterable {
        case controls = "Controls"
        case clipboard = "Clipboard"
        case notes = "Notes"
    }

    var body: some View {
        if embedded {
            content
                .padding(.top, topInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            content
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
    }

    private var content: some View {
        VStack(spacing: 12) {
            // Header
            HStack(spacing: 10) {
                AMORARobotView(robot: robot, compact: true)
                    .frame(width: 32, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text("AMORA")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(personality.message ?? "What are we doing?")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(personality.message == nil ? .white.opacity(0.65) : palette.accent.opacity(0.95))
                        .lineLimit(1)
                        .animation(.easeInOut(duration: 0.25), value: personality.message)
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
                .accessibilityLabel("Open full dashboard")

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
                .accessibilityLabel("Close panel")
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
                        .foregroundStyle(palette.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .overlay(celebrationOverlay)
        .onChange(of: personality.celebrationToken) { _, _ in
            triggerCelebration()
        }
    }

    // A single themed surface for every module card, so a theme switch recolors
    // them all in one place instead of scattered white-opacity literals.
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(palette.accent.opacity(0.08), lineWidth: 0.5)
            )
    }

    // A brief, non-blocking sparkle burst when PersonalityEngine fires a
    // celebration (e.g. a finished focus session). Honors Reduce Motion by
    // showing a static acknowledgment instead of the outward burst.
    @ViewBuilder private var celebrationOverlay: some View {
        if celebrationActive {
            CelebrationBurst(tint: palette.accent, animated: !MotionConfig.reduceMotion)
                .allowsHitTesting(false)
        }
    }

    private func triggerCelebration() {
        celebrationActive = true
        let linger = MotionConfig.reduceMotion ? 0.8 : 1.4
        DispatchQueue.main.asyncAfter(deadline: .now() + linger) {
            celebrationActive = false
        }
    }

    // MARK: - Controls View
    private var controlsView: some View {
        VStack(spacing: 10) {
            // Music Card
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "music.note")
                        .font(.system(size: 16))
                        .foregroundStyle(palette.accent)
                        .frame(width: 36, height: 36)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(palette.accent.opacity(0.15)))
                        .opacity(music.isPlaying ? 0.7 + robot.antennaPhase * 0.3 : 1)

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

                    HStack(spacing: 10) {
                        Button {
                            music.previousTrack()
                        } label: {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Previous track")

                        Button {
                            music.togglePlayPause()
                        } label: {
                            Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 13))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(music.isPlaying ? "Pause" : "Play")

                        Button {
                            music.nextTrack()
                        } label: {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Next track")
                    }
                    .foregroundStyle(.white.opacity(0.9))
                }

                // Live progress — only when a track is loaded with a known length.
                if music.isAvailable && music.duration > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.12))
                            Capsule().fill(palette.accent.opacity(0.9))
                                .frame(width: max(2, geo.size.width * music.progress))
                        }
                    }
                    .frame(height: 3)
                    .animation(.linear(duration: 0.3), value: music.progress)
                }
            }
            .padding(10)
            .background(cardBackground)

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
                .background(cardBackground)

                // Timer Card
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "timer")
                            .foregroundStyle(palette.accent)
                        Spacer()
                        Text(timer.isRunning ? timer.formattedTime : "Timer")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                    }

                    if timer.isRunning {
                        // Depleting bar — fills from full down to empty as the
                        // focus session elapses.
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.12))
                                Capsule().fill(palette.accent.opacity(0.9))
                                    .frame(width: max(2, geo.size.width * timer.progress))
                            }
                        }
                        .frame(height: 3)
                        .animation(.linear(duration: 0.3), value: timer.progress)

                        HStack(spacing: 8) {
                            Button(timer.isPaused ? "Resume" : "Pause") {
                                if timer.isPaused {
                                    timer.resumeTimer()
                                } else {
                                    timer.pauseTimer()
                                }
                            }
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(palette.accent)

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
                .background(cardBackground)
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
            .background(cardBackground)
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
                                        .foregroundStyle(palette.accent)
                                }
                                .buttonStyle(.plain)
                                .help("Copy back to clipboard")
                                .accessibilityLabel("Copy to clipboard")
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
                        .background(RoundedRectangle(cornerRadius: 8).fill(palette.accent.opacity(0.85)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add note")
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
                                .accessibilityLabel("Delete note")
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

/// A short, self-contained sparkle burst used to celebrate a finished focus
/// session or other happy moment. It lives and dies with its parent's state and
/// runs its animation once on appear; when `animated` is false (Reduce Motion)
/// the sparkles stay clustered as a quiet, static acknowledgment.
private struct CelebrationBurst: View {
    let tint: Color
    var animated: Bool = true
    @State private var expand = false

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                let angle = Double(i) / 8.0 * 2.0 * .pi
                Image(systemName: "sparkle")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                    .offset(
                        x: CGFloat(cos(angle)) * (expand ? 46 : 6),
                        y: CGFloat(sin(angle)) * (expand ? 46 : 6)
                    )
                    .opacity(expand ? 0 : 0.95)
                    .scaleEffect(expand ? 1.4 : 0.5)
            }
        }
        .onAppear {
            guard animated else { return }
            withAnimation(.easeOut(duration: 1.2)) {
                expand = true
            }
        }
    }
}
