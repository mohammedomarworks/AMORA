using System;
using System.Threading.Tasks;
using AMORA.Orbit.Models;

namespace AMORA.Orbit.Services.Contracts;

public interface IAISettingsService
{
    AISettings CurrentSettings { get; }

    Task<AISettings> LoadSettingsAsync();
    Task SaveSettingsAsync(AISettings settings);

    Task<bool> HasApiKeyAsync(string providerId);
    Task<string?> GetApiKeyAsync(string providerId);
    Task SetApiKeyAsync(string providerId, string apiKey);
    Task ClearApiKeyAsync(string providerId);

    event EventHandler<AISettings>? SettingsChanged;
}
