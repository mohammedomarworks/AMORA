# AMORA Windows continuation — Mac-reference composition and native feature work

The final checkpoint audit at the end of this report supersedes the historical package and uncommitted-state ledger below. Evidence filenames refer to artifacts retained in the collaboration workspace's `outputs/`; screenshots, logs, ZIPs, SDK/model fixtures and machine-specific paths are deliberately excluded from Git. Repository reproduction commands are in [VALIDATION.md](VALIDATION.md).

Status as of 2026-10-27 (Asia/Dhaka): the corrected frozen-source Release build, **643/643 tests**, **630-file self-contained ZIP** and all **five package-validator cases** pass. The accepted extracted ZIP visibly launched and passed keyboard, truthful unavailable-Calculator, real offline generation, timer and mascot interactions. Recorded diagnostics showed zero relevant application errors, unchanged historical crash logs and clean app/native-child shutdown. The earlier [milestone](MILESTONE_REPORT.md) completed a separate 477-test/x64 ZIP run; that historical result is not used to validate newer source. Full Mac parity is **not** claimed.

## Preserved baseline and scope

Checkpoint implementation started from `main` at `8c166706cb71134ae8db256fc861af36b9288f04`. The final audit below supersedes the original uncommitted-state description. Mac implementation, tags and public releases are unchanged. Windows version remains `0.6.0-beta.2`; new locally built artifacts must not retarget or replace the already published beta tag/package.

The newly supplied Mac UI references and actual `WideIslandView`, `IslandPages`, robot renderer and settings sources drive this increment: persistent 220-point companion area, balanced shallow control rows, no empty suggestion strip, an integrated quick menu, the authentic visor/eye composition, a GitHub activity surface, and a separate settings window with categories. Product code remains native C#/WinUI 3.

The evidence-backed matrix retains all 34 baseline capability rows and adds superseding current status without treating mocks or buttons as completion: [PARITY_ROADMAP.md](PARITY_ROADMAP.md).

## Integrated work and current limits

| Area | Implementation | Remaining acceptance or gap |
|---|---|---|
| Island/companion composition | Home and workspace composition revised around the persistent companion column; balanced media/timer and power/system rows; integrated menu and category settings window. | Actual Home/settings rendered correctly; the initial Alt+2 issue was corrected and verified in the first ZIP. Accepted-package Alt+1/Alt+2, local chat, timer and mascot interactions also passed; recorded diagnostics and clean shutdown passed. |
| Mascot identity/personality | Layered navy robot pod, center antenna, white-core cyan arched eyes and smile; added music/excited/bored/sleepy/concerned expressions; deterministic click debounce/cycle/rapid-click reaction, expiry, ambient/critical priority and disposal. | Tests passed in the final suite, and accepted-ZIP click produced heart eyes/positive response. Broader expression/priority accessibility remains unverified. |
| GitHub activity | Real official read-only profile/repository/event/authored-PR APIs; optional DPAPI token; token-only GraphQL calendar; panel model with last 28 actual weeks, fixed colors, day labels/selection, cancellation/refresh/disconnect. | Actual public service and native Activity/Repos/PRs tabs passed. Live-token GraphQL/credential reuse remain unverified. Mac OAuth loopback/backend flow is not ported. |
| Safe app/folder navigation | Fixed Calculator/Notepad/Paint/Windows Settings targets; Downloads/Documents/Desktop/Home via Windows known-folder APIs and explicit folder confirmation. | Windows Settings visibly opened. Missing Calculator exposed a stub false positive; protocol preflight and truthful wording passed both tests and the accepted-ZIP unavailable-app check. Third-party installed-app discovery remains narrower than Mac. |
| Local Brain | Pinned official llama.cpp Windows x64 CPU runtime, two hash-pinned Mac-catalog GGUF models, explicit install/download/cancel/delete, resource/integrity checks, private authenticated loopback server, native process-job cleanup, local provider routing and settings VM. | Production-service integration, actual app selection/cached-install/start/chat and child cleanup passed; accepted ZIP generated another real offline reply after restart; recorded diagnostics and clean shutdown passed. Local agent tool planning, automatic memory context, prewarm/GPU/arm64 equivalence are not claimed. |
| Browser bridge | Native Windows host, current-user named-pipe transport, strict framed protocol, explicit HKCU registration, single media coordinator and settings VM reuse the unchanged shared extension. | Focused source-linked transport/personality tests passed 48/48, including a real current-user pipe round trip with synthetic metadata; host project compiled. Actual Chrome/Edge registration, extension connection and YouTube transport remain unverified. GSMTC alone is not browser-bridge parity. |

