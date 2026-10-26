# AMORA Orbit — Native Windows Companion

AMORA Orbit is the native Windows companion application for AMORA. Designed specifically for Windows 10 and 11, Orbit delivers a floating, top-center ambient intelligence experience that honors the Windows desktop paradigms rather than copying macOS hardware cutouts.

---

## Design Philosophy

- **Genuine Windows Aesthetic**: A detached, floating top-center capsule (`#0D0F17` / `#161822`) with subtle borders (`#2A2E3D`), soft shadows, electric cyan highlights (`#52CCFF`), and Segoe UI typography.
- **No Hardware Cutout Illusion**: Orbit is explicitly not a camera notch or Dynamic Island. It is an ambient intelligence capsule anchored to the active display's work area.
- **Adaptive Ergonomics**:
  - **Collapsed Capsule Pill** (240 × 38 DIPs): A compact pill with AMORA's icon, status label, and an animated breathing cyan indicator.
  - **Expanded Downward Panel** (660 × 500 DIPs): Smooth downward expansion revealing the interactive companion workspace.
- **Desktop PC Awareness**: Correctly distinguishes laptops on battery/charging from desktop towers connected directly to AC power (`BatteryFlag = 128` / `BatteryLifePercent = 255`), avoiding misleading 0% battery indicators.
- **Fullscreen App Avoidance**: Automatically detects foreground fullscreen games or presentation apps via Win32 `GetWindowRect` and display monitor bounds, preventing intrusive overlays.
- **Global Hotkey & Tray Integration**: Instant access via `Ctrl + Alt + O` and the Windows Taskbar Notification Area (System Tray). Pressing `Escape` collapses the expanded panel immediately.

---

## Layout Breakdown

### 1. Left Panel (Companion & Action)
- **AMORA Robot Mascot**: Vector-rendered robot head with antenna, glowing cyan eyes, and expressive mood reactions (Idle, Focused, Happy, Thinking, Alert).
- **Proactive Suggestion Card**: Contextual intelligence card with primary action, Snooze (15m), and Dismiss controls.

### 2. Right Panel (Controls & Telemetry)
- **Top Chip Banner**: Notification chip indicating active workspace insights and priority.
- **Assistant Command Bar**: Quick command input bar with Ask and Clear buttons, real-time status feedback, and two-step confirmation prompts for consequential actions.
- **Media Player**: Global System Media Transport Controls (GSMTC) integration with Spotify/Apple Music badge, track details, scrub bar, and controls.
- **Focus Timer**: Quick-start 5m, 15m, and 25m Pomodoro presets, active countdown (`25:00`), pause/resume, and +1m adjustments.
- **System Telemetry Bar**: Battery / AC power status, live CPU load percentage, and RAM usage gauges.

---

## Solution Structure

