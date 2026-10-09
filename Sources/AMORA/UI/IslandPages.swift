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
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 24))
                .foregroundColor(palette.accent)
            
            Text("GitHub Activity")
                .font(.system(size: 12, weight: .bold))
            
            Text("Connect your GitHub account to see activity here.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Connect GitHub") {}
                .buttonStyle(.amoraPill)
                .disabled(true)
            
            Text("Requires GitHub OAuth app configuration.")
                .font(.system(size: 8))
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
