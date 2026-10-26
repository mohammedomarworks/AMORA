using System.ComponentModel;
using System.Runtime.CompilerServices;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.ViewModels;

public class OrbitViewModel : INotifyPropertyChanged, IDisposable
{
    private readonly IWindowPositioningService _positioningService;
    private readonly IHotKeyService? _hotKeyService;
    private readonly ITaskbarTrayService? _trayService;

    private bool _isExpanded;
    private bool _isPinned;
    private bool _isVisible = true;
    private bool _isHovered;
    private CapsuleBounds _currentBounds;
    private readonly object _hoverLock = new();
    private CancellationTokenSource? _hoverCollapseCts;
    private IntPtr _windowHandle;
    private Action<Action>? _dispatchToUi;
    private bool _isWorkspaceOpen;
    private bool _hasKeyboardFocus;
    private bool _disposed;
    private CancellationTokenSource? _hoverExpandCts;
    private int _workspaceHeight = 520;
    public string ActivePage { get; set; } = "home";

    public OrbitViewModel(
        IWindowPositioningService positioningService,
        RobotMascotViewModel mascot,
        MediaControlViewModel media,
        TimerControlViewModel timer,
        SuggestionViewModel suggestion,
        SystemStatusViewModel systemStatus,
        AssistantCommandViewModel assistant,
        IHotKeyService? hotKeyService = null,
        ITaskbarTrayService? trayService = null,
        SettingsViewModel? settings = null,
        AutomationsViewModel? automations = null,
        ClipboardViewModel? clipboard = null,
        WorkspaceToolsViewModel? workspace = null,
        PresentationViewModel? presentation = null,
        GitHubActivityViewModel? gitHub = null,
        LocalBrainViewModel? localBrain = null,
        BrowserBridgeViewModel? browserBridge = null)
    {
        _positioningService = positioningService ?? throw new ArgumentNullException(nameof(positioningService));
        Mascot = mascot ?? throw new ArgumentNullException(nameof(mascot));
        Media = media ?? throw new ArgumentNullException(nameof(media));
        Timer = timer ?? throw new ArgumentNullException(nameof(timer));
        Suggestion = suggestion ?? throw new ArgumentNullException(nameof(suggestion));
        SystemStatus = systemStatus ?? throw new ArgumentNullException(nameof(systemStatus));
        Assistant = assistant ?? throw new ArgumentNullException(nameof(assistant));
        Settings = settings;
        Automations = automations;
        Clipboard = clipboard;
        Workspace = workspace;
        Presentation = presentation;
        GitHub = gitHub;
        LocalBrain = localBrain;
        BrowserBridge = browserBridge;
        _hotKeyService = hotKeyService;
        _trayService = trayService;

        if (Automations != null)
        {
            Automations.PropertyChanged += OnPanelPropertyChanged;
        }

        if (Presentation != null) Presentation.PreviewChanged += OnPresentationChanged;
        Mascot.PropertyChanged += OnCompanionChanged;
        Media.PropertyChanged += OnCompanionChanged;
        Timer.PropertyChanged += OnCompanionChanged;
        Suggestion.PropertyChanged += OnCompanionChanged;
        Assistant.PropertyChanged += OnCompanionChanged;

        Assistant.ResultReceived += OnAssistantResultReceived;

        _currentBounds = _positioningService.CalculateCapsuleBounds(IntPtr.Zero, isExpanded: false);

        if (_hotKeyService != null)
        {
            _hotKeyService.HotKeyPressed += OnHotKeyPressed;
        }

        if (_trayService != null)
        {
            _trayService.ToggleRequested += OnTrayToggleRequested;
            _trayService.SettingsRequested += OnTraySettingsRequested;
        }
    }