```
Windows/
├── AMORA.sln                                     # Visual Studio Solution (.NET 8)
├── README.md                                     # This documentation
├── AMORA.Orbit/                                  # WinUI 3 Desktop App Project
│   ├── AMORA.Orbit.csproj                        # Target: net8.0-windows10.0.19041.0
│   ├── app.manifest                              # PerMonitorV2 DPI awareness & OS compatibility
│   ├── App.xaml / App.xaml.cs                    # Application lifecycle & DI container
│   ├── MainWindow.xaml / MainWindow.xaml.cs      # Borderless, topmost DWM-styled capsule window
│   ├── Interop/
│   │   ├── NativeMethods.cs                      # Win32 user32/kernel32/dwmapi/shell32 P/Invoke
│   │   └── DpiHelper.cs                          # Per-monitor DPI scale factor conversions
│   ├── Models/
│   │   ├── AISettings.cs                         # AI provider configuration & test connection results
│   │   ├── AmoraContextSnapshot.cs               # Compact, privacy-first context snapshot of active services
│   │   ├── AssistantCommand.cs                   # Strongly-typed discriminated command union
│   │   ├── AssistantExecutionResult.cs           # Truthful execution outcomes & mood reactions
│   │   ├── BatterySnapshot.cs                    # Power status with Desktop AC fallback
│   │   ├── CapsuleBounds.cs                      # Capsule coordinate bounds model
│   │   ├── ChatMessage.cs                        # Session-only conversational turn (User / Model)
│   │   ├── MascotExpression.cs                   # Mascot moods and facial expressions
│   │   ├── MediaTrack.cs                         # Media metadata and playback formatting
│   │   ├── ProactiveSuggestion.cs                # Proactive intelligence suggestions
│   │   ├── SystemTelemetrySnapshot.cs            # CPU & RAM hardware metrics
│   │   └── TimerState.cs                         # Focus timer snapshots and progress
│   ├── Services/
│   │   ├── Contracts/                            # Decoupled service interfaces
│   │   │   ├── IAIProvider.cs                    # Provider-neutral AI completion contract
│   │   │   ├── IAISettingsService.cs             # AI settings and secure credential management
│   │   │   ├── IAssistantCommandRouter.cs        # Contextual command routing interface
│   │   │   ├── IAssistantEngine.cs               # Assistant execution engine contract
│   │   │   ├── IBatteryService.cs
│   │   │   ├── IConversationSession.cs           # Ephemeral multi-turn context contract
│   │   │   ├── IHotKeyService.cs
│   │   │   ├── IMediaService.cs
│   │   │   ├── ISecureCredentialStorage.cs       # Windows DPAPI user-encrypted secret storage
│   │   │   ├── ISuggestionService.cs
│   │   │   ├── ISystemTelemetryService.cs
│   │   │   ├── ITaskbarTrayService.cs
│   │   │   ├── ITimerService.cs
│   │   │   └── IWindowPositioningService.cs
│   │   └── Implementations/                      # Windows & Preview implementations
│   │       ├── AISettingsService.cs              # AI settings persistence & key coordination
│   │       ├── AssistantEngine.cs                # Unified command execution engine with AI tool parsing
│   │       ├── ConversationSession.cs            # Thread-safe in-memory bounded turn manager
│   │       ├── DeterministicCommandRouter.cs     # Pattern-based router with contextual disambiguation
│   │       ├── GeminiAIProvider.cs               # Google Gemini REST API v1beta cloud provider
│   │       ├── InMemoryCredentialStorage.cs      # In-memory secure storage for tests
│   │       ├── LocalStubAIProvider.cs            # Safe offline stub provider
│   │       ├── PreviewBatteryService.cs          # Offline / preview battery mock
│   │       ├── PreviewMediaService.cs            # Offline / interactive preview media
│   │       ├── PreviewSystemTelemetryService.cs  # Offline / preview telemetry mock
│   │       ├── ProactiveSuggestionService.cs     # Suggestion queue, snooze, and dismiss
│   │       ├── StandardTimerService.cs           # Thread-safe focus countdown timer
│   │       ├── TaskbarTrayService.cs             # Win32 Shell_NotifyIcon tray integration
│   │       ├── WindowsBatteryService.cs          # Win32 GetSystemPowerStatus
│   │       ├── WindowsCredentialStorage.cs       # Windows DPAPI CurrentUser encrypted storage
│   │       ├── WindowsHotKeyService.cs           # Win32 RegisterHotKey (Ctrl+Alt+O)
│   │       ├── WindowsMediaService.cs            # WinRT GlobalSystemMediaTransportControls
│   │       ├── WindowsSystemTelemetryService.cs  # Win32 GetSystemTimes & GlobalMemoryStatusEx
│   │       └── WindowsWindowPositioningService.cs # Multi-monitor work area & clamp math
│   ├── ViewModels/                               # MVVM ViewModels
│   │   ├── AssistantCommandViewModel.cs          # Command input, feedback & confirmation state
│   │   ├── OrbitViewModel.cs                     # Master capsule state machine
│   │   ├── RobotMascotViewModel.cs               # Mascot expressions and interactive reactions
│   │   ├── MediaControlViewModel.cs              # Media playback controls
│   │   ├── SettingsViewModel.cs                  # AI provider, DPAPI key management & connection test
│   │   ├── TimerControlViewModel.cs              # Focus timer controls & presets
│   │   ├── SuggestionViewModel.cs                # Actionable suggestions
│   │   └── SystemStatusViewModel.cs              # Battery & telemetry polling loop
│   └── Views/                                    # WinUI 3 XAML Views
│       ├── OrbitCapsuleView.xaml                 # Main capsule container (collapsed pill + expanded)
│       ├── RobotMascotView.xaml                  # AMORA mascot vector visor & antenna
│       ├── SuggestionBannerView.xaml             # Notification chip banner
│       ├── MediaControlView.xaml                 # Media playback card
│       ├── TimerControlView.xaml                 # Focus timer card
│       └── SystemStatusView.xaml                 # Battery & hardware gauges
└── AMORA.Orbit.Tests/                            # Unit Test Project
    ├── AMORA.Orbit.Tests.csproj                  # Target: net8.0-windows10.0.19041.0
    ├── AmoraContextSnapshotTests.cs              # Snapshot generation, inactive honesty & privacy assertions
    ├── AssistantCommandViewModelTests.cs         # Command ViewModel, input tracking & confirmation tests
    ├── AssistantEngineAIToolExecutionTests.cs    # AI natural language interpretation & safe tool execution
    ├── AssistantEngineContextTests.cs            # Context-aware queries, truthful data & privacy defaults tests
    ├── AssistantEngineConversationTests.cs       # Multi-turn conversation history, follow-up & reset tests
    ├── AssistantEngineTests.cs                   # End-to-end execution, real timers, media & honest failures
    ├── BatteryServiceTests.cs                    # Power status, AC detection & charging calculations tests
    ├── ConversationSessionTests.cs               # Bounded in-memory turn management & trimming tests
    ├── DeterministicCommandRouterTests.cs        # Command regex parsing, context disambiguation & safety
    ├── GeminiAIProviderTests.cs                  # Mock-HTTP Gemini REST tests (auth, rate limits, timeouts)
    ├── MascotExpressionTests.cs                  # Expression factory state tests
    ├── MediaTrackTests.cs                        # Duration formatting & progress percent tests
    ├── PositioningServiceTests.cs                # Work area centering, DPI & clamping tests
    ├── ProactiveSuggestionEngineTests.cs        # Opt-in defaults, triggers, cooldowns, duplicate suppression & safety tests
    ├── SecureCredentialStorageTests.cs           # DPAPI / in-memory credential storage & masking tests
    ├── SettingsViewModelTests.cs                 # Settings lifecycle, key save/clear & connection testing
    ├── SuggestionServiceTests.cs                 # Action execution, snooze, and dismiss tests
    ├── TelemetryServiceTests.cs                  # CPU & RAM metric calculations tests
    └── TimerServiceTests.cs                      # Countdown, pause, resume, and add minute tests
```

