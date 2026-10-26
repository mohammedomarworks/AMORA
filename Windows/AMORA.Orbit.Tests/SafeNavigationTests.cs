using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;
using AMORA.Orbit.Services.Implementations;
using Xunit;

namespace AMORA.Orbit.Tests;

public sealed class SafeNavigationTests
{
    [Theory]
    [InlineData("open calculator", SafeApplication.Calculator)]
    [InlineData("Please launch Notepad", SafeApplication.Notepad)]
    [InlineData("can you please open paint?", SafeApplication.Paint)]
    [InlineData("show Windows Settings", SafeApplication.WindowsSettings)]
    public async Task AllowlistedAppIntentsUseOnlyTypedNativeTarget(string input, SafeApplication expected)
    {
        var platform = new Platform();
        var service = new SafeNavigationService(platform);
        var result = await service.TryExecuteAsync(input);
        Assert.Equal(AssistantResultStatus.Success, result!.Status);
        Assert.Equal(expected, Assert.Single(platform.Apps));
        Assert.Empty(platform.Folders);
    }

    [Theory]
    [InlineData("open downloads", SafeKnownFolder.Downloads)]
    [InlineData("show my documents folder", SafeKnownFolder.Documents)]
    [InlineData("open desktop", SafeKnownFolder.Desktop)]
    [InlineData("open my home folder", SafeKnownFolder.Home)]
    public async Task KnownFolderRequiresOwnPendingConfirmation(string input, SafeKnownFolder expected)
    {
        var platform = new Platform();
        var service = new SafeNavigationService(platform);
        Assert.Equal(AssistantResultStatus.Information, (await service.ConfirmAsync()).Status);
        var request = await service.TryExecuteAsync(input);
        Assert.Equal(AssistantResultStatus.NeedsConfirmation, request!.Status);
        Assert.Equal(SafeNavigationService.ConfirmationActionId, request.PendingActionId);
        Assert.Empty(platform.Folders);
        Assert.Equal(AssistantResultStatus.Success, (await service.ConfirmAsync()).Status);
        Assert.Equal(expected, Assert.Single(platform.Folders));
        Assert.Equal(AssistantResultStatus.Information, (await service.ConfirmAsync()).Status);
        Assert.Single(platform.Folders);
    }

    [Theory]
    [InlineData("open powershell")]
    [InlineData("open cmd /c calc.exe")]
    [InlineData("launch C:\\Windows\\System32\\calc.exe")]
    [InlineData("open https://example.com")]
    [InlineData("open calculator && del files")]
    [InlineData("open notepad.exe")]
    [InlineData("open terminal")]
    [InlineData("show \\server\\share")]
    public async Task UnknownAndExecutablePathArgumentsNeverReachNativeLauncher(string input)
    {
        var platform = new Platform();
        var result = await new SafeNavigationService(platform).TryExecuteAsync(input);
        Assert.Equal(AssistantResultStatus.Unsupported, result!.Status);
        Assert.Empty(platform.Apps);
        Assert.Empty(platform.Folders);
        Assert.DoesNotContain(input, result.Message);
    }

    [Theory]
    [InlineData("open notes")]
    [InlineData("open settings")]
    [InlineData("show github")]
    [InlineData("show file shelf")]
    [InlineData("open home")]
    [InlineData("I opened calculator yesterday")]
    [InlineData("start a 5 minute timer")]
    public async Task OtherAndAmoraViewCommandsAreNotCaptured(string input) =>
        Assert.Null(await new SafeNavigationService(new Platform()).TryExecuteAsync(input));

    [Fact]
    public async Task NewInputCancellationAndExpiryInvalidateConfirmation()
    {
        var platform = new Platform();
        var now = DateTimeOffset.UtcNow;
        var service = new SafeNavigationService(platform, () => now);
        await service.TryExecuteAsync("open documents");
        service.CancelPending();
        Assert.Equal(AssistantResultStatus.Information, (await service.ConfirmAsync()).Status);
        await service.TryExecuteAsync("open documents");
        await service.TryExecuteAsync("hello");
        Assert.Equal(AssistantResultStatus.Information, (await service.ConfirmAsync()).Status);
        await service.TryExecuteAsync("open documents");
        now = now.AddMinutes(3);
        Assert.Equal(AssistantResultStatus.Information, (await service.ConfirmAsync()).Status);
        Assert.Empty(platform.Folders);
    }

    [Fact]
    public async Task FailedNativeLaunchIsNotReportedAsSuccess()
    {
        var platform = new Platform { Result = false };
        var service = new SafeNavigationService(platform);
        Assert.Equal(AssistantResultStatus.Unsupported, (await service.TryExecuteAsync("open calculator"))!.Status);
        await service.TryExecuteAsync("open documents");
        Assert.Equal(AssistantResultStatus.Unsupported, (await service.ConfirmAsync()).Status);
    }