    public RobotMascotViewModel Mascot { get; }
    public MediaControlViewModel Media { get; }
    public TimerControlViewModel Timer { get; }
    public SuggestionViewModel Suggestion { get; }
    public SystemStatusViewModel SystemStatus { get; }
    public AssistantCommandViewModel Assistant { get; }
    public SettingsViewModel? Settings { get; }
    public AutomationsViewModel? Automations { get; }
    public ClipboardViewModel? Clipboard { get; }
    public WorkspaceToolsViewModel? Workspace { get; }
    public PresentationViewModel? Presentation { get; }
    public GitHubActivityViewModel? GitHub { get; }
    public LocalBrainViewModel? LocalBrain { get; }
    public BrowserBridgeViewModel? BrowserBridge { get; }
    public string SoundGlyph => Presentation?.SoundEnabled == false ? "\uE74F" : "\uE767";
    public string CompanionBadge => Assistant.IsProcessing ? "Thinking" : Suggestion.HasSuggestion ? Suggestion.Category :
        Timer.HasActiveTimer ? Timer.TimeRemainingFormatted : ActivePage == "github" && GitHub?.IsConnected == true ? "GitHub" :
        Media.IsPlaying ? "Music" : Mascot.Mood is not (MascotMood.Idle or MascotMood.Neutral) ? Mascot.StatusDescription : "Online";
    public string CompanionMessage
    {
        get
        {
            if (Assistant.IsProcessing) return "Thinking it through…";
            if (Suggestion.HasSuggestion) return Suggestion.Message;
            if (Mascot.Mood is not (MascotMood.Idle or MascotMood.Neutral or MascotMood.Bored or MascotMood.Sleepy) && !string.IsNullOrWhiteSpace(Mascot.StatusSubtext))
                return Mascot.StatusSubtext.Length <= 100 ? Mascot.StatusSubtext : "Here is what I found. Open Talk to read it.";
            if (Timer.HasActiveTimer) return $"{Timer.Label} ({Timer.TimeRemainingFormatted})";
            if (ActivePage == "github" && GitHub?.IsConnected == true) return GitHub.HasCalendar ? GitHub.ContributionSummary : $"{GitHub.Login} activity synced";
            if (Media.IsPlaying) return $"Listening to {Media.Title}";
            return DateTime.Now.Hour switch { >= 5 and < 12 => "Good morning! Ready when you are.", >= 12 and < 17 => "Good afternoon. Here if you need me.", >= 17 and < 22 => "Good evening. What's on your mind?", _ => "Working late? I'm here with you." };
        }
    }
    public event EventHandler? SettingsRequested;
    public void RequestSettings() => SettingsRequested?.Invoke(this, EventArgs.Empty);
    private void OnCompanionChanged(object? sender, PropertyChangedEventArgs e)
    {
        RefreshCompanion();
        if (sender == Suggestion && e.PropertyName == nameof(SuggestionViewModel.HasSuggestion)) UpdatePosition();
    }
    public void RefreshCompanion() { OnPropertyChanged(nameof(CompanionBadge)); OnPropertyChanged(nameof(CompanionMessage)); }
    private void OnPresentationChanged(object? sender, EventArgs e) { OnPropertyChanged(nameof(SoundGlyph)); UpdatePosition(); }

    public bool IsWorkspaceOpen
    {
        get => _isWorkspaceOpen;
        set
        {
            if (_isWorkspaceOpen == value) return;
            _isWorkspaceOpen = value;
            OnPropertyChanged();
            if (value && !IsExpanded) IsExpanded = true;
            else UpdatePosition();
        }
    }

    public bool HasKeyboardFocus
    {
        get => _hasKeyboardFocus;
        set => _hasKeyboardFocus = value;
    }

    // WinUI flyouts are separate native surfaces. Pointer exit from the island
    // while entering its own menu must not collapse the owner beneath the menu.
    public bool IsTransientOpen { get; set; }

    public void SetWorkspaceOpen(bool open, int height = 520) { _workspaceHeight = height; IsWorkspaceOpen = open; UpdatePosition(); }

    public void SetDispatcher(Action<Action> dispatchToUi) => _dispatchToUi = dispatchToUi;

    private void OnUi(Action action)
    {
        if (_disposed) return;
        if (_dispatchToUi is { } dispatch) dispatch(() => { if (!_disposed) action(); });
        else action();
    }

