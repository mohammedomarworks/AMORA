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
        // 1. Instantiate Core & Secure Settings Services
        ISecureCredentialStorage credentialStorage = new WindowsCredentialStorage();
        IAISettingsService aiSettingsService = new AISettingsService(credentialStorage);

        IWindowPositioningService positioningService = new WindowsWindowPositioningService();
        IBatteryService batteryService = new WindowsBatteryService();
        ISystemTelemetryService telemetryService = new WindowsSystemTelemetryService();
        IMediaService mediaService = new PreviewMediaService(); // Falls back to interactive preview
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
        _ = LoadAutomationsSafelyAsync(automationService);

        var hotKeyService = new WindowsHotKeyService();
        var trayService = new TaskbarTrayService();

        // 2. Instantiate AI Provider & ViewModels

        IAIProvider aiProvider = new GeminiAIProvider(
            () => aiSettingsService.GetApiKeyAsync(AISettings.ProviderGemini),
            () => aiSettingsService.CurrentSettings
        );

        var settingsVm = new SettingsViewModel(aiSettingsService, aiProvider);
        var automationsVm = new AutomationsViewModel(automationService);

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
            () => aiSettingsService.CurrentSettings
        );
        var assistantVm = new AssistantCommandViewModel(assistantEngine);

        var mascotVm = new RobotMascotViewModel();
        var mediaVm = new MediaControlViewModel(mediaService);
        var timerVm = new TimerControlViewModel(timerService);
        var suggestionVm = new SuggestionViewModel(suggestionService);
        var systemStatusVm = new SystemStatusViewModel(batteryService, telemetryService);

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
            automationsVm
        );

        // 3. Create and activate Window
        CrashLogger.SetStartupStage("window-and-xaml-construction");
        _mainWindow = new MainWindow(_orbitViewModel, hotKeyService, trayService);
        var servicesDisposed = false;
        _mainWindow.Closed += (_, _) =>
        {
            if (servicesDisposed)
            {
                return;
            }

            servicesDisposed = true;
            if (aiProvider is IDisposable disposableProvider)
            {
                disposableProvider.Dispose();
            }
            if (suggestionService is IDisposable disposableSuggestion)
            {
                disposableSuggestion.Dispose();
            }
            if (automationService is IDisposable disposableAutomation)
            {
                disposableAutomation.Dispose();
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
