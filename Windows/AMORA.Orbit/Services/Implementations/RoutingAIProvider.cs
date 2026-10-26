using System.Net.Http;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.Services.Implementations;

/// <summary>One configured provider per request; never silently falls back to a different cloud.</summary>
public sealed class RoutingAIProvider : IAIProvider, IDisposable
{
    private readonly Func<AISettings> _settings;
    private readonly Dictionary<string, IAIProvider> _providers;
    private readonly LocalStubAIProvider _localOnly = new();

    public RoutingAIProvider(Func<string, Task<string?>> apiKeyProvider, Func<AISettings> settingsProvider, HttpClient? httpClient = null,
        IAIProvider? localBrainProvider = null)
    {
        ArgumentNullException.ThrowIfNull(apiKeyProvider);
        _settings = settingsProvider ?? throw new ArgumentNullException(nameof(settingsProvider));
        _providers = new(StringComparer.OrdinalIgnoreCase)
        {
            [AISettings.ProviderGemini] = new GeminiAIProvider(() => apiKeyProvider(AISettings.ProviderGemini), _settings, httpClient),
            [AISettings.ProviderOpenAI] = new OpenAIChatProvider(() => apiKeyProvider(AISettings.ProviderOpenAI), _settings, httpClient),
            [AISettings.ProviderAnthropic] = new AnthropicMessagesProvider(() => apiKeyProvider(AISettings.ProviderAnthropic), _settings, httpClient)
        };
        if (localBrainProvider != null) _providers[AISettings.ProviderLocalBrain] = localBrainProvider;
    }

    private IAIProvider Current => _providers.GetValueOrDefault(_settings().SelectedProvider ?? "", _localOnly);
    public string ProviderId => Current.ProviderId;
    public string DisplayName => Current.DisplayName;
    public bool IsConfigured => Current.IsConfigured;
    public Task<string> GenerateResponseAsync(string prompt, CancellationToken cancellationToken = default) =>
        GenerateResponseAsync(prompt, null, cancellationToken);
    public Task<string> GenerateResponseAsync(string prompt, IReadOnlyList<ChatMessage>? history, CancellationToken cancellationToken = default)
    {
        var current = Current;
        if (current.ProviderId == AISettings.ProviderLocalBrain)
            return current.GenerateResponseAsync(prompt, history, cancellationToken);
        HttpChatAIProvider.EnsureCloudPrompt(prompt);
        return current.GenerateResponseAsync(prompt, HttpChatAIProvider.FilterHistory(history, _settings().MaxHistoryTurns), cancellationToken);
    }
    public Task<ConnectionTestResult> TestConnectionAsync(CancellationToken cancellationToken = default) =>
        Current.TestConnectionAsync(cancellationToken);
    public void Dispose()
    {
        foreach (var provider in _providers.Values.OfType<IDisposable>()) provider.Dispose();
    }
}
