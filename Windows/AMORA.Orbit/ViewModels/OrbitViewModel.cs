using System.ComponentModel;
using System.Runtime.CompilerServices;
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

    public OrbitViewModel(
        IWindowPositioningService positioningService,
        RobotMascotViewModel mascot,
        MediaControlViewModel media,
        TimerControlViewModel timer,
        SuggestionViewModel suggestion,
        SystemStatusViewModel systemStatus,
        IHotKeyService? hotKeyService = null,
        ITaskbarTrayService? trayService = null)
    {
        _positioningService = positioningService ?? throw new ArgumentNullException(nameof(positioningService));
        Mascot = mascot ?? throw new ArgumentNullException(nameof(mascot));
        Media = media ?? throw new ArgumentNullException(nameof(media));
        Timer = timer ?? throw new ArgumentNullException(nameof(timer));
        Suggestion = suggestion ?? throw new ArgumentNullException(nameof(suggestion));
        SystemStatus = systemStatus ?? throw new ArgumentNullException(nameof(systemStatus));
        _hotKeyService = hotKeyService;
        _trayService = trayService;

        _currentBounds = _positioningService.CalculateBounds(IntPtr.Zero, isExpanded: false);

        if (_hotKeyService != null)
        {
            _hotKeyService.HotKeyPressed += OnHotKeyPressed;
        }

        if (_trayService != null)
        {
            _trayService.ToggleRequested += OnTrayToggleRequested;
        }
    }

    public RobotMascotViewModel Mascot { get; }
    public MediaControlViewModel Media { get; }
    public TimerControlViewModel Timer { get; }
    public SuggestionViewModel Suggestion { get; }
    public SystemStatusViewModel SystemStatus { get; }

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
    public string PinIconGlyph => _isPinned ? "\uE718" : "\uE77A"; // Pin / Unpin

    public event PropertyChangedEventHandler? PropertyChanged;
    public event EventHandler<CapsuleBounds>? BoundsChanged;

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
        if (IsExpanded)
        {
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
            _hoverCollapseCts = null;
            IsHovered = true;
        }
    }

    public void OnPointerExited()
    {
        lock (_hoverLock)
        {
            IsHovered = false;
            if (_isPinned || !_isExpanded) return;

            _hoverCollapseCts?.Cancel();
            _hoverCollapseCts = new CancellationTokenSource();
            var token = _hoverCollapseCts.Token;

            // Grace period before auto-collapsing on exit
            _ = Task.Run(async () =>
            {
                try
                {
                    await Task.Delay(400, token);
                    if (!token.IsCancellationRequested && !_isPinned)
                    {
                        Collapse();
                    }
                }
                catch (TaskCanceledException)
                {
                }
            }, token);
        }
    }

    public void UpdatePosition(IntPtr windowHandle = default)
    {
        // Check fullscreen suppression
        if (_positioningService.IsForegroundAppFullscreen(windowHandle))
        {
            IsVisible = false;
            return;
        }

        IsVisible = true;
        var newBounds = _positioningService.CalculateBounds(windowHandle, _isExpanded);
        CurrentBounds = newBounds;
        BoundsChanged?.Invoke(this, newBounds);
    }

    private void OnHotKeyPressed(object? sender, EventArgs e)
    {
        ToggleExpanded();
    }

    private void OnTrayToggleRequested(object? sender, EventArgs e)
    {
        ToggleExpanded();
    }

    protected void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }

    public void Dispose()
    {
        if (_hotKeyService != null)
        {
            _hotKeyService.HotKeyPressed -= OnHotKeyPressed;
        }

        if (_trayService != null)
        {
            _trayService.ToggleRequested -= OnTrayToggleRequested;
        }

        lock (_hoverLock)
        {
            _hoverCollapseCts?.Cancel();
            _hoverCollapseCts?.Dispose();
        }

        Media.Dispose();
        Timer.Dispose();
        Suggestion.Dispose();
        SystemStatus.Dispose();
    }
}
