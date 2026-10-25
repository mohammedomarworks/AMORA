using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.Services.Implementations;

/// <summary>
/// Safe default AI provider implementation when no remote cloud provider (OpenAI, Anthropic, Gemini)
/// is configured.
///
/// Security note:
/// API keys and cloud credentials must never be stored in plaintext configuration files or committed
/// to source repositories. On Windows, credentials should be persisted using Windows DPAPI
/// (System.Security.Cryptography.ProtectedData) or the Windows Credential Manager
/// (Windows.Security.Credentials.PasswordVault).
/// </summary>
public class LocalStubAIProvider : IAIProvider
{
    public string ProviderId => "local_stub";
    public string DisplayName => "Local Assistant Engine";
    public bool IsConfigured => false;

    public Task<string> GenerateResponseAsync(string prompt, CancellationToken cancellationToken = default)
    {
        // Truthful response: cloud AI provider is not configured.
        return Task.FromResult(
            "Cloud AI is not configured. AMORA is operating with the local deterministic command engine. " +
            "You can control timers, media, and system status directly."
        );
    }
}
