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
│   │   ├── MascotExpression.cs                   # Mascot moods and facial expressions
│   │   ├── MediaTrack.cs                         # Media metadata and playback formatting
│   │   ├── TimerState.cs                         # Focus timer snapshots and progress
│   │   ├── ProactiveSuggestion.cs                # Proactive intelligence suggestions
│   │   ├── BatterySnapshot.cs                    # Power status with Desktop AC fallback
│   │   └── SystemTelemetrySnapshot.cs            # CPU & RAM hardware metrics
│   ├── Services/
│   │   ├── Contracts/                            # Decoupled service interfaces
│   │   │   ├── IBatteryService.cs
│   │   │   ├── IHotKeyService.cs
│   │   │   ├── IMediaService.cs
│   │   │   ├── ISuggestionService.cs
│   │   │   ├── ISystemTelemetryService.cs
│   │   │   ├── ITaskbarTrayService.cs
│   │   │   ├── ITimerService.cs
│   │   │   └── IWindowPositioningService.cs
│   │   └── Implementations/                      # Windows & Preview implementations
│   │       ├── WindowsWindowPositioningService.cs # Multi-monitor work area & clamp math
│   │       ├── WindowsBatteryService.cs          # Win32 GetSystemPowerStatus
│   │       ├── PreviewBatteryService.cs          # Offline / preview battery mock
│   │       ├── WindowsSystemTelemetryService.cs  # Win32 GetSystemTimes & GlobalMemoryStatusEx
│   │       ├── PreviewSystemTelemetryService.cs  # Offline / preview telemetry mock
│   │       ├── WindowsMediaService.cs            # WinRT GlobalSystemMediaTransportControls
│   │       ├── PreviewMediaService.cs            # Offline / interactive preview media
│   │       ├── StandardTimerService.cs           # Thread-safe focus countdown timer
│   │       ├── ProactiveSuggestionService.cs     # Suggestion queue, snooze, and dismiss
│   │       ├── WindowsHotKeyService.cs           # Win32 RegisterHotKey (Ctrl+Alt+O)
│   │       └── TaskbarTrayService.cs             # Win32 Shell_NotifyIcon tray integration
│   ├── ViewModels/                               # MVVM ViewModels
│   │   ├── OrbitViewModel.cs                     # Master capsule state machine
│   │   ├── RobotMascotViewModel.cs               # Mascot expressions and interactive reactions
│   │   ├── MediaControlViewModel.cs              # Media playback controls
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
    ├── PositioningServiceTests.cs                # Work area centering, DPI & clamping tests
    ├── TimerServiceTests.cs                      # Countdown, pause, resume, and add minute tests
    ├── BatteryServiceTests.cs                    # Desktop AC vs laptop battery parsing tests
    ├── TelemetryServiceTests.cs                  # CPU & RAM metric calculations tests
    ├── SuggestionServiceTests.cs                 # Action execution, snooze, and dismiss tests
    ├── MascotExpressionTests.cs                  # Expression factory state tests
    └── MediaTrackTests.cs                        # Duration formatting & progress percent tests
```

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

### Build and Test via Command Line (Windows Machine)
```cmd
cd Windows
dotnet build AMORA.sln -c Release
dotnet test AMORA.Orbit.Tests/AMORA.Orbit.Tests.csproj -c Release
```

> [!NOTE]
> The 7 xUnit test files in `AMORA.Orbit.Tests` were authored and verified for API/model correctness, but Windows App SDK tests require a Windows environment with the Windows App SDK runtime. They cannot be executed on macOS hosts.

---

## macOS Host Compatibility

The macOS host environment runs Swift/AppKit builds and macOS unit tests. The Windows solution is completely decoupled from the macOS build system:
- No shared Swift files or AppKit dependencies are touched by the Windows solution.
- The 567 macOS unit tests continue to build and pass with zero regressions (`swift test`).
- The Windows C# code uses standard .NET 8 / WinUI 3 syntax ready for Windows CI/CD pipelines.

---

## Phase 6E Roadmap (Shared-Core Integration)

In Phase 6E, AMORA Orbit will connect directly to the shared AMORA application engine:
1. **Event Bridge**: Hook `AMORA.Orbit` into the shared event sink (`AmoraEventSink`) established in Phase 6C.
2. **Deterministic Agent Routing**: Connect Orbit suggestion actions to the portable agent loop.
3. **Local AI / LLM Streaming**: Route local model inference into the Orbit mascot speech bubbles and proactive cards.
