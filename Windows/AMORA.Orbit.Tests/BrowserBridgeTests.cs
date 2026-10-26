using System.IO.Pipes;
using System.Text.Json;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.BrowserBridge;
using AMORA.Orbit.Services.Contracts;
using AMORA.Orbit.Services.Implementations;
using AMORA.Orbit.ViewModels;
using Xunit;

namespace AMORA.Orbit.Tests;

public class BrowserBridgeTests
{
    private sealed class Transport : IBrowserBridgeTransport
    {
        public bool Enabled, Disposed;
        public List<string> Commands { get; } = [];
        public event EventHandler<string>? MessageReceived;
        public event EventHandler<bool>? ConnectionChanged;
        public void SetEnabled(bool enabled) => Enabled = enabled;
        public void Connect(bool connected = true) => ConnectionChanged?.Invoke(this, connected);
        public void Receive(string json) => MessageReceived?.Invoke(this, json);
        public Task SendAsync(string message, CancellationToken token)
        { token.ThrowIfCancellationRequested(); Commands.Add(message); return Task.CompletedTask; }
        public void Dispose() => Disposed = true;
        public string LastCommand => Commands.Last(x => x.Contains("mediaCommand"));
    }
    private sealed class Clock : TimeProvider
    {
        public DateTimeOffset Now = new(2026, 10, 27, 12, 0, 0, TimeSpan.Zero);
        public override DateTimeOffset GetUtcNow() => Now;
    }
    private static string State(bool playing = false, int tab = 17, string url = "https://www.youtube.com/watch?v=local-test") => JsonSerializer.Serialize(new
    {
        type = "mediaState", browser = "Chrome", provider = "YouTube", tabId = tab, windowId = 4,
        title = "Controlled protocol fixture", channel = "AMORA", isPlaying = playing,
        duration = 120d, currentTime = 12d, url, contentScriptReady = true, hasVideo = true, trackedMediaTabCount = 1
    });
    private static string Ack(string command, bool success = true, int? tabOverride = null, string? actionOverride = null)
    {
        using var doc = BrowserWireProtocol.Parse(command);
        var value = doc.RootElement;
        var action = actionOverride ?? value.GetProperty("action").GetString();
        var tab = tabOverride ?? value.GetProperty("tabId").GetInt32();
        return JsonSerializer.Serialize(new { type = "mediaCommandResult", provider = "youtube", requestId = value.GetProperty("requestId").GetString(), action,
            tabId = tab, success, reason = success ? null : "target_tab_does_not_exist", state = JsonSerializer.Deserialize<JsonElement>(State(action == "play", tab)) });
    }

    [Theory]
    [InlineData("https://www.youtube.com/watch?v=one", true)]
    [InlineData("https://youtube.com/shorts/one", true)]
    [InlineData("https://youtu.be/one", true)]
    [InlineData("http://youtube.com/watch?v=one", false)]
    [InlineData("https://youtube.com.evil.test/watch?v=one", false)]
    [InlineData("https://youtube.com@evil.test/watch?v=one", false)]
    [InlineData("https://youtube.com:8443/watch?v=one", false)]
    [InlineData("https://youtube.com/feed/history", false)]
    [InlineData("file:///C:/private.txt", false)]
    public void MediaUrlsAreNarrowlyAllowlisted(string url, bool allowed) => Assert.Equal(allowed, BrowserWireProtocol.IsYouTubeUrl(url));

    [Fact]
    public async Task FramingRoundTripsMessagesAndRejectsInvalidLengths()
    {
        using var buffer = new MemoryStream();
        await BrowserWireProtocol.WriteAsync(buffer, "{\"type\":\"hello\"}");
        buffer.Position = 0;
        Assert.Equal("{\"type\":\"hello\"}", await BrowserWireProtocol.ReadAsync(buffer));
        Assert.Null(await BrowserWireProtocol.ReadAsync(buffer));
        using var invalid = new MemoryStream([1, 0, 1, 0]); // 65537 exceeds the bound.
        await Assert.ThrowsAsync<InvalidDataException>(() => BrowserWireProtocol.ReadAsync(invalid));
        using var truncated = new MemoryStream([8, 0, 0, 0, 123]);
        await Assert.ThrowsAsync<EndOfStreamException>(() => BrowserWireProtocol.ReadAsync(truncated));
    }

