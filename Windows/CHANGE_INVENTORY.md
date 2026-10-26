# Cumulative Windows change inventory

Baseline: `main` at `8c166706cb71134ae8db256fc861af36b9288f04`. This lists every currently modified tracked file and untracked source/document/script in the working tree; generated ignored outputs, external evidence and scratch files are excluded. This inventory records the implementation relative to that baseline; the final audit authorizes one checkpoint commit and normal push. Mac implementation and shared browser extension sources remain unchanged.

This is a cumulative source inventory, not a claim that every behavior has complete Mac parity. Read [MILESTONE_REPORT.md](MILESTONE_REPORT.md) for first-increment evidence and [CONTINUATION_REPORT.md](CONTINUATION_REPORT.md) for the current continuation. Verification applies only to the source snapshots recorded there.

File count: **148**. Paths are repository-relative.

| File | Why it changed |
|---|---|
| `.github/workflows/windows-orbit.yml` | Publish the self-contained browser host and unchanged extension with the shared helper; enforce their validation while retaining existing release/security gates. |
| `Windows/.gitignore` | Ignore Windows build/test output and binary build logs without hiding source or release evidence. |
| `Windows/AMORA.BrowserHost/AMORA.BrowserHost.csproj` | Build a native Windows console messaging host with matching app version and self-contained runtime identifiers, without WinUI or third-party packages. |
| `Windows/AMORA.BrowserHost/Program.cs` | Forward strictly validated framed messages between the pinned extension origin and the current Windows user pipe, with bounded connection and safe shutdown. |
| `Windows/AMORA.Orbit.Tests/AMORA.Orbit.Tests.csproj` | .NET-only non-UI test task fix and broader XAML source fixtures; app PRI retained. |
| `Windows/AMORA.Orbit.Tests/ApplicationResourcesTests.cs` | Preserve standard-resource-first regression and validate application resource references across views. |
| `Windows/AMORA.Orbit.Tests/AssistantCommandViewModelTests.cs` | Regress assistant result/busy/confirmation presentation changes. |
| `Windows/AMORA.Orbit.Tests/AssistantEngineAIToolExecutionTests.cs` | Assert sanitized tool/provider failures preserve the bounded execution boundary and truthful actionable result states. |
| `Windows/AMORA.Orbit.Tests/AssistantEngineTests.cs` | Regress provider unavailable/error classification and existing deterministic command execution. |
| `Windows/AMORA.Orbit.Tests/AutomationReliabilityTests.cs` | Mutation rollback, concurrent occurrence execution, result persistence and explicit reminders. |
| `Windows/AMORA.Orbit.Tests/AutomationsViewModelTests.cs` | Overlong-name validation and restored persisted row state after a failed toggle. |
| `Windows/AMORA.Orbit.Tests/BrowserBridgeTests.cs` | Framing/URL/schema limits, opt-in collection, real user pipe roundtrip, acknowledgements/timeouts/disconnect, registration and single-source arbitration. |
| `Windows/AMORA.Orbit.Tests/ClipboardHistoryTests.cs` | Fake-source opt-in/privacy/cancel/restore/limit/lifecycle boundaries; no user's clipboard used. |
| `Windows/AMORA.Orbit.Tests/CloudProviderParityTests.cs` | Mocked endpoint/header/schema/history/provenance/cancel/error/selection behavior. |
| `Windows/AMORA.Orbit.Tests/DeterministicCommandRouterTests.cs` | Regress actual relative timer adjustment command semantics. |
| `Windows/AMORA.Orbit.Tests/ExplicitMemoryTests.cs` | Explicit grammar/privacy/lifecycle/ambiguity/rollback/limits and actual temporary DPAPI reload/corruption/conflict. |
| `Windows/AMORA.Orbit.Tests/GitHubActivityTests.cs` | Mock official endpoint/auth/schema rules, owner validation, limits/partial failure, safe links, explicit credentials, cancellation and disposal. |
| `Windows/AMORA.Orbit.Tests/LiveSystemStatusTests.cs` | Actual resampling cadence, unknown/error metrics and UI/disposal dispatch. |
| `Windows/AMORA.Orbit.Tests/LocalBrainTests.cs` | Injected runtime/assets verify integrity/resource/setup/no-cloud boundaries, context limits, cancel/restart/delete/readiness and late UI callbacks. |
| `Windows/AMORA.Orbit.Tests/MascotExpressionTests.cs` | Update expected rendering parameters for authentic new expressions without replacing behavior checks with UI placeholders. |
| `Windows/AMORA.Orbit.Tests/MascotPersonalityTests.cs` | Deterministic click debounce/cycle/grumpy reaction, priority/expiry, real ambient state, sleep and disposal regressions. |
| `Windows/AMORA.Orbit.Tests/MascotViewModelTests.cs` | Mood/expression parity and deterministic interaction mapping. |
| `Windows/AMORA.Orbit.Tests/NativeLocalBrainIntegrationTests.cs` | Explicitly enabled actual production-service/native-model generation, cached install without download, cancellation and process-stop acceptance. |
| `Windows/AMORA.Orbit.Tests/OrbitWindowLifecycleTests.cs` | Native shell workspace/visibility/navigation/disposal behavior. |
| `Windows/AMORA.Orbit.Tests/PositioningServiceTests.cs` | Compact/home/workspace geometry, DPI, invalid monitors and fullscreen exclusions. |
| `Windows/AMORA.Orbit.Tests/PresentationPreferencesTests.cs` | Durability/rollback/corrupt recovery/range validation, preview/save snapshots, disposal, fresh Local Brain and default-off browser privacy regressions. |
| `Windows/AMORA.Orbit.Tests/ProactiveSuggestionEngineTests.cs` | Truthful disabled state and visible retry behavior after action failure. |
| `Windows/AMORA.Orbit.Tests/PublicBetaReadinessTests.cs` | Assert visible corrupt-store recovery and deliberate fresh-install Local Brain settings while preserving unavailable states. |
| `Windows/AMORA.Orbit.Tests/SafeNavigationTests.cs` | Typed parser allowlists, shell/path rejection, explicit folder confirmation expiry/cancel and truthful native failures. |
| `Windows/AMORA.Orbit.Tests/SettingsPersistenceTests.cs` | Atomic settings/error handling and protected credential lifecycle. |
| `Windows/AMORA.Orbit.Tests/SettingsViewModelTests.cs` | Explicitly select cloud provider for credential lifecycle tests under new fresh-local defaults; preserve sanitization/model semantics. |
| `Windows/AMORA.Orbit.Tests/TimerDeadlineTests.cs` | Callback delays, pause/resume, adjustment, once-only completion and disposal. |
| `Windows/AMORA.Orbit.Tests/ViewModelShutdownTests.cs` | Queued/in-flight callbacks cannot update disposed viewmodels; credential writes retain submitted provider despite concurrent selection changes. |
| `Windows/AMORA.Orbit.Tests/WindowsMediaServiceTests.cs` | Real service transport abstraction/capability/error/polling behavior. |
| `Windows/AMORA.Orbit.Tests/WorkspaceToolsTests.cs` | Distinct note search, CRUD/pin, storage failure/conflict/corruption, reference-only persistence, unsafe path/type rejection, launch outcomes and VM lifecycle. |
| `Windows/AMORA.Orbit/AMORA.Orbit.csproj` | Embed complete runtime/model license notices for explicit Local Brain installation; keep version metadata unchanged. |
| `Windows/AMORA.Orbit/App.xaml` | Refine dark/cyan resources while preserving first-position standard WinUI control resources. |
| `Windows/AMORA.Orbit/App.xaml.cs` | Wire native media, provider dispatch, explicit memory, clipboard/workspace and UI dispatcher; dispose native/service ownership. |
| `Windows/AMORA.Orbit/Assets/Licenses/llama-cpp-MIT.txt` | Ship the complete MIT notice for the official pinned llama.cpp runtime. |
| `Windows/AMORA.Orbit/Assets/Licenses/Qwen-Apache-2.0.txt` | Ship the complete Apache 2.0 notice for the official pinned Qwen model assets. |
| `Windows/AMORA.Orbit/Interop/NativeMethods.cs` | Native window/display/foreground/fullscreen and motion/accessibility interop used by shell. |
| `Windows/AMORA.Orbit/MainWindow.xaml.cs` | Native size/state transitions, display/fullscreen response, focus/keyboard and shutdown lifecycle. |
| `Windows/AMORA.Orbit/Models/AISettings.cs` | Provider IDs/privacy options, fresh-install actual Local Brain default, selected catalog model; preserve persisted existing provider choices. |
| `Windows/AMORA.Orbit/Models/AmoraContextSnapshot.cs` | Keep unavailable telemetry/power truthful in owned-state summaries. |
| `Windows/AMORA.Orbit/Models/BatterySnapshot.cs` | Distinguish physical battery, known power and unavailable charge. |
| `Windows/AMORA.Orbit/Models/ChatMessage.cs` | Carry memory-derived provenance for cloud-history exclusion. |
| `Windows/AMORA.Orbit/Models/ClipboardEntry.cs` | Bounded local clipboard text/history presentation model. |
| `Windows/AMORA.Orbit/Models/ExplicitMemory.cs` | Explicit fact identity/timestamps, parsed command and load/recovery models. |
| `Windows/AMORA.Orbit/Models/GitHubActivity.cs` | Immutable real profile, repository, event, pull-request, contribution-day/calendar and action-result models. |
| `Windows/AMORA.Orbit/Models/LocalBrainModels.cs` | Pinned official runtime/model catalog, sizes/hashes/licenses, resource limits and observable installation/runtime states. |
| `Windows/AMORA.Orbit/Models/MascotExpression.cs` | Add authentic music, excited, bored, sleepy and concerned expressions and rendering parameters. |
| `Windows/AMORA.Orbit/Models/PresentationPreferences.cs` | Validated finite theme/size/opacity/motion/behavior/sound/module preferences with browser capture off by default. |
| `Windows/AMORA.Orbit/Models/SafeNavigation.cs` | Typed fixed application/known-folder targets and explicit navigation request results; no shell command strings. |
| `Windows/AMORA.Orbit/Models/SystemTelemetrySnapshot.cs` | Represent independent CPU/RAM availability and freshness. |
| `Windows/AMORA.Orbit/Models/TimerState.cs` | Timer state for monotonic countdown/recovery behavior. |
| `Windows/AMORA.Orbit/Models/WorkspaceItems.cs` | Immutable notes, path references, snapshots and action results. |
| `Windows/AMORA.Orbit/Services/BrowserBridge/BrowserHostRegistration.cs` | Explicit stable per-user host installation and pinned Chrome/Edge HKCU native-host registration/removal; no automatic registration. |
| `Windows/AMORA.Orbit/Services/BrowserBridge/BrowserWireProtocol.cs` | Shared bounded little-endian framing, strict UTF-8/JSON allowlist, safe YouTube URLs and current-user pipe identity. |
| `Windows/AMORA.Orbit/Services/BrowserBridge/IBrowserBridgeTransport.cs` | Injectable browser transport/events boundary for real pipe ownership and deterministic failure tests. |
| `Windows/AMORA.Orbit/Services/BrowserBridge/NamedPipeBrowserTransport.cs` | Actual current-user-only Windows named-pipe connection/read/write lifecycle without a network listener. |
| `Windows/AMORA.Orbit/Services/Contracts/IClipboardHistoryService.cs` | Clipboard capture/source/history boundaries for opt-in and tests. |
| `Windows/AMORA.Orbit/Services/Contracts/IExplicitMemoryService.cs` | Explicit command, own confirmation and injected storage contract. |
| `Windows/AMORA.Orbit/Services/Contracts/IGitHubActivityService.cs` | Explicit read-only GitHub connect/refresh/disconnect, saved-token availability, immutable snapshots and disposal contract. |
| `Windows/AMORA.Orbit/Services/Contracts/ILocalBrainRuntime.cs` | Injectable installed-asset/resource/runtime boundaries for real inference and network-free unit tests. |
| `Windows/AMORA.Orbit/Services/Contracts/ILocalBrainService.cs` | Unified installation, selection, generation, cancellation, deletion and owned local runtime lifecycle. |
| `Windows/AMORA.Orbit/Services/Contracts/IMediaService.cs` | Native media capability/refresh contract. |
| `Windows/AMORA.Orbit/Services/Contracts/ISafeNavigationService.cs` | Separate explicit command/confirmation service from typed Windows app/known-folder launching. |
| `Windows/AMORA.Orbit/Services/Contracts/ISuggestionService.cs` | Explicit reminder delivery independent of proactive opt-in. |
| `Windows/AMORA.Orbit/Services/Contracts/IWindowPositioningService.cs` | Geometry for compact, quick-home and workspace states. |
| `Windows/AMORA.Orbit/Services/Contracts/IWorkspaceToolsService.cs` | Workspace CRUD/query, injected storage and explicit native-launch boundary. |
| `Windows/AMORA.Orbit/Services/Implementations/AISettingsService.cs` | Serialize saves, atomically persist before updating active settings, surface failures. |
| `Windows/AMORA.Orbit/Services/Implementations/AssistantEngine.cs` | Integrate explicit memory and safe navigation before cloud routing, preserve bounded AI tools/confirmation, sanitize provider errors and memory provenance. |
| `Windows/AMORA.Orbit/Services/Implementations/BrowserMediaBridgeService.cs` | Opt-in live media metadata, truthful capabilities, matched tab/request acknowledgements, stale/timeout handling and disable cleanup. |
| `Windows/AMORA.Orbit/Services/Implementations/ClipboardHistoryService.cs` | Opt-in volatile history, limits/dedup, cancellation, explicit restore/clear. |
| `Windows/AMORA.Orbit/Services/Implementations/ClipboardPrivacyFilter.cs` | Sensitive-format and structured-secret exclusion without logging content. |
| `Windows/AMORA.Orbit/Services/Implementations/DeterministicCommandRouter.cs` | Preserve deterministic timer/command semantics needed by new controls. |
| `Windows/AMORA.Orbit/Services/Implementations/DpapiMemoryStorage.cs` | Separate encrypted user memory, atomic writes, corruption preservation and conflict protection. |
| `Windows/AMORA.Orbit/Services/Implementations/ExplicitMemoryService.cs` | Bounded explicit operations, unique-target safety, pending-clear lifecycle and rollback. |
| `Windows/AMORA.Orbit/Services/Implementations/GitHubActivityService.cs` | Official bounded read-only REST/GraphQL transport, public-user mode, optional DPAPI tokens, partial failure, cancellation and safe links/errors. |
| `Windows/AMORA.Orbit/Services/Implementations/HttpChatAIProvider.cs` | Real OpenAI/Anthropic protocol adapters with cancellation, privacy and safe errors. |
| `Windows/AMORA.Orbit/Services/Implementations/JsonWorkspaceStorage.cs` | Bounded versioned notes/reference persistence, atomic replacement and stale-writer protection. |
| `Windows/AMORA.Orbit/Services/Implementations/LlamaServerRuntime.cs` | Owned hidden Windows CPU inference process with private authenticated loopback transport, bounded context/generation and decisive native cancellation. |
| `Windows/AMORA.Orbit/Services/Implementations/LocalAutomationService.cs` | Durable mutation/occurrence reservation, rollback, recovery and visible errors. |
| `Windows/AMORA.Orbit/Services/Implementations/LocalBrainAIProvider.cs` | Route conversation into the actual on-device service without silent cloud fallback or implicit downloads. |
| `Windows/AMORA.Orbit/Services/Implementations/LocalBrainAssetStore.cs` | Explicit hash/size-verified runtime/model download and extraction, disk/RAM validation, cached setup and licensed asset publication. |
| `Windows/AMORA.Orbit/Services/Implementations/LocalBrainProcessJob.cs` | Windows kill-on-close job ownership for the inference child and cancellation/shutdown cleanup. |
| `Windows/AMORA.Orbit/Services/Implementations/LocalBrainService.cs` | Serialize model setup/start/generation/stop/delete, verify readiness, reject unavailable models and preserve truthful failure/cancel states. |
| `Windows/AMORA.Orbit/Services/Implementations/MediaCoordinatorService.cs` | One IMediaService chooses live browser/native playback for UI, assistant and automations instead of duplicate sources. |
| `Windows/AMORA.Orbit/Services/Implementations/MemoryCommandParser.cs` | Deterministic explicit save/recall/update/list/forget/clear grammar. |
| `Windows/AMORA.Orbit/Services/Implementations/MemoryPrivacyValidator.cs` | Sensitive-content validation and bounded fact shape. |
| `Windows/AMORA.Orbit/Services/Implementations/NavigationCommandParser.cs` | Recognize only explicit app/folder command grammar and fixed aliases; preserve reserved AMORA workspace navigation. |
| `Windows/AMORA.Orbit/Services/Implementations/PresentationPreferencesStore.cs` | Atomic validated JSON settings, visible load errors, original corruption preservation and committed-state publication after durable success. |
| `Windows/AMORA.Orbit/Services/Implementations/ProactiveSuggestionService.cs` | Distinct explicit reminder queue, cooldown/duplicate behavior and visible retryable action failure. |
| `Windows/AMORA.Orbit/Services/Implementations/RoutingAIProvider.cs` | Select exactly one configured provider and apply privacy boundary, no silent cloud fallback. |
| `Windows/AMORA.Orbit/Services/Implementations/SafeNavigationService.cs` | Allowlisted explicit app launch and expiring single-use folder confirmation with safe failure/cancel semantics. |
| `Windows/AMORA.Orbit/Services/Implementations/StandardTimerService.cs` | Elapsed-time/deadline countdown, once-only completion and generation invalidation. |
| `Windows/AMORA.Orbit/Services/Implementations/TaskbarTrayService.cs` | Reliable visible tray icon and recovery access. |
| `Windows/AMORA.Orbit/Services/Implementations/WindowsBatteryService.cs` | Truthful GetSystemPowerStatus failure/unknown/no-battery handling. |
| `Windows/AMORA.Orbit/Services/Implementations/WindowsClipboardSource.cs` | Native WinRT clipboard bridge with privacy markers and UI dispatch. |
| `Windows/AMORA.Orbit/Services/Implementations/WindowsCredentialStorage.cs` | Atomic DPAPI-only storage, zero temporary plaintext and surface deletion failures. |
| `Windows/AMORA.Orbit/Services/Implementations/WindowsFeedbackSoundService.cs` | Owned Windows notification audio for timer completion/explicit preview, honoring enabled/volume settings and disposal. |
| `Windows/AMORA.Orbit/Services/Implementations/WindowsMediaService.cs` | Real GSMTC polling, identity, capability checks, progress and command failures. |
| `Windows/AMORA.Orbit/Services/Implementations/WindowsSafeNavigationPlatform.cs` | Preflight fixed Calculator/Settings URI handlers; reject unavailable protocols and immediate Notepad/Paint stub exit, preserve fixed System paths and native known-folder resolution without arbitrary shell arguments. |
| `Windows/AMORA.Orbit/Services/Implementations/WindowsSystemTelemetryService.cs` | Real CPU/RAM sampling with independent unavailable/error handling. |
| `Windows/AMORA.Orbit/Services/Implementations/WindowsWindowPositioningService.cs` | DPI/work-area/top-center/monitor/fullscreen geometry and recovery. |
| `Windows/AMORA.Orbit/Services/Implementations/WindowsWorkspaceLauncher.cs` | Explicit StorageFile/StorageFolder/Launcher open/reveal without shell execution. |
| `Windows/AMORA.Orbit/Services/Implementations/WorkspacePathPolicy.cs` | Local drive path validation; reject URI/device/network/ADS and unsafe opens. |
| `Windows/AMORA.Orbit/Services/Implementations/WorkspaceToolsService.cs` | Local note CRUD/search and shelf reference/dedup/missing/pin operations. |
| `Windows/AMORA.Orbit/ViewModels/AssistantCommandViewModel.cs` | Expose current assistant/confirmation/result state to compact workspace interaction. |
| `Windows/AMORA.Orbit/ViewModels/AutomationsViewModel.cs` | UI-dispatched load/action errors and persistence feedback. |
| `Windows/AMORA.Orbit/ViewModels/BrowserBridgeViewModel.cs` | Explicit register/remove controls, status and package location with cancellation/disposal-safe notifications. |
| `Windows/AMORA.Orbit/ViewModels/ClipboardViewModel.cs` | History presentation and explicit local restore/clear with lifecycle guards. |
| `Windows/AMORA.Orbit/ViewModels/GitHubActivityViewModel.cs` | Explicit connect/refresh/disconnect UI, public/credential states, actual 28-week calendar, safe links and late-result protection. |
| `Windows/AMORA.Orbit/ViewModels/LocalBrainViewModel.cs` | Observable model selection/install/start/stop/cancel/remove and explicit provider selection with truthful progress/lifetime guards. |
| `Windows/AMORA.Orbit/ViewModels/MediaControlViewModel.cs` | Poll real session state, truthful control capability/failure and UI lifetime. |
| `Windows/AMORA.Orbit/ViewModels/OrbitViewModel.cs` | Shared compact/home/workspace state, navigation, new module wiring and lifecycle. |
| `Windows/AMORA.Orbit/ViewModels/PresentationViewModel.cs` | Live immutable appearance/behavior/module previews, explicit captured-snapshot saving and disposal-safe change events. |
| `Windows/AMORA.Orbit/ViewModels/RobotMascotViewModel.cs` | Drive authentic renderer states from deterministic interaction, priority, expiry, music/sleep/critical owned state and disposal. |
| `Windows/AMORA.Orbit/ViewModels/SettingsViewModel.cs` | Provider-specific selection/model/key controls, privacy settings and durable failure feedback. |
| `Windows/AMORA.Orbit/ViewModels/SuggestionViewModel.cs` | Real suggestion/reminder/disabled/retry state. |
| `Windows/AMORA.Orbit/ViewModels/SystemStatusViewModel.cs` | Actually refresh native services, UI dispatch and disposal-safe sampling loop. |
| `Windows/AMORA.Orbit/ViewModels/TimerControlViewModel.cs` | Bind timer lifecycle/controls through the shared service with UI dispatch. |
| `Windows/AMORA.Orbit/ViewModels/WorkspaceToolsViewModel.cs` | Notes/files editor and lists, drop/add/open/reveal, preserved failed-save drafts, disposal-safe callbacks. |
| `Windows/AMORA.Orbit/Views/GitHubPanelView.xaml` | Native GitHub profile/activity/repository/PR/calendar surface using real bound data and explicit connection states. |
| `Windows/AMORA.Orbit/Views/GitHubPanelView.xaml.cs` | Wire explicit read-only GitHub actions, actual contribution-day selection and safe native link opening. |
| `Windows/AMORA.Orbit/Views/MediaControlView.xaml` | Compact horizontal media region with truthful metadata and controls. |
| `Windows/AMORA.Orbit/Views/OrbitCapsuleView.xaml` | Reference-led compact capsule/home layout and accessible workspace navigation/settings/modules. |
| `Windows/AMORA.Orbit/Views/OrbitCapsuleView.xaml.cs` | Real navigation/input/control handlers, native file selection/drop integration, and the audited startup motion-preference correction. |
| `Windows/AMORA.Orbit/Views/RobotMascotView.xaml` | Recognizable native robot vector surface and interactive/accessibility shape. |
| `Windows/AMORA.Orbit/Views/RobotMascotView.xaml.cs` | Bind expressions, safe geometry ownership and deterministic eye/mouth/head rendering. |
| `Windows/AMORA.Orbit/Views/SettingsWindow.xaml` | Separate native category settings with real appearance, behavior, sound, providers, Local Brain, privacy, memory, modules and automation controls. |
| `Windows/AMORA.Orbit/Views/SettingsWindow.xaml.cs` | Bind settings categories, preview/save, native feedback, local model and explicit browser registration actions; own settings window lifecycle. |
| `Windows/AMORA.Orbit/Views/SuggestionBannerView.xaml` | Refine suggestion action/snooze/dismiss composition. |
| `Windows/AMORA.Orbit/Views/SystemStatusView.xaml` | Compact truthful battery/CPU/RAM status regions. |
| `Windows/AMORA.Orbit/Views/SystemStatusView.xaml.cs` | Keep compact real power/system presentation synchronized with the revised integrated island. |
| `Windows/AMORA.Orbit/Views/TimerControlView.xaml` | Compact presets/countdown/pause/resume/cancel controls. |
| `Windows/AMORA.sln` | Include the native browser host in coordinated solution builds alongside the WinUI app and xUnit tests. |
| `Windows/BROWSER_BRIDGE.md` | Document explicit host/extension setup, privacy/protocol/source-selection boundaries and honestly unverified native integration. |
| `Windows/CHANGE_INVENTORY.md` | Cumulative exact changed-file ledger against the inspected Git baseline, excluding ignored generated outputs. |
| `Windows/CONTINUATION_REPORT.md` | Separate current Mac-reference/GitHub/navigation/Local Brain/browser continuation evidence from the earlier accepted ZIP. |
| `Windows/GITHUB_NAVIGATION_MILESTONE.md` | Source-backed GitHub endpoint/navigation comparison, API shapes, implementation boundaries and actual public-account evidence. |
| `Windows/LOCAL_BRAIN.md` | Document official pins/licenses, explicit setup, private native runtime, source-of-truth differences and distinct test/UI evidence. |
| `Windows/MILESTONE_REPORT.md` | This source/change/evidence/gap ledger. |
| `Windows/PARITY_ROADMAP.md` | Evidence-backed baseline/current capability matrix, dependencies and acceptance criteria. |
| `Windows/Scripts/Publish-Release.ps1` | Shared local/CI fresh-directory self-contained app and browser-host publishing plus unchanged extension and manifest staging. |
| `Windows/Scripts/Test-ReleaseValidation.ps1` | Five meaningful validator cases: valid, missing host, changed extension, damaged PRI and traversal; no original payload mutation. |
| `Windows/Scripts/Validate-Release.ps1` | Full archive/version/runtime/x64/hash validation now also requires a correctly versioned self-contained host and byte-identical pinned extension. |
| `Windows/VALIDATION.md` | Reproducible native build/test/publish/ZIP and separate interactive acceptance instructions. |