## Verified evidence so far

### Live public GitHub service

The isolated .NET 8 harness compiles the **actual repository** GitHub service/models/contracts; it uses a guard that accepts only unauthenticated HTTPS GET requests to `api.github.com`. Its credential-store implementation throws if any credential method is accessed. It does not compile WinUI or touch solution `obj` outputs, and it does not prove native UI behavior.

Executed from the task workspace:

```powershell
& ./work/dotnet/dotnet.exe run --project work/github-public-check/GitHubPublicCheck.csproj --configuration Release -- outputs/evidence/public-github-service.json
```

Exit code **0**. At 18:08:01–18:08:05 UTC on 2026-10-26, the public account `mohammedomarworks` returned its actual profile, **five repositories, ten recent events and one authored open PR** through four GET requests, all HTTP 200. Credential accesses: **zero**. No token, Authorization header or private-account API was used. The contribution calendar was correctly reported unavailable because public recent events are not a yearly contribution history. `evidence/public-github-service.json` (Detailed evidence).

API safety, models, endpoint mapping, source inspection, new file reasons and mock-test scope are detailed in [GITHUB_NAVIGATION_MILESTONE.md](GITHUB_NAVIGATION_MILESTONE.md). The service deliberately does not reproduce the Mac's recent-event calendar fallback as if it were complete contribution history.

### Native Local Brain runtime check

`evidence/localbrain-initial-runtime.json` (Runtime-only evidence) records official llama.cpp `b11901`, the pinned compact Qwen 2.5 0.5B Q4_K_M model, loopback `127.0.0.1`, offline mode, and the response `5` to “What is 2 + 3? Answer with the number only.” This verifies the downloaded native runtime/model can generate on this machine. It does **not** yet verify the C# LocalBrainService, app settings/download lifecycle, cancellation, main conversation routing or packaged startup. Those are separate required integration checks.

The subsequent **production C# LocalBrainService integration passed 1/1, zero skipped** in `evidence/test-results/parity2-native-localbrain.trx` (parity2-native-localbrain.trx), duration approximately 3.25 seconds. It used the real asset verifier/native runtime with the pinned compact model, generated exactly `5`, reached Ready, then canceled a real generation after 100 ms and verified stopped state. No `llama-server` processes remained. This is stronger service evidence than the standalone runtime probe, but still does not replace visible app/settings/download or extracted-package acceptance.

Executed by the Local Brain integration owner with `AMORA_LOCAL_BRAIN_TEST_ROOT` pointing to this task's `work/localbrain-fixture`:

```powershell
dotnet test Windows/AMORA.Orbit.Tests/AMORA.Orbit.Tests.csproj -c Release -p:Platform=x64 --no-build --filter Category=NativeLocalBrain
```

The full coordinated suite's first continuation attempt compiled with zero warnings/errors but reported 575 total: 566 passed, eight failed, one opt-in native test skipped. Failures included old fresh-install Gemini assumptions and sanitized assistant error classifications. The next run reported 627 total, 624 passed and three failed: Windows file-lock exception type, cached-model free-space handling and credential-error string sanitization. These were corrected while preserving storage/privacy/action boundaries.

The next coordinated Release build passed with **zero warnings/errors** in 9.36 seconds, and `evidence/test-results/parity2-ui.trx` (parity2-ui.trx) passed **635/635, zero skipped**. This explicitly includes the real native Local Brain test (approximately 3.35 seconds), now also verifying cached installation under simulated 4 MB free space without any download. It verifies real generation, 100 ms cancellation and process stop. Two additional browser-default/persistence assertions were saved after that build; they were subsequently included in the final 643-test acceptance run below. Actual new `evidence/parity2-home.png` (Home rendering), `evidence/parity2-collapsed.png` (collapsed capsule), and `evidence/parity2-settings-appearance.png` (category settings) have been captured; subsequent functional UI and package acceptance is recorded below.

### Browser host and source-linked protocol verification

The standalone `AMORA.BrowserHost` Release build passed with zero warnings/errors. A separate source-linked .NET test harness passed **48/48** protocol, browser coordinator and mascot tests, including an actual current-user Windows named-pipe round trip. `evidence/browser-tests/browser-mascot-focused.trx` (Focused TRX). Browser media data in these tests is synthetic; this is not Chrome/Edge extension or real YouTube playback acceptance.

