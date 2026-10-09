import SwiftUI
import UniformTypeIdentifiers

// MARK: - 1. IslandHomePage
@MainActor
struct IslandHomePage: View {
    private var palette: ThemePalette { AppState.shared.settings.palette }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                // Music Card
                MusicCompactCard()

                // Timer Card
                TimerCompactCard()
            }
            HStack(spacing: 8) {
                // Battery Card
                BatteryCompactCard()

                // System Card
                SystemCompactCard()
            }
        }
        .padding(8)
    }
}

@MainActor
struct MusicCompactCard: View {
    private var palette: ThemePalette { AppState.shared.settings.palette }
    private var music: MusicService { MusicService.shared }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "music.note")
                .foregroundColor(palette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(music.trackTitle.isEmpty ? "Not Playing" : music.trackTitle)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                if !music.artist.isEmpty {
                    Text(music.artist)
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if music.isAvailable {
                Button {
                    music.togglePlayPause()
                } label: {
                    Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 10))
                }
                .buttonStyle(.amoraHeaderCircle)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(palette.accent.opacity(0.2), lineWidth: 1)
        )
    }
}

@MainActor
struct TimerCompactCard: View {
    private var palette: ThemePalette { AppState.shared.settings.palette }
    private var timer: TimerService { TimerService.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .foregroundColor(palette.accent)
                Text(timer.isRunning || timer.isPaused ? timer.formattedTime : "Timer Off")
                    .font(.system(size: 10, weight: .bold))
                Spacer(minLength: 0)
            }
            if timer.isRunning || timer.isPaused {
                VStack(spacing: 4) {
                    ProgressView(value: timer.progress)
                        .progressViewStyle(.linear)
                        .tint(palette.accent)
                        .scaleEffect(y: 0.5, anchor: .center)
                    HStack(spacing: 8) {
                        Button {
                            timer.isRunning ? timer.pauseTimer() : timer.resumeTimer()
                        } label: {
                            Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.amoraHeaderCircle)

                        Button {
                            timer.stopTimer()
                        } label: {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.amoraHeaderCircle)
                    }
                }
            } else {
                HStack(spacing: 4) {
                    ForEach([5, 15, 25], id: \.self) { mins in
                        Button("\(mins)m") {
                            timer.startTimer(minutes: mins)
                        }
                        .font(.system(size: 9))
                        .buttonStyle(.amoraPill)
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(palette.accent.opacity(0.2), lineWidth: 1)
        )
    }
}

@MainActor
struct BatteryCompactCard: View {
    private var palette: ThemePalette { AppState.shared.settings.palette }
    private var battery: BatteryService { BatteryService.shared }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: battery.isCharging ? "battery.100.bolt" : "battery.50")
                .foregroundColor(battery.isCharging ? .green : palette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(battery.level)%")
                    .font(.system(size: 10, weight: .bold))
                if !battery.timeRemainingDescription.isEmpty {
                    Text(battery.timeRemainingDescription)
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(palette.accent.opacity(0.2), lineWidth: 1)
        )
    }
}

@MainActor
struct SystemCompactCard: View {
    private var palette: ThemePalette { AppState.shared.settings.palette }
    private var system: SystemMonitorService { SystemMonitorService.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                    .foregroundColor(palette.accent)
                Text(String(format: "%.1f%%", system.cpuUsagePercent))
                    .font(.system(size: 10, weight: .medium))
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                Image(systemName: "memorychip")
                    .foregroundColor(palette.accent)
                Text(String(format: "%.1f/%.1f GB", system.memoryUsedGB, system.memoryTotalGB))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Spacer(minLength: 0)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(palette.accent.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - 2. IslandAITalkPage
@MainActor
struct IslandAITalkPage: View {
    private var palette: ThemePalette { AppState.shared.settings.palette }
    private var assistant: AssistantManager { AssistantManager.shared }
    private var actionCoordinator: AmoraActionExecutionCoordinator { AmoraActionExecutionCoordinator.shared }

    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            // Content Area
            if actionCoordinator.state != .idle {
                ActionExecutionView(compact: true)
                    .frame(maxHeight: 100)
            } else if let response = assistant.response {
                ScrollView {
                    Text(response)
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 100)
            } else {
                switch assistant.state {
                case .thinking:
                    VStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Thinking...")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: 100)
                case .failed:
                    Text("Request failed.")
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, maxHeight: 100)
                case .cancelled:
                    Text("Request cancelled.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: 100)
                default:
                    Spacer()
                }
            }

            // Bottom Bar
            HStack(spacing: 8) {
                if assistant.state == .thinking {
                    Button("Stop") {
                        assistant.cancel()
                    }
                    .buttonStyle(.amoraPill)
                } else if assistant.response != nil {
                    Button("New Chat") {
                        assistant.startNewConversation()
                    }
                    .buttonStyle(.amoraPill)
                }

                TextField("Ask AMORA anything…", text: $inputText)
                    .font(.system(size: 11))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.4))
                    .cornerRadius(8)
                    .focused($isInputFocused)
                    .onSubmit {
                        submitRequest()
                    }

                Button {
                    submitRequest()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(inputText.isEmpty ? .secondary : palette.accent)
                }
                .disabled(inputText.isEmpty || assistant.state == .thinking)
                .buttonStyle(.plain)
            }
            .padding(.bottom, 4)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }

    private func submitRequest() {
        guard !inputText.isEmpty else { return }
        let text = inputText
        inputText = ""
        Task {
            await assistant.submit(text, settings: AppState.shared.settings.aiSettingsSnapshot)
        }
    }
}

// MARK: - 3. IslandTimerPage
@MainActor
struct IslandTimerPage: View {
    private var palette: ThemePalette { AppState.shared.settings.palette }
    private var timer: TimerService { TimerService.shared }

    var body: some View {
        VStack {
            if timer.isRunning || timer.isPaused {
                VStack(spacing: 12) {
                    Text(timer.formattedTime)
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundColor(palette.accent)

                    ProgressView(value: timer.progress)
                        .progressViewStyle(.linear)
                        .tint(palette.accent)
                        .padding(.horizontal, 40)

                    HStack(spacing: 24) {
                        Button {
                            timer.isRunning ? timer.pauseTimer() : timer.resumeTimer()
                        } label: {
                            Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                                .font(.system(size: 16))
                        }
                        .buttonStyle(.amoraHeaderCircle)

                        Button {
                            timer.stopTimer()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16))
                        }
                        .buttonStyle(.amoraHeaderCircle)
                    }
                }
                .padding(.vertical, 10)
            } else {
                VStack(spacing: 12) {
                    Text("Set Timer")
                        .font(.system(size: 12, weight: .semibold))

                    HStack(spacing: 12) {
                        ForEach([5, 15, 25, 50], id: \.self) { mins in
                            Button("\(mins)m") {
                                timer.startTimer(minutes: mins)
                            }
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(palette.accent.opacity(0.2), lineWidth: 1)
                            )
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 4. IslandClipboardPage
@MainActor
struct IslandClipboardPage: View {
    private var palette: ThemePalette { AppState.shared.settings.palette }
    private var clipboard: ClipboardService { ClipboardService.shared }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Clipboard")
                    .font(.system(size: 11, weight: .bold))
                Spacer()
                if !clipboard.history.isEmpty {
                    Button("Clear") {
                        clipboard.clearHistory()
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.amoraPill)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            if clipboard.history.isEmpty {
                AmoraEmptyStateView(
                    iconName: "doc.on.clipboard",
                    title: "Clipboard Empty",
                    subtitle: "Copied items will appear here."
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(clipboard.history, id: \.id) { item in
                            HStack {
                                Text(item.preview)
                                    .font(.system(size: 10))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Button {
                                    clipboard.copyToClipboard(item)
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 10))
                                }
                                .buttonStyle(.amoraHeaderCircle)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(6)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                }
            }
        }
    }
}

// MARK: - 5. IslandNotesPage
@MainActor
struct IslandNotesPage: View {
    private var palette: ThemePalette { AppState.shared.settings.palette }
    private var notesService: NotesService { NotesService.shared }

    @State private var newNoteText: String = ""

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("Add a note...", text: $newNoteText)
                    .font(.system(size: 11))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.4))
                    .cornerRadius(6)
                    .onSubmit { addNote() }

                Button {
                    addNote()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12))
                }
                .buttonStyle(.amoraHeaderCircle)
                .disabled(newNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            if notesService.notes.isEmpty {
                AmoraEmptyStateView(
                    iconName: "note.text",
                    title: "No Notes",
                    subtitle: "Jot down a quick thought."
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(notesService.notes, id: \.id) { note in
                            HStack(alignment: .top) {
                                Text(note.text)
                                    .font(.system(size: 10))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)

                                Button {
                                    notesService.deleteNote(id: note.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 10))
                                        .foregroundColor(.red.opacity(0.8))
                                }
                                .buttonStyle(.amoraHeaderCircle)
                            }
                            .padding(8)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(6)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private func addNote() {
        let text = newNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        notesService.addNote(text)
        newNoteText = ""
    }
}

// MARK: - 6. IslandFileShelfPage
@MainActor
struct IslandFileShelfPage: View {
    private var palette: ThemePalette { AppState.shared.settings.palette }
    private var shelf: FileShelfService { FileShelfService.shared }

    @State private var isDropTargeted: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("File Shelf (\(shelf.items.count))")
                    .font(.system(size: 11, weight: .bold))
                Spacer()
                if !shelf.items.isEmpty {
                    Button("Clear") {
                        shelf.clearShelf()
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.amoraPill)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            if shelf.items.isEmpty {
                AmoraEmptyStateView(
                    iconName: "folder",
                    title: "Shelf Empty",
                    subtitle: "Drag and drop files here."
                )
                .frame(maxHeight: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isDropTargeted ? palette.accent : Color.clear, style: StrokeStyle(lineWidth: 2, dash: [6]))
                )
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(shelf.items, id: \.id) { item in
                            HStack(spacing: 6) {
                                Image(systemName: "doc")
                                    .font(.system(size: 12))
                                    .foregroundColor(item.isMissing ? .red : palette.accent)

                                Text(item.name)
                                    .font(.system(size: 10))
                                    .lineLimit(1)
                                    .strikethrough(item.isMissing)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                HStack(spacing: 4) {
                                    if !item.isMissing {
                                        Button {
                                            _ = shelf.openFile(item)
                                        } label: { Image(systemName: "arrow.up.right.square") }
                                        .buttonStyle(.amoraHeaderCircle)

                                        Button {
                                            _ = shelf.revealFile(item)
                                        } label: { Image(systemName: "magnifyingglass") }
                                        .buttonStyle(.amoraHeaderCircle)
                                    }

                                    Button {
                                        shelf.removeItem(id: item.id)
                                    } label: { Image(systemName: "xmark") }
                                    .buttonStyle(.amoraHeaderCircle)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(6)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isDropTargeted ? palette.accent : Color.clear, style: StrokeStyle(lineWidth: 2, dash: [6]))
                )
            }
        }
        .onDrop(of: [.fileURL, .item], isTargeted: $isDropTargeted) { providers in
            return shelf.handleDrop(providers: providers) { _ in
                shelf.refreshItemStates()
            }
        }
        .onAppear {
            shelf.refreshItemStates()
        }
    }
}

