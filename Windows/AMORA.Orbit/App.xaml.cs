using Microsoft.UI.Xaml;
using System.Runtime.InteropServices;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;
using AMORA.Orbit.Services.Implementations;
using AMORA.Orbit.ViewModels;
using AMORA.Orbit.Views;

namespace AMORA.Orbit;

public partial class App : Application
{
    private MainWindow? _mainWindow;
    private OrbitViewModel? _orbitViewModel;

    public App()
    {
        // Install process-level diagnostics before XAML/resource initialization.
        AppDomain.CurrentDomain.UnhandledException += OnDomainUnhandledException;
        TaskScheduler.UnobservedTaskException += OnUnobservedTaskException;
        CrashLogger.SetStartupStage("app-constructor-before-xaml");
        UnhandledException += OnUnhandledException;
        try
        {
            InitializeComponent();
            CrashLogger.SetStartupStage("app-xaml-initialized");
        }
        catch (Exception ex)
        {
            CrashLogger.LogException(ex, startupStage: "app-xaml-initialization");
            ShowStartupFailure();
            throw;
        }
    }

    private void OnUnhandledException(object sender, Microsoft.UI.Xaml.UnhandledExceptionEventArgs e)
    {
        try
        {
            CrashLogger.LogException(e.Exception);
        }
        catch
        {
            // Do not fault during crash logging
        }
    }

    private void OnDomainUnhandledException(object sender, System.UnhandledExceptionEventArgs e)
    {
        try
        {
            CrashLogger.LogException(e.ExceptionObject as Exception, startupStage: "app-domain-unhandled");
        }
        catch { }
    }

    private void OnUnobservedTaskException(object? sender, UnobservedTaskExceptionEventArgs e)
    {
        try
        {
            CrashLogger.LogException(e.Exception, startupStage: "unobserved-task");
        }
        catch { }
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        try
        {
            LaunchCore();
        }
        catch (Exception ex)
        {
            CrashLogger.LogException(ex);
            ShowStartupFailure();
            throw;
        }
    }

