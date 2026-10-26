# AMORA Windows parity milestone — implementation and verification ledger

This report records the first completed increment. Newer source, browser-host packaging and Mac-reference continuation work have their own status in [CONTINUATION_REPORT.md](CONTINUATION_REPORT.md); the results below do not automatically validate those later changes.

All working-tree, workflow, provider and Git statements below describe that historical increment. The final checkpoint audit supersedes them where implementation progressed. Evidence filenames identify local collaboration artifacts deliberately excluded from Git; they are not repository links or distributable packages. Commands use portable task-relative SDK paths instead of personal machine paths.

This is a substantial M1–M3 increment, **not a claim of complete Mac parity or permission to publish a beta**. The final Release build has zero warnings/errors, all **477 tests pass**, and the validated self-contained ZIP visibly launched on this Windows machine with real workspace interactions. The final diagnostic interval contains no AMORA Application errors or new crash-log entries, and Alt+F4 cleanly exited the tested process. The source-backed baseline and current status register are in [PARITY_ROADMAP.md](PARITY_ROADMAP.md). Read the final verification section below; earlier results apply only to their intermediate working trees.

## Repository and release baseline

- Repository: `https://github.com/mohammedomarworks/AMORA.git`; branch `main`; starting and current HEAD `8c166706cb71134ae8db256fc861af36b9288f04`. Work remains uncommitted. No staging, commit, push, tag move, or public release was performed.
- Initial repository checkout was clean. All implementation edits are under `Windows/`; the Mac implementation and `.github/workflows/windows-orbit.yml` remain unchanged.
- Windows app/test/informational version is `0.6.0-beta.2`; assembly and file version are `0.6.0.0`. `Windows/RELEASE_MANIFEST.md` names `AMORA.Orbit-v0.6.0-beta.2-win-x64.zip`. Root `VERSION` belongs to the Mac product and remains `1.0.0`.
- Read-only tag inspection: `v0.6.0-beta` → `7d18aa7`, `v0.6.0-beta.1` → `e033a2e`, `v0.6.0-beta.2` → `8c16670`; separate Mac tag `v1.0.0-beta.1` → `ccc8c27`. Existing tags were not retargeted. Local test packages with the unchanged version are development acceptance artifacts, not replacements for that public release.
- The downloaded existing [v0.6.0-beta.2 release ZIP](https://github.com/mohammedomarworks/AMORA/releases/tag/v0.6.0-beta.2) was 66,588,553 bytes, SHA-256 `a0ce58f35a532b3cabb815cd87bd9185261b2fa919f3db0e07d9d768f9cc599f`; digest matched GitHub asset metadata. It contained 436 files. This verifies the inspected existing artifact, not newly edited source.
- Build host: actual Windows machine; recorded display inventory reports Windows NT `10.0.26300.0`, one 1920×1080 display at 96 DPI/100%. Local .NET SDK `8.0.427` was installed inside this task's `work/dotnet`. No Visual Studio installation was required for the repaired non-UI test project.

## Actual source inspection

Mac implementation inspected includes `Sources/AMORA/Core` window/notch/island geometry, command and deterministic routing, `AIProvider.swift`, `AITools.swift`, conversation/provenance, agent loop, contextual follow-ups, event sink and personality; mascot/robot drawing and island pages; `Settings/Preferences.swift`; module services for timers, music/browser media, battery/system monitoring, clipboard, notes, file shelf and GitHub; and the complete `Memory/` implementation. The parity matrix cites the specific service/test for every capability, including local inference, automation and platform-only gaps.

Behavioral tests consulted include `MemoryV1Tests.swift`, `AmoraNoteSearchTests.swift`, shelf persistence/dedup/missing/drop tests in `AMORATests.swift`, `AmoraEventSinkTests.swift`, `ActionEngineTests.swift`, `AmoraAgentLoopTests.swift`, `FreshInstallAITests.swift`, `PreBetaStabilityTests.swift`, timer/context/personality tests, and automation/browser/GitHub tests cited in the matrix. Notes search must preserve distinct records even if content matches. Memory is explicit and separately stored; remote providers exclude memory provenance. Mac file shelf stores path/bookmark references and tracks missing originals.

Windows inspection covered the solution/app/test projects; App/MainWindow/resource dictionaries; all existing views, viewmodels, service contracts/models and implementations; AI/Gemini credentials and bounded action execution; timer/media/system/suggestion/automation flows; interop/hotkey/tray/window positioning and lifecycle; existing xUnit tests; release manifest/project metadata; publish profiles; and the full CI workflow's version, architecture, runtime and archive checks.

## Startup defects and corrective evidence

The checked-out `App.xaml` already contained the reported `XamlControlsResources` fix **first** in `Application.Resources.MergedDictionaries`, and its regression test existed. That order was preserved. A broader source-fixture resource test now checks application-owned resource references across all views. This source check cannot establish that every WinUI control loads successfully; actual XAML construction/launch is recorded separately.

The first .NET-only solution build compiled the app but the non-UI xUnit project failed loading Visual Studio-only PRI packaging tasks (`ExpandPriContent`, subsequently `RemovePayloadDuplicates`). Selecting the NuGet Windows App SDK tasks with `EnableMsixTooling`, unpackaged `WindowsPackageType=None`, and disabling unnecessary PRI generation **only in the non-UI test host** fixed that build prerequisite. The application's XAML/PRI pipeline was retained.

New UI construction exposed real errors rather than being accepted on compilation alone: invalid `IsEnabled` on `StackPanel` was diagnosed with the underlying XAML compiler task and moved to interactive controls; a mascot `E_INVALIDARG` was traced to geometry retaining its temporary XAML parser owner, then fixed by detaching geometry before assigning it to the visible vector path. Startup exceptions remain logged and rethrown. Final successful launch and diagnostic interval must be confirmed below.

## Functional and visual increment

- Replaced the large permanent panel with a compact 176×34 DIP top-center capsule, a wide 860×300 DIP quick-home island, and an explicitly selected taller workspace. The reference's companion/suggestion/media/timer/power/system composition drives the home view. Dark charcoal surfaces, restrained cyan, shallow rows and consistent radii preserve AMORA identity.
- Native shell handles retained HWND ownership, DPI conversion, work-area bounds, display changes, foreground monitor placement, fullscreen suppression, tray/hotkey access, Escape/keyboard behavior and reduced-motion-aware transitions. Unit geometry checks are separate from unavailable physical multi-monitor/DPI tests.
- Actual AMORA-inspired vector expressions are connected to the existing mascot state model and interaction/event reactions. Static decorative eyes were replaced by state-driven shapes. Geometry is fixed application-owned markup, never model/user supplied XAML.
- Replaced production preview-media injection with Windows GSMTC; truthful track/session/capabilities, elapsed progress and command outcomes are displayed. Generic browser sessions no longer pretend to be verified YouTube. Timer countdown uses monotonic elapsed time/deadlines, preserves pause/resume/adjustment, and completes once despite delayed callbacks.
- Battery/CPU/RAM are resampled on cadence, dispatched to UI safely, and show unavailable/stale state instead of invented 0% CPU or desktop AC. Physical battery presence remains distinguishable from unknown charge.
- Added explicit bounded save/recall/list/update/forget memory, conservative ambiguity refusal, clear-all confirmation/expiry, DPAPI user-bound encryption, atomic commit before publishing cache, corrupt-file preservation, stale-writer protection and secret rejection. Memory commands stay out of cloud conversation history.
- Added real OpenAI and Anthropic HTTP adapters alongside Gemini, selected-provider dispatch, official endpoint restrictions, secure credential selection, bounded payloads/responses, cancellation and sanitized error messages. Tests use fake HTTP transport; no real key or paid connection was provisioned or exercised. Apple FoundationModels and Windows Local Brain inference are not implemented.
- Added default-off, volatile 15-item clipboard history with native privacy-format checks before reading text, structured-secret filtering, cancellation/generation guards, explicit private restore and clear/disable behavior. No screenshots, file contents, keystrokes or Windows clipboard-history retrieval are collected.
- Added local note CRUD/search/pin and file/folder reference shelf, batch drop/add, deduplication, pin/remove, missing-state refresh, safe Windows open/reveal, bounded atomic JSON persistence and stale-writer/corrupt-file safety. Shelf does not copy, read or index original file contents. Executables/scripts/macros/shortcuts/URIs/network/device/ADS and redirected-path opening are blocked; original documents are never deleted by removing a reference.
- Automation mutations are persisted before activation, occurrences are reserved before side effects, persistence failures remain visible, and explicit reminder delivery no longer depends on enabling proactive suggestions. Missed recurring schedules are skipped/rescheduled, not replayed in a burst. Durable reservation favors avoiding duplicate effects; it is not an exactly-once transaction with external media players.
- Settings persist before updating active state; DPAPI is mandatory for Windows credentials, plaintext byte buffers are cleared, write/delete failures propagate, and no plaintext non-Windows fallback remains. UI callbacks use dispatch/lifecycle guards where changed.

## Changed files and reasons

Paths below are relative to `Windows/`. This ledger lists modified tracked files and new source/docs/scripts, not generated `bin`, `obj`, extracted packages or tool scratch files. It describes the current working-tree increment, including final integration edits still being validated.

| File | Reason |
|---|---|
| `.gitignore` | Ignore Windows build/test output and binary build logs without hiding source or release evidence. |
| `AMORA.Orbit/App.xaml` | Refine dark/cyan resources while preserving first-position standard WinUI control resources. |
| `AMORA.Orbit/App.xaml.cs` | Wire native media, provider dispatch, explicit memory, clipboard/workspace and UI dispatcher; dispose native/service ownership. |
| `AMORA.Orbit/MainWindow.xaml.cs` | Native size/state transitions, display/fullscreen response, focus/keyboard and shutdown lifecycle. |
| `AMORA.Orbit/Interop/NativeMethods.cs` | Native window/display/foreground/fullscreen and motion/accessibility interop used by shell. |
| `AMORA.Orbit/Models/AISettings.cs` | Provider IDs and explicit memory/clipboard/privacy feature settings. |
| `AMORA.Orbit/Models/AmoraContextSnapshot.cs` | Keep unavailable telemetry/power truthful in owned-state summaries. |
| `AMORA.Orbit/Models/BatterySnapshot.cs` | Distinguish physical battery, known power and unavailable charge. |
| `AMORA.Orbit/Models/ChatMessage.cs` | Carry memory-derived provenance for cloud-history exclusion. |
| `AMORA.Orbit/Models/SystemTelemetrySnapshot.cs` | Represent independent CPU/RAM availability and freshness. |
| `AMORA.Orbit/Models/TimerState.cs` | Timer state for monotonic countdown/recovery behavior. |
| `AMORA.Orbit/Models/ClipboardEntry.cs` | Bounded local clipboard text/history presentation model. |
| `AMORA.Orbit/Models/ExplicitMemory.cs` | Explicit fact identity/timestamps, parsed command and load/recovery models. |
| `AMORA.Orbit/Models/WorkspaceItems.cs` | Immutable notes, path references, snapshots and action results. |
| `AMORA.Orbit/Services/Contracts/IMediaService.cs` | Native media capability/refresh contract. |
| `AMORA.Orbit/Services/Contracts/ISuggestionService.cs` | Explicit reminder delivery independent of proactive opt-in. |
| `AMORA.Orbit/Services/Contracts/IWindowPositioningService.cs` | Geometry for compact, quick-home and workspace states. |
| `AMORA.Orbit/Services/Contracts/IClipboardHistoryService.cs` | Clipboard capture/source/history boundaries for opt-in and tests. |
| `AMORA.Orbit/Services/Contracts/IExplicitMemoryService.cs` | Explicit command, own confirmation and injected storage contract. |
| `AMORA.Orbit/Services/Contracts/IWorkspaceToolsService.cs` | Workspace CRUD/query, injected storage and explicit native-launch boundary. |
| `AMORA.Orbit/Services/Implementations/AISettingsService.cs` | Serialize saves, atomically persist before updating active settings, surface failures. |
| `AMORA.Orbit/Services/Implementations/AssistantEngine.cs` | Handle explicit memory locally with confirmation and keep memory out of cloud conversation. |
| `AMORA.Orbit/Services/Implementations/DeterministicCommandRouter.cs` | Preserve deterministic timer/command semantics needed by new controls. |
| `AMORA.Orbit/Services/Implementations/LocalAutomationService.cs` | Durable mutation/occurrence reservation, rollback, recovery and visible errors. |
| `AMORA.Orbit/Services/Implementations/ProactiveSuggestionService.cs` | Distinct explicit reminder queue, cooldown/duplicate behavior and visible retryable action failure. |
| `AMORA.Orbit/Services/Implementations/StandardTimerService.cs` | Elapsed-time/deadline countdown, once-only completion and generation invalidation. |
| `AMORA.Orbit/Services/Implementations/TaskbarTrayService.cs` | Reliable visible tray icon and recovery access. |
| `AMORA.Orbit/Services/Implementations/WindowsBatteryService.cs` | Truthful GetSystemPowerStatus failure/unknown/no-battery handling. |
| `AMORA.Orbit/Services/Implementations/WindowsCredentialStorage.cs` | Atomic DPAPI-only storage, zero temporary plaintext and surface deletion failures. |
| `AMORA.Orbit/Services/Implementations/WindowsMediaService.cs` | Real GSMTC polling, identity, capability checks, progress and command failures. |
| `AMORA.Orbit/Services/Implementations/WindowsSystemTelemetryService.cs` | Real CPU/RAM sampling with independent unavailable/error handling. |
| `AMORA.Orbit/Services/Implementations/WindowsWindowPositioningService.cs` | DPI/work-area/top-center/monitor/fullscreen geometry and recovery. |
| `AMORA.Orbit/Services/Implementations/ClipboardHistoryService.cs` | Opt-in volatile history, limits/dedup, cancellation, explicit restore/clear. |
| `AMORA.Orbit/Services/Implementations/ClipboardPrivacyFilter.cs` | Sensitive-format and structured-secret exclusion without logging content. |
| `AMORA.Orbit/Services/Implementations/WindowsClipboardSource.cs` | Native WinRT clipboard bridge with privacy markers and UI dispatch. |
| `AMORA.Orbit/Services/Implementations/DpapiMemoryStorage.cs` | Separate encrypted user memory, atomic writes, corruption preservation and conflict protection. |
| `AMORA.Orbit/Services/Implementations/ExplicitMemoryService.cs` | Bounded explicit operations, unique-target safety, pending-clear lifecycle and rollback. |
| `AMORA.Orbit/Services/Implementations/MemoryCommandParser.cs` | Deterministic explicit save/recall/update/list/forget/clear grammar. |
| `AMORA.Orbit/Services/Implementations/MemoryPrivacyValidator.cs` | Sensitive-content validation and bounded fact shape. |
| `AMORA.Orbit/Services/Implementations/HttpChatAIProvider.cs` | Real OpenAI/Anthropic protocol adapters with cancellation, privacy and safe errors. |
| `AMORA.Orbit/Services/Implementations/RoutingAIProvider.cs` | Select exactly one configured provider and apply privacy boundary, no silent cloud fallback. |
| `AMORA.Orbit/Services/Implementations/JsonWorkspaceStorage.cs` | Bounded versioned notes/reference persistence, atomic replacement and stale-writer protection. |
| `AMORA.Orbit/Services/Implementations/WorkspacePathPolicy.cs` | Local drive path validation; reject URI/device/network/ADS and unsafe opens. |
| `AMORA.Orbit/Services/Implementations/WindowsWorkspaceLauncher.cs` | Explicit StorageFile/StorageFolder/Launcher open/reveal without shell execution. |
| `AMORA.Orbit/Services/Implementations/WorkspaceToolsService.cs` | Local note CRUD/search and shelf reference/dedup/missing/pin operations. |
| `AMORA.Orbit/ViewModels/AssistantCommandViewModel.cs` | Expose current assistant/confirmation/result state to compact workspace interaction. |
| `AMORA.Orbit/ViewModels/AutomationsViewModel.cs` | UI-dispatched load/action errors and persistence feedback. |
| `AMORA.Orbit/ViewModels/MediaControlViewModel.cs` | Poll real session state, truthful control capability/failure and UI lifetime. |
| `AMORA.Orbit/ViewModels/OrbitViewModel.cs` | Shared compact/home/workspace state, navigation, new module wiring and lifecycle. |
| `AMORA.Orbit/ViewModels/RobotMascotViewModel.cs` | Map supported expression moods to real renderer state/reactions. |
| `AMORA.Orbit/ViewModels/SettingsViewModel.cs` | Provider-specific selection/model/key controls, privacy settings and durable failure feedback. |
| `AMORA.Orbit/ViewModels/SuggestionViewModel.cs` | Real suggestion/reminder/disabled/retry state. |
| `AMORA.Orbit/ViewModels/SystemStatusViewModel.cs` | Actually refresh native services, UI dispatch and disposal-safe sampling loop. |
| `AMORA.Orbit/ViewModels/TimerControlViewModel.cs` | Bind timer lifecycle/controls through the shared service with UI dispatch. |
| `AMORA.Orbit/ViewModels/ClipboardViewModel.cs` | History presentation and explicit local restore/clear with lifecycle guards. |
| `AMORA.Orbit/ViewModels/WorkspaceToolsViewModel.cs` | Notes/files editor and lists, drop/add/open/reveal, preserved failed-save drafts, disposal-safe callbacks. |
| `AMORA.Orbit/Views/MediaControlView.xaml` | Compact horizontal media region with truthful metadata and controls. |
| `AMORA.Orbit/Views/OrbitCapsuleView.xaml` | Reference-led compact capsule/home layout and accessible workspace navigation/settings/modules. |
| `AMORA.Orbit/Views/OrbitCapsuleView.xaml.cs` | Real navigation/input/control handlers and native file selection/drop integration. |
| `AMORA.Orbit/Views/RobotMascotView.xaml` | Recognizable native robot vector surface and interactive/accessibility shape. |
| `AMORA.Orbit/Views/RobotMascotView.xaml.cs` | Bind expressions, safe geometry ownership and deterministic eye/mouth/head rendering. |
| `AMORA.Orbit/Views/SuggestionBannerView.xaml` | Refine suggestion action/snooze/dismiss composition. |
| `AMORA.Orbit/Views/SystemStatusView.xaml` | Compact truthful battery/CPU/RAM status regions. |
| `AMORA.Orbit/Views/TimerControlView.xaml` | Compact presets/countdown/pause/resume/cancel controls. |
| `AMORA.Orbit.Tests/AMORA.Orbit.Tests.csproj` | .NET-only non-UI test task fix and broader XAML source fixtures; app PRI retained. |
| `AMORA.Orbit.Tests/ApplicationResourcesTests.cs` | Preserve standard-resource-first regression and validate application resource references across views. |
| `AMORA.Orbit.Tests/AssistantCommandViewModelTests.cs` | Regress assistant result/busy/confirmation presentation changes. |
| `AMORA.Orbit.Tests/AutomationsViewModelTests.cs` | Overlong-name validation and restored persisted row state after a failed toggle. |
| `AMORA.Orbit.Tests/DeterministicCommandRouterTests.cs` | Regress actual relative timer adjustment command semantics. |
| `AMORA.Orbit.Tests/PositioningServiceTests.cs` | Compact/home/workspace geometry, DPI, invalid monitors and fullscreen exclusions. |
| `AMORA.Orbit.Tests/ProactiveSuggestionEngineTests.cs` | Truthful disabled state and visible retry behavior after action failure. |
| `AMORA.Orbit.Tests/PublicBetaReadinessTests.cs` | Assert corrupt automation recovery is reported rather than silently ignored. |
| `AMORA.Orbit.Tests/SettingsViewModelTests.cs` | Align provider selection and supported/unavailable state expectations. |
| `AMORA.Orbit.Tests/AutomationReliabilityTests.cs` | Mutation rollback, concurrent occurrence execution, result persistence and explicit reminders. |
| `AMORA.Orbit.Tests/ClipboardHistoryTests.cs` | Fake-source opt-in/privacy/cancel/restore/limit/lifecycle boundaries; no user's clipboard used. |
| `AMORA.Orbit.Tests/CloudProviderParityTests.cs` | Mocked endpoint/header/schema/history/provenance/cancel/error/selection behavior. |
| `AMORA.Orbit.Tests/ExplicitMemoryTests.cs` | Explicit grammar/privacy/lifecycle/ambiguity/rollback/limits and actual temporary DPAPI reload/corruption/conflict. |
| `AMORA.Orbit.Tests/LiveSystemStatusTests.cs` | Actual resampling cadence, unknown/error metrics and UI/disposal dispatch. |
| `AMORA.Orbit.Tests/MascotViewModelTests.cs` | Mood/expression parity and deterministic interaction mapping. |
| `AMORA.Orbit.Tests/OrbitWindowLifecycleTests.cs` | Native shell workspace/visibility/navigation/disposal behavior. |
| `AMORA.Orbit.Tests/SettingsPersistenceTests.cs` | Atomic settings/error handling and protected credential lifecycle. |
| `AMORA.Orbit.Tests/TimerDeadlineTests.cs` | Callback delays, pause/resume, adjustment, once-only completion and disposal. |
| `AMORA.Orbit.Tests/ViewModelShutdownTests.cs` | Queued callbacks and in-flight work do not update closed viewmodels after disposal. |
| `AMORA.Orbit.Tests/WindowsMediaServiceTests.cs` | Real service transport abstraction/capability/error/polling behavior. |
| `AMORA.Orbit.Tests/WorkspaceToolsTests.cs` | Distinct note search, CRUD/pin, storage failure/conflict/corruption, reference-only persistence, unsafe path/type rejection, launch outcomes and VM lifecycle. |
| `PARITY_ROADMAP.md` | Evidence-backed baseline/current capability matrix, dependencies and acceptance criteria. |
| `Scripts/Validate-Release.ps1` | Local full-file ZIP/hash/runtime/native architecture/version checks plus optional separately labeled process smoke. |
| `Scripts/Test-ReleaseValidation.ps1` | Meaningful validator regressions for valid, tampered-resource and traversal archives. |
| `VALIDATION.md` | Reproducible native build/test/publish/ZIP and separate interactive acceptance instructions. |
| `MILESTONE_REPORT.md` | This source/change/evidence/gap ledger. |

## Recorded verification before final integration

| Layer/run | Actual observation | Limit |
|---|---|---|
| Initial .NET-only test run after task fix | 269 tests: 262 passed, seven positioning assertions failed because new geometry was being integrated. Both resource regression tests passed. | An intermediate working tree, not pristine baseline and not final green acceptance. |
| First island run | `island-milestone.trx`: 314 total, 313 passed, one suggestion wording/state expectation failed. | Superseded by later memory run. |
| Island + memory build | `work/island-build.log`: Release solution built, 0 warnings/0 errors. | Does not include later workspace/clipboard changes. |
| Island + memory tests | `outputs/evidence/test-results/island-memory.trx`: **378/378 passed**, zero skipped. | Intermediate verified source only. |
| Later service integration build | `work/integrated-build.log`: Release solution built, 0 warnings/0 errors. | Before clipboard/workspace final integration. |
| Later service integration tests | `outputs/evidence/test-results/integrated-services.trx`: **405/407 passed**. Two old assertions expected silent corrupt-automation fallback and dismissal of failed suggestion actions. | Those assertions were strengthened to require visible recovery/retry; final rerun required. All ten new automation reliability tests passed in this run. |
| Workspace/clipboard integration build | `work/integrated-build-final.log`: Release solution built, 0 warnings/0 errors. | Subsequent flyout-collapse and late-disposal changes still require a final rebuild. |
| Workspace/clipboard integration tests | `outputs/evidence/test-results/workspace-integrated.trx` and `work/workspace-integrated-tests.log`: **470/470 passed**, zero skipped. | This is the most recent completed green suite before the final source fixes. It does not establish UI or package acceptance. |
| Subsequent rebuild attempt | `work/final-integrated-build.log`: MSB3027/MSB3021 copying apphost because the running test AMORA process held the executable open. | A file-lock verification failure, not a source compiler diagnostic. Close the owned app and rerun before final acceptance. |
| Existing public beta package | Local validator passed metadata/x64/self-contained runtime and 436 full ZIP file/hash comparisons. | Comparison directory came from the same downloaded official ZIP, not an independent source rebuild. Process smoke was not requested in this baseline check. |
| Validator regressions | Valid archive accepted; modified `resources.pri` rejected by hash; `../must-not-exist.txt` rejected before extraction. All three cases passed. | Tests validate the validator, not actual UI behavior. |
| Recorded display | One 1920×1080/96 DPI display. | Physical monitor removal, alternate DPI and real fullscreen games/presentations require further hardware/manual acceptance. |
| Native media fixture | Paused JSON at 17:18:04Z contains `pause`; resumed JSON at 17:19:10Z contains `pause`,`play` and Playing state. | Dedicated real Windows media verification fixture, not Spotify/Apple Music/YouTube acceptance. |
| Live timer controls | Started the 5-minute preset, observed countdown, paused, then added one minute; display became 05:56. | Exercised on the earlier integrated executable; `evidence/island-expanded-timer.png` (timer capture). Final ZIP startup reused the tested service, but this timer sequence was not repeated there. |
| Notes interaction | Integration owner saved a note through the actual workspace UI; `notes-saved.png` records the result. | Edit/delete/pin/search/restart and the actual packaged build remain separate acceptance checks. |
| Fullscreen avoidance | A 1920×1080 fullscreen fixture hid AMORA; native app inventory reported it hidden. Escape restored the same workspace; before/after captures retained. | This verifies the tested fixture on the single display, not every game/presentation or monitor arrangement. |
| Crash diagnostic checkpoint | Integration owner observed crash log unchanged at 11,005 bytes with last-write time 17:13:46 UTC after these interactions. | Final ZIP launch interval and Event Viewer results must still be recorded. Earlier diagnostic exceptions remain in the log intentionally. |

Exact command executed for the initial test audit (from repository root; task paths shown explicitly):

```powershell
& '../../work/dotnet/dotnet.exe' test Windows/AMORA.Orbit.Tests/AMORA.Orbit.Tests.csproj --configuration Release --no-build --no-restore /p:Platform=x64 --verbosity normal --logger 'trx;LogFileName=baseline-release-audit.trx' --results-directory '../../work/test-results'
```

Supported reproduction commands, distinct from the executed final command ledger, are in [VALIDATION.md](VALIDATION.md). The integration owner will append the exact final build/test/publish/launch commands and artifacts below.

### Captured intermediate application evidence

These files exist under `outputs/evidence/`. They are actual application captures retained by the integration owner; they are not substitutes for final-package acceptance. Paths are relative to this report:

- `evidence/baseline-expanded.png` (Baseline expanded app)
- `evidence/island-collapsed.png` (Compact island)
- `evidence/island-expanded-timer.png` (Expanded island and running timer)
- `evidence/mascot-click-reaction.png` (Mascot click reaction)
- `evidence/memory-save-recall.png` (Explicit memory save/recall)
- `evidence/native-media-paused.png` (Native media pause), `evidence/native-media-paused.json` (pause state), `evidence/native-media-resumed.json` (resume state)
- `evidence/display-inventory.json` (Display inventory)
- `evidence/integrated-expanded.png` (Integrated expanded island), `evidence/notes-saved.png` (note saved in actual UI)
- `evidence/fullscreen-avoidance.png` (Fullscreen fixture with island hidden), `evidence/fullscreen-restored.png` (workspace restored after Escape)
- `evidence/test-results/island-memory.trx` (378-test TRX), `evidence/test-results/integrated-services.trx` (407-test intermediate TRX), `evidence/test-results/workspace-integrated.trx` (470-test passing TRX)

## Outstanding acceptance and platform differences

1. Full Mac parity remains unachieved. Local Brain runtime/model acquisition/inference, Apple-only FoundationModels, browser native messaging/precise YouTube support, Mac GitHub module, volume/brightness controls, broader application/known-folder routing, and remaining event/conditional automation scope are not covered by this increment.
2. Real cloud provider account/model access and credential connection tests remain unverified. Protocol tests use mocked HTTP only. Model IDs must be supplied explicitly for OpenAI/Anthropic; no untested provider/model is advertised as operational.
3. Final integrated source tests passed; note save/restart/body loading/delete, memory recall/targeted forget and folder reference/native open/removal were exercised from the extracted ZIP. Clipboard opt-in/capture/restore, actual drag-and-drop, document open/Explorer reveal, note edit/pin/search and broader error/restart combinations remain unverified manually. After popups, UI Automation inspection sometimes exposed only PopupHost; visual and keyboard paths were tested, but full Narrator, high-contrast and reduced-motion acceptance remain unverified.
4. Windows file references do not have Mac security-scoped bookmarks and will become missing when originals move. Reparse/redirected paths, network shares, executable/script/shortcut/macro opening are conservatively unavailable. No arbitrary shell is exposed; app launch parity is not claimed.
5. Automation recovery skips/reschedules missed occurrences, unlike Mac catch-up behavior. Pre-action reservation prevents replay but a crash can lose that occurrence; post-action persistence failure reports that the action already ran. Multiple AMORA processes sharing automation storage are not yet supported.
6. Clipboard privacy depends partly on source-app format markers; structured-secret filtering is conservative, not proof of detecting every sensitive text. AMORA rejects some explicitly history-enabled content conservatively and stores history only in memory. Notes are explicit local JSON; persistent assistant memory/credentials are separately DPAPI protected.
7. The one available monitor verifies only 100% DPI on that machine. Alternate scaling, multiple monitors, disconnection/recovery, real fullscreen presentation/game avoidance, physical battery charging/unplug, and arm64 execution remain separate acceptance requirements.
8. The final development ZIP passed package checks, visibly launched, exercised the interactions below and closed cleanly with no new crash entries or AMORA Application-log errors in the recorded interval. Public beta publication remains inappropriate while substantial parity gaps remain; the local unchanged-version package must not replace or retarget the existing public beta.

## Final integrated verification

The integration owner ran these steps against the uncommitted Windows working tree based on `8c166706cb71134ae8db256fc861af36b9288f04`. This includes the late flyout-collapse and disposal fixes. No version metadata, public tag or release was changed.

Executed build, test, publish and validation commands, from `outputs/AMORA`:

```powershell
$amoraDotnet = '../../work/dotnet/dotnet.exe'
& $amoraDotnet build Windows/AMORA.sln --configuration Release /p:Platform=x64 --no-restore --verbosity minimal
& $amoraDotnet test Windows/AMORA.Orbit.Tests/AMORA.Orbit.Tests.csproj --configuration Release --no-build --no-restore /p:Platform=x64 --verbosity minimal --logger 'trx;LogFileName=acceptance.trx' --results-directory ../../outputs/evidence/test-results
& $amoraDotnet publish Windows/AMORA.Orbit/AMORA.Orbit.csproj --configuration Release --runtime win-x64 --self-contained true /p:Platform=x64 /p:WindowsAppSDKSelfContained=true --output ../development-validation/publish
Copy-Item Windows/RELEASE_MANIFEST.md ../development-validation/publish/RELEASE_MANIFEST.md
Compress-Archive -Path ../development-validation/publish/* -DestinationPath ../development-validation/AMORA.Orbit-v0.6.0-beta.2-win-x64.zip
./Windows/Scripts/Validate-Release.ps1 -PublishDirectory ../development-validation/publish -ArchivePath ../development-validation/AMORA.Orbit-v0.6.0-beta.2-win-x64.zip -ExtractionDirectory ../development-validation/extracted -ReportPath ../evidence/package-validation.json
./Windows/Scripts/Test-ReleaseValidation.ps1 -PublishDirectory ../development-validation/publish -ArchivePath ../development-validation/AMORA.Orbit-v0.6.0-beta.2-win-x64.zip -TestDirectory ../../work/package-regression-final
```

The result files below preserve the command output. The validator's process-smoke option was not used. The extracted executable was launched and inspected separately, so its native UI evidence does not come from the package script.

| Evidence layer | Final result | Evidence/limit |
|---|---|---|
| Release x64 build | **Passed**, 0 warnings, 0 errors | `evidence/acceptance-build.log` (acceptance-build.log), 12.04 seconds. |
| Full xUnit suite | **477 executed, 477 passed, 0 failed, 0 skipped** | `evidence/test-results/acceptance.trx` (acceptance.trx), `evidence/acceptance-tests.log` (test output). Includes explicit memory, cloud mock transport, clipboard fake-source boundaries, notes/shelf, timer/media, automation and late shutdown regressions. |
| Self-contained publish | **Succeeded** | `evidence/acceptance-publish.log` (acceptance-publish.log); output `outputs/development-validation/publish`. |
| ZIP integrity/native architecture | **Passed**; 437 files, 66,704,902 bytes | `evidence/package-validation.json` (package-validation.json): complete publish/extraction file and SHA-256 matching, x64 native headers, required self-contained runtime and consistent version/manifest. |
| ZIP SHA-256 | `a72499e5e56293135815f400ec759d7c9c5c7d0b94a6a8619860da376021b84f` | `development-validation/AMORA.Orbit-v0.6.0-beta.2-win-x64.zip` (Local development-validation ZIP). Different artifact from the existing public beta; no public release/replacement performed. |
| Validator negative tests | **3/3 passed** | `evidence/package-regression-final.log` (package-regression-final.log): valid accepted, changed `resources.pri` rejected, traversal entry rejected before extraction. |
| Extracted executable startup | **Actual process and visible UI verified** | PID 34656; `outputs/development-validation/extracted/AMORA.Orbit.exe`. This was the extracted ZIP app, not merely the build directory. |
| Compact/expanded rendering | **Verified** | `evidence/zip-collapsed.png` (ZIP compact), `evidence/zip-expanded.png` (ZIP expanded). Main controls render; reported `TabViewButtonBackground` failure did not occur during this launch. |
| Final crash/Event Viewer interval | **Passed for the observed interval** | `evidence/runtime-diagnostics.json` (runtime-diagnostics.json): 17:26:45.4756925–17:35:58.5003886 UTC (23:26:45–23:35:58 local); zero AMORA Application Error/.NET Runtime/Windows Error Reporting events. Crash log remained 11,005 bytes, last write 17:13:46.2465384 UTC; earlier diagnostic entries were retained, not erased. |
| Final graceful shutdown | **Verified** | Alt+F4 closed extracted-ZIP PID 34656; process lookup confirmed it absent. Native verification fixtures were stopped. Runtime diagnostics records `ProcessRunningAfterAltF4=false`. |

### Controls actually exercised from the extracted ZIP

| Interaction | Observed behavior | Evidence/limit |
|---|---|---|
| Notes persistence | A note saved in the earlier actual UI survived restart; selecting it loaded its saved body. | `evidence/zip-note-persisted.png` (Persisted note). Broader notes operations remain covered by tests but not all manually exercised. |
| Explicit memory persistence | Earlier synthetic explicitly saved memory could be recalled after restarting from the ZIP. | `evidence/zip-memory-persisted.png` (Persisted memory recall). No automatic capture or cloud memory injection was used. |
| File/folder shelf | Added a test-folder reference; native Open returned “Opened with Windows” and File Explorer opened that exact folder. The test Explorer window was closed after verification. | `evidence/zip-file-shelf.png` (Shelf), `evidence/zip-folder-opened.png` (opened test folder). This does not verify document associations or drag-and-drop. |
| Clipboard privacy default | Clipboard history stayed off. No OS clipboard content was read for this acceptance. | `evidence/zip-clipboard-off.png` (Clipboard off). Native capture/restore remains deliberately unverified. |
| Provider settings | Choosing OpenAI reset model/credential entry appropriately; no key was saved and no API call was made. | `evidence/zip-settings.png` (Settings). Live provider authentication/model access remains unverified. |
| Explicit automation | Created Daily Focus, used Run Now to deliver its reminder, then confirmed Delete cleanup. No test schedules remained. | `evidence/zip-automation-run.png` (Run Now), `evidence/zip-automation-cleanup.png` (cleanup). This is not a long-duration/restart scheduler trial. |
| Explicit reminder vs proactive opt-in | Home displayed the delivered user-created reminder while proactive suggestions were off. | `evidence/zip-reminder-home.png` (Reminder on home). Native toast delivery is not claimed. |
| Flyout interaction | With the island unpinned, the flyout stayed open without prematurely collapsing the island, and its Notes action worked. | Integration owner observed after the final fix. |
| Targeted synthetic-memory cleanup | `forget my parity test color` returned Forgotten and removed only the memory created for acceptance. | `evidence/zip-memory-forgotten.png` (Memory forgotten). No bulk memory clear was used. |
| Synthetic note cleanup | Confirmed Delete removed the acceptance note. | `evidence/zip-note-deleted.png` (Note deleted). |
| Shelf reference cleanup | Removed only the test-folder reference. The original verification document still existed. | `evidence/zip-shelf-cleanup.png` (Shelf cleanup); diagnostics records `OriginalShelfTestDocumentStillExists=true`. |

The test automation was deleted, its reminder acknowledged, and synthetic memory/note/shelf references were removed. No acceptance-created schedules or saved workspace items were left active. This cleanup did not delete the original shelf document or alter unrelated user data.

The earlier timer/mascot/native-media and fullscreen-fixture observations remain useful targeted evidence, but only the rows explicitly labeled above were repeated from the final extracted ZIP. Visual rendering, process startup, unit tests, package integrity and each functional interaction are separate claims. Full Mac parity is still not achieved.
