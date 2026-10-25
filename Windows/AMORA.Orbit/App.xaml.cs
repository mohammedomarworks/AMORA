using Microsoft.UI.Xaml;
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
        // 1. Instantiate Services
        IWindowPositioningService positioningService = new WindowsWindowPositioningService();
        IBatteryService batteryService = new WindowsBatteryService();
        ISystemTelemetryService telemetryService = new WindowsSystemTelemetryService();
        IMediaService mediaService = new PreviewMediaService(); // Falls back to interactive preview
        ITimerService timerService = new StandardTimerService();
        ISuggestionService suggestionService = new ProactiveSuggestionService();
        var hotKeyService = new WindowsHotKeyService();
        var trayService = new TaskbarTrayService();

        // Seed an initial demo suggestion matching the design concept
        suggestionService.PresentSuggestion(new Models.ProactiveSuggestion(
            Id: "sug-init-1",
            Title: "High Focus Session Recommended",
            Message: "You have 45 minutes of uninterrupted calendar time. Start 25m Pomodoro focus?",
            ActionLabel: "Start Focus",
            Category: "Productivity",
            Priority: Models.SuggestionPriority.Medium,
            OnAction: () =>
            {
                timerService.Start(TimeSpan.FromMinutes(25), "Pomodoro Focus");
                return Task.CompletedTask;
            }
        ));

        // 2. Instantiate ViewModels
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
            hotKeyService,
            trayService
        );

        // 3. Create and activate Window
        _mainWindow = new MainWindow(_orbitViewModel, hotKeyService, trayService);
        _mainWindow.Activate();
    }
}