    private void LaunchCore()
    {
        CrashLogger.SetStartupStage("service-construction");
        var uiDispatcher = Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread();
        Action<Action> dispatch = action =>
        {
            if (uiDispatcher.HasThreadAccess) action();
            else uiDispatcher.TryEnqueue(() => action());
        };
        // 1. Instantiate Core & Secure Settings Services
        ISecureCredentialStorage credentialStorage = new WindowsCredentialStorage();
        IAISettingsService aiSettingsService = new AISettingsService(credentialStorage);
        var presentationVm = new PresentationViewModel(new PresentationPreferencesStore());
        var localBrainService = new LocalBrainService();
        var localBrainVm = new LocalBrainViewModel(localBrainService, aiSettingsService, dispatch);
        _ = localBrainVm.InitializeAsync();
        var gitHubVm = new GitHubActivityViewModel(new GitHubActivityService(credentialStorage), dispatch);
        _ = gitHubVm.InitializeAsync();
        var sounds = new WindowsFeedbackSoundService(presentationVm);

        IWindowPositioningService positioningService = new WindowsWindowPositioningService();
        IBatteryService batteryService = new WindowsBatteryService();
        ISystemTelemetryService telemetryService = new WindowsSystemTelemetryService();
        var browserBridge = new BrowserMediaBridgeService(() => presentationVm.BrowserBridgeEnabled);
        var browserVm = new BrowserBridgeViewModel(browserBridge, dispatch);
        EventHandler browserPreferenceChanged = (_, _) => browserVm.SetEnabled(presentationVm.BrowserBridgeEnabled);
        presentationVm.PreviewChanged += browserPreferenceChanged;
        IMediaService mediaService = new MediaCoordinatorService(new WindowsMediaService(), browserBridge);
        ITimerService timerService = new StandardTimerService();
        ISuggestionService suggestionService = new ProactiveSuggestionService(
            timerService,
            batteryService,
            aiSettingsService,
            () => aiSettingsService.CurrentSettings
        );
        IAutomationService automationService = new LocalAutomationService(
            timerService,
            mediaService,
            suggestionService
        );

        var hotKeyService = new WindowsHotKeyService();
        var trayService = new TaskbarTrayService();

        // 2. Instantiate AI Provider & ViewModels

        IAIProvider aiProvider = new RoutingAIProvider(
            aiSettingsService.GetApiKeyAsync,
            () => aiSettingsService.CurrentSettings,
            localBrainProvider: new LocalBrainAIProvider(localBrainService, () => aiSettingsService.CurrentSettings)
        );

        var settingsVm = new SettingsViewModel(aiSettingsService, aiProvider, dispatch);
        var clipboardService = new ClipboardHistoryService(new WindowsClipboardSource(dispatch));
        clipboardService.SetEnabled(aiSettingsService.CurrentSettings.EnableClipboardHistory);
        EventHandler<AISettings> clipboardSettingsChanged = (_, settings) => clipboardService.SetEnabled(settings.EnableClipboardHistory);
        aiSettingsService.SettingsChanged += clipboardSettingsChanged;
        var clipboardVm = new ClipboardViewModel(clipboardService, dispatch);
        var workspaceService = new WorkspaceToolsService(new JsonWorkspaceStorage(), new WindowsWorkspaceLauncher());
        var workspaceVm = new WorkspaceToolsViewModel(workspaceService, dispatch);
        _ = workspaceVm.InitializeAsync();
        var automationsVm = new AutomationsViewModel(automationService, dispatch);
        _ = automationsVm.LoadAsync();

        var conversationSession = new ConversationSession(
            () => aiSettingsService.CurrentSettings.MaxHistoryTurns
        );

        var router = new DeterministicCommandRouter();
        var assistantEngine = new AssistantEngine(
            router,
            timerService,
            mediaService,
            batteryService,
            telemetryService,
            aiProvider,
            conversationSession,
            () => aiSettingsService.CurrentSettings,
            new ExplicitMemoryService(isEnabled: () => aiSettingsService.CurrentSettings.MemoryEnabled),
            new SafeNavigationService(),
            workspaceService
        );
        var assistantVm = new AssistantCommandViewModel(assistantEngine, dispatch);

        var mascotVm = new RobotMascotViewModel();
        var mediaVm = new MediaControlViewModel(mediaService, dispatch);
        var timerVm = new TimerControlViewModel(timerService, dispatch);
        var suggestionVm = new SuggestionViewModel(suggestionService, dispatch);
        var systemStatusVm = new SystemStatusViewModel(batteryService, telemetryService, dispatch);

        _orbitViewModel = new OrbitViewModel(
            positioningService,
            mascotVm,
            mediaVm,
            timerVm,
            suggestionVm,
            systemStatusVm,
            assistantVm,
            hotKeyService,
            trayService,
            settingsVm,
            automationsVm,
            clipboardVm,
            workspaceVm,
            presentationVm,
            gitHubVm,
            localBrainVm,
            browserVm
        );

        // 3. Create and activate Window
        CrashLogger.SetStartupStage("window-and-xaml-construction");
        _mainWindow = new MainWindow(_orbitViewModel, hotKeyService, trayService, sounds);
        var servicesDisposed = false;
        EventHandler timerCompleteSound = (_, _) => dispatch(async () => { if (!servicesDisposed) await sounds.PlayAsync(); });
        timerService.TimerCompleted += timerCompleteSound;
        _mainWindow.Closed += (_, _) =>
        {
            if (servicesDisposed)
            {
                return;
            }

            servicesDisposed = true;
            presentationVm.PreviewChanged -= browserPreferenceChanged;
            timerService.TimerCompleted -= timerCompleteSound;
            (automationService as IDisposable)?.Dispose();
            localBrainService.Dispose();
            sounds.Dispose();
            aiSettingsService.SettingsChanged -= clipboardSettingsChanged;
            clipboardService.Dispose();
            (mediaService as IDisposable)?.Dispose();
            (timerService as IDisposable)?.Dispose();
            (batteryService as IDisposable)?.Dispose();
            (telemetryService as IDisposable)?.Dispose();
            if (aiProvider is IDisposable disposableProvider)
            {
                disposableProvider.Dispose();
            }
            if (suggestionService is IDisposable disposableSuggestion)
            {
                disposableSuggestion.Dispose();
            }
        };
        CrashLogger.SetStartupStage("window-activation");
        _mainWindow.Activate();
        CrashLogger.SetStartupStage("running");
    }

    private static async Task LoadAutomationsSafelyAsync(IAutomationService service)
    {
        try
        {
            await service.LoadAutomationsAsync();
        }
        catch (Exception ex)
        {
            CrashLogger.LogException(ex, startupStage: "automation-load");
        }
    }

    private static void ShowStartupFailure()
    {
        try
        {
            MessageBoxW(IntPtr.Zero,
                "AMORA Orbit could not finish starting. A sanitized diagnostic report was saved, when possible, to %LOCALAPPDATA%\\AMORA\\Logs\\crash.log. Please include that file when reporting this startup problem.",
                "AMORA Orbit startup error", 0x10);
        }
        catch { }
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "MessageBoxW")]
    private static extern int MessageBoxW(IntPtr hwnd, string text, string caption, uint type);
}