    [Fact]
    public void ProtocolDropsUnknownPrivateFieldsAndRejectsArbitraryActions()
    {
        var payload = State()[..^1] + ",\"pageContent\":\"private browser text\",\"cookies\":\"secret\"}";
        var normalized = BrowserWireProtocol.NormalizeBrowserMessage(payload);
        Assert.NotNull(normalized);
        Assert.DoesNotContain("private browser text", normalized);
        Assert.DoesNotContain("secret", normalized);
        Assert.Null(BrowserWireProtocol.NormalizeBrowserMessage(State(url: "https://example.com/watch")));
        Assert.Null(BrowserWireProtocol.NormalizeAppCommand(JsonSerializer.Serialize(new { type = "mediaCommand", provider = "youtube", tabId = 17, requestId = Guid.NewGuid(), action = "executeScript" })));
    }

    [Fact]
    public void DisabledByDefaultNeverAcceptsBrowserMetadata()
    {
        var transport = new Transport();
        using var bridge = new BrowserMediaBridgeService(() => false, transport, startPolling: false);
        transport.Connect(); transport.Receive(State(true));
        Assert.False(transport.Enabled);
        Assert.False(bridge.IsConnected);
        Assert.False(bridge.CurrentTrack.IsAvailable);
        Assert.Empty(transport.Commands);
    }

    [Fact]
    public async Task SuccessfulCommandRequiresMatchingAcknowledgementAndUpdatesRealState()
    {
        var transport = new Transport();
        using var bridge = new BrowserMediaBridgeService(() => true, transport, startPolling: false);
        transport.Connect(); transport.Receive(State());
        var play = bridge.PlayAsync();
        Assert.False(play.IsCompleted);
        Assert.False(bridge.CurrentTrack.IsPlaying);
        transport.Receive(Ack(transport.LastCommand));
        await play;
        Assert.True(bridge.CurrentTrack.IsPlaying);
        Assert.False(bridge.CanGoNext);
        Assert.False(bridge.CanSeek);
        await Assert.ThrowsAsync<InvalidOperationException>(() => bridge.NextTrackAsync());
    }

    [Theory]
    [InlineData(99, null)]
    [InlineData(null, "pause")]
    public async Task WrongTargetOrActionNeverClaimsSuccess(int? tab, string? action)
    {
        var transport = new Transport();
        using var bridge = new BrowserMediaBridgeService(() => true, transport, startPolling: false);
        transport.Connect(); transport.Receive(State());
        var play = bridge.PlayAsync();
        transport.Receive(Ack(transport.LastCommand, tabOverride: tab, actionOverride: action));
        await Assert.ThrowsAsync<InvalidOperationException>(() => play);
        Assert.False(bridge.CurrentTrack.IsPlaying);
        Assert.Contains("mismatched", bridge.StatusText);
    }

    [Fact]
    public async Task TimeoutAndLateAcknowledgementCannotCreateSuccess()
    {
        var transport = new Transport();
        using var bridge = new BrowserMediaBridgeService(() => true, transport, startPolling: false) { CommandTimeout = TimeSpan.FromMilliseconds(30) };
        transport.Connect(); transport.Receive(State());
        await Assert.ThrowsAsync<InvalidOperationException>(() => bridge.PlayAsync());
        transport.Receive(Ack(transport.LastCommand));
        Assert.False(bridge.CurrentTrack.IsPlaying);
        Assert.Contains("respond", bridge.StatusText);
    }

    [Fact]
    public async Task DisconnectFailsPendingCommandAndClearsPrivateState()
    {
        var transport = new Transport();
        using var bridge = new BrowserMediaBridgeService(() => true, transport, startPolling: false);
        transport.Connect(); transport.Receive(State());
        var command = bridge.PlayAsync();
        var ack = Ack(transport.LastCommand);
        transport.Connect(false);
        await Assert.ThrowsAsync<InvalidOperationException>(() => command);
        transport.Receive(ack);
        Assert.False(bridge.CurrentTrack.IsAvailable);
        Assert.False(bridge.IsConnected);
    }

    [Fact]
    public async Task DisableRejectsPendingCommandsAndReconnectNeedsFreshState()
    {
        var transport = new Transport();
        using var bridge = new BrowserMediaBridgeService(() => true, transport, startPolling: false);
        transport.Connect(); transport.Receive(State());
        var command = bridge.PlayAsync();
        bridge.SetEnabled(false);
        await Assert.ThrowsAsync<InvalidOperationException>(() => command);
        Assert.False(transport.Enabled);
        Assert.False(bridge.CurrentTrack.IsAvailable);
        bridge.SetEnabled(true); transport.Connect();
        Assert.False(bridge.CurrentTrack.IsAvailable);
        transport.Receive(State(true, 42));
        Assert.True(bridge.CurrentTrack.IsPlaying);
    }

