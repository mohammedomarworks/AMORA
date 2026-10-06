import Foundation

/// The central Action Engine executing strongly-typed, validated AMORA actions.
@MainActor
public final class AmoraActionEngine: Sendable {
    public let registry: AmoraActionRegistry
    public static let shared = AmoraActionEngine.makeDefault()

    public init(registry: AmoraActionRegistry) {
        self.registry = registry
    }

    /// Factory configuring the action engine with production dependencies.
    public static func makeDefault(
        mediaController: any AmoraMediaControlling = DefaultAmoraMediaController(),
        appLauncher: any AmoraApplicationLaunching = NativeAmoraApplicationLauncher(),
        folderOpener: any AmoraFolderOpening = NativeAmoraFolderOpener(),
        workspaceController: any AmoraWorkspaceControlling = DefaultAmoraWorkspaceController(),
        timerController: any AmoraTimerControlling = DefaultAmoraTimerController()
    ) -> AmoraActionEngine {
        let registry = AmoraActionRegistry()
        registerDefaultActions(
            into: registry,
            mediaController: mediaController,
            appLauncher: appLauncher,
            folderOpener: folderOpener,
            workspaceController: workspaceController,
            timerController: timerController
        )
        return AmoraActionEngine(registry: registry)
    }

    /// Executes a strongly typed `AmoraAction`.
    public func execute(_ action: AmoraAction, context: AmoraActionContext = .init()) async -> AmoraActionResult {
        AMORAEventCenter.shared.emit(.commandProcessing)

        guard let definition = registry.definition(for: action.identifier) else {
            let result = AmoraActionResult.unavailable(
                actionId: action.identifier,
                message: "Action '\(action.identifier)' is not registered in the Action Engine."
            )
            AMORAEventCenter.shared.emit(.commandFailed)
            return result
        }

        // 1. Validation check
        let validation = definition.validator(action)
        switch validation {
        case .invalid(let reason):
            let result = AmoraActionResult.invalidInput(actionId: action.identifier, message: reason)
            AMORAEventCenter.shared.emit(.commandFailed)
            return result
        case .requiresConfirmation(let prompt) where !context.isConfirmed:
            let result = AmoraActionResult.needsConfirmation(actionId: action.identifier, prompt: prompt)
            AMORAEventCenter.shared.emit(.commandFailed)
            return result
        case .valid, .requiresConfirmation:
            break
        }

        // 2. Confirmation check
        if !context.isConfirmed {
            let confirmation = definition.confirmationRequirement(action)
            switch confirmation {
            case .required(let prompt):
                let result = AmoraActionResult.needsConfirmation(actionId: action.identifier, prompt: prompt)
                AMORAEventCenter.shared.emit(.commandFailed)
                return result
            case .notRequired:
                break
            }
        }

        // 3. Execution handler
        let result = await definition.handler(action, context)
        switch result.status {
        case .success:
            AMORAEventCenter.shared.emit(.commandSucceeded)
        case .failed, .invalidInput, .notPermitted, .unavailable, .needsConfirmation:
            AMORAEventCenter.shared.emit(.commandFailed)
        }
        return result
    }

    /// Validates an action without executing it.
    public func validate(_ action: AmoraAction) -> AmoraActionValidationResult {
        guard let definition = registry.definition(for: action.identifier) else {
            return .invalid(reason: "Action '\(action.identifier)' is not registered.")
        }
        return definition.validator(action)
    }

