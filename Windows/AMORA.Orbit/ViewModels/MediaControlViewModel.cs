using System.ComponentModel;
using System.Runtime.CompilerServices;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.ViewModels;

public class MediaControlViewModel : INotifyPropertyChanged, IDisposable
{
    private readonly IMediaService _mediaService;
    private MediaTrack? _track;
    private bool _isPlaying;

    public MediaControlViewModel(IMediaService mediaService)
    {
        _mediaService = mediaService ?? throw new ArgumentNullException(nameof(mediaService));
        _track = _mediaService.CurrentTrack;
        _isPlaying = _track?.IsPlaying ?? false;

        _mediaService.TrackChanged += OnTrackChanged;
    }

    public MediaTrack? CurrentTrack => _track;

    public string Title => _track?.Title ?? "No Media Playing";
    public string Artist => _track?.Artist ?? "AMORA Audio";
    public string SourceName => _track?.Source.ToString() ?? "Windows";
    public bool HasTrack => _track != null;

    public bool IsPlaying
    {
        get => _isPlaying;
        private set
        {
            if (_isPlaying != value)
            {
                _isPlaying = value;
                OnPropertyChanged();
                OnPropertyChanged(nameof(PlayPauseIconGlyph));
            }
        }
    }

    public string PlayPauseIconGlyph => _isPlaying ? "\uE769" : "\uE768"; // Segoe Fluent Icons: Pause / Play

    public double ProgressRatio => _track?.ProgressPercent ?? 0.0;

    public string FormattedProgress
    {
        get
        {
            if (_track == null || _track.Duration <= TimeSpan.Zero)
            {
                return "--:-- / --:--";
            }
            return $"{_track.FormattedElapsed} / {_track.FormattedDuration}";
        }
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public async Task TogglePlayPauseAsync()
    {
        await _mediaService.TogglePlayPauseAsync();
    }

    public async Task NextTrackAsync()
    {
        await _mediaService.NextTrackAsync();
    }

    public async Task PreviousTrackAsync()
    {
        await _mediaService.PreviousTrackAsync();
    }

    public async Task SeekRelativeAsync(double ratio)
    {
        if (_track != null && _track.Duration > TimeSpan.Zero)
        {
            double clamped = Math.Clamp(ratio, 0.0, 1.0);
            var target = TimeSpan.FromSeconds(_track.Duration.TotalSeconds * clamped);
            await _mediaService.SeekToAsync(target);
        }
    }

    private void OnTrackChanged(object? sender, MediaTrack? track)
    {
        _track = track;
        IsPlaying = track?.IsPlaying ?? false;
        NotifyAllProperties();
    }

    private void NotifyAllProperties()
    {
        OnPropertyChanged(nameof(CurrentTrack));
        OnPropertyChanged(nameof(Title));
        OnPropertyChanged(nameof(Artist));
        OnPropertyChanged(nameof(SourceName));
        OnPropertyChanged(nameof(HasTrack));
        OnPropertyChanged(nameof(ProgressRatio));
        OnPropertyChanged(nameof(FormattedProgress));
    }

    protected void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }

    public void Dispose()
    {
        _mediaService.TrackChanged -= OnTrackChanged;
    }
}
