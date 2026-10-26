using Microsoft.UI.Xaml;
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
        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
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
        var hotKeyService = new WindowsHotKeyService();
        var trayService = new TaskbarTrayService();

        // 2. Instantiate AI Provider & ViewModels

        IAIProvider aiProvider = new GeminiAIProvider(
            () => aiSettingsService.GetApiKeyAsync(AISettings.ProviderGemini),
            () => aiSettingsService.CurrentSettings
        );

        var settingsVm = new SettingsViewModel(aiSettingsService, aiProvider);

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
            settingsVm
        );

        // 3. Create and activate Window
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
        };
        _mainWindow.Activate();
    }
}
