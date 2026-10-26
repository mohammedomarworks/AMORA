using System.ComponentModel;
using System.Runtime.CompilerServices;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.ViewModels;

public class TimerControlViewModel : INotifyPropertyChanged, IDisposable
{
    private readonly ITimerService _timerService;
    private TimerSnapshot _snapshot;
    private readonly Action<Action> _dispatch;
    private bool _disposed;

    public TimerControlViewModel(ITimerService timerService, Action<Action>? dispatch = null)
    {
        _dispatch = dispatch ?? (action => action());
        _timerService = timerService ?? throw new ArgumentNullException(nameof(timerService));
        _snapshot = _timerService.CurrentTimer;

        _timerService.TimerUpdated += OnTimerUpdated;
        _timerService.TimerFinished += OnTimerFinished;
    }

    public TimerSnapshot Snapshot => _snapshot;

    public string TimeRemainingFormatted => _snapshot.FormattedRemaining;
    public double ProgressRatio => _snapshot.ProgressPercent;
    public TimerStatus Status => _snapshot.Status;
    public string Label => _snapshot.Label;

    public bool HasActiveTimer => _snapshot.IsActive;
    public string PauseResumeGlyph => IsRunning ? "\uE769" : "\uE768";
    public bool IsRunning => _snapshot.Status == TimerStatus.Running;
    public bool IsPaused => _snapshot.Status == TimerStatus.Paused;

    public string StatusText => _snapshot.Status switch
    {
        TimerStatus.Running => "Focusing",
        TimerStatus.Paused => "Paused",
        TimerStatus.Completed => "Time's up!",
        _ => "Timer off"
    };

    public event PropertyChangedEventHandler? PropertyChanged;

    public void StartPreset(int minutes)
    {
        string label = minutes switch
        {
            5 => "Quick Break",
            15 => "Short Sprint",
            25 => "Pomodoro Focus",
            _ => $"{minutes}m Focus"
        };
        _timerService.Start(TimeSpan.FromMinutes(minutes), label);
    }

    public void TogglePause()
    {
        if (IsRunning)
        {
            _timerService.Pause();
        }
        else if (IsPaused)
        {
            _timerService.Resume();
        }
    }

    public void Cancel()
    {
        _timerService.Cancel();
    }

    public void AddOneMinute()
    {
        _timerService.AddMinute();
    }

    private void OnTimerUpdated(object? sender, TimerSnapshot snapshot)
    {
        _dispatch(() => { if (!_disposed) { _snapshot = snapshot; NotifyProperties(); } });
    }

    private void OnTimerFinished(object? sender, TimerSnapshot snapshot)
    {
        OnTimerUpdated(sender, snapshot);
    }

    private void NotifyProperties()
    {
        OnPropertyChanged(nameof(Snapshot));
        OnPropertyChanged(nameof(TimeRemainingFormatted));
        OnPropertyChanged(nameof(ProgressRatio));
        OnPropertyChanged(nameof(Status));
        OnPropertyChanged(nameof(Label));
        OnPropertyChanged(nameof(HasActiveTimer));
        OnPropertyChanged(nameof(IsRunning));
        OnPropertyChanged(nameof(IsPaused));
        OnPropertyChanged(nameof(StatusText));
        OnPropertyChanged(nameof(PauseResumeGlyph));
    }

    protected void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }

    public void Dispose()
    {
        _disposed = true;
        _timerService.TimerUpdated -= OnTimerUpdated;
        _timerService.TimerFinished -= OnTimerFinished;
    }
}