---

## Assistant Integration & Security Architecture

Phase 6E connects AMORA Orbit to an end-to-end assistant command execution engine:
1. **Deterministic Local Router (`DeterministicCommandRouter`)**: Parses user natural language inputs for timer, media, power, and system commands using pattern matching and contextual awareness. If a command like "pause" is ambiguous because both timer and media are active, it prompts the user for clarification rather than making assumptions.
2. **Real Cloud AI Provider (`GeminiAIProvider`)**: Implements official Google Gemini v1beta REST API (`gemini-2.5-flash`), providing natural language understanding with zero external SDK bloat. Uses `x-goog-api-key` headers to prevent URL key leakage, handles rate limits (HTTP 429), timeouts, and authentication failures cleanly.
3. **User-Encrypted Credential Storage (`WindowsCredentialStorage`)**: API keys are encrypted at rest using Windows DPAPI (`DataProtectionScope.CurrentUser`). Keys are never written to plaintext configuration files, logs, or exception messages. Masks keys in the UI and redacts them from diagnostics.
4. **AI-Connected Safe Tool Execution**: When the cloud AI interprets a user request and proposes an action (e.g. `[COMMAND: start 15m timer]`), the action is routed through the deterministic allowlist engine and executed against the real service. Consequential actions strictly enforce two-step user confirmation.
5. **Real Service Execution (`AssistantEngine`)**: Routes actions directly to registered service instances (`ITimerService`, `IMediaService`, `IBatteryService`, `ISystemTelemetryService`).
6. **Truthful Outcome Reporting**: Never reports fake success. If an operation cannot be performed (e.g. attempting to resume an already running timer, or pausing when no timer exists), a structured failure status is returned and displayed to the user.
7. **Allowlisted Consequential Actions**: Consequential or destructive operations (e.g., "reset settings", "clear all memories") require a mandatory two-step confirmation workflow before any mutation is permitted.
8. **Bounded Session-Only Conversational Context (`ConversationSession`)**: Implements multi-turn conversational follow-up understanding using Gemini's native alternating `user`/`model` content history. Context is held strictly in memory with configurable turn limits (default: 6 turns) and predictable FIFO trimming that guarantees history always starts with a user turn. Never persists conversation content to disk or logs sensitive prompts. Failed requests and cancellations are safely omitted, and conversation can be reset via UI button or deterministic commands.
9. **Privacy-First Context Awareness V1 (`AmoraContextSnapshot`)**: Synthesizes a compact, read-only context snapshot exclusively from AMORA-owned services (`ITimerService`, `IMediaService`, `IBatteryService`, `ISystemTelemetryService`). Resolves contextual follow-ups ("pause it", "how much time is left?", "am I charging?") deterministically without cloud AI when possible. Never captures screenshots, clipboard contents, keystrokes, window titles, or file systems. Status context is never sent to the AI provider unless the user explicitly opts in via a dedicated Settings toggle (`SendStatusContextToAI`, default: off). Snapshots are ephemeral and strictly excluded from conversation history turns.
10. **Proactive AMORA V1 (`ProactiveSuggestionService`)**: Implements a lightweight, privacy-first proactive suggestion engine generating deterministic local insights strictly from AMORA-owned state (timer completions and low battery while unplugged). Opt-in by default (`EnableProactiveSuggestions`, default: off). Displays at most one suggestion at a time inside the existing Orbit UI, with duplicate suppression, cooldowns, and dismissal respect. Resolves obsolete alerts automatically (e.g. plugging in power clears low battery alerts; starting a new timer clears completion alerts). Never calls cloud AI, captures screenshots, or spams notifications. Offers safe actions without ever auto-executing.

