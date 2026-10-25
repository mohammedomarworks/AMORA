using System;

namespace AMORA.Orbit.Models;

/// <summary>
/// Configuration for assistant AI completion providers.
/// </summary>
public record AISettings(
    string SelectedProvider = AISettings.ProviderGemini,
    string Model = AISettings.DefaultGeminiModel,
    double Temperature = 0.7,
    int MaxOutputTokens = 1024,
    string? CustomEndpoint = null
)
{
    public const string ProviderGemini = "gemini";
    public const string ProviderLocalStub = "local_stub";

    public const string DefaultGeminiModel = "gemini-2.5-flash";

    public static AISettings Default => new();
}

/// <summary>
/// Result of an AI provider connectivity check.
/// </summary>
public record ConnectionTestResult(
    bool IsSuccessful,
    string Message,
    TimeSpan Latency = default
)
{
    public static ConnectionTestResult Success(string message, TimeSpan latency = default) =>
        new(true, message, latency);

    public static ConnectionTestResult Failure(string message) =>
        new(false, message);
}