// MARK: - 7. IslandAutomationsPage
@MainActor
struct IslandAutomationsPage: View {
    private var palette: ThemePalette { AppState.shared.settings.palette }
    private var automationsService: AmoraAutomationService { AmoraAutomationService.shared }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Automations (\(automationsService.automations.count))")
                    .font(.system(size: 11, weight: .bold))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            if automationsService.automations.isEmpty {
                AmoraEmptyStateView(
                    iconName: "gearshape.2",
                    title: "No Automations",
                    subtitle: "Create one in Settings."
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(automationsService.automations, id: \.id) { auto in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(auto.name)
                                        .font(.system(size: 11, weight: .medium))
                                    HStack(spacing: 4) {
                                        Image(systemName: auto.trigger.systemImage)
                                        Text(auto.trigger.displayName)
                                        Image(systemName: "arrow.right")
                                        Image(systemName: auto.action.systemImage)
                                        Text(auto.action.displayName)
                                    }
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                HStack(spacing: 8) {
                                    Toggle("", isOn: Binding(
                                        get: { auto.enabled },
                                        set: { _ in
                                            Task {
                                                _ = try? await automationsService.toggleEnabled(id: auto.id)
                                            }
                                        }
                                    ))
                                    .toggleStyle(.switch)
                                    .scaleEffect(0.6)
                                    .frame(width: 30)

                                    Button {
                                        Task {
                                            _ = await automationsService.runManually(id: auto.id)
                                        }
                                    } label: {
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 10))
                                    }
                                    .buttonStyle(.amoraHeaderCircle)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(6)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                }
            }
        }
    }
}

