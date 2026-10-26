using System;
using System.IO;
using System.Text.Json;
using System.Threading.Tasks;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.Services.Implementations;

public class AISettingsService : IAISettingsService
{
    private readonly ISecureCredentialStorage _credentialStorage;
    private readonly string _settingsFilePath;
    private AISettings _currentSettings;

    public AISettings CurrentSettings => _currentSettings;
    public event EventHandler<AISettings>? SettingsChanged;

    public AISettingsService(ISecureCredentialStorage credentialStorage, string? customSettingsPath = null)
    {
        _credentialStorage = credentialStorage ?? throw new ArgumentNullException(nameof(credentialStorage));

        if (!string.IsNullOrWhiteSpace(customSettingsPath))
        {
            _settingsFilePath = customSettingsPath;
        }
        else
        {
            string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            if (string.IsNullOrWhiteSpace(localAppData))
            {
                localAppData = AppContext.BaseDirectory;
            }
            _settingsFilePath = Path.Combine(localAppData, "AMORA", "ai_settings.json");
        }

        _currentSettings = LoadSettingsInternal();
    }

    public Task<AISettings> LoadSettingsAsync()
    {
        _currentSettings = LoadSettingsInternal();
        return Task.FromResult(_currentSettings);
    }

    public async Task SaveSettingsAsync(AISettings settings)
    {
        _currentSettings = settings ?? throw new ArgumentNullException(nameof(settings));

        try
        {
            string dir = Path.GetDirectoryName(_settingsFilePath)!;
            Directory.CreateDirectory(dir);

            string json = JsonSerializer.Serialize(_currentSettings, new JsonSerializerOptions
            {
                WriteIndented = true
            });
            await File.WriteAllTextAsync(_settingsFilePath, json);
        }
        catch
        {
            // Transient write failure; in-memory settings remain active
        }

        SettingsChanged?.Invoke(this, _currentSettings);
    }

    public Task<bool> HasApiKeyAsync(string providerId)
    {
        string target = GetCredentialTarget(providerId);
        return _credentialStorage.HasCredentialAsync(target);
    }

    public Task<string?> GetApiKeyAsync(string providerId)
    {
        string target = GetCredentialTarget(providerId);
        return _credentialStorage.GetCredentialAsync(target);
    }

    public async Task SetApiKeyAsync(string providerId, string apiKey)
    {
        string target = GetCredentialTarget(providerId);
        await _credentialStorage.SetCredentialAsync(target, apiKey);
        SettingsChanged?.Invoke(this, _currentSettings);
    }

    public async Task ClearApiKeyAsync(string providerId)
    {
        string target = GetCredentialTarget(providerId);
        await _credentialStorage.DeleteCredentialAsync(target);
        SettingsChanged?.Invoke(this, _currentSettings);
    }

    private static string GetCredentialTarget(string providerId) =>
        $"amora.ai.{providerId.ToLowerInvariant().Trim()}.apikey";

    private AISettings LoadSettingsInternal()
    {
        try
        {
            if (File.Exists(_settingsFilePath))
            {
                string json = File.ReadAllText(_settingsFilePath);
                var loaded = JsonSerializer.Deserialize<AISettings>(json);
                if (loaded != null)
                {
                    return loaded;
                }
            }
        }
        catch
        {
        }

        return AISettings.Default;
    }
}
