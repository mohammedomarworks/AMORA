using System.Threading;
using System.Threading.Tasks;
using AMORA.Orbit.Models;

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

    Task<ConnectionTestResult> TestConnectionAsync(CancellationToken cancellationToken = default) =>
        Task.FromResult(ConnectionTestResult.Failure("Connectivity test not implemented for this provider."));
}
