import AppKit

@main
@MainActor
enum AMORAApp {
    private static var appDelegate: AppDelegate?

    static func main() async {
        if CommandLine.arguments.contains("--smoke-test") {
            var explicitModelPath: String? = nil
            let args = CommandLine.arguments
            for (idx, arg) in args.enumerated() {
                if (arg == "--model-path" || arg == "--candidate-path") && idx + 1 < args.count {
                    explicitModelPath = args[idx + 1]
                    break
                }
            }
            await runSmokeTestCLI(explicitModelPath: explicitModelPath)
            return
        }

        if CommandLine.arguments.contains("--eval") || CommandLine.arguments.contains("eval") {
            await runEvaluationCLI()
            return
        }

        if CommandLine.arguments.contains("--verify-proactive") {
            await runVerifyProactiveCLI()
            return
        }

        if CommandLine.arguments.contains("--verify-automation-ui") {
            await runVerifyAutomationUICLI()
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        appDelegate = delegate
        app.delegate = delegate
        app.run()
    }

    private static func runEvaluationCLI() async {
        let args = CommandLine.arguments
        let mode: EvaluationRunnerMode
        if args.contains("--router") {
            mode = .deterministicOnly
        } else if args.contains("--real") {
            mode = .realModelOnly
        } else if args.contains("--mock") {
            mode = .mockBaseline
        } else {
            mode = .endToEndProduction
        }

        var explicitModelPath: String? = nil
        for (idx, arg) in args.enumerated() {
            if (arg == "--model-path" || arg == "--candidate-path") && idx + 1 < args.count {
                explicitModelPath = args[idx + 1]
                break
            }
        }

        let provider: AmoraLocalBrainProvider?
        if let path = explicitModelPath {
            provider = AmoraLocalBrainProvider.forModelPath(path)
        } else {
            provider = nil
        }

        print("🚀 Running AMORA Evaluation V1 in mode: \(mode.rawValue)...")
        if let provider {
            print("🤖 Evaluated Model: \(provider.modelManager.descriptor.displayName) (Path: \(provider.modelManager.modelFileURL.path))")
        } else {
            print("🤖 Evaluated Model: Default Model (\(AmoraModelDescriptor.defaultModel.displayName))")
        }

        let runner = AmoraEvaluationRunner(mode: mode, provider: provider)
        let report = await runner.run { current, total, scenario in
            print("[\(current)/\(total)] \(scenario.id) (\(scenario.category.rawValue))")
        }
        print("\n" + AmoraEvaluationRunner.formatMarkdownReport(report))
        AmoraLlamaCppRuntime.shared.unloadSync()
        fflush(stdout)
        exit(0)
    }

    private static func runSmokeTestCLI(explicitModelPath: String?) async {
        let path = explicitModelPath ?? AmoraModelManager.shared.modelFileURL.path
        print("🔍 Starting Runtime Smoke Test for: \(path)")
        let provider: AmoraLocalBrainProvider
        if let explicit = explicitModelPath {
            provider = AmoraLocalBrainProvider.forModelPath(explicit)
        } else {
            provider = AmoraLocalBrainProvider.shared
        }
        let desc = provider.modelManager.descriptor
        print("🤖 Model: \(desc.displayName)")
        print("🆔 ID: \(desc.id)")
        print("📁 Path: \(provider.modelManager.modelFileURL.path)")
        print("📏 Prefix: '\(desc.generationPrefix)'")

        // Test 1: Simple Question ("What is 2+2?")
        print("\n--- Test 1: Simple Question ('What is 2+2?') ---")
        do {
            let messages = [AIMessage(role: .user, content: "What is 2+2?")]
            let resp = try await provider.send(messages: messages, model: desc.id, apiKey: nil)
            print("Response text: \(resp)")
            let decision = try AmoraAgentDecisionParser.parse(resp)
            print("Parsed decision: \(decision)")
        } catch {
            print("Test 1 FAILED: \(error)")
        }

        // Test 2: AI Talk Note-Search Request through AssistantManager
        print("\n--- Test 2: AI Talk Note Search ('Find notes about budget') ---")
        NotesService.shared.useIsolatedStorage()
        NotesService.shared.clearAll()
        NotesService.shared.addNote("Quarterly budget review meeting on Friday")
        let assistant = AssistantManager(provider: provider)
        let settings = AISettingsSnapshot(enabled: true, provider: .local, model: "local", apiKey: nil)
        let noteAnswer = await assistant.submit("Find notes about budget", settings: settings)
        print("AI Talk Note Response: \(noteAnswer)")

        // Test 3: AI Talk 10-minute Timer through AssistantManager
        print("\n--- Test 3: AI Talk Timer ('Set a 10 minute timer') ---")
        TimerService.shared.isSimulationMode = true
        let timerAnswer = await assistant.submit("Set a 10 minute timer", settings: settings)
        print("AI Talk Timer Response: \(timerAnswer)")
        print("Timer Running State: \(TimerService.shared.isRunning), Remaining: \(TimerService.shared.remainingSeconds)s")

        AmoraLlamaCppRuntime.shared.unloadSync()
        fflush(stdout)
        exit(0)
    }

    private static func runVerifyProactiveCLI() async {
        print("🚀 Starting Proactive AMORA V1 Verification...")

        let app = NSApplication.shared
        let delegate = AppDelegate()
        appDelegate = delegate
        app.delegate = delegate

        // 1. Initial State Check
        AppState.shared.handleLaunch()
        WindowManager.shared.showNotchWindow()

        let settings = AppState.shared.settings
        settings.proactiveAmoraEnabled = true
        settings.proactiveTimerCompletedEnabled = true
        AmoraProactiveService.shared.cooldownTracker.reset()
        AmoraProactiveService.shared.dismissCurrentSuggestion()

        print("✅ Step 1: Packaged AMORA launched, notch window initialized.")
        print("   Island State: \(IslandModel.shared.displayState)")
        print("   Proactive Enabled: \(settings.proactiveAmoraEnabled)")

        // 2. Set a short timer (2 seconds)
        print("\n⏳ Step 2: Setting a 2-second focus timer...")
        TimerService.shared.isSimulationMode = false
        TimerService.shared.startTimer(seconds: 2)
        print("   Timer running: \(TimerService.shared.isRunning), remaining: \(TimerService.shared.remainingSeconds)s")

        // Run main loop until timer completes
        let startTime = Date()
        while TimerService.shared.isRunning && Date().timeIntervalSince(startTime) < 5.0 {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        // Wait another 0.4s for Task @MainActor to execute handleEvent
        for _ in 0..<4 {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        print("   Timer finished. Timer running: \(TimerService.shared.isRunning)")

        // 3. Verify Proactive Suggestion generated and Dynamic Island updated
        print("\n💡 Step 3: Checking Proactive Suggestion in Dynamic Island...")
        guard let suggestion = AmoraProactiveService.shared.currentSuggestion else {
            print("❌ FAILURE: No proactive suggestion generated upon timer completion!")
            exit(1)
        }

        print("   Suggestion Trigger: \(suggestion.trigger.rawValue)")
        print("   Suggestion Title: \(suggestion.trigger.displayName)")
        print("   Suggestion Message: \(suggestion.message)")
        print("   Action Title: \(suggestion.actionTitle ?? "nil")")
        print("   Dynamic Island State: \(IslandModel.shared.displayState)")
        print("   Island Navigation Page: \(IslandNavigationModel.shared.selectedPage)")

        guard suggestion.trigger == .timerCompleted else {
            print("❌ FAILURE: Expected trigger .timerCompleted, got \(suggestion.trigger)")
            exit(1)
        }
        guard IslandModel.shared.displayState == .quick else {
            print("❌ FAILURE: Expected island state .quick, got \(IslandModel.shared.displayState)")
            exit(1)
        }
        guard IslandNavigationModel.shared.selectedPage == .home else {
            print("❌ FAILURE: Expected navigation page .home, got \(IslandNavigationModel.shared.selectedPage)")
            exit(1)
        }
        print("✅ Proactive suggestion successfully presented in Dynamic Island!")

        // 4. Test Snooze
        print("\n💤 Step 4: Testing Snooze...")
        AmoraProactiveService.shared.snoozeCurrentSuggestion()
        print("   Current Suggestion after Snooze: \(String(describing: AmoraProactiveService.shared.currentSuggestion))")
        let isCoolingDownAfterSnooze = AmoraProactiveService.shared.isCoolingDown(trigger: .timerCompleted)
        print("   Is Cooling Down for .timerCompleted: \(isCoolingDownAfterSnooze)")
        guard AmoraProactiveService.shared.currentSuggestion == nil && isCoolingDownAfterSnooze else {
            print("❌ FAILURE: Snooze did not clear suggestion or apply cooldown!")
            exit(1)
        }
        print("✅ Snooze successfully cleared suggestion and applied cooldown.")

        // 5. Test Dismiss
        print("\n❌ Step 5: Testing Dismiss...")
        AmoraProactiveService.shared.cooldownTracker.reset()
        let reevaluated = await AmoraProactiveService.shared.evaluateTrigger(.timerCompleted)
        guard reevaluated != nil else {
            print("❌ FAILURE: Failed to re-evaluate suggestion for dismiss test!")
            exit(1)
        }
        print("   Re-evaluated suggestion: \(reevaluated?.message ?? "")")
        AmoraProactiveService.shared.dismissCurrentSuggestion()
        let isCoolingDownAfterDismiss = AmoraProactiveService.shared.isCoolingDown(trigger: .timerCompleted)
        print("   Current Suggestion after Dismiss: \(String(describing: AmoraProactiveService.shared.currentSuggestion))")
        print("   Is Cooling Down for .timerCompleted: \(isCoolingDownAfterDismiss)")
        guard AmoraProactiveService.shared.currentSuggestion == nil && isCoolingDownAfterDismiss else {
            print("❌ FAILURE: Dismiss did not clear suggestion or apply cooldown!")
            exit(1)
        }
        print("✅ Dismiss successfully cleared suggestion and applied cooldown.")

        // 6. Test Settings Toggle
        print("\n⚙️ Step 6: Testing Settings Toggle (Disabling Proactive AMORA)...")
        settings.proactiveAmoraEnabled = false
        AmoraProactiveService.shared.cooldownTracker.reset()
        let candidateWhenDisabled = await AmoraProactiveService.shared.evaluateTrigger(.timerCompleted)
        print("   Candidate when disabled: \(String(describing: candidateWhenDisabled))")
        guard candidateWhenDisabled == nil && AmoraProactiveService.shared.currentSuggestion == nil else {
            print("❌ FAILURE: Suggestion was produced while Proactive AMORA is disabled!")
            exit(1)
        }
        print("✅ Disabling Proactive AMORA successfully prevented new suggestions.")

        // Restore setting
        settings.proactiveAmoraEnabled = true

        print("\n🎉 ALL PROACTIVE AMORA V1 VERIFICATION CHECKS PASSED!")
        AmoraLlamaCppRuntime.shared.unloadSync()
        fflush(stdout)
        exit(0)
    }

    private static func runVerifyAutomationUICLI() async {
        print("🚀 Starting Automation Notifications UI Verification...")

        let app = NSApplication.shared
        let delegate = AppDelegate()
        appDelegate = delegate
        app.delegate = delegate

        // 1. Initial State Check
        AppState.shared.handleLaunch()
        WindowManager.shared.showNotchWindow()

        print("✅ Step 1: Packaged AMORA launched, notch window initialized.")
        print("   Island State: \(IslandModel.shared.displayState)")

        // Collapse island initially to test auto-expansion
        WindowManager.shared.collapseIsland()
        IslandModel.shared.displayState = .collapsed
        AmoraAutomationService.shared.reset()

        // 2. Register test automation: Timer completion -> Show notification
        print("\n⚙️ Step 2: Creating timer-completion notification automation...")
        let testAuto = try? await AmoraAutomationService.shared.create(
            name: "Test Timer Break",
            trigger: .timerCompletion,
            action: .showNotification(message: "Focus timer finished! Time to stretch."),
            enabled: true,
            allowDuplicate: true
        )
        guard let testAuto else {
            print("❌ FAILURE: Could not create test automation!")
            exit(1)
        }
        print("   Automation created: '\(testAuto.name)', trigger: \(testAuto.trigger.displayName)")

        // 3. Set a short 2-second focus timer
        print("\n⏳ Step 3: Setting a 2-second focus timer...")
        TimerService.shared.isSimulationMode = false
        TimerService.shared.startTimer(seconds: 2)
        print("   Timer running: \(TimerService.shared.isRunning), remaining: \(TimerService.shared.remainingSeconds)s")

        // Run loop until timer completes
        let startTime = Date()
        while TimerService.shared.isRunning && Date().timeIntervalSince(startTime) < 5.0 {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        // Wait for @MainActor Task to execute handleEvent
        for _ in 0..<5 {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        print("   Timer completed. Checking automation notification delivery...")

        // 4. Verify Automation Notification in Dynamic Island
        print("\n💡 Step 4: Checking Automation Notification underneath AMORA Mascot...")
        guard let notification = AmoraAutomationService.shared.currentNotification else {
            print("❌ FAILURE: No automation notification was delivered upon timer completion!")
            exit(1)
        }

        print("   Notification Trigger Icon: \(notification.triggerIcon)")
        print("   Notification Trigger Name: \(notification.triggerName)")
        print("   Notification Message: \(notification.message)")
        print("   Dynamic Island State: \(IslandModel.shared.displayState)")

        guard notification.triggerIcon == "timer" else {
            print("❌ FAILURE: Expected triggerIcon 'timer', got '\(notification.triggerIcon)'")
            exit(1)
        }
        guard notification.message == "Focus timer finished! Time to stretch." else {
            print("❌ FAILURE: Expected message 'Focus timer finished! Time to stretch.', got '\(notification.message)'")
            exit(1)
        }
        guard IslandModel.shared.displayState == .quick else {
            print("❌ FAILURE: Expected island state .quick, got \(IslandModel.shared.displayState)")
            exit(1)
        }
        print("✅ Automation notification successfully delivered and Dynamic Island expanded!")

        // 5. Test Dismiss
        print("\n❌ Step 5: Testing Notification Dismissal...")
        AmoraAutomationService.shared.dismissNotification()
        print("   Current Notification after Dismiss: \(String(describing: AmoraAutomationService.shared.currentNotification))")
        guard AmoraAutomationService.shared.currentNotification == nil else {
            print("❌ FAILURE: Notification was not dismissed!")
            exit(1)
        }
        print("✅ Notification dismissed cleanly.")

        // 6. Test Action Execution on Notification
        print("\n⚡ Step 6: Testing Action Execution on Notification...")
        let actionNotification = AmoraAutomationNotification(
            triggerIcon: "timer",
            triggerName: "Break Timer",
            message: "Start a 5-minute break timer?",
            action: .startTimer(duration: 300),
            actionTitle: "Start Break"
        )
        AmoraAutomationService.shared.presentNotification(actionNotification)
        guard AmoraAutomationService.shared.currentNotification != nil else {
            print("❌ FAILURE: Action notification could not be presented!")
            exit(1)
        }

        await AmoraAutomationService.shared.executeCurrentNotificationAction()
        print("   Current Notification after action execution: \(String(describing: AmoraAutomationService.shared.currentNotification))")
        guard AmoraAutomationService.shared.currentNotification == nil else {
            print("❌ FAILURE: Notification was not cleared after action execution!")
            exit(1)
        }
        print("✅ Action executed safely and notification cleared.")

        // Cleanup
        _ = await AmoraAutomationService.shared.delete(id: testAuto.id)
        TimerService.shared.stopTimer()

        print("\n🎉 ALL AUTOMATION NOTIFICATIONS UI VERIFICATION CHECKS PASSED!")
        AmoraLlamaCppRuntime.shared.unloadSync()
        fflush(stdout)
        exit(0)
    }
}