---

## Building and Running

### Prerequisites (Windows Development Machine)
1. **Windows 10 Version 1809 (Build 17763) or Windows 11**.
2. **Visual Studio 2022** (v17.8 or higher) with workloads:
   - *.NET Desktop Development*
   - *Windows App SDK C# Templates*
   - Windows 10/11 SDK (10.0.19041.0 or higher)
3. Or **.NET 8 SDK** via command line with Windows App SDK installed.

### Build via Visual Studio
1. Open `Windows/AMORA.sln` in Visual Studio 2022.
2. Select target platform `x64` or `arm64` and configuration `Debug` or `Release`.
3. Set `AMORA.Orbit` as the Startup Project.
4. Press `F5` to build and launch AMORA Orbit.

### Build and Test via Command Line (Windows Machine / CI)
```cmd
cd Windows
dotnet build AMORA.sln -c Release
dotnet test AMORA.Orbit.Tests/AMORA.Orbit.Tests.csproj -c Release
```

> [!NOTE]
> Unit tests run automatically in GitHub Actions on `windows-latest` via `.github/workflows/windows-orbit.yml`. They test pure C# view models, service contracts, command routing, and execution logic.

---

## macOS Host Compatibility

The macOS host environment runs Swift/AppKit builds and macOS unit tests. The Windows solution is completely decoupled from the macOS build system:
- No shared Swift files or AppKit dependencies are touched by the Windows solution.
- The 567 macOS unit tests continue to build and pass with zero regressions (`swift test`).
- The Windows C# code uses standard .NET 8 / WinUI 3 syntax ready for Windows CI/CD pipelines.
