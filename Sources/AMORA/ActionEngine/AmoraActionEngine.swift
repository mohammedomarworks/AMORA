import Foundation

/// The central Action Engine executing strongly-typed, validated AMORA actions.
@MainActor
public final class AmoraActionEngine: Sendable {
    public let registry: AmoraActionRegistry
    public let decider: any AmoraActionDeciding
    public static let shared = AmoraActionEngine.makeDefault()

    public init(
        registry: AmoraActionRegistry,
        decider: any AmoraActionDeciding = AmoraActionDecisionEngine()
    ) {
        self.registry = registry
        self.decider = decider
    }

    /// Factory configuring the action engine with production dependencies.
    public static func makeDefault(
        mediaController: any AmoraMediaControlling = DefaultAmoraMediaController(),
        appLauncher: any AmoraApplicationLaunching = NativeAmoraApplicationLauncher(),
        folderOpener: any AmoraFolderOpening = NativeAmoraFolderOpener(),
        workspaceController: any AmoraWorkspaceControlling = DefaultAmoraWorkspaceController(),
        timerController: any AmoraTimerControlling = DefaultAmoraTimerController(),
        memoryStore: any AmoraMemoryStoring = AmoraMemoryStore.shared,
        decider: any AmoraActionDeciding = AmoraActionDecisionEngine()
    ) -> AmoraActionEngine {
        let registry = AmoraActionRegistry()
        registerDefaultActions(
            into: registry,
            mediaController: mediaController,
            appLauncher: appLauncher,
            folderOpener: folderOpener,
            workspaceController: workspaceController,
            timerController: timerController,
            memoryStore: memoryStore
        )
        return AmoraActionEngine(registry: registry, decider: decider)
    }