    [Fact]
    public async Task CanceledRequestDoesNotLaunchOrArmConfirmation()
    {
        var platform = new Platform();
        var service = new SafeNavigationService(platform);
        using var source = new CancellationTokenSource();
        source.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => service.TryExecuteAsync("open documents", source.Token));
        Assert.Equal(AssistantResultStatus.Information, (await service.ConfirmAsync()).Status);
        Assert.Empty(platform.Folders);
    }

    [Theory]
    [InlineData(SafeApplication.Calculator, "calculator:")]
    [InlineData(SafeApplication.WindowsSettings, "ms-settings:")]
    public async Task MissingProtocolNeverInvokesLaunchOrExecutableFallback(SafeApplication app, string expected)
    {
        var queried = new List<string>();
        int launches = 0;
        var platform = new WindowsSafeNavigationPlatform(
            (uri, _) => { queried.Add(uri.OriginalString); return Task.FromResult(false); },
            (_, _) => { launches++; return Task.FromResult(true); },
            (_, _) => throw new InvalidOperationException("Executable fallback is forbidden."));
        Assert.False(await platform.OpenApplicationAsync(app));
        Assert.Equal(expected, Assert.Single(queried));
        Assert.Equal(0, launches);
    }

    [Theory]
    [InlineData(SafeApplication.Calculator, "calculator:")]
    [InlineData(SafeApplication.WindowsSettings, "ms-settings:")]
    public async Task AvailableProtocolUsesOnlyPreflightedFixedUriAndPropagatesRejection(SafeApplication app, string expected)
    {
        var calls = new List<string>();
        var platform = new WindowsSafeNavigationPlatform(
            (uri, _) => { calls.Add("query " + uri.OriginalString); return Task.FromResult(true); },
            (uri, _) => { calls.Add("launch " + uri.OriginalString); return Task.FromResult(false); },
            (_, _) => throw new InvalidOperationException("Executable fallback is forbidden."));
        Assert.False(await platform.OpenApplicationAsync(app));
        Assert.Equal(new[] { "query " + expected, "launch " + expected }, calls);
    }

    [Theory]
    [InlineData(SafeApplication.Notepad, "notepad.exe")]
    [InlineData(SafeApplication.Paint, "mspaint.exe")]
    public async Task Win32TargetsUseOnlyFixedSystemPathsAndRejectUnconfirmedStubResult(SafeApplication app, string expected)
    {
        string? requested = null;
        var platform = new WindowsSafeNavigationPlatform(
            (_, _) => throw new InvalidOperationException("No arbitrary protocol probing."),
            (_, _) => throw new InvalidOperationException("No protocol fallback."),
            (path, _) => { requested = path; return Task.FromResult(false); });
        Assert.False(await platform.OpenApplicationAsync(app));
        Assert.Equal(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), expected), requested);
    }

    [Fact]
    public async Task CancellationAfterProtocolPreflightDoesNotLaunch()
    {
        using var source = new CancellationTokenSource();
        int launches = 0;
        var platform = new WindowsSafeNavigationPlatform(
            (_, _) => { source.Cancel(); return Task.FromResult(true); },
            (_, _) => { launches++; return Task.FromResult(true); });
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => platform.OpenApplicationAsync(SafeApplication.Calculator, source.Token));
        Assert.Equal(0, launches);
    }

    [Fact]
    public async Task AcceptedLaunchRequestDoesNotClaimAVisibleWindowWasOpened()
    {
        var result = await new SafeNavigationService(new Platform()).TryExecuteAsync("open notepad");
        Assert.Equal(AssistantResultStatus.Success, result!.Status);
        Assert.Equal("Windows accepted the request to open Notepad.", result.Message);
        Assert.DoesNotContain("Opened", result.Message);
    }

    private sealed class Platform : ISafeNavigationPlatform
    {
        public List<SafeApplication> Apps { get; } = new();
        public List<SafeKnownFolder> Folders { get; } = new();
        public bool Result { get; init; } = true;
        public Task<bool> OpenApplicationAsync(SafeApplication application, CancellationToken cancellationToken = default)
        { cancellationToken.ThrowIfCancellationRequested(); Apps.Add(application); return Task.FromResult(Result); }
        public Task<bool> OpenKnownFolderAsync(SafeKnownFolder folder, CancellationToken cancellationToken = default)
        { cancellationToken.ThrowIfCancellationRequested(); Folders.Add(folder); return Task.FromResult(Result); }
    }
}
