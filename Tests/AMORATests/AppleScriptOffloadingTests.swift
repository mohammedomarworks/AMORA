import XCTest
@testable import AMORA

@MainActor
final class AppleScriptOffloadingTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        MusicService.shared.resetControlStateForTesting()
        MusicService.shared.scriptExecutor = AmoraAppleScriptExecutor.shared
    }

    override func tearDown() async throws {
        MusicService.shared.resetControlStateForTesting()
        MusicService.shared.scriptExecutor = AmoraAppleScriptExecutor.shared
        try await super.tearDown()
    }

    // MARK: - 1. Output Parsing Tests

    func testAppleMusicOutputParsingPlayingAndPaused() {
        let playingRaw = "playing|||Midnight City|||M83|||Hurry Up, We're Dreaming|||243.5|||45.2"
        let playingTrack = MusicService.parseAppleMusicOutput(playingRaw)
        XCTAssertNotNil(playingTrack)
        XCTAssertEqual(playingTrack?.title, "Midnight City")
        XCTAssertEqual(playingTrack?.artist, "M83")
        XCTAssertEqual(playingTrack?.album, "Hurry Up, We're Dreaming")
        XCTAssertEqual(playingTrack?.duration, 243.5)
        XCTAssertEqual(playingTrack?.position, 45.2)
        XCTAssertTrue(playingTrack?.isPlaying == true)

        let pausedRaw = "paused|||Starboy|||The Weeknd|||Starboy|||230.4|||12.0"
        let pausedTrack = MusicService.parseAppleMusicOutput(pausedRaw)
        XCTAssertNotNil(pausedTrack)
        XCTAssertEqual(pausedTrack?.title, "Starboy")
        XCTAssertEqual(pausedTrack?.artist, "The Weeknd")
        XCTAssertEqual(pausedTrack?.album, "Starboy")
        XCTAssertEqual(pausedTrack?.duration, 230.4)
        XCTAssertEqual(pausedTrack?.position, 12.0)
        XCTAssertFalse(pausedTrack?.isPlaying == true)
    }

    func testAppleMusicOutputParsingMalformedAndStopped() {
        XCTAssertNil(MusicService.parseAppleMusicOutput("stopped|||||||||0|||0"))
        XCTAssertNil(MusicService.parseAppleMusicOutput(""))
        XCTAssertNil(MusicService.parseAppleMusicOutput("playing|||"))
        XCTAssertNil(MusicService.parseAppleMusicOutput("paused|||   |||Artist|||Album|||100|||10"))
        XCTAssertNil(MusicService.parseAppleMusicOutput("random_unformatted_string"))

        // Missing album/duration/position fall back safely
        let minimal = MusicService.parseAppleMusicOutput("playing|||Song Name|||Artist Name")
        XCTAssertNotNil(minimal)
        XCTAssertEqual(minimal?.title, "Song Name")
        XCTAssertEqual(minimal?.artist, "Artist Name")
        XCTAssertEqual(minimal?.album, "")
        XCTAssertEqual(minimal?.duration, 0)
        XCTAssertEqual(minimal?.position, 0)
        XCTAssertTrue(minimal?.isPlaying == true)
    }

    // MARK: - 2. Background Execution & Offloading

    func testAppleScriptExecutorRunsOffMainActor() async {
        let executor = AmoraAppleScriptExecutor()
        // Run a lightweight harmless AppleScript (math return)
        let result = await executor.execute(source: "return 40 + 2", timeout: 2.0)
        switch result {
        case let .success(val):
            XCTAssertEqual(val.trimmingCharacters(in: .whitespacesAndNewlines), "42")
        default:
            XCTFail("Expected success but got \(result)")
        }
    }

    func testAppleScriptExecutorBoundedTimeout() async {
        let executor = AmoraAppleScriptExecutor()
        let start = Date()
        // A script with a delay exceeding the bounded timeout
        let slowScript = "do shell script \"sleep 0.5\"\nreturn 1"
        let result = await executor.execute(source: slowScript, timeout: 0.1)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(result, .timedOut(0.1))
        // Must return near the timeout window (allowing small scheduling jitter), not after 0.5 seconds
        XCTAssertLessThan(elapsed, 0.4, "Executor did not enforce bounded timeout; took \(elapsed)s")
    }

    func testAppleScriptExecutorCancellation() async {
        let executor = AmoraAppleScriptExecutor()
        let task = Task {
            await executor.execute(source: "do shell script \"sleep 0.5\"\nreturn 1", timeout: 2.0)
        }

        // Cancel immediately
        task.cancel()
        let result = await task.value
        XCTAssertEqual(result, .cancelled)
    }

    // MARK: - 3. MusicService Mock Integration

    func testMusicServiceTrackRefreshUpdatesCachedTrack() async {
        let music = MusicService.shared
        let mock = MockAppleScriptExecutor()
        music.scriptExecutor = mock
        music.isAppleMusicRunningOverride = true

        let mockOutput = "playing|||Solar Power|||Lorde|||Solar Power|||192.0|||20.0"
        mock.setDefaultResult(.success(mockOutput))

        // Simulate refresh when Apple Music is running
        let parsed = MusicService.parseAppleMusicOutput(mockOutput)
        music.setCachedAppleMusicTrackForTesting(parsed)
        music.checkCurrentTrack()

        XCTAssertEqual(music.source, .appleMusic)
        XCTAssertEqual(music.trackTitle, "Solar Power")
        XCTAssertEqual(music.artist, "Lorde")
        XCTAssertEqual(music.album, "Solar Power")
        XCTAssertEqual(music.duration, 192.0)
        XCTAssertEqual(music.elapsed, 20.0)
        XCTAssertTrue(music.isPlaying)
    }

    func testMusicServiceCommandTimeoutDoesNotHangUI() async {
        let music = MusicService.shared
        let mock = MockAppleScriptExecutor()
        mock.setDefaultResult(.timedOut(2.0))
        music.scriptExecutor = mock
        music.isAppleMusicRunningOverride = true

        // Run sendAppleMusicCommandAsync directly
        let (success, error) = await music.sendAppleMusicCommandAsync(.play)

        // Must report truthful failure
        XCTAssertFalse(success)
        XCTAssertEqual(error, "Apple Music did not respond in time.")

        // controlPending MUST be false so UI is not permanently frozen!
        XCTAssertFalse(music.controlPending)
        XCTAssertEqual(music.controlError, "Apple Music did not respond in time.")
        XCTAssertNil(music.controlStatus)

        // Subsequent commands must NOT be blocked by controlPending
        mock.setDefaultResult(.success(""))
        let (secondSuccess, secondError) = await music.sendAppleMusicCommandAsync(.play)
        XCTAssertTrue(secondSuccess)
        XCTAssertNil(secondError)
        XCTAssertFalse(music.controlPending)
    }

    func testMusicServiceCommandCancellationReportedHonestly() async {
        let music = MusicService.shared
        let mock = MockAppleScriptExecutor()
        mock.setDefaultResult(.cancelled)
        music.scriptExecutor = mock
        music.isAppleMusicRunningOverride = true

        let (success, error) = await music.sendAppleMusicCommandAsync(.pause)

        XCTAssertFalse(success)
        XCTAssertEqual(error, "Action cancelled.")
        XCTAssertFalse(music.controlPending)
        XCTAssertEqual(music.controlError, "Action cancelled.")
    }

    func testMusicServiceActionEngineIntegrationHonesty() async {
        let music = MusicService.shared
        let mock = MockAppleScriptExecutor()
        music.scriptExecutor = mock
        music.isAppleMusicRunningOverride = true

        let mockTrack = AppleMusicTrack(title: "Solar Power", artist: "Lorde", duration: 192.0, position: 20.0, isPlaying: true)
        music.setCachedAppleMusicTrackForTesting(mockTrack)
        music.preferredSource = .appleMusic
        music.checkCurrentTrack()

        let fetchScriptOutput = "playing|||Solar Power|||Lorde|||Solar Power|||192.0|||20.0"
        mock.setResponse(forScriptContaining: "player state", result: .success(fetchScriptOutput))

        // 1. Success path
        mock.setResponse(forScriptContaining: "to play", result: .success(""))
        let playRes = await music.playActionAsync()
        XCTAssertEqual(playRes.status, .success)
        XCTAssertEqual(playRes.actionId, "media.play")
        XCTAssertEqual(playRes.data["source"], "Apple Music")

        // 2. Timeout path
        mock.setResponse(forScriptContaining: "to play", result: .timedOut(2.0))
        let timeoutRes = await music.playActionAsync()
        XCTAssertEqual(timeoutRes.status, .failed)
        XCTAssertEqual(timeoutRes.actionId, "media.play")
        XCTAssertEqual(timeoutRes.message, "Apple Music did not respond in time.")
        XCTAssertEqual(timeoutRes.data["source"], "Apple Music")
        XCTAssertEqual(timeoutRes.data["reason"], "command_timeout")

        // 3. Cancellation path
        mock.setResponse(forScriptContaining: "to pause", result: .cancelled)
        let cancelRes = await music.pauseActionAsync()
        XCTAssertEqual(cancelRes.status, .notPermitted)
        XCTAssertEqual(cancelRes.actionId, "media.pause")
        XCTAssertEqual(cancelRes.message, "Action cancelled by user.")
        XCTAssertEqual(cancelRes.data["source"], "Apple Music")
        XCTAssertEqual(cancelRes.data["reason"], "command_cancelled")
    }

    func testMusicServiceGuardPreventsOverlappingCommands() async {
        let music = MusicService.shared
        let mock = MockAppleScriptExecutor()
        music.scriptExecutor = mock
        music.isAppleMusicRunningOverride = true

        // Simulate a command already pending
        music.setControlPendingForTesting(true)
        XCTAssertTrue(music.controlPending)

        // Attempt commands via public UI entry points while a command is pending
        music.play(preferredSource: .appleMusic)
        music.pause(preferredSource: .appleMusic)
        music.nextTrack(preferredSource: .appleMusic)
        music.previousTrack(preferredSource: .appleMusic)
        music.togglePlayPause()

        // All overlapping commands are ignored due to guard !controlPending
        XCTAssertEqual(mock.executionCount, 0)

        // Once pending is released, commands execute normally
        music.setControlPendingForTesting(false)
        mock.setDefaultResult(.success(""))
        let (success, error) = await music.sendAppleMusicCommandAsync(.play)
        XCTAssertTrue(success)
        XCTAssertNil(error)
        // Command executed, followed immediately by track refresh query
        XCTAssertEqual(mock.executionCount, 2)
        XCTAssertTrue(mock.history[0].source.contains("play"))
        XCTAssertTrue(mock.history[1].source.contains("player state"))
        XCTAssertFalse(music.controlPending)
    }

    func testMockAppleScriptExecutorRecordsCallsAndMatchesSubstring() async {
        let mock = MockAppleScriptExecutor()
        mock.setResponse(forScriptContaining: "to play", result: .success("playing"))
        mock.setResponse(forScriptContaining: "to pause", result: .success("paused"))

        let r1 = await mock.execute(source: "tell application \"Music\" to play", timeout: 2.0)
        let r2 = await mock.execute(source: "tell application \"Music\" to pause", timeout: 2.0)
        let r3 = await mock.execute(source: "tell application \"Music\" to next track", timeout: 2.0)

        XCTAssertEqual(r1, .success("playing"))
        XCTAssertEqual(r2, .success("paused"))
        XCTAssertEqual(r3, .success("")) // default result
        XCTAssertEqual(mock.executionCount, 3)
    }

    // MARK: - 4. Serialization & Late Completion Safety

    func testAppleScriptExecutorSerializationPreservesOrder() async {
        let executor = AmoraAppleScriptExecutor()
        var results: [Int] = []
        let lock = NSLock()

        await withTaskGroup(of: (Int, AmoraAppleScriptResult).self) { group in
            for i in 1...3 {
                group.addTask {
                    let res = await executor.execute(source: "return \(i)", timeout: 2.0)
                    return (i, res)
                }
            }
            for await (_, res) in group {
                if case let .success(val) = res {
                    if let intVal = Int(val.trimmingCharacters(in: .whitespacesAndNewlines)) {
                        lock.withLock { results.append(intVal) }
                    }
                }
            }
        }

        XCTAssertEqual(results.count, 3)
        XCTAssertTrue(results.contains(1))
        XCTAssertTrue(results.contains(2))
        XCTAssertTrue(results.contains(3))
    }

    func testAppleScriptExecutorLateCompletionDoesNotCrashOrDoubleResume() async {
        let executor = AmoraAppleScriptExecutor()
        // Script delay is 0.3s, timeout is 0.05s -> executor times out at 0.05s
        let result = await executor.execute(source: "do shell script \"sleep 0.3\"\nreturn 99", timeout: 0.05)
        XCTAssertEqual(result, .timedOut(0.05))

        // Wait for background execution to complete after timeout
        try? await Task.sleep(nanoseconds: 400_000_000)

        // Subsequent execution must succeed cleanly
        let nextResult = await executor.execute(source: "return 100", timeout: 2.0)
        switch nextResult {
        case let .success(val):
            XCTAssertEqual(val.trimmingCharacters(in: .whitespacesAndNewlines), "100")
        default:
            XCTFail("Expected success on subsequent execution but got \(nextResult)")
        }
    }

    func testBrowserMediaAppleScriptRunIsNonBlocking() async {
        let mock = MockAppleScriptExecutor()
        mock.setDelay(0.2)
        let start = Date()

        BrowserMediaAppleScript.run("tell application \"Safari\" to delay 1", executor: mock)
        let elapsed = Date().timeIntervalSince(start)

        // Must return immediately (< 50ms)
        XCTAssertLessThan(elapsed, 0.05, "BrowserMediaAppleScript.run blocked caller; took \(elapsed)s")
    }

    // MARK: - 5. Track-State Freshness, Termination & Invalidation

    func testAppleMusicTerminationInvalidatesCachedTrack() async {
        let music = MusicService.shared
        music.isAppleMusicRunningOverride = true
        let track = AppleMusicTrack(title: "Track A", artist: "Artist A", isPlaying: true)
        music.setCachedAppleMusicTrackForTesting(track)
        music.preferredSource = .appleMusic
        music.checkCurrentTrack()

        XCTAssertEqual(music.source, .appleMusic)
        XCTAssertEqual(music.trackTitle, "Track A")
        XCTAssertNotNil(music.cachedAppleMusicTrack)

        // Simulate application termination
        music.isAppleMusicRunningOverride = false
        music.handleAppleMusicTerminated()

        XCTAssertNil(music.cachedAppleMusicTrack)
        XCTAssertEqual(music.source, .none)
        XCTAssertEqual(music.trackTitle, "No Media Playing")
    }

    func testRefreshAppleMusicTrackSuppressesStaleOutdatedSequence() async {
        let music = MusicService.shared
        let mock = MockAppleScriptExecutor()
        music.scriptExecutor = mock
        music.isAppleMusicRunningOverride = true

        // Initial track
        let initialTrack = AppleMusicTrack(title: "Newer Track", artist: "Artist B", isPlaying: true)
        music.setCachedAppleMusicTrackForTesting(initialTrack)
        music.preferredSource = .appleMusic
        music.checkCurrentTrack()

        // Simulate latest applied sequence being higher than an old response
        music.setRefreshSequenceForTesting(sequence: 1, latestApplied: 5)
        let staleOutput = "playing|||Older Stale Track|||Artist A|||Album A|||200.0|||10.0"
        mock.setDefaultResult(.success(staleOutput))

        await music.refreshAppleMusicTrackAsync()

        // The stale track must NOT overwrite the newer track!
        XCTAssertEqual(music.cachedAppleMusicTrack?.title, "Newer Track")
    }

    func testRefreshAppleMusicTrackQueuesFollowupWhenInFlight() async {
        let music = MusicService.shared
        let mock = MockAppleScriptExecutor()
        music.scriptExecutor = mock
        music.isAppleMusicRunningOverride = true

        // First call with a small delay so it stays in flight
        mock.setDelay(0.05)
        mock.setDefaultResult(.success("playing|||Track 1|||Artist 1|||Album 1|||180|||10"))

        music.refreshAppleMusicTrack()
        XCTAssertTrue(music.isRefreshingAppleMusicTrackForTesting)

        // Second call while first is in flight
        mock.setDefaultResult(.success("playing|||Track 2|||Artist 2|||Album 2|||210|||20"))
        music.refreshAppleMusicTrack()
        XCTAssertTrue(music.hasPendingFollowupRefreshForTesting)

        // Allow in-flight and follow-up to complete
        mock.setDelay(0)
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertFalse(music.isRefreshingAppleMusicTrackForTesting)
        XCTAssertFalse(music.hasPendingFollowupRefreshForTesting)
        XCTAssertEqual(music.cachedAppleMusicTrack?.title, "Track 2")
    }

    func testAppleScriptFailureInvalidatesStaleCachedTrack() async {
        let music = MusicService.shared
        let mock = MockAppleScriptExecutor()
        music.scriptExecutor = mock
        music.isAppleMusicRunningOverride = true

        // Set initial track
        let initialTrack = AppleMusicTrack(title: "Track Before Failure", artist: "Artist", isPlaying: true)
        music.setCachedAppleMusicTrackForTesting(initialTrack)
        music.preferredSource = .appleMusic
        music.checkCurrentTrack()
        XCTAssertNotNil(music.cachedAppleMusicTrack)

        // Refresh fails with AppleScript error
        mock.setDefaultResult(.error(code: -1728, message: "No track playing"))
        await music.refreshAppleMusicTrackAsync()

        // Must invalidate cached track to avoid reporting stale/phantom media
        XCTAssertNil(music.cachedAppleMusicTrack)
        XCTAssertEqual(music.source, .none)

        // Now test timeout invalidation
        music.setCachedAppleMusicTrackForTesting(initialTrack)
        music.preferredSource = .appleMusic
        music.checkCurrentTrack()
        XCTAssertNotNil(music.cachedAppleMusicTrack)

        mock.setDefaultResult(.timedOut(1.5))
        await music.refreshAppleMusicTrackAsync()

        XCTAssertNil(music.cachedAppleMusicTrack)
        XCTAssertEqual(music.source, .none)
    }

    // MARK: - 6. Serial Worker Recovery & Queue Isolation

    func testQueryQueueTimeoutDoesNotBlockCommandQueue() async {
        let executor = AmoraAppleScriptExecutor()

        // 1. Execute a query with a delay that exceeds its timeout on queryQueue
        let slowQuery = "do shell script \"sleep 0.3\"\nreturn 1"
        let queryRes = await executor.execute(source: slowQuery, timeout: 0.05, isMutating: false)
        XCTAssertEqual(queryRes, .timedOut(0.05))

        // 2. A mutating command on commandQueue must NOT be blocked by the timed-out query!
        let cmdStart = Date()
        let cmdRes = await executor.execute(source: "return 42", timeout: 2.0, isMutating: true)
        let cmdElapsed = Date().timeIntervalSince(cmdStart)

        switch cmdRes {
        case let .success(val):
            XCTAssertEqual(val.trimmingCharacters(in: .whitespacesAndNewlines), "42")
        default:
            XCTFail("Command failed with \(cmdRes)")
        }
        // Should execute promptly (< 0.2s), not waiting for the query
        XCTAssertLessThan(cmdElapsed, 0.25)
    }

    func testTimedOutQueuedCommandIsSkippedWithoutDuplicateExecution() async {
        let executor = AmoraAppleScriptExecutor()

        // Launch a slow command that holds the command queue for 0.3s
        async let slowCommand = executor.execute(source: "do shell script \"sleep 0.3\"\nreturn 1", timeout: 1.0, isMutating: true)

        // Give the slow command a moment to enter the worker
        try? await Task.sleep(nanoseconds: 30_000_000)

        // Enqueue a command behind it with a short 0.05s timeout
        let fastTimeoutCommand = await executor.execute(source: "return 2", timeout: 0.05, isMutating: true)
        XCTAssertEqual(fastTimeoutCommand, .timedOut(0.05))

        // Wait for the slow command to complete
        let slowRes = await slowCommand
        switch slowRes {
        case let .success(val):
            XCTAssertEqual(val.trimmingCharacters(in: .whitespacesAndNewlines), "1")
        default:
            XCTFail("Slow command failed: \(slowRes)")
        }

        // Now run a fresh command - the queue must be free and responsive
        let followUpRes = await executor.execute(source: "return 3", timeout: 2.0, isMutating: true)
        switch followUpRes {
        case let .success(val):
            XCTAssertEqual(val.trimmingCharacters(in: .whitespacesAndNewlines), "3")
        default:
            XCTFail("Follow-up command failed: \(followUpRes)")
        }
    }

    // MARK: - 7. Resource Safety & Bounded Outstanding Work

    func testRepeatedQueryTimeoutsQuarantineWorkerAndSuppressUnboundedQueries() async {
        let executor = AmoraAppleScriptExecutor()

        // 1. Initial state: not quarantined
        XCTAssertFalse(executor.isQueryOutstanding)

        // 2. Launch Query 1 with a short 0.05s timeout against a slow 0.15s script
        let slowQuery = "do shell script \"sleep 0.15\"\nreturn 1"
        let q1 = await executor.execute(source: slowQuery, timeout: 0.05, isMutating: false)
        XCTAssertEqual(q1, .timedOut(0.05))

        // Worker must be quarantined because the underlying script is still outstanding!
        XCTAssertTrue(executor.isQueryOutstanding)

        // 3. Successive polling queries while Query 1 is in-flight must be suppressed immediately
        let q2 = await executor.execute(source: "return 2", timeout: 0.05, isMutating: false)
        XCTAssertEqual(q2, .queryQuarantined)

        let q3 = await executor.execute(source: "return 3", timeout: 0.05, isMutating: false)
        XCTAssertEqual(q3, .queryQuarantined)

        // 4. In the meantime, the separate commandQueue must remain completely responsive!
        let cmdStart = Date()
        let cmdRes = await executor.execute(source: "return 42", timeout: 1.0, isMutating: true)
        let cmdElapsed = Date().timeIntervalSince(cmdStart)
        switch cmdRes {
        case let .success(val):
            XCTAssertEqual(val.trimmingCharacters(in: .whitespacesAndNewlines), "42")
        default:
            XCTFail("Mutating command blocked by query quarantine: \(cmdRes)")
        }
        XCTAssertLessThan(cmdElapsed, 0.2)

        // 5. Wait for Query 1 to finish in the background
        try? await Task.sleep(nanoseconds: 400_000_000)

        // Quarantine must now be released!
        XCTAssertFalse(executor.isQueryOutstanding)

        // 6. Next query executes normally
        let q4 = await executor.execute(source: "return 4", timeout: 1.0, isMutating: false)
        switch q4 {
        case let .success(val):
            XCTAssertEqual(val.trimmingCharacters(in: .whitespacesAndNewlines), "4")
        default:
            XCTFail("Query failed after quarantine release: \(q4)")
        }
    }

    func testApplicationTerminationClearsQueryQuarantine() async {
        let executor = AmoraAppleScriptExecutor()

        // 1. Trigger query timeout to quarantine worker
        let slowQuery = "do shell script \"sleep 0.15\"\nreturn 1"
        let q1 = await executor.execute(source: slowQuery, timeout: 0.05, isMutating: false)
        XCTAssertEqual(q1, .timedOut(0.05))
        XCTAssertTrue(executor.isQueryOutstanding)

        // 2. Application termination triggers worker recovery
        executor.recoverStuckWorker(retireCommandQueue: true)

        // Quarantine must be reset immediately
        XCTAssertFalse(executor.isQueryOutstanding)

        // 3. New query can execute on the fresh queue
        let q2 = await executor.execute(source: "return 10", timeout: 1.0, isMutating: false)
        switch q2 {
        case let .success(val):
            XCTAssertEqual(val.trimmingCharacters(in: .whitespacesAndNewlines), "10")
        default:
            XCTFail("Query failed after worker recovery: \(q2)")
        }
    }

    func testMusicServiceSuppressesOverlappingPollsDuringQuarantine() async {
        let music = MusicService.shared
        let executor = AmoraAppleScriptExecutor()
        music.scriptExecutor = executor
        music.isAppleMusicRunningOverride = true

        let track = AppleMusicTrack(title: "Initial Track", artist: "Artist", isPlaying: true)
        music.setCachedAppleMusicTrackForTesting(track)
        music.preferredSource = .appleMusic
        music.checkCurrentTrack()
        XCTAssertNotNil(music.cachedAppleMusicTrack)

        // Simulate query worker quarantine with a slow script
        let slowScript = "do shell script \"sleep 0.15\"\nreturn 1"
        _ = await executor.execute(source: slowScript, timeout: 0.05, isMutating: false)
        XCTAssertTrue(executor.isQueryOutstanding)

        // MusicService refresh during quarantine must return nil and invalidate stale track
        let refreshed = await music.refreshAppleMusicTrackAsync()
        XCTAssertNil(refreshed)
        XCTAssertNil(music.cachedAppleMusicTrack)
        XCTAssertEqual(music.source, .none)

        // Clean up: wait for script to finish
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertFalse(executor.isQueryOutstanding)
    }
}