    private void OnPanelPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName != "IsOpen") return;
        OnUi(() =>
        {
            if (sender == Settings && Settings?.IsOpen == true && Automations != null)
                Automations.IsOpen = false;
            if (sender == Automations && Automations?.IsOpen == true && Settings != null)
                Settings.IsOpen = false;
            if (Automations?.IsOpen == true) SetWorkspaceOpen(true, 460);
        });
    }

    public bool IsExpanded
    {
        get => _isExpanded;
        set
        {
            if (_isExpanded != value)
            {
                _isExpanded = value;
                OnPropertyChanged();
                OnPropertyChanged(nameof(ExpandedVisibility));
                OnPropertyChanged(nameof(CollapsedIndicatorVisibility));
                UpdatePosition();
            }
        }
    }

    public bool IsPinned
    {
        get => _isPinned;
        set
        {
            if (_isPinned != value)
            {
                _isPinned = value;
                OnPropertyChanged();
                OnPropertyChanged(nameof(PinIconGlyph));
            }
        }
    }

    public bool IsVisible
    {
        get => _isVisible;
        set
        {
            if (_isVisible != value)
            {
                _isVisible = value;
                OnPropertyChanged();
            }
        }
    }

    public bool IsHovered
    {
        get => _isHovered;
        private set
        {
            if (_isHovered != value)
            {
                _isHovered = value;
                OnPropertyChanged();
            }
        }
    }

    public CapsuleBounds CurrentBounds
    {
        get => _currentBounds;
        private set
        {
            if (_currentBounds != value)
            {
                _currentBounds = value;
                OnPropertyChanged();
            }
        }
    }

    public bool ExpandedVisibility => _isExpanded;
    public bool CollapsedIndicatorVisibility => !_isExpanded;
    public string PinIconGlyph => _isPinned ? "" : ""; // Pin / Unpin

    public event PropertyChangedEventHandler? PropertyChanged;
    public event EventHandler<CapsuleBounds>? BoundsChanged;
    public event EventHandler? ActivationRequested;

    public void ToggleExpanded()
    {
        IsExpanded = !IsExpanded;
    }

    public void Expand()
    {
        IsExpanded = true;
    }

    public void Collapse()
    {
        if (IsPinned) return;
        IsExpanded = false;
    }

    public void HandleEscape()
    {
        if (Automations?.IsOpen == true)
        {
            Automations.IsOpen = false;
            return;
        }

        if (Settings?.IsOpen == true)
        {
            Settings.IsOpen = false;
            return;
        }

        if (IsWorkspaceOpen)
        {
            Assistant.CancelActiveRequest();
            IsWorkspaceOpen = false;
            return;
        }

        if (IsExpanded)
        {
            Assistant.CancelActiveRequest();
            IsExpanded = false;
            IsPinned = false;
        }
    }

    public void TogglePin()
    {
        IsPinned = !IsPinned;
    }

    public void OnPointerEntered()
    {
        lock (_hoverLock)
        {
            _hoverCollapseCts?.Cancel();
            _hoverCollapseCts?.Dispose();
            _hoverCollapseCts = null;
            IsHovered = true;
            if (Presentation?.HoverToExpand == true && !IsExpanded)
            {
                _hoverExpandCts?.Cancel();
                _hoverExpandCts?.Dispose();
                _hoverExpandCts = new CancellationTokenSource();
                var token = _hoverExpandCts.Token;
                _ = ExpandAfterHoverAsync(token);
            }
        }
    }

    public void OnPointerExited()
    {
        lock (_hoverLock)
        {
            IsHovered = false;
            _hoverExpandCts?.Cancel();
            if (!CanAutoCollapse) return;

            _hoverCollapseCts?.Cancel();
            _hoverCollapseCts?.Dispose();
            _hoverCollapseCts = new CancellationTokenSource();
            var token = _hoverCollapseCts.Token;

            // Grace period before auto-collapsing on exit
            _ = Task.Run(async () =>
            {
                try
                {
                    await Task.Delay(TimeSpan.FromSeconds(Presentation?.AutoCollapseSeconds ?? .4), token);
                    OnUi(() =>
                    {
                        if (!token.IsCancellationRequested && !IsHovered && CanAutoCollapse) Collapse();
                    });
                }
                catch (TaskCanceledException)
                {
                }
            }, token);
        }
    }
    private async Task ExpandAfterHoverAsync(CancellationToken token)
    {
        try
        {
            await Task.Delay(350, token);
            OnUi(() => { if (!token.IsCancellationRequested && IsHovered && Presentation?.HoverToExpand == true && !IsExpanded) Expand(); });
        }
        catch (OperationCanceledException) { }
    }

    public void UpdatePosition(IntPtr windowHandle = default)
    {
        if (_disposed) return;
        if (windowHandle != IntPtr.Zero) _windowHandle = windowHandle;
        // Check fullscreen suppression
        if (Presentation?.AvoidFullscreen != false && _positioningService.IsForegroundAppFullscreen(_windowHandle))
        {
            IsVisible = false;
            return;
        }

        IsVisible = true;
        var newBounds = _positioningService.CalculateCapsuleBounds(_windowHandle, _isExpanded,
            expandedWidth: Presentation != null ? 960 : 860,
            expandedHeight: IsWorkspaceOpen ? _workspaceHeight : Presentation != null ? (Suggestion.HasSuggestion ? 328 : 280) : 300);
        if (CurrentBounds == newBounds) return;
        CurrentBounds = newBounds;
        BoundsChanged?.Invoke(this, newBounds);
    }

    private void OnHotKeyPressed(object? sender, EventArgs e)
    {
        OnUi(() =>
        {
            Mascot.NoteInteraction();
            ToggleExpanded();
            if (IsExpanded && IsVisible) ActivationRequested?.Invoke(this, EventArgs.Empty);
        });
    }

    private void OnTrayToggleRequested(object? sender, EventArgs e)
    {
        OnHotKeyPressed(sender, e);
    }

    private void OnTraySettingsRequested(object? sender, EventArgs e) => OnUi(() =>
    {
        RequestSettings();
    });

    private bool CanAutoCollapse => !_isPinned && _isExpanded && !HasKeyboardFocus && !IsTransientOpen &&
        !IsWorkspaceOpen && !Assistant.IsProcessing && !Assistant.HasPendingConfirmation && !Assistant.HasText;

    protected void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }

    private void OnAssistantResultReceived(object? sender, AssistantExecutionResult result)
    {
        OnUi(() => Mascot.SetMood(result.Mood, result.Message));
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        Assistant.ResultReceived -= OnAssistantResultReceived;
        Mascot.PropertyChanged -= OnCompanionChanged;
        Media.PropertyChanged -= OnCompanionChanged;
        Timer.PropertyChanged -= OnCompanionChanged;
        Suggestion.PropertyChanged -= OnCompanionChanged;
        Assistant.PropertyChanged -= OnCompanionChanged;
        if (Presentation != null) Presentation.PreviewChanged -= OnPresentationChanged;
        if (Settings != null) Settings.PropertyChanged -= OnPanelPropertyChanged;
        if (Automations != null) Automations.PropertyChanged -= OnPanelPropertyChanged;

        if (_hotKeyService != null)
        {
            _hotKeyService.HotKeyPressed -= OnHotKeyPressed;
        }

        if (_trayService != null)
        {
            _trayService.ToggleRequested -= OnTrayToggleRequested;
            _trayService.SettingsRequested -= OnTraySettingsRequested;
        }

        lock (_hoverLock)
        {
            _hoverCollapseCts?.Cancel();
            _hoverCollapseCts?.Dispose();
            _hoverExpandCts?.Cancel();
            _hoverExpandCts?.Dispose();
        }

        Media.Dispose();
        Timer.Dispose();
        Suggestion.Dispose();
        SystemStatus.Dispose();
        Automations?.Dispose();
        Settings?.Dispose();
        Clipboard?.Dispose();
        Workspace?.Dispose();
        GitHub?.Dispose();
        LocalBrain?.Dispose();
        BrowserBridge?.Dispose();
        Presentation?.Dispose();
        Mascot.Dispose();
        Assistant.Dispose();
    }
}