    /// Registers standard V1 actions into the given registry.
    public static func registerDefaultActions(
        into registry: AmoraActionRegistry,
        mediaController: any AmoraMediaControlling,
        appLauncher: any AmoraApplicationLaunching,
        folderOpener: any AmoraFolderOpening,
        workspaceController: any AmoraWorkspaceControlling,
        timerController: any AmoraTimerControlling
    ) {
        // --- 1. Media: Play ---
        registry.register(AmoraActionDefinition(
            identifier: "media.play",
            name: "Play Music",
            description: "Starts or resumes audio playback via the active media provider.",
            handler: { _, _ in
                mediaController.play()
                return .success(
                    actionId: "media.play",
                    message: "Music playback started.",
                    data: [
                        "source": mediaController.sourceName,
                        "track": mediaController.trackTitle
                    ]
                )
            }
        ))

        // --- 2. Media: Pause ---
        registry.register(AmoraActionDefinition(
            identifier: "media.pause",
            name: "Pause Music",
            description: "Pauses audio playback on the active media provider.",
            handler: { _, _ in
                mediaController.pause()
                return .success(
                    actionId: "media.pause",
                    message: "Music playback paused.",
                    data: ["source": mediaController.sourceName]
                )
            }
        ))

        // --- 3. Media: Next Track ---
        registry.register(AmoraActionDefinition(
            identifier: "media.next",
            name: "Next Track",
            description: "Skips to the next track on the active media provider.",
            handler: { _, _ in
                mediaController.nextTrack()
                return .success(
                    actionId: "media.next",
                    message: "Skipped to next track.",
                    data: ["source": mediaController.sourceName]
                )
            }
        ))

        // --- 4. Media: Previous Track ---
        registry.register(AmoraActionDefinition(
            identifier: "media.previous",
            name: "Previous Track",
            description: "Returns to the previous track on the active media provider.",
            handler: { _, _ in
                mediaController.previousTrack()
                return .success(
                    actionId: "media.previous",
                    message: "Skipped to previous track.",
                    data: ["source": mediaController.sourceName]
                )
            }
        ))

        // --- 5. Application Launch ---
        registry.register(AmoraActionDefinition(
            identifier: "app.open",
            name: "Open Application",
            description: "Opens an installed macOS application safely without shell execution.",
            validator: { action in
                if case .openApplication(let name) = action {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? .invalid(reason: "Application name cannot be empty.") : .valid
                }
                return .invalid(reason: "Invalid action payload for app.open.")
            },
            handler: { action, _ in
                guard case .openApplication(let name) = action else {
                    return .invalidInput(actionId: "app.open", message: "Missing application name.")
                }
                guard let appURL = appLauncher.resolveApplicationURL(named: name) else {
                    return .unavailable(
                        actionId: "app.open",
                        message: "Could not find application '\(name)' on this Mac."
                    )
                }
                do {
                    try await appLauncher.openApplication(at: appURL)
                    return .success(
                        actionId: "app.open",
                        message: "Opening \(name).",
                        data: ["appURL": appURL.path]
                    )
                } catch {
                    return .failed(
                        actionId: "app.open",
                        message: "Failed to open \(name): \(error.localizedDescription)"
                    )
                }
            }
        ))

        // --- 6. Folder / Location Open ---
        registry.register(AmoraActionDefinition(
            identifier: "folder.open",
            name: "Open Folder",
            description: "Safely opens a known filesystem location without shell execution.",
            validator: { action in
                if case .openFolder(let location) = action {
                    let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let allowed = ["downloads", "download", "documents", "document", "docs", "desktop", "home"]
                    return allowed.contains(trimmed) ? .valid : .invalid(reason: "Location '\(location)' is not a permitted folder.")
                }
                return .invalid(reason: "Invalid action payload for folder.open.")
            },
            handler: { action, _ in
                guard case .openFolder(let location) = action else {
                    return .invalidInput(actionId: "folder.open", message: "Missing folder location.")
                }
                guard let folderURL = folderOpener.resolveFolderURL(for: location) else {
                    return .unavailable(
                        actionId: "folder.open",
                        message: "Could not find folder location '\(location)' on this Mac."
                    )
                }
                do {
                    try await folderOpener.openFolder(at: folderURL)
                    return .success(
                        actionId: "folder.open",
                        message: "Opening \(location.capitalized).",
                        data: ["folderURL": folderURL.path]
                    )
                } catch {
                    return .failed(
                        actionId: "folder.open",
                        message: "Failed to open folder \(location): \(error.localizedDescription)"
                    )
                }
            }
        ))

        // --- 7. Workspace: Open ---
        registry.register(AmoraActionDefinition(
            identifier: "workspace.open",
            name: "Open Workspace",
            description: "Transitions AMORA into the enlarged Dynamic Island Workspace view.",
            handler: { action, _ in
                let section: String?
                if case .openWorkspace(let sec) = action { section = sec } else { section = nil }
                workspaceController.showWorkspace(section: section)
                return .success(
                    actionId: "workspace.open",
                    message: "Opened AMORA Workspace.",
                    data: section.map { ["section": $0] } ?? [:]
                )
            }
        ))

        // --- 8. Timer: Start ---
        registry.register(AmoraActionDefinition(
            identifier: "timer.start",
            name: "Start Timer",
            description: "Starts a focus timer for a specified duration in seconds.",
            validator: { action in
                guard case .startTimer(let duration) = action else {
                    return .invalid(reason: "Invalid action payload for timer.start.")
                }
                guard duration >= 1 && duration <= 86_400 else {
                    return .invalid(reason: "Timer duration must be between 1 second and 24 hours.")
                }
                return .valid
            },
            handler: { action, _ in
                guard case .startTimer(let duration) = action else {
                    return .invalidInput(actionId: "timer.start", message: "Missing duration.")
                }
                let seconds = Int(duration)
                timerController.startTimer(seconds: seconds)
                let formatted = Self.formatDuration(seconds: seconds)
                return .success(
                    actionId: "timer.start",
                    message: "Timer started for \(formatted).",
                    data: ["seconds": "\(seconds)"]
                )
            }
        ))

        // --- 9. Timer: Cancel ---
        registry.register(AmoraActionDefinition(
            identifier: "timer.cancel",
            name: "Cancel Timer",
            description: "Stops and clears any active focus timer.",
            handler: { _, _ in
                guard timerController.isRunning else {
                    return .unavailable(
                        actionId: "timer.cancel",
                        message: "I don't see an active timer. Would you like to start one?"
                    )
                }
                timerController.stopTimer()
                return .success(actionId: "timer.cancel", message: "Timer stopped.")
            }
        ))

        // --- 10. Timer: Pause ---
        registry.register(AmoraActionDefinition(
            identifier: "timer.pause",
            name: "Pause Timer",
            description: "Pauses active focus timer if supported.",
            handler: { _, _ in
                return .unavailable(
                    actionId: "timer.pause",
                    message: "I can stop the timer, but pause/resume isn't available yet."
                )
            }
        ))

        // --- 11. Timer: Resume ---
        registry.register(AmoraActionDefinition(
            identifier: "timer.resume",
            name: "Resume Timer",
            description: "Resumes paused focus timer if supported.",
            handler: { _, _ in
                return .unavailable(
                    actionId: "timer.resume",
                    message: "I can stop the timer, but pause/resume isn't available yet."
                )
            }
        ))
    }

    private static func formatDuration(seconds: Int) -> String {
        if seconds % 3600 == 0 {
            let hours = seconds / 3600
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        }
        if seconds % 60 == 0 {
            let minutes = seconds / 60
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        }
        return "\(seconds) seconds"
    }
}