```powershell
work/dotnet/dotnet.exe test work/browser-bridge-check/BrowserBridgeCheck.csproj -c Release --nologo --logger 'trx;LogFileName=browser-mascot-focused.trx' --results-directory outputs/evidence/browser-tests
dotnet build Windows/AMORA.BrowserHost/AMORA.BrowserHost.csproj -c Release --nologo
```

Automatic approval review rejected a separate real-host process fixture with the reason “blocked by policy.” That fixture was not retried. It supplies no process/extension acceptance evidence. The source, packet limits, source arbitration and explicit setup boundaries are documented in [BROWSER_BRIDGE.md](BROWSER_BRIDGE.md).

## Continuation source inventory

The exact cumulative ledger of **148 changed source/document/script files**, with an individual reason for every path, is [CHANGE_INVENTORY.md](CHANGE_INVENTORY.md). This table groups this continuation's areas; earlier behavior and verification are described in [MILESTONE_REPORT.md](MILESTONE_REPORT.md). Generated build outputs and external evidence are excluded from the source ledger.

| Area/files under `Windows/` | Reason |
|---|---|
| `AMORA.Orbit/Views/OrbitCapsuleView.xaml`, `.xaml.cs`; `ViewModels/OrbitViewModel.cs`; `MainWindow.xaml.cs`; `App.xaml`, `.xaml.cs` | Persistent companion, revised integrated surface/menu/navigation, new service wiring and window ownership. |
| `AMORA.Orbit/Views/SettingsWindow.xaml`, `.xaml.cs` | Separate category-based settings window with actual bound controls. |
| `AMORA.Orbit/Models/PresentationPreferences.cs`; `Services/Implementations/PresentationPreferencesStore.cs`; `ViewModels/PresentationViewModel.cs` | Validated persisted theme/sizing/opacity/behavior/sound preferences and live presentation state. |
| `AMORA.Orbit/Services/Implementations/WindowsFeedbackSoundService.cs` | Native Windows notification audio for explicit preview/timer completion using current enabled/volume preferences and owned-player disposal. No third-party audio bundle. |
| `AMORA.Orbit/Views/RobotMascotView.xaml`, `.xaml.cs`; `Models/MascotExpression.cs`; `ViewModels/RobotMascotViewModel.cs`; `AMORA.Orbit.Tests/MascotPersonalityTests.cs` | Mac-reference vector renderer, additional moods, deterministic reaction/lifetime tests. |
| `AMORA.Orbit/Views/GitHubPanelView.xaml`, `.xaml.cs`; `Models/GitHubActivity.cs`; `Services/Contracts/IGitHubActivityService.cs`; `Services/Implementations/GitHubActivityService.cs`; `ViewModels/GitHubActivityViewModel.cs`; `AMORA.Orbit.Tests/GitHubActivityTests.cs` | Real read-only GitHub transport/models/UI and guarded credentials, partial-failure/cancel/link tests. |
| `AMORA.Orbit/Models/SafeNavigation.cs`; `Services/Contracts/ISafeNavigationService.cs`; `Services/Implementations/NavigationCommandParser.cs`, `SafeNavigationService.cs`, `WindowsSafeNavigationPlatform.cs`; `AMORA.Orbit.Tests/SafeNavigationTests.cs` | Typed OS app/folder allowlists, explicit grammar, confirmation lifecycle and safe native launch boundary. |
| `AMORA.Orbit/Models/LocalBrainModels.cs`; `Services/Contracts/ILocalBrainService.cs`, `ILocalBrainRuntime.cs`; `Services/Implementations/LocalBrainService.cs`, `LocalBrainAssetStore.cs`, `LocalBrainAIProvider.cs`, `LocalBrainProcessJob.cs`, `LlamaServerRuntime.cs`; `ViewModels/LocalBrainViewModel.cs` | Pinned model/runtime installation, integrity/resource safeguards, bounded native offline generation and lifecycle. |
| `AMORA.Orbit/Models/AISettings.cs`; `Services/Implementations/RoutingAIProvider.cs`; settings integration | Actual local provider/model selection without silent cloud fallback. |
| `AMORA.Orbit/AMORA.Orbit.csproj`; `Assets/Licenses/llama-cpp-MIT.txt`, `Qwen-Apache-2.0.txt`; `LOCAL_BRAIN.md` | Embed complete dependency license notices, copy attribution with explicit asset installation, and document pins/native architecture/privacy/runtime differences. Version metadata is unchanged. |
| `AMORA.Orbit/Services/Implementations/AssistantEngine.cs`; `ViewModels/SettingsViewModel.cs`; associated assistant/settings tests | Integrate explicit safe navigation and real local provider; preserve stored provider choice, truthful unavailable states, sanitized failures and existing allowlisted tool boundaries. |
| `AMORA.Orbit.Tests/LocalBrainTests.cs`, `NativeLocalBrainIntegrationTests.cs` | Mocked asset/runtime/failure paths plus explicitly enabled native integration check; native test is not assumed to pass or run by default. |
| `AMORA.Orbit.Tests/PresentationPreferencesTests.cs` | Durable/failed settings writes, corruption preservation, finite/range validation, explicit preview/save snapshots, disposal and fresh-local-vs-existing-provider regressions. |
| `AMORA.Orbit.Tests/PublicBetaReadinessTests.cs`, `SettingsViewModelTests.cs`, `ViewModelShutdownTests.cs` | Update intentional fresh-install Local Brain expectations while explicitly selecting Gemini in credential lifecycle/race tests so their safety coverage remains meaningful. |
| `AMORA.BrowserHost/AMORA.BrowserHost.csproj`, `Program.cs`; `AMORA.Orbit/Services/BrowserBridge/BrowserWireProtocol.cs`, `IBrowserBridgeTransport.cs`, `NamedPipeBrowserTransport.cs`, `BrowserHostRegistration.cs` | Self-contained browser host, pinned origin, bounded framing/schema, current-user Windows pipe transport and explicit stable per-user registration. |
| `AMORA.Orbit/Services/Implementations/BrowserMediaBridgeService.cs`, `MediaCoordinatorService.cs`; `ViewModels/BrowserBridgeViewModel.cs`; `AMORA.Orbit.Tests/BrowserBridgeTests.cs`; `BROWSER_BRIDGE.md` | Truthful metadata/acknowledgements/capabilities, opt-in ownership, one shared browser/native media source, setup UI boundary, synthetic/native-pipe regressions and documented limits. |
| `Scripts/Publish-Release.ps1`, `Validate-Release.ps1`, `Test-ReleaseValidation.ps1`; `.github/workflows/windows-orbit.yml` (repository root); `VALIDATION.md` | Ship actual self-contained browser host and unchanged shared extension; require matching versions/x64/runtime/extension hashes and identity; add missing-host/changed-extension negative fixtures; use the same publish helper locally/CI while preserving all previous release checks. No registration occurs during packaging. |
| `AMORA.sln` | Include the native browser host in coordinated solution builds; all three projects compiled after this metadata addition. |
| `PARITY_ROADMAP.md`, `GITHUB_NAVIGATION_MILESTONE.md`, `CONTINUATION_REPORT.md` | Current capability/evidence/status register and honest continuation boundaries. |

