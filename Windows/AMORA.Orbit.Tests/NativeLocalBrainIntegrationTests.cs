using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Implementations;
using System.Net.Http;
using Xunit;

namespace AMORA.Orbit.Tests;

/// <summary>Explicit opt-in only. The fixture must already contain the pinned runtime ZIP, extracted runtime and compact GGUF.</summary>
public sealed class NativeLocalBrainIntegrationTests
{
    [NativeLocalBrainFact]
    [Trait("Category", "NativeLocalBrain")]
    public async Task VerifiedNativeRuntimeProducesRealOfflineAnswerAndStops()
    {
        string root = Environment.GetEnvironmentVariable("AMORA_LOCAL_BRAIN_TEST_ROOT")!;
        using var downloads = new HttpClient(new NoDownloadsHandler());
        using var runtime = new LlamaServerRuntime();
        // A valid cached installation must repair notices even when a new 491 MB download would not fit.
        using var service = new LocalBrainService(root, assets: new LocalBrainAssetStore(root, downloads, availableStorage: () => 4 * 1024 * 1024), runtime: runtime);
        await service.InstallAsync(LocalBrainCatalog.CompactModelId);
        Assert.Equal(LocalBrainState.Installed, service.Snapshot.State);
        Assert.Contains("MIT License", await File.ReadAllTextAsync(Path.Combine(root, "llama-cpp-MIT.txt")));
        Assert.Contains("Apache License", await File.ReadAllTextAsync(Path.Combine(root, "Qwen-Apache-2.0.txt")));
        await service.StartAsync(LocalBrainCatalog.CompactModelId);
        Assert.True(runtime.IsRunning);
        Assert.Equal(LocalBrainState.Ready, service.Snapshot.State);
        string answer = await service.GenerateAsync(LocalBrainCatalog.CompactModelId, "What is 2 + 3? Answer with the number only.");
        Assert.Equal("5", answer.Trim().TrimEnd('.'));
        Assert.Equal(LocalBrainState.Ready, service.Snapshot.State);
        using var cancellation = new CancellationTokenSource(TimeSpan.FromMilliseconds(100));
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => service.GenerateAsync(LocalBrainCatalog.CompactModelId,
            "Count from 1 to 200, one number per line. Continue until 200.", cancellationToken: cancellation.Token));
        Assert.False(runtime.IsRunning);
        Assert.Equal(LocalBrainState.Cancelled, service.Snapshot.State);
        await service.StopAsync();
        Assert.False(runtime.IsRunning);
        Assert.Equal(LocalBrainState.Stopped, service.Snapshot.State);
    }
    private sealed class NoDownloadsHandler : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
            => throw new Xunit.Sdk.XunitException("Prepared native fixture must not use network setup.");
    }
}

public sealed class NativeLocalBrainFactAttribute : FactAttribute
{
    public NativeLocalBrainFactAttribute()
    {
        if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("AMORA_LOCAL_BRAIN_TEST_ROOT")))
            Skip = "Requires explicit AMORA_LOCAL_BRAIN_TEST_ROOT with already verified official native artifacts; never downloads during tests.";
    }
}
