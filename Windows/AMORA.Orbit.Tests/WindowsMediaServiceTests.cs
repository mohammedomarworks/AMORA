using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Implementations;
using AMORA.Orbit.ViewModels;
using Xunit;

namespace AMORA.Orbit.Tests;

public class WindowsMediaServiceTests
{
    [Fact]
    public async Task NoSession_StaysUnavailableAndCannotPretendPlaybackSucceeded()
    {
        var backend = new ControlledBackend { Snapshot = WindowsMediaSnapshot.Empty };
        using var service = new WindowsMediaService(backend, startPolling: false);
        await service.RefreshAsync();
        Assert.False(service.IsConnected);
        Assert.False(service.CanTogglePlayPause);
        await Assert.ThrowsAsync<InvalidOperationException>(() => service.PlayAsync());
        Assert.Equal(0, backend.Executions);
        Assert.Contains("No active", service.StatusText);
    }

    [Fact]
    public async Task RejectedCommand_ReportsFailureInsteadOfChangingPlaybackState()
    {
        var backend = new ControlledBackend { AcceptCommand = false };
        using var service = new WindowsMediaService(backend, startPolling: false);
        await Assert.ThrowsAsync<InvalidOperationException>(() => service.PlayAsync());
        Assert.Equal(1, backend.Executions);
        Assert.False(service.CurrentTrack.IsPlaying);
        Assert.Contains("rejected", service.StatusText);
    }

    [Fact]
    public async Task UnsupportedControl_DoesNotCallPlayer()
    {
        var backend = new ControlledBackend();
        using var service = new WindowsMediaService(backend, startPolling: false);
        await service.RefreshAsync();
        Assert.False(service.CanGoNext);
        await Assert.ThrowsAsync<InvalidOperationException>(() => service.NextTrackAsync());
        Assert.Equal(0, backend.Executions);
    }

    [Fact]
    public async Task AcceptedPlayback_RefreshesActualPlayerState()
    {
        var backend = new ControlledBackend();
        using var service = new WindowsMediaService(backend, startPolling: false);
        await service.PlayAsync();
        Assert.True(service.CurrentTrack.IsPlaying);
        Assert.Equal(string.Empty, service.StatusText);
    }

    [Fact]
    public async Task Toggle_FallsBackToSupportedExplicitPlay()
    {
        var backend = new ControlledBackend { Snapshot = ControlledBackend.Available with { CanToggle = false } };
        using var service = new WindowsMediaService(backend, startPolling: false);
        await service.RefreshAsync();
        Assert.True(service.CanTogglePlayPause);
        await service.TogglePlayPauseAsync();
        Assert.True(service.CurrentTrack.IsPlaying);
        Assert.Equal(1, backend.Executions);
    }

    [Fact]
    public async Task PollFailure_ClearsStaleTrackWithoutExposingExceptionContent()
    {
        var backend = new ControlledBackend();
        using var service = new WindowsMediaService(backend, startPolling: false);
        await service.RefreshAsync();
        Assert.True(service.IsConnected);
        backend.ReadError = new InvalidOperationException("private media metadata");
        await service.RefreshAsync();
        Assert.False(service.IsConnected);
        Assert.False(service.CurrentTrack.IsAvailable);
        Assert.DoesNotContain("private", service.StatusText);
    }

    [Fact]
    public async Task Seek_ClampsToKnownDurationAndRejectsNonFiniteInput()
    {
        var backend = new ControlledBackend();
        using var service = new WindowsMediaService(backend, startPolling: false);
        await service.SeekAsync(999);
        Assert.Equal(180, backend.LastSeek);
        await Assert.ThrowsAsync<ArgumentOutOfRangeException>(() => service.SeekAsync(double.NaN));
        Assert.Equal(1, backend.Executions);
    }

    [Theory]
    [InlineData("chrome.exe", MediaSourceType.System)]
    [InlineData("msedge.exe", MediaSourceType.System)]
    [InlineData("Microsoft.ZuneMusic", MediaSourceType.System)]
    [InlineData("Spotify.exe", MediaSourceType.Spotify)]
    [InlineData("AppleInc.AppleMusic", MediaSourceType.AppleMusic)]
    public void SourceIdentity_DoesNotInventWebsiteOrPlayer(string appId, MediaSourceType expected) =>
        Assert.Equal(expected, WindowsMediaService.ClassifySource(appId));

    [Fact]
    public async Task ViewModel_UsesAvailabilityAndDispatchesSessionUpdates()
    {
        var backend = new ControlledBackend { Snapshot = WindowsMediaSnapshot.Empty };
        using var service = new WindowsMediaService(backend, startPolling: false);
        var queued = new Queue<Action>();
        using var vm = new MediaControlViewModel(service, action => queued.Enqueue(action));
        Assert.False(vm.HasTrack);
        backend.Snapshot = ControlledBackend.Available;
        await service.RefreshAsync();
        Assert.False(vm.HasTrack);
        while (queued.TryDequeue(out var action)) action();
        Assert.True(vm.HasTrack);
        Assert.Equal("Test track", vm.Title);
        Assert.True(vm.CanPlayPause);
        Assert.False(vm.CanNext);
    }

    [Fact]
    public async Task ViewModel_ActionFailureIsVisibleAndDoesNotEscapeAsyncClick()
    {
        var backend = new ControlledBackend { AcceptCommand = false };
        using var service = new WindowsMediaService(backend, startPolling: false);
        await service.RefreshAsync();
        using var vm = new MediaControlViewModel(service);
        await vm.TogglePlayPauseAsync();
        Assert.Contains("rejected", vm.StatusText);
        Assert.False(vm.IsPlaying);
        Assert.True(vm.CanPlayPause);
    }

    [Fact]
    public async Task DisposedService_DoesNotPublishInFlightSessionData()
    {
        var backend = new ControlledBackend();
        using var service = new WindowsMediaService(backend, startPolling: false);
        var updates = 0;
        service.TrackChanged += (_, _) => updates++;
        service.Dispose();
        await service.RefreshAsync();
        Assert.Equal(0, updates);
        Assert.Equal(0, backend.Reads);
    }

    private sealed class ControlledBackend : IWindowsMediaSessionBackend
    {
        public static WindowsMediaSnapshot Available => new(new MediaTrack("Test track", "Test artist",
            Source: MediaSourceType.System, IsPlaying: false, Duration: TimeSpan.FromSeconds(180)),
            CanPlay: true, CanPause: true, CanToggle: true, CanSeek: true);
        public WindowsMediaSnapshot Snapshot { get; set; } = Available;
        public bool AcceptCommand { get; set; } = true;
        public Exception? ReadError { get; set; }
        public int Executions { get; private set; }
        public int Reads { get; private set; }
        public double LastSeek { get; private set; }
        public Task<WindowsMediaSnapshot> ReadAsync(CancellationToken token)
        {
            Reads++;
            token.ThrowIfCancellationRequested();
            if (ReadError != null) throw ReadError;
            return Task.FromResult(Snapshot);
        }
        public Task<bool> ExecuteAsync(WindowsMediaAction action, double seconds, CancellationToken token)
        {
            Executions++;
            LastSeek = seconds;
            if (AcceptCommand && action == WindowsMediaAction.Play)
                Snapshot = Snapshot with { Track = Snapshot.Track with { IsPlaying = true } };
            return Task.FromResult(AcceptCommand);
        }
    }
}