## Actual application checks before final packaging

The 635-test build was launched and inspected on Windows. Home visibly kept the companion column with two balanced control/status rows and no unused suggestion strip. The separate Settings window rendered its category sidebar without overlapping labels. Selecting Ocean changed live accents (`evidence/parity2-theme-preview.png` (preview)); Midnight was then restored and Save preferences reported success. This is actual UI interaction evidence, not only a persisted-object test.

The already checksum-verified compact Qwen runtime/model fixture was copied only into the previously absent app-specific Local Brain directory (`evidence/localbrain-app-fixture.json` (fixture record)); setup was not silently performed by app startup. In the actual settings UI, the compact model was selected, **Use this Local Brain model** persisted the provider choice, **Install** verified the cached assets (`evidence/parity2-localbrain-installed.png` (installed)), and **Start** reached Ready (`evidence/parity2-localbrain-ready.png` (ready)). The owned native child PID was 2236, approximately 523 MB at that checkpoint.

The actual Talk UI showed `evidence/parity2-localbrain-thinking.png` (thinking), then `evidence/parity2-localbrain-response.png` (the generated response) to the synthetic prompt “In one sentence, describe a quiet forest at sunrise.” It answered “A quiet forest in the early morning, with a serene landscape of dawn and trees.” No cloud credential or request was used. Alt+F4 then closed the app; the owned runtime PID 2236 and all AMORA/llama-server processes were absent. This verifies real app-to-native-model routing and process cleanup; it does not establish model quality, full download/recovery UI, local agent planning or final extracted-package acceptance.

