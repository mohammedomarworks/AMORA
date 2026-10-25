namespace AMORA.Orbit.Services.Contracts;

/// <summary>
/// Provider-neutral seam for AI completion/reasoning providers.
/// Designed for secure credential storage (Windows DPAPI or Credential Manager),
/// keeping API keys and secrets strictly out of plaintext repository files.
/// </summary>
public interface IAIProvider
{
    string ProviderId { get; }
    string DisplayName { get; }
    bool IsConfigured { get; }

    Task<string> GenerateResponseAsync(string prompt, CancellationToken cancellationToken = default);
}