    [Fact]
    public async Task StalePlaybackIsNotPresentedAsCurrent()
    {
        var clock = new Clock(); var transport = new Transport();
        using var bridge = new BrowserMediaBridgeService(() => true, transport, clock, false);
        transport.Connect(); transport.Receive(State(true));
        clock.Now += TimeSpan.FromSeconds(31);
        await bridge.RefreshAsync();
        Assert.False(bridge.CurrentTrack.IsAvailable);
        Assert.Contains("stale", bridge.StatusText);
    }

    [Fact]
    public async Task NamedPipeRoundTripUsesActualCurrentUserWindowsIpc()
    {
        var name = "AMORA.BrowserTests." + Guid.NewGuid().ToString("N");
        using var transport = new NamedPipeBrowserTransport(name);
        var received = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
        var connected = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        transport.MessageReceived += (_, value) => received.TrySetResult(value);
        transport.ConnectionChanged += (_, value) => { if (value) connected.TrySetResult(); };
        transport.SetEnabled(true);
        using var client = new NamedPipeClientStream(".", name, PipeDirection.InOut, PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
        await client.ConnectAsync(3000);
        await connected.Task.WaitAsync(TimeSpan.FromSeconds(3));
        await BrowserWireProtocol.WriteAsync(client, State());
        Assert.Equal(State(), await received.Task.WaitAsync(TimeSpan.FromSeconds(3)));
        var command = JsonSerializer.Serialize(new { type = "mediaCommand", provider = "youtube", tabId = 17, requestId = Guid.NewGuid().ToString(), action = "play" });
        await transport.SendAsync(command, CancellationToken.None);
        Assert.Equal(BrowserWireProtocol.NormalizeAppCommand(command), await BrowserWireProtocol.ReadAsync(client));
        transport.SetEnabled(false);
    }

    private sealed class Registration : IBrowserHostRegistration
    {
        public bool IsRegistered { get; private set; }
        public int Registrations;
        public Task RegisterAsync(CancellationToken token = default) { Registrations++; IsRegistered = true; return Task.CompletedTask; }
        public Task UnregisterAsync(CancellationToken token = default) { IsRegistered = false; return Task.CompletedTask; }
    }
    [Fact]
    public async Task RegistrationIsExplicitAndDoesNotEnableContextCollection()
    {
        var registration = new Registration(); var transport = new Transport();
        using var bridge = new BrowserMediaBridgeService(() => false, transport, startPolling: false);
        using var vm = new BrowserBridgeViewModel(bridge, registration: registration);
        Assert.Equal(0, registration.Registrations);
        await vm.RegisterNativeHostAsync();
        Assert.True(vm.IsHostRegistered);
        Assert.False(vm.Enabled);
        Assert.False(transport.Enabled);
        await vm.UnregisterNativeHostAsync();
        Assert.False(vm.IsHostRegistered);
    }

    private sealed class NativeMedia : IMediaService
    {
        public MediaTrack CurrentTrack { get; set; } = new("Native fixture", "AMORA", Source: MediaSourceType.Spotify, IsPlaying: true);
        public bool IsConnected => true;
        public string ProviderName => "Fixture";
        public int Plays;
        public event EventHandler<MediaTrack>? TrackChanged;
        public Task TogglePlayPauseAsync() => Task.CompletedTask;
        public Task PlayAsync() { Plays++; return Task.CompletedTask; }
        public Task NextTrackAsync() => Task.CompletedTask;
        public Task PreviousTrackAsync() => Task.CompletedTask;
        public Task SeekAsync(double seconds) => Task.CompletedTask;
        public Task RefreshAsync() { TrackChanged?.Invoke(this, CurrentTrack); return Task.CompletedTask; }
    }
    [Fact]
    public async Task CoordinatorKeepsPlayingNativeSessionAheadOfPausedBrowser()
    {
        var native = new NativeMedia(); var transport = new Transport();
        var bridge = new BrowserMediaBridgeService(() => true, transport, startPolling: false);
        using var coordinator = new MediaCoordinatorService(native, bridge);
        transport.Connect(); transport.Receive(State());
        Assert.Equal(MediaSourceType.Spotify, coordinator.CurrentTrack.Source);
        await coordinator.PlayAsync();
        Assert.Equal(1, native.Plays);
        transport.Receive(State(true));
        Assert.Equal(MediaSourceType.YouTube, coordinator.CurrentTrack.Source);
        Assert.False(coordinator.CanGoNext);
        transport.Connect(false);
        Assert.Equal(MediaSourceType.Spotify, coordinator.CurrentTrack.Source);
    }
}