// MARK: - 8. IslandGitHubPage
@MainActor
struct IslandGitHubPage: View {
    private var palette: ThemePalette { AppState.shared.settings.palette }
    @Bindable private var gitHub = GitHubService.shared

    @State private var isShowingHub: Bool = false
    @State private var selectedTab: GitHubTab = .activity

    enum GitHubTab: String, CaseIterable, Identifiable {
        case activity = "Activity"
        case repos = "Repos"
        case pullRequests = "PRs"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 6) {
            switch gitHub.authState {
            case .disconnected, .cancelled:
                disconnectedView
            case .connecting:
                connectingView
            case .authorizing(let url):
                authorizingView(url: url)
            case .authenticating:
                authenticatingView
            case .connected(let user):
                if isShowingHub {
                    hubView(user: user)
                } else {
                    contributionView(user: user)
                }
            case .rateLimited(let resetDate):
                rateLimitedView(resetDate: resetDate)
            case .error(let message):
                errorView(message: message)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            if !gitHub.authState.isConnected {
                await gitHub.checkExistingAuth()
            }
        }
    }

    // MARK: - Subviews

    private var disconnectedView: some View {
        VStack(spacing: 8) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 20))
                .foregroundColor(palette.accent)

            Text("GitHub Activity")
                .font(.system(size: 11, weight: .bold))

            Text("Connect your GitHub account with one click to see real commits, repositories, and pull requests.")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            Button("Connect GitHub") {
                Task {
                    await gitHub.startAuthentication()
                }
            }
            .buttonStyle(.amoraPill)
        }
    }

    private var connectingView: some View {
        VStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Starting secure authentication…")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            Button("Cancel") {
                gitHub.cancelAuthentication()
            }
            .font(.system(size: 10))
            .buttonStyle(.amoraPill)
        }
    }

    private func authorizingView(url: URL) -> some View {
        VStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)

            Text("Authorizing on GitHub")
                .font(.system(size: 11, weight: .bold))

            Text("Complete sign-in in your browser and click 'Authorize'.")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            HStack(spacing: 8) {
                Button("Re-open Browser") {
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.amoraPill)

                Button("Cancel") {
                    gitHub.cancelAuthentication()
                }
                .font(.system(size: 10))
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
        }
    }

    private var authenticatingView: some View {
        VStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Exchanging credentials and loading profile…")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    private func contributionView(user: GitHubUser) -> some View {
        let calendar = gitHub.contributionCalendar ?? GitHubContributionCalendar.generateFallback(from: gitHub.events)
        return GitHubContributionGraphView(
            calendar: calendar,
            isLoading: gitHub.isLoadingData,
            onBackToHub: {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    isShowingHub = true
                }
            }
        )
    }

    private func hubView(user: GitHubUser) -> some View {
        VStack(spacing: 4) {
            // Header Bar
            HStack(spacing: 6) {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        isShowingHub = false
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9, weight: .bold))
                        Text("Grid")
                            .font(.system(size: 9, weight: .semibold))
                    }
                }
                .buttonStyle(.amoraPill)
                .help("Back to contribution heatmap grid")

                AsyncImage(url: user.avatarUrl.flatMap(URL.init)) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Image(systemName: "person.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 18, height: 18)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 0) {
                    Text(user.name ?? user.login)
                        .font(.system(size: 10, weight: .bold))
                        .lineLimit(1)
                    Text("@\(user.login)")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Profile link button
                Button {
                    if let url = URL(string: user.htmlUrl) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 10))
                }
                .buttonStyle(.amoraHeaderCircle)
                .help("Open GitHub Profile")

                // Refresh button
                Button {
                    Task {
                        await gitHub.refreshData()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                }
                .buttonStyle(.amoraHeaderCircle)
                .help("Refresh GitHub Data")

                // Disconnect button
                Button {
                    Task {
                        await gitHub.disconnect()
                    }
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 10))
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.amoraHeaderCircle)
                .help("Disconnect Account")
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)

            // Segmented Picker
            HStack(spacing: 4) {
                ForEach(GitHubTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Text(tabTitle(tab))
                            .font(.system(size: 9, weight: selectedTab == tab ? .bold : .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selectedTab == tab ? Color.white.opacity(0.12) : Color.clear)
                            )
                            .foregroundColor(selectedTab == tab ? .white : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 10)

            Divider()
                .opacity(0.2)

            // Content Area
            if gitHub.isLoadingData {
                VStack {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Updating…")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        switch selectedTab {
                        case .activity:
                            VStack(alignment: .leading, spacing: 6) {
                                let calendar = gitHub.contributionCalendar ?? GitHubContributionCalendar.generateFallback(from: gitHub.events)
                                GitHubContributionGraphView(
                                    calendar: calendar,
                                    isLoading: gitHub.isLoadingData,
                                    onBackToHub: {
                                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                            isShowingHub = false
                                        }
                                    }
                                )

                                Divider()
                                    .opacity(0.15)
                                    .padding(.vertical, 2)

                                HStack {
                                    Text("Recent Events")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Button {
                                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                            isShowingHub = false
                                        }
                                    } label: {
                                        HStack(spacing: 3) {
                                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                                .font(.system(size: 7))
                                            Text("Expand Grid")
                                                .font(.system(size: 8))
                                        }
                                        .foregroundColor(palette.accent)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 4)

                                activityList
                            }
                        case .repos:
                            reposList
                        case .pullRequests:
                            pullRequestsList
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                }
            }
        }
    }

    private func tabTitle(_ tab: GitHubTab) -> String {
        switch tab {
        case .activity:
            return "Activity (\(gitHub.events.count))"
        case .repos:
            return "Repos (\(gitHub.repositories.count))"
        case .pullRequests:
            return "PRs (\(gitHub.pullRequests.count))"
        }
    }

    private var activityList: some View {
        Group {
            if gitHub.events.isEmpty {
                AmoraEmptyStateView(
                    iconName: "bolt.horizontal",
                    title: "No Recent Activity",
                    subtitle: "Public events will appear here."
                )
                .frame(height: 80)
            } else {
                ForEach(gitHub.events) { event in
                    HStack(spacing: 6) {
                        Image(systemName: iconForEvent(event.type))
                            .font(.system(size: 9))
                            .foregroundColor(palette.accent)
                            .frame(width: 14)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.summary)
                                .font(.system(size: 9, weight: .medium))
                                .lineLimit(1)
                            Text(event.repo.name)
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        if let date = event.createdAt {
                            Text(timeAgo(from: date))
                                .font(.system(size: 7))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(5)
                }
            }
        }
    }

    private var reposList: some View {
        Group {
            if gitHub.repositories.isEmpty {
                AmoraEmptyStateView(
                    iconName: "folder",
                    title: "No Repositories",
                    subtitle: "Your repositories will appear here."
                )
                .frame(height: 80)
            } else {
                ForEach(gitHub.repositories) { repo in
                    Button {
                        if let url = URL(string: repo.htmlUrl) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: repo.isPrivate ? "lock.fill" : "book.closed")
                                .font(.system(size: 9))
                                .foregroundColor(palette.accent)

                            Text(repo.name)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)

                            Spacer()

                            if let lang = repo.language {
                                Text(lang)
                                    .font(.system(size: 7))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.white.opacity(0.08))
                                    .cornerRadius(3)
                                    .foregroundColor(.secondary)
                            }

                            if repo.stargazersCount > 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 7))
                                        .foregroundColor(.yellow)
                                    Text("\(repo.stargazersCount)")
                                        .font(.system(size: 7))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var pullRequestsList: some View {
        Group {
            if gitHub.pullRequests.isEmpty {
                AmoraEmptyStateView(
                    iconName: "arrow.triangle.pull",
                    title: "No Open Pull Requests",
                    subtitle: "PRs authored by you will appear here."
                )
                .frame(height: 80)
            } else {
                ForEach(gitHub.pullRequests) { pr in
                    Button {
                        if let url = URL(string: pr.htmlUrl) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.pull")
                                .font(.system(size: 9))
                                .foregroundColor(.green)

                            VStack(alignment: .leading, spacing: 1) {
                                Text("#\(pr.number) \(pr.title)")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                if let repo = pr.repoFullName {
                                    Text(repo)
                                        .font(.system(size: 8))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            if let date = pr.createdAt {
                                Text(timeAgo(from: date))
                                    .font(.system(size: 7))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func rateLimitedView(resetDate: Date) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundColor(.orange)

            Text("Rate Limit Exceeded")
                .font(.system(size: 11, weight: .bold))

            let formatter = DateFormatter()
            let _ = { formatter.timeStyle = .short }()
            Text("GitHub API limit reached. Resets at \(formatter.string(from: resetDate)).")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            Button("Retry Now") {
                Task {
                    await gitHub.refreshData()
                }
            }
            .buttonStyle(.amoraPill)
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.red)

            Text("Connection Error")
                .font(.system(size: 11, weight: .bold))

            Text(message)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            HStack(spacing: 8) {
                Button("Try Again") {
                    Task {
                        await gitHub.startAuthentication()
                    }
                }
                .buttonStyle(.amoraPill)

                Button("Reset") {
                    Task {
                        await gitHub.disconnect()
                    }
                }
                .font(.system(size: 9))
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
        }
    }

    private func iconForEvent(_ type: String) -> String {
        switch type {
        case "PushEvent": return "arrow.up.circle.fill"
        case "PullRequestEvent": return "arrow.triangle.pull"
        case "CreateEvent": return "plus.circle"
        case "WatchEvent": return "star.fill"
        case "ForkEvent": return "arrow.triangle.branch"
        default: return "circle.fill"
        }
    }

    private func timeAgo(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        return "\(days)d ago"
    }
}

// MARK: - GitHub Contribution Graph View

@MainActor
struct GitHubContributionGraphView: View {
    let calendar: GitHubContributionCalendar
    var isLoading: Bool = false
    let onBackToHub: () -> Void

    @State private var hoveredDay: GitHubContributionDay? = nil
    @State private var selectedDay: GitHubContributionDay? = nil

    private let cellSize: CGFloat = 10.5
    private let spacing: CGFloat = 2.5
    private let visibleWeeksCount: Int = 28

    private var activeDay: GitHubContributionDay? {
        hoveredDay ?? selectedDay ?? latestDay
    }

    private var latestDay: GitHubContributionDay? {
        calendar.weeks.last?.days.last
    }

    private var headerSubtitle: String {
        if let day = activeDay {
            return day.contributionSummary
        } else if calendar.totalContributions > 0 {
            let plural = calendar.totalContributions == 1 ? "contribution" : "contributions"
            return "\(calendar.totalContributions) \(plural) in past year"
        } else {
            return "No contributions"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header Bar matching reference image:
            // Left: "< Activity" button
            // Right: "Sep 1 · 10 contributions"
            HStack(alignment: .center) {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        onBackToHub()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .bold))
                        Text("Activity")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .help("View GitHub repositories, pull requests, and options")

                Spacer()

                HStack(spacing: 6) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 10, height: 10)
                    }

                    Text(headerSubtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.white.opacity(0.85))
                        .animation(.easeInOut(duration: 0.15), value: headerSubtitle)
                }
            }
            .padding(.horizontal, 4)

            // Panoramic Contribution Heatmap Grid (7 rows of rounded cells)
            let weeksToShow = Array(calendar.weeks.suffix(visibleWeeksCount))
            HStack(alignment: .top, spacing: spacing) {
                ForEach(weeksToShow) { week in
                    VStack(spacing: spacing) {
                        ForEach(0..<7, id: \.self) { weekday in
                            if let day = week.days.first(where: { $0.weekday == weekday }) {
                                cellView(for: day)
                            } else {
                                Color.clear
                                    .frame(width: cellSize, height: cellSize)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func cellView(for day: GitHubContributionDay) -> some View {
        let isHovered = hoveredDay?.id == day.id
        let isSelected = selectedDay?.id == day.id
        let isHighlighted = isHovered || isSelected

        return ZStack {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(cellColor(for: day))

            if isHighlighted {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .stroke(Color.white, lineWidth: 1.5)
            }
        }
        .frame(width: cellSize, height: cellSize)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoveredDay = day
            } else if hoveredDay?.id == day.id {
                hoveredDay = nil
            }
        }
        .onTapGesture {
            selectedDay = day
        }
        .help(day.contributionSummary)
    }

    private func cellColor(for day: GitHubContributionDay) -> Color {
        switch day.level {
        case 0:
            return Color(red: 0.12, green: 0.14, blue: 0.17)
        case 1:
            return Color(red: 0.05, green: 0.28, blue: 0.16)
        case 2:
            return Color(red: 0.0, green: 0.43, blue: 0.22)
        case 3:
            return Color(red: 0.15, green: 0.65, blue: 0.26)
        default:
            return Color(red: 0.22, green: 0.83, blue: 0.33)
        }
    }
}
