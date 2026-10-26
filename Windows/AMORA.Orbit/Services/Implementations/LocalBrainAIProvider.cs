using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.Services.Implementations;

/// <summary>Real offline generation; never downloads or selects another provider implicitly.</summary>
public sealed class LocalBrainAIProvider(ILocalBrainService service, Func<AISettings> settings) : IAIProvider
{
    public string ProviderId => AISettings.ProviderLocalBrain;
    public string DisplayName => "AMORA Local Brain";
    public bool IsConfigured => service.IsInstalled(settings().LocalBrainModelId);
    public Task<string> GenerateResponseAsync(string prompt, CancellationToken cancellationToken = default) => GenerateResponseAsync(prompt, null, cancellationToken);
    public Task<string> GenerateResponseAsync(string prompt, IReadOnlyList<ChatMessage>? history, CancellationToken cancellationToken = default) =>
        service.GenerateAsync(settings().LocalBrainModelId, prompt, history, cancellationToken);
    public async Task<ConnectionTestResult> TestConnectionAsync(CancellationToken cancellationToken = default)
    {
        try { await service.StartAsync(settings().LocalBrainModelId, cancellationToken); return ConnectionTestResult.Success("Local model loaded on this PC. No API key or cloud connection is used."); }
        catch (OperationCanceledException) { throw; }
        catch (LocalBrainException error) { return ConnectionTestResult.Failure(error.Message); }
        catch { return ConnectionTestResult.Failure("Local Brain is unavailable. Check its setup panel."); }
    }
}
