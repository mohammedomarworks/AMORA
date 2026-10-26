using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Windowing;
using System.ComponentModel;
using AMORA.Orbit.ViewModels;
using AMORA.Orbit.Services.Implementations;

namespace AMORA.Orbit.Views;
public sealed partial class SettingsWindow : Window
{
    private readonly OrbitViewModel _model;
    private readonly Action<string> _openPage;
    private readonly WindowsFeedbackSoundService _sounds;
    private bool _ready;
    public SettingsWindow(OrbitViewModel model, Action<string> openPage, WindowsFeedbackSoundService sounds)
    {
        InitializeComponent();
        _model = model;
        _openPage = openPage;
        _sounds = sounds;
        Root.DataContext = model;
        _ready = true;
        SelectSection("Appearance");
        model.Settings!.IsOpen = true;
        var id = Win32Interop.GetWindowIdFromWindow(WinRT.Interop.WindowNative.GetWindowHandle(this));
        var window = AppWindow.GetFromWindowId(id);
        try
        {
            window.TitleBar.BackgroundColor = Windows.UI.Color.FromArgb(255,41,42,44);
            window.TitleBar.ForegroundColor = Colors.White;
            window.TitleBar.ButtonBackgroundColor = Windows.UI.Color.FromArgb(255,41,42,44);
            window.TitleBar.ButtonForegroundColor = Colors.White;
        }
        catch { /* Older Windows builds retain their native title bar. */ }
        var area = DisplayArea.GetFromWindowId(id, DisplayAreaFallback.Primary).WorkArea;
        double scale = Math.Max(1, AMORA.Orbit.Interop.NativeMethods.GetDpiForWindow(WinRT.Interop.WindowNative.GetWindowHandle(this)) / 96.0);
        int width = Math.Min((int)(1040 * scale), area.Width - 32), height = Math.Min((int)(760 * scale), area.Height - 32);
        window.MoveAndResize(new Windows.Graphics.RectInt32(area.X+(area.Width-width)/2, area.Y+(area.Height-height)/2, width,height));
        if (model.Presentation != null) model.Presentation.PropertyChanged += OnPreferencesChanged;
        UpdateThemeSelection();
        Closed += (_, _) => { _ready = false; model.Settings.IsOpen = false; if (model.Presentation != null) model.Presentation.PropertyChanged -= OnPreferencesChanged; };
    }
    private void OnSectionChanged(object sender, SelectionChangedEventArgs e)
    { if (_ready && Sections.SelectedItem is ListBoxItem { Tag: string tag }) SelectSection(tag); }
    private void SelectSection(string name)
    {
        foreach (var panel in new FrameworkElement[] { AppearancePanel, BehaviorPanel, SoundsPanel, AiPanel, ContextPanel, MemoryPanel, ModulesPanel, AutomationSettingsPanel, AboutPanel })
            panel.Visibility = Visibility.Collapsed;
        var info = name switch
        {
            "Behavior" => (BehaviorPanel, "Behavior", "Island interaction, idle sleep and auto-collapse timing."),
            "Sounds" => (SoundsPanel, "Sounds", "Subtle Windows audio feedback, volume and preview."),
            "AI" => (AiPanel, "AI Assistant", "Provider configuration and offline Local Brain model setup."),
            "Context" => (ContextPanel, "Context & Proactive", "Local suggestions and explicit control of cloud context."),
            "Memory" => (MemoryPanel, "Memory", "User-approved facts, stored separately from session chat."),
            "Modules" => (ModulesPanel, "Modules & Media", "Immediate controls and privacy-aware local tools."),
            "Automations" => (AutomationSettingsPanel, "Automations", "Local schedules, reminders and allowlisted actions."),
            "About" => (AboutPanel, "About", "AMORA for Windows and local build information."),
            _ => (AppearancePanel, "Appearance", "Visual themes, character sizing, surface opacity and motion effects.")
        };
        info.Item1.Visibility = Visibility.Visible;
        SectionTitle.Text = info.Item2; SectionDescription.Text = info.Item3;
    }
    private void OnTheme(object sender, RoutedEventArgs e)
    { if (sender is FrameworkElement { Tag: string theme } && _model.Presentation != null) _model.Presentation.Theme = theme; }
    private void OnPreferencesChanged(object? sender, PropertyChangedEventArgs e) { if (_ready && e.PropertyName == nameof(PresentationViewModel.Theme)) UpdateThemeSelection(); }
    private void UpdateThemeSelection()
    {
        foreach (var child in ThemeChoices.Children.OfType<Button>())
        {
            bool selected = child.Tag as string == _model.Presentation?.Theme;
            child.BorderThickness = new Thickness(selected ? 2 : 0);
            child.BorderBrush = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["OrbitCyanAccentBrush"];
        }
    }
    private async void OnSavePreferences(object sender, RoutedEventArgs e) { if (_model.Presentation != null) await _model.Presentation.SaveAsync(); }
    private async void OnPreviewSound(object sender, RoutedEventArgs e) => SoundStatus.Text = await _sounds.PlayAsync();
    private void OnKeyChanged(object sender, RoutedEventArgs e) { if (_ready && _model.Settings != null) _model.Settings.ApiKeyInput = SettingsApiKeyBox.Password; }
    private async void OnSaveProvider(object sender, RoutedEventArgs e)
    { if (_model.Settings != null) { await _model.Settings.SaveAsync(); SettingsApiKeyBox.Password = ""; } }
    private async void OnTestProvider(object sender, RoutedEventArgs e) { if (_model.Settings != null) await _model.Settings.TestConnectionAsync(); }
    private async void OnDeleteKey(object sender, RoutedEventArgs e) { if (_model.Settings != null) { await _model.Settings.ClearKeyAsync(); SettingsApiKeyBox.Password = ""; } }
    private async void OnInstallBrain(object sender, RoutedEventArgs e) { if (_model.LocalBrain != null) await _model.LocalBrain.InstallAsync(); }
    private async void OnStartBrain(object sender, RoutedEventArgs e) { if (_model.LocalBrain != null) await _model.LocalBrain.StartAsync(); }
    private async void OnStopBrain(object sender, RoutedEventArgs e) { if (_model.LocalBrain != null) await _model.LocalBrain.StopAsync(); }
    private void OnCancelBrain(object sender, RoutedEventArgs e) => _model.LocalBrain?.Cancel();
    private async void OnDeleteBrain(object sender, RoutedEventArgs e)
    {
        if (_model.LocalBrain == null) return;
        var confirm = new ContentDialog { XamlRoot=Root.XamlRoot, RequestedTheme=ElementTheme.Dark, Title="Remove this local model?", Content="The downloaded model is deleted from this PC. You can install it again later.", PrimaryButtonText="Remove", CloseButtonText="Cancel", DefaultButton=ContentDialogButton.Close };
        if (await confirm.ShowAsync() == ContentDialogResult.Primary) await _model.LocalBrain.DeleteAsync();
    }
    private async void OnUseBrain(object sender, RoutedEventArgs e) { if (_model.LocalBrain != null) await _model.LocalBrain.UseSelectedAsync(); }
    private async void OnRegisterBrowser(object sender, RoutedEventArgs e) { if (_model.BrowserBridge != null) await _model.BrowserBridge.RegisterNativeHostAsync(); }
    private async void OnUnregisterBrowser(object sender, RoutedEventArgs e) { if (_model.BrowserBridge != null) await _model.BrowserBridge.UnregisterNativeHostAsync(); }
    private void OnReviewMemories(object sender, RoutedEventArgs e) { _openPage("memory"); Close(); }
    private void OnOpenAutomations(object sender, RoutedEventArgs e) { _openPage("automations"); Close(); }
}
