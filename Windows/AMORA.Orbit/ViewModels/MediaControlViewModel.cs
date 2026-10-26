using System.ComponentModel;
using System.Runtime.CompilerServices;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.ViewModels;

public class MediaControlViewModel : INotifyPropertyChanged, IDisposable
{
    private readonly IMediaService _mediaService;
    private readonly Action<Action> _dispatch;
    private MediaTrack _track;
    private string _actionStatus = string.Empty;
    private bool _isBusy;
    private bool _disposed;

    public MediaControlViewModel(IMediaService mediaService, Action<Action>? dispatch = null)
    {
        _mediaService = mediaService ?? throw new ArgumentNullException(nameof(mediaService));
        _dispatch = dispatch ?? (action => action());
        _track = _mediaService.CurrentTrack;
        _mediaService.TrackChanged += OnTrackChanged;
    }

    public MediaTrack CurrentTrack => _track;
    public string Title => IsAvailable ? _track.Title : "No media playing";
    public string Artist => IsAvailable ? _track.Artist : "Open a player with Windows media controls";
    public string SourceName => IsAvailable ? (_track.Source == MediaSourceType.System ? "Windows media" : _track.Source.ToString()) : "Windows media";
    public bool HasTrack => IsAvailable;
    public bool IsAvailable => _track.IsAvailable && _mediaService.IsConnected;
    public bool IsPlaying => IsAvailable && _track.IsPlaying;
    public bool CanPlayPause => !_isBusy && IsAvailable && _mediaService.CanTogglePlayPause;
    public bool CanNext => !_isBusy && IsAvailable && _mediaService.CanGoNext;
    public bool CanPrevious => !_isBusy && IsAvailable && _mediaService.CanGoPrevious;
    public bool CanSeek => !_isBusy && IsAvailable && _mediaService.CanSeek;
    public bool HasProgress => IsAvailable && _track.Duration > TimeSpan.Zero;
    public bool HasActionStatus => _actionStatus.Length > 0;
    public string StatusText => _actionStatus.Length > 0 ? _actionStatus : _mediaService.StatusText;
    public string PlayPauseIconGlyph => IsPlaying ? "\uE769" : "\uE768";
    public double ProgressRatio => IsAvailable ? _track.ProgressFraction : 0;
    public string FormattedProgress => IsAvailable && _track.Duration > TimeSpan.Zero
        ? $"{_track.FormattedElapsed} / {_track.FormattedDuration}" : "--:-- / --:--";
    public event PropertyChangedEventHandler? PropertyChanged;

    public Task TogglePlayPauseAsync() => RunActionAsync(_mediaService.TogglePlayPauseAsync);
    public Task NextTrackAsync() => RunActionAsync(_mediaService.NextTrackAsync);
    public Task PreviousTrackAsync() => RunActionAsync(_mediaService.PreviousTrackAsync);
    public Task SeekRelativeAsync(double ratio)
    {
        if (!double.IsFinite(ratio) || !CanSeek || _track.Duration <= TimeSpan.Zero) return Task.CompletedTask;
        return RunActionAsync(() => _mediaService.SeekAsync(_track.Duration.TotalSeconds * Math.Clamp(ratio, 0, 1)));
    }

    private async Task RunActionAsync(Func<Task> action)
    {
        if (_disposed || _isBusy) return;
        _isBusy = true;
        _actionStatus = string.Empty;
        NotifyAllProperties();
        try { await action(); }
        catch (OperationCanceledException) { }
        catch (InvalidOperationException)
        {
            _dispatch(() =>
            {
                if (_disposed) return;
                _actionStatus = string.IsNullOrWhiteSpace(_mediaService.StatusText)
                    ? "This media command is unavailable." : _mediaService.StatusText;
            });
        }
        catch
        {
            _dispatch(() => { if (!_disposed) _actionStatus = "Windows media did not respond. Try the player again."; });
        }
        finally
        {
            _dispatch(() =>
            {
                if (_disposed) return;
                _isBusy = false;
                NotifyAllProperties();
            });
        }
    }

    private void OnTrackChanged(object? sender, MediaTrack track) => _dispatch(() =>
    {
        if (_disposed) return;
        _track = track;
        NotifyAllProperties();
    });

    private void NotifyAllProperties()
    {
        foreach (var property in new[] { nameof(CurrentTrack), nameof(Title), nameof(Artist), nameof(SourceName),
            nameof(HasTrack), nameof(IsAvailable), nameof(IsPlaying), nameof(PlayPauseIconGlyph), nameof(CanPlayPause),
            nameof(CanNext), nameof(CanPrevious), nameof(CanSeek), nameof(HasProgress), nameof(HasActionStatus), nameof(StatusText), nameof(ProgressRatio), nameof(FormattedProgress) })
            OnPropertyChanged(property);
    }

    protected void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _mediaService.TrackChanged -= OnTrackChanged;
    }
}