    /// Factory configuring the action engine with controlled evaluation adapters
    /// that validate targets without launching applications or opening Finder windows.
    public static func makeControlledForEvaluation(
        onAppOpen: (@Sendable (URL) -> Void)? = nil,
        onFolderOpen: (@Sendable (URL) -> Void)? = nil,
        memoryStore: any AmoraMemoryStoring = AmoraMemoryStore(storage: AmoraInMemoryStorage())
    ) -> AmoraActionEngine {
        let registry = AmoraActionRegistry()
        registerDefaultActions(
            into: registry,
            mediaController: ControlledAmoraMediaController(),
            appLauncher: ControlledAmoraApplicationLauncher(onOpen: onAppOpen),
            folderOpener: ControlledAmoraFolderOpener(onOpen: onFolderOpen),
            workspaceController: ControlledAmoraWorkspaceController(),
            timerController: DefaultAmoraTimerController(),
            memoryStore: memoryStore
        )
        return AmoraActionEngine(registry: registry, decider: AmoraActionDecisionEngine())
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

        // 2. Context-aware decision check
        // Manual / user-confirmed requests should still execute even when the snapshot already reports the desired state.
        if !context.isConfirmed {
            let decision = decider.decide(action: action, context: context)
            if case let .alreadyInState(actionId, message, data) = decision {
                let result = AmoraActionResult.alreadyInState(actionId: actionId, message: message, data: data)
                AMORAEventCenter.shared.emit(.commandSucceeded)
                return result
            }
        }

        // 3. Confirmation check
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

    /// Executes a sequential array of strongly typed `AmoraAction`s, coordinating state, progress, and confirmation.
    public func executeSequence(
        _ actions: [AmoraAction],
        context: AmoraActionContext = .init(),
        coordinator: AmoraActionExecutionCoordinator = .shared
    ) async -> [AmoraActionResult] {
        guard !actions.isEmpty else {
            coordinator.reset()
            return []
        }

        AMORAEventCenter.shared.emit(.commandProcessing)
        if !coordinator.isCancelled {
            coordinator.beginSequence(actions)
        }
        var results: [AmoraActionResult] = []
        var currentContext = context

        for (index, action) in actions.enumerated() {
            if coordinator.isCancelled {
                for remainingIndex in index..<actions.count {
                    coordinator.didCancelItem(at: remainingIndex)
                    results.append(AmoraActionResult.notPermitted(
                        actionId: actions[remainingIndex].identifier,
                        message: "Action cancelled by user."
                    ))
                }
                break
            }

            coordinator.willExecuteItem(at: index)

            guard let definition = registry.definition(for: action.identifier) else {
                let unavailableResult = AmoraActionResult.unavailable(
                    actionId: action.identifier,
                    message: "Action '\(action.identifier)' is not registered."
                )
                coordinator.didFailItem(at: index, result: unavailableResult)
                results.append(unavailableResult)
                continue
            }

            // 1. Validation check
            let validation = definition.validator(action)
            var actionPrompt: String? = nil
            switch validation {
            case .invalid(let reason):
                let invalidResult = AmoraActionResult.invalidInput(actionId: action.identifier, message: reason)
                coordinator.didFailItem(at: index, result: invalidResult)
                results.append(invalidResult)
                continue
            case .requiresConfirmation(let prompt):
                actionPrompt = prompt
            case .valid:
                break
            }

            // 2. Context-aware decision check
            // User-confirmed/manual steps should continue even when the current snapshot already reflects the desired state.
            var itemContext = currentContext
            if !itemContext.isConfirmed {
                let decision = decider.decide(action: action, context: currentContext)
                if case let .alreadyInState(actionId, message, data) = decision {
                    let result = AmoraActionResult.alreadyInState(actionId: actionId, message: message, data: data)
                    coordinator.didCompleteItem(at: index, result: result)
                    results.append(result)
                    continue
                }
            }

            // 3. Confirmation requirement check
            if actionPrompt == nil {
                let confirmationReq = definition.confirmationRequirement(action)
                if case .required(let prompt) = confirmationReq {
                    actionPrompt = prompt
                }
            }

            if let prompt = actionPrompt, !itemContext.isConfirmed {
                let confirmed = await coordinator.requestConfirmation(for: action, prompt: prompt, at: index)
                if !confirmed {
                    let notPermittedResult = AmoraActionResult.notPermitted(
                        actionId: action.identifier,
                        message: "Action cancelled: confirmation was not granted."
                    )
                    coordinator.didCancelItem(at: index)
                    results.append(notPermittedResult)
                    for remainingIndex in (index + 1)..<actions.count {
                        coordinator.didCancelItem(at: remainingIndex)
                        results.append(AmoraActionResult.notPermitted(
                            actionId: actions[remainingIndex].identifier,
                            message: "Action cancelled: prior step confirmation was denied."
                        ))
                    }
                    break
                }
                itemContext.isConfirmed = true
            }

            // 4. Execution handler
            let result = await definition.handler(action, itemContext)
            if result.status == .success {
                coordinator.didCompleteItem(at: index, result: result)
                if let snap = currentContext.snapshot {
                    currentContext.snapshot = decider.updatingSnapshot(snap, afterExecuting: action)
                }
            } else {
                coordinator.didFailItem(at: index, result: result)
            }
            results.append(result)

            if NSClassFromString("XCTestCase") == nil {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }

        coordinator.finishSequence(results: results)
        let allSucceeded = results.allSatisfy { $0.status == .success }
        if allSucceeded {
            AMORAEventCenter.shared.emit(.commandSucceeded)
        } else {
            AMORAEventCenter.shared.emit(.commandFailed)
        }

        return results
    }

    /// Executes an `AmoraActionPlan`, resolving calls into actions and executing them sequentially.
    public func executePlan(
        _ plan: AmoraActionPlan,
        context: AmoraActionContext = .init(),
        coordinator: AmoraActionExecutionCoordinator = .shared
    ) async -> [AmoraActionResult] {
        let resolved = plan.resolveActions()
        var validActions: [AmoraAction] = []
        var resolutionFailures: [(index: Int, result: AmoraActionResult)] = []

        for (idx, item) in resolved.enumerated() {
            switch item {
            case .success(let action):
                validActions.append(action)
            case .failure(let error):
                resolutionFailures.append((idx, .invalidInput(actionId: "unknown", message: error.message)))
            }
        }

        if validActions.isEmpty {
            coordinator.beginThinking()
            let results = resolutionFailures.map(\.result)
            coordinator.finishSequence(results: results)
            return results
        }

        var results = await executeSequence(validActions, context: context, coordinator: coordinator)
        for failure in resolutionFailures {
            results.append(failure.result)
        }
        return results
    }

    /// Validates an action without executing it.
    public func validate(_ action: AmoraAction) -> AmoraActionValidationResult {
        guard let definition = registry.definition(for: action.identifier) else {
            return .invalid(reason: "Action '\(action.identifier)' is not registered.")
        }
        return definition.validator(action)
    }

    /// Evaluates an array of strongly typed actions against context to produce planned decisions prior to execution.
    public func plan(
        actions: [AmoraAction],
        context: AmoraActionContext = .init()
    ) -> [AmoraActionPlanDecision] {
        decider.plan(actions: actions, context: context)
    }

    /// Evaluates an `AmoraActionPlan` against context to produce planned decisions prior to execution.
    public func plan(
        _ plan: AmoraActionPlan,
        context: AmoraActionContext = .init()
    ) -> [AmoraActionPlanDecision] {
        let actions = plan.actions.compactMap { call -> AmoraAction? in
            try? call.toActionRequest().resolveAction().get()
        }
        return decider.plan(actions: actions, context: context)
    }

    /// Registers standard V1 actions into the given registry.
    public static func registerDefaultActions(
        into registry: AmoraActionRegistry,
        mediaController: any AmoraMediaControlling,
        appLauncher: any AmoraApplicationLaunching,
        folderOpener: any AmoraFolderOpening,
        workspaceController: any AmoraWorkspaceControlling,
        timerController: any AmoraTimerControlling,
        memoryStore: any AmoraMemoryStoring = AmoraMemoryStore.shared
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

        // --- 12. System: Confirmation Test ---
        registry.register(AmoraActionDefinition(
            identifier: "system.confirm_test",
            name: "Confirmation Test",
            description: "A safely controlled test action that requires user confirmation before running.",
            isConfirmationRequiredByDefault: true,
            confirmationRequirement: { action in
                if case .confirmTest(_, let prompt) = action {
                    return .required(prompt: prompt)
                }
                return .required(prompt: "Are you sure you want to run this test action?")
            },
            handler: { action, context in
                guard context.isConfirmed else {
                    let prompt: String
                    if case .confirmTest(_, let p) = action { prompt = p }
                    else { prompt = "Are you sure you want to run this test action?" }
                    return .needsConfirmation(actionId: "system.confirm_test", prompt: prompt)
                }
                let name: String
                if case .confirmTest(let n, _) = action { name = n }
                else { name = "Test Action" }
                return .success(
                    actionId: "system.confirm_test",
                    message: "Confirmed and executed '\(name)'."
                )
            }
        ))

        // --- 13. Memory: Save ---
        registry.register(AmoraActionDefinition(
            identifier: "memory.save",
            name: "Save Memory",
            description: "Persists a memorable fact, preference, or project explicitly requested by the user.",
            validator: { action in
                guard case .saveMemory(let key, let value) = action else {
                    return .invalid(reason: "Invalid action payload for memory.save.")
                }
                let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedKey.isEmpty || trimmedValue.isEmpty {
                    return .invalid(reason: "Memory key and value cannot be empty.")
                }
                let validation = AmoraMemoryPrivacyValidator.shared.validate(key: trimmedKey, value: trimmedValue)
                if case .rejected(let reason) = validation {
                    return .invalid(reason: reason)
                }
                return .valid
            },
            handler: { action, _ in
                guard case .saveMemory(let key, let value) = action else {
                    return .invalidInput(actionId: "memory.save", message: "Missing key or value.")
                }
                do {
                    try await memoryStore.save(key: key, value: value)
                    return .success(
                        actionId: "memory.save",
                        message: "Remembered that \(key) is \(value).",
                        data: ["key": key, "value": value]
                    )
                } catch {
                    return .failed(
                        actionId: "memory.save",
                        message: "Failed to save memory: \(error.localizedDescription)"
                    )
                }
            }
        ))

        // --- 14. Memory: Forget ---
        registry.register(AmoraActionDefinition(
            identifier: "memory.forget",
            name: "Forget Memory",
            description: "Deletes matching stored memories matching a topic or query.",
            validator: { action in
                guard case .forgetMemory(let query) = action else {
                    return .invalid(reason: "Invalid action payload for memory.forget.")
                }
                let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmedQuery.isEmpty ? .invalid(reason: "Query cannot be empty.") : .valid
            },
            handler: { action, _ in
                guard case .forgetMemory(let query) = action else {
                    return .invalidInput(actionId: "memory.forget", message: "Missing query.")
                }
                do {
                    let deleted = try await memoryStore.deleteMatching(query: query)
                    if !deleted.isEmpty {
                        let count = deleted.count
                        return .success(
                            actionId: "memory.forget",
                            message: "Removed \(count) memory item\(count == 1 ? "" : "s") matching '\(query)'.",
                            data: ["query": query, "deletedCount": "\(count)"]
                        )
                    } else {
                        return .unavailable(
                            actionId: "memory.forget",
                            message: "I couldn't find any saved memories matching '\(query)'."
                        )
                    }
                } catch {
                    return .failed(
                        actionId: "memory.forget",
                        message: "Failed to remove memory: \(error.localizedDescription)"
                    )
                }
            }
        ))

        // --- 15. Memory: Update ---
        registry.register(AmoraActionDefinition(
            identifier: "memory.update",
            name: "Update Memory",
            description: "Updates a matching stored memory with a new value.",
            validator: { action in
                guard case .updateMemory(let target, let newValue) = action else {
                    return .invalid(reason: "Invalid action payload for memory.update.")
                }
                let trimmedTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedValue = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedTarget.isEmpty || trimmedValue.isEmpty {
                    return .invalid(reason: "Target and value cannot be empty.")
                }
                let validation = AmoraMemoryPrivacyValidator.shared.validate(key: trimmedTarget, value: trimmedValue)
                if case .rejected(let reason) = validation {
                    return .invalid(reason: reason)
                }
                return .valid
            },
            handler: { action, _ in
                guard case .updateMemory(let target, let newValue) = action else {
                    return .invalidInput(actionId: "memory.update", message: "Missing target or value.")
                }
                do {
                    if let updated = try await memoryStore.updateMatching(query: target, newValue: newValue, newKey: nil) {
                        return .success(
                            actionId: "memory.update",
                            message: "Updated \(updated.key) to: \(updated.value).",
                            data: ["key": updated.key, "value": updated.value]
                        )
                    } else {
                        return .unavailable(
                            actionId: "memory.update",
                            message: "I couldn't find any saved memories matching '\(target)' to update."
                        )
                    }
                } catch {
                    return .failed(
                        actionId: "memory.update",
                        message: "Failed to update memory: \(error.localizedDescription)"
                    )
                }
            }
        ))

        // --- 16. Memory: Clear All ---
        registry.register(AmoraActionDefinition(
            identifier: "memory.clear",
            name: "Clear Memories",
            description: "Clears all stored memories (requires confirmation).",
            validator: { action in
                guard case .clearMemories = action else {
                    return .invalid(reason: "Invalid action payload for memory.clear.")
                }
                return .valid
            },
            handler: { action, context in
                guard case .clearMemories(let confirmed) = action else {
                    return .invalidInput(actionId: "memory.clear", message: "Invalid payload.")
                }
                guard confirmed || context.isConfirmed else {
                    return .needsConfirmation(
                        actionId: "memory.clear",
                        prompt: "Are you sure you want me to forget everything? This will permanently delete all stored memories."
                    )
                }
                do {
                    try await memoryStore.clearAll()
                    return .success(actionId: "memory.clear", message: "Cleared all stored memories.")
                } catch {
                    return .failed(actionId: "memory.clear", message: "Failed to clear memories: \(error.localizedDescription)")
                }
            }
        ))
    }

    /// Registers the AMORA notification action into the given registry.
    public static func registerNotificationAction(
        into registry: AmoraActionRegistry,
        notificationPresenter: any AmoraNotificationPresenting = DefaultAmoraNotificationPresenter()
    ) {
        registry.register(AmoraActionDefinition(
            identifier: "amora.notification",
            name: "Show Notification",
            description: "Presents an AMORA notification message.",
            validator: { action in
                guard case .showNotification(let msg) = action else {
                    return .invalid(reason: "Invalid payload for amora.notification.")
                }
                let trimmed = msg.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? .invalid(reason: "Notification message cannot be empty.") : .valid
            },
            handler: { action, _ in
                guard case .showNotification(let msg) = action else {
                    return .invalidInput(actionId: "amora.notification", message: "Missing notification message.")
                }
                notificationPresenter.present(message: msg)
                return .success(
                    actionId: "amora.notification",
                    message: msg,
                    data: ["message": msg]
                )
            }
        ))
    }

    nonisolated public static func formatDuration(seconds: Int) -> String {
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