The actual public GitHub panel loaded ten `evidence/parity2-github-activity.png` (activity events), five `evidence/parity2-github-repositories.png` (repositories), and one `evidence/parity2-github-prs.png` (authored open pull request). Tab changes were exercised. No token was supplied; the calendar correctly remained unavailable instead of displaying invented contribution history.

Alt+2 did not open Talk during the initial run. The actual native keyboard path was corrected and Alt+2 subsequently opened Talk from the first ZIP's root surface. Accelerator tooltip placement was also hidden to keep native Alt tooltips from obscuring the compact interface. That candidate ZIP additionally generated an actual offline response (`evidence/parity2-zip-offline-response.png` (response)); it is superseded by the later navigation correction rather than distributed as the final accepted artifact.

## Final coordinated acceptance

**Navigation correction:** actual Windows Settings navigation opened a real native Settings window and was closed afterwards (`evidence/parity2-native-navigation-window.json` (window evidence)). Calculator was absent on this PC, yet its System32 stub exited successfully and the earlier code reported “Opened Calculator.” This was a real acceptance failure. `WindowsSafeNavigationPlatform` now preflights the fixed `calculator:`/`ms-settings:` protocol using [QueryUriSupportAsync](https://learn.microsoft.com/en-us/uwp/api/windows.system.launcher.queryurisupportasync), accepts only Available, and has no executable/Store fallback. Fixed Notepad/Paint launches reject immediate stub exit; successful application requests say Windows accepted the request, without claiming visible-window proof. Eight injected, OS-launch-free regression cases were added and passed in the final **643/643** run. The 635-test build and first 630-file package are superseded by this correction; corrected packaging and actual unavailable-Calculator verification passed.

| Layer | Verified result or current status | Evidence/limit |
|---|---|---|
| Final all-three-project Release build | Passed, **0 warnings / 0 errors**, 9.49 s | `evidence/parity2-acceptance-build.log` (Acceptance build log), includes the host project and final navigation correction. |
| Final full tests | **643 executed, 643 passed, zero failed or skipped** | `evidence/test-results/parity2-acceptance.trx` (Acceptance TRX), `evidence/parity2-acceptance-tests.log` (output). Native fixture enabled; includes browser privacy and protocol/stub regressions. |
| Self-contained publish | Corrected source succeeded for app, native browser host and unchanged extension | `evidence/parity2-acceptance-publish.log` (Acceptance publish log). |
| Actual UI and offline generation | Home/settings/theme preview/GitHub tabs/local-model install/start/chat observed | Screenshots and limits above; accepted-package keyboard, offline-generation, timer and mascot reruns also passed below. |
| Native app-close cleanup | Alt+F4 closed the tested app and owned inference runtime | Process inventory showed no AMORA or llama-server afterwards; final extracted-package lifecycle remains separate. |
| ZIP integrity/version/architecture | **Passed**, 630 complete files, **101,228,345 bytes** | `evidence/parity2-accepted-package.json` (Accepted package report): full publish/archive/extraction hashes, native x64, self-contained app/host runtime, version agreement, four unchanged extension files and pinned identity. |
| ZIP SHA-256 | `294ae316d8669920f4dab6413b73fcd479a9fd03a79c0fdca7f0f87c2bce24f6` | `parity2-validation/accepted/AMORA.Orbit-v0.6.0-beta.2-win-x64.zip` (Accepted development ZIP). The copied user-facing ZIP independently matched the validated staging archive hash. |
| Validator regressions | **5/5 passed** | `evidence/parity2-accepted-package-tests.log` (Accepted-package test log): original accepted; missing host, changed extension, corrupted PRI and traversal rejected. No negative fixture launched. |
| Accepted extracted ZIP launch | **Actual process and visible UI passed** | PID 23916, started 00:39:42 +06:00 from `work/release-staging/parity2-accepted-extracted/AMORA.Orbit.exe`. Interactions below use this corrected package. |
| Actual runtime ownership | App loaded its packaged .NET/WinUI runtimes from the extraction directory | `evidence/accepted-runtime-modules.json` (Loaded modules): `hostfxr`, `hostpolicy`, `coreclr`, WindowsAppRuntime and XAML/control modules resolve inside the accepted extraction, not the SDK installation. |
| Accepted ZIP runtime diagnostics | **Passed for the recorded interval** | `evidence/parity2-accepted-runtime.json` (Runtime diagnostics): 00:21:45–00:45:16 +06:00 on 2026-10-27, zero AMORA/BrowserHost/llama Application errors. Historical crash log remained **11,005 bytes**, last written 17:13:46.2465384 UTC on 2026-10-26. No diagnostic history was erased. |
| Accepted ZIP shutdown | **Verified** | Alt+F4 closed PID 23916; `AppRunningAfterAltF4=false`, `OwnedLlamaProcesses=0`. After a brief final idle-Home screenshot reopening, the 18:48:19 UTC cleanup check again found **zero AMORA and zero llama-server processes**. |
| Signing | `NotSigned` | This is an unsigned local development artifact. No public release/tag replacement or signing claim is made. |

The corrected publish target is `work/release-staging/parity2-acceptance-publish`; final archive/extraction are `parity2-accepted` and `parity2-accepted-extracted` under that staging directory. Staging is a junction to `a separate local validation volume`, because C: had roughly 700 MB free. The accepted ZIP was copied to `outputs/parity2-validation/accepted` and its SHA-256 matched. No existing scratch data was deleted: automatic approval review rejected a proposed scratch-cleanup command with the reason “blocked by policy,” and it was not executed. Using available D: staging allowed verification to continue without that cleanup.

### Exact final build and test commands

Executed from the repository root. `dotnet` here is the task-local .NET 8 SDK at `../../work/dotnet/dotnet.exe`.

```powershell
dotnet build Windows/AMORA.sln -c Release /p:Platform=x64 --no-restore --verbosity minimal
$env:AMORA_LOCAL_BRAIN_TEST_ROOT = (Resolve-Path ../../work/localbrain-fixture).Path
dotnet test Windows/AMORA.Orbit.Tests/AMORA.Orbit.Tests.csproj -c Release --no-build --no-restore /p:Platform=x64 --logger 'trx;LogFileName=parity2-acceptance.trx' --results-directory ../evidence/test-results --verbosity minimal
```

Publishing/validation used the repository scripts with these recorded argument values (paths relative to the repository root):

| Script | Recorded inputs |
|---|---|
| `Windows/Scripts/Publish-Release.ps1` | `-OutputDirectory ../../work/release-staging/parity2-acceptance-publish`; `-DotnetPath` set to the task-local SDK above. |
| `Windows/Scripts/Validate-Release.ps1` | `-PublishDirectory ../../work/release-staging/parity2-acceptance-publish`; `-ArchivePath ../../work/release-staging/parity2-accepted/AMORA.Orbit-v0.6.0-beta.2-win-x64.zip`; `-ExtractionDirectory ../../work/release-staging/parity2-accepted-extracted`; `-ReportPath ../evidence/parity2-accepted-package.json`. Process smoke was not requested; manual native acceptance is separately recorded. |
| `Windows/Scripts/Test-ReleaseValidation.ps1` | Same publish/archive inputs; `-TestDirectory ../../work/release-staging/parity2-accepted-validator`. |

### Actual accepted-ZIP interactions

| Interaction | Observed result | Evidence/limit |
|---|---|---|
| Direct keyboard navigation | Alt+2 from collapsed opened Talk; Alt+1 while input had focus returned Home. Native accelerator tooltips no longer obscured the island. | Actual accepted executable; full keyboard/screen-reader accessibility remains broader than these checks. |
| Calculator absent | `open calculator` returned a truthful unavailable result, with no false claim of an opened application. | `evidence/accepted-unavailable-app.png` (Unavailable app). Calculator is absent on this PC; Notepad/Paint native transport remains unverified. |
| Offline generation after restart | The real local model answered “Hello, how can I assist you today?” to “Write a five-word greeting.” | `evidence/accepted-offline-response.png` (Accepted offline response). This proves native generation after restart; the response did **not** meet the requested word count, so instruction-following quality is not claimed. |
| Timer source and controls | Started 5m, observed 04:52, paused, added one minute to 05:52, then canceled to zero/idle. | `evidence/accepted-timer-running.png` (Running), `evidence/accepted-timer-paused-adjusted.png` (paused/adjusted). Actual UI and shared timer state; completion/suspend variants remain separate. |
| Mascot reaction | Clicking the actual mascot produced pink heart eyes and a positive response. | `evidence/accepted-mascot-reaction.png` (Mascot reaction). Confirms event-driven rendering, not every expression/priority/accessibility scenario. |

Actual accepted-package state captures: `evidence/accepted-collapsed.png` (collapsed capsule), `evidence/accepted-home.png` (idle expanded Home), and `evidence/accepted-timer-running.png` (expanded island with live timer). The final idle Home capture was visually inspected as the actual 960×280 expanded island before cleanup; it shows the persistent mascot/companion column and balanced media/timer/power/system rows.

Remaining before full parity: actual browser extension registration/Chrome/Edge/YouTube behavior; live cloud and GitHub token/calendar/OAuth acceptance; enabled native clipboard capture/restore; complete file drag/drop/association/recovery and installed-app discovery; Mac Local Agent planning, automatic approved-memory context and prewarming/GPU/arm64; wider automation triggers/conditions; complete proactive/personality/follow-up scope; multi-monitor/DPI/removal/fullscreen variants and Narrator/high-contrast accessibility. The small local model's imperfect instruction following and unsigned artifact status are documented above.

No remaining item is treated as completed from source inspection, mocked HTTP tests, successful publication or the previous milestone's package evidence. The recorded x64 acceptance establishes this working increment, not full Mac equivalence or permission to publish a public beta.

## Final checkpoint audit — 2026-10-27

The enclosing collaboration directory is not a Git repository. `outputs/AMORA` is a genuine full clone with its own `.git`, original clone reflog and intact canonical history. Its fetch/push origin is `https://github.com/mohammedomarworks/AMORA.git`; branch `main` tracks `origin/main`. Both local HEAD and the remote branch resolved to `8c166706cb71134ae8db256fc861af36b9288f04` before the checkpoint. The reviewed baseline had 59 modified tracked files, 89 untracked intended source/doc/script files and no deletions or staged changes. All 148 paths are itemized in [CHANGE_INVENTORY.md](CHANGE_INVENTORY.md). No duplicate repository, validation payload, Mac implementation, shared browser extension source, version metadata or unrelated workflow is included.

The full per-file source diff and every new file were reviewed, including models/contracts, native adapters, service wiring, viewmodels, XAML/code-behind, tests, licenses, scripts and the complete Windows workflow. All 137 recorded code-file SHA-256 values matched the prior accepted source before the audit correction. Mac model descriptors, generation limits, mascot click cycle, memory privacy and tool confirmation sources were rechecked against the implementation. The standard WinUI control dictionary remains first; both application-resource regression tests passed. Production media uses GSMTC plus the optional bridge, rather than preview services. Explicit memory/navigation run before AI routing, cloud history excludes memory requests, and local inference has no cloud fallback.

One concrete defect was corrected: `OrbitCapsuleView.OnLoaded` restarted the capsule breathing animation using only the Windows preference, overriding AMORA's saved zero-motion value. It now calls the same `ApplyPresentation` path used by live preference changes, which combines both settings. No new feature batch was added. Documentation also removes personal machine paths, replaces links to deliberately untracked evidence with artifact names, and corrects a stale GitHub-test pending statement. Earlier milestone claims are retained as historical observations.

Exact commands executed from the repository root used the task-local .NET SDK 8.0.427 at `../../work/dotnet/dotnet.exe`:

```powershell
& ../../work/dotnet/dotnet.exe build Windows/AMORA.sln -c Release /p:Platform=x64 --no-restore --verbosity minimal
$env:AMORA_LOCAL_BRAIN_TEST_ROOT = (Resolve-Path ../../work/localbrain-fixture).Path
& ../../work/dotnet/dotnet.exe test Windows/AMORA.Orbit.Tests/AMORA.Orbit.Tests.csproj -c Release --no-build --no-restore /p:Platform=x64 --logger 'trx;LogFileName=final-audit-corrected.trx' --results-directory ../evidence/test-results --verbosity minimal
& ./Windows/Scripts/Publish-Release.ps1 -OutputDirectory ../../work/release-staging/final-audit-publish -DotnetPath (Resolve-Path ../../work/dotnet/dotnet.exe).Path
```

The full build/test run was performed both before and after the motion correction. The corrected build passed with **0 warnings and 0 errors** (11.73 seconds); the full suite executed **643 tests, all passed, zero failed or skipped**, including the native model generation/cancellation test and both WinUI resource tests. CI normally skips the explicitly opted-in native test unless a verified model fixture is supplied; a normal hosted run must not claim to have executed local inference without it. No model or runtime download occurs during this suite.

The corrected publish folder received `LOCAL_DEVELOPMENT_BUILD.txt`, `LOCAL_BRAIN.md` and `BROWSER_BRIDGE.md`, then its entire contents were archived as `outputs/final-audit-validation/AMORA.Orbit-v0.6.0-beta.2-win-x64.zip`. Validation commands were:

```powershell
./Windows/Scripts/Validate-Release.ps1 -PublishDirectory ../../work/release-staging/final-audit-publish -ArchivePath ../final-audit-validation/AMORA.Orbit-v0.6.0-beta.2-win-x64.zip -ExtractionDirectory ../../work/release-staging/final-audit-extracted -ReportPath ../evidence/final-audit-package.json
./Windows/Scripts/Test-ReleaseValidation.ps1 -PublishDirectory ../../work/release-staging/final-audit-publish -ArchivePath ../final-audit-validation/AMORA.Orbit-v0.6.0-beta.2-win-x64.zip -TestDirectory ../../work/release-staging/final-audit-validator
```

The current package has **630 files, 101,228,059 bytes**, SHA-256 **`c2b4f69cee01f854fea2f272c9997fc69fffc94b6903038c90e8000f3f8adb41`**. Full publish/archive/extraction hashes, x64 PE headers, self-contained app/host runtimes, matching versions, four unchanged extension files and pinned extension identity passed. All **five validator cases passed**. The current Release EXE, app DLL and `resources.pri` independently matched the publish files by SHA-256. This corrected package supersedes the earlier `294ae316…` artifact; it remains unsigned local validation, not a replacement public beta.

The actual executable from the new extraction visibly launched. Compact and expanded native captures are `evidence/final-audit-collapsed.png` and `evidence/final-audit-home.png`. Native module inspection found eight relevant .NET/WinUI modules, all loaded from this extraction. Alt+2 opened Talk, and actual Qwen 2.5 **0.5B Q4_K_M** inference through official **llama.cpp b11901 CPU x64** answered `5` to the synthetic arithmetic prompt (`evidence/final-audit-offline.png`). The 5-minute preset counted down to 04:54 with the focused mascot and was canceled. User media metadata was read without issuing playback commands.

The Appearance UI saved motion intensity zero, the app closed, and the extracted app restarted with that value. Alt+1 expanded immediately, and clicking the native mascot still rendered pink heart eyes without bounce (`evidence/final-audit-mascot-zero-motion.png`). Reopened settings reported persisted value zero. The original value one was restored and saved before final closure. This verifies the AMORA preference/restart path; it does not claim a complete Windows accessibility or physical display matrix.

The native acceptance interval was **19:04:35–19:07:21 UTC on 2026-10-26** (01:04:35–01:07:21 local on 2026-10-27). Both owned app runs closed through Alt+F4; final counts were **zero AMORA and zero llama-server processes**. Application-log inspection was available and returned no relevant errors. The historical crash log remained **11,005 bytes** with an unchanged SHA-256. Logs and screenshots remain local artifacts, not committed user data.

Browser infrastructure remains **Partial/unverified end to end**. The available automatic-review result rejected a separate command that would write and run a standalone real-host fixture, saying only **“blocked by policy.”** No more specific reason was supplied. That rejected fixture is not part of these 148 source paths and is excluded from the checkpoint. It was not retried, disguised, or replaced with equivalent execution. The production host and bounded current-user pipe infrastructure compile and have synthetic protocol/real-pipe coverage; actual Chrome/Edge registration, extension pairing and YouTube transport are still unverified. No host registration or extension installation was performed during this audit.

The staged audit passed for exactly **148 files**: only the reviewed Windows implementation/tests/docs/licenses/scripts and `.github/workflows/windows-orbit.yml`. Every staged blob matched the reviewed working file after Git's configured line-ending normalization; `git diff --cached --check` passed. Filename/generated-output checks found no prohibited files. The credential/private-path scan found seven deliberately synthetic test strings, each inspected in context, and **zero unresolved candidates**; no personal machine path or production credential was staged. The rejected browser fixture, generated ZIP/publish/build directories, SDK/model files, logs and screenshots are excluded. Remote `main` still matched the baseline at the final pre-commit check.

The checkpoint is intended for one normal commit/push to the existing canonical `main` branch under the user's explicit authorization; the commit containing this report identifies the audited source. Version/tag/release state is unchanged. Full Mac parity, clean-machine signing/download acceptance, local multi-step agent/memory retrieval/prewarm/GPU/ARM64, broader automation conditions, live browser/cloud/token integrations, Narrator/high-contrast and physical multi-display/DPI/battery coverage remain outside this checkpoint's completion claim.
