using System;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Threading.Tasks;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;
using AMORA.Orbit.Services.Implementations;

namespace AMORA.Orbit.ViewModels;

public class SettingsViewModel : INotifyPropertyChanged, IDisposable
{
    private readonly IAISettingsService _settingsService;
    private readonly IAIProvider _aiProvider;
    private readonly Action<Action> _dispatch;
    private readonly CancellationTokenSource _lifetime = new();
    private readonly CancellationToken _lifetimeToken;
    private bool _disposed;
    private int _keyRequestGeneration;

    private bool _isOpen;
    private string _selectedProvider;
    private string _modelName;
    private bool _sendStatusContextToAI;
    private bool _enableProactiveSuggestions;
    private bool _memoryEnabled;
    private bool _enableClipboardHistory;
    private string _apiKeyInput = string.Empty;
    private string _maskedApiKey = string.Empty;
    private bool _hasSavedKey;
    private bool _isTesting;
    private string? _testStatusMessage;
    private string? _testStatusColor;
    private string? _testStatusGlyph;
    public IReadOnlyList<string> Providers { get; } = new[] { AISettings.ProviderLocalBrain, AISettings.ProviderGemini, AISettings.ProviderOpenAI, AISettings.ProviderAnthropic };
    public string CredentialLabel => IsLocalBrainSelected ? "Local Brain uses no API key" : $"{_selectedProvider} API key";
    public bool IsLocalBrainSelected => _selectedProvider == AISettings.ProviderLocalBrain;
    public bool IsCloudSelected => !IsLocalBrainSelected;

    public SettingsViewModel(IAISettingsService settingsService, IAIProvider aiProvider, Action<Action>? dispatch = null)
    {
        _settingsService = settingsService ?? throw new ArgumentNullException(nameof(settingsService));
        _aiProvider = aiProvider ?? throw new ArgumentNullException(nameof(aiProvider));
        _dispatch = dispatch ?? (action => action());
        _lifetimeToken = _lifetime.Token;

        var settings = _settingsService.CurrentSettings;
        _selectedProvider = settings.SelectedProvider;
        _modelName = settings.Model;
        _sendStatusContextToAI = settings.SendStatusContextToAI;
        _enableProactiveSuggestions = settings.EnableProactiveSuggestions;
        _memoryEnabled = settings.MemoryEnabled;
        _enableClipboardHistory = settings.EnableClipboardHistory;

        _ = RefreshKeyStatusAsync();
        _settingsService.SettingsChanged += OnSavedSettingsChanged;
    }

    public bool IsOpen
    {
        get => _isOpen;
        set
        {
            if (_isOpen != value)
            {
                _isOpen = value;
                OnPropertyChanged();
                if (_isOpen)
                {
                    _ = RefreshKeyStatusAsync();
                }
            }
        }
    }

    public string SelectedProvider
    {
        get => _selectedProvider;
        set
        {
            if (_selectedProvider != value)
            {
                _selectedProvider = value;
                ApiKeyInput = string.Empty;
                ModelName = value == AISettings.ProviderGemini ? AISettings.DefaultGeminiModel : string.Empty;
                OnPropertyChanged();
                OnPropertyChanged(nameof(IsGeminiSelected));
                OnPropertyChanged(nameof(CredentialLabel));
                OnPropertyChanged(nameof(IsLocalBrainSelected));
                OnPropertyChanged(nameof(IsCloudSelected));
                _ = RefreshKeyStatusAsync();
            }
        }
    }

    public bool IsGeminiSelected => _selectedProvider == AISettings.ProviderGemini;
    public bool MemoryEnabled
    {
        get => _memoryEnabled;
        set { if (_memoryEnabled != value) { _memoryEnabled = value; OnPropertyChanged(); } }
    }
    public bool EnableClipboardHistory
    {
        get => _enableClipboardHistory;
        set { if (_enableClipboardHistory != value) { _enableClipboardHistory = value; OnPropertyChanged(); } }
    }

    public string ModelName
    {
        get => _modelName;
        set
        {
            if (_modelName != value)
            {
                _modelName = value;
                OnPropertyChanged();
            }
        }
    }

    public bool SendStatusContextToAI
    {
        get => _sendStatusContextToAI;
        set
        {
            if (_sendStatusContextToAI != value)
            {
                _sendStatusContextToAI = value;
                OnPropertyChanged();
            }
        }
    }

    public bool EnableProactiveSuggestions
    {
        get => _enableProactiveSuggestions;
        set
        {
            if (_enableProactiveSuggestions != value)
            {
                _enableProactiveSuggestions = value;
                OnPropertyChanged();
            }
        }
    }

    public string ApiKeyInput
    {
        get => _apiKeyInput;
        set
        {
            if (_apiKeyInput != value)
            {
                _apiKeyInput = value;
                OnPropertyChanged();
                OnPropertyChanged(nameof(HasInputText));
            }
        }
    }

    public bool HasInputText => !string.IsNullOrWhiteSpace(_apiKeyInput);

    public string MaskedApiKey
    {
        get => _maskedApiKey;
        private set
        {
            if (_maskedApiKey != value)
            {
                _maskedApiKey = value;
                OnPropertyChanged();
            }
        }
    }

    public bool HasSavedKey
    {
        get => _hasSavedKey;
        private set
        {
            if (_hasSavedKey != value)
            {
                _hasSavedKey = value;
                OnPropertyChanged();
            }
        }
    }

    public bool IsTesting
    {
        get => _isTesting;
        private set
        {
            if (_isTesting != value)
            {
                _isTesting = value;
                OnPropertyChanged();
                OnPropertyChanged(nameof(CanTest));
            }
        }
    }

    public bool CanTest => !_disposed && !_isTesting;

    public string? TestStatusMessage
    {
        get => _testStatusMessage;
        private set
        {
            if (_testStatusMessage != value)
            {
                _testStatusMessage = value;
                OnPropertyChanged();
                OnPropertyChanged(nameof(HasTestStatus));
            }
        }
    }

    public bool HasTestStatus => !string.IsNullOrWhiteSpace(_testStatusMessage);

    public string? TestStatusColor
    {
        get => _testStatusColor;
        private set
        {
            if (_testStatusColor != value)
            {
                _testStatusColor = value;
                OnPropertyChanged();
            }
        }
    }

    public string? TestStatusGlyph
    {
        get => _testStatusGlyph;
        private set
        {
            if (_testStatusGlyph != value)
            {
                _testStatusGlyph = value;
                OnPropertyChanged();
            }
        }
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public void ToggleOpen()
    {
        IsOpen = !IsOpen;
    }

    public async Task RefreshKeyStatusAsync()
    {
        if (_disposed) return;
        var provider = _selectedProvider;
        int generation = ++_keyRequestGeneration;
        if (IsLocalBrainSelected) { HasSavedKey = false; MaskedApiKey = string.Empty; return; }
        try
        {
            string? key = await _settingsService.GetApiKeyAsync(provider);
            bool hasKey = !string.IsNullOrWhiteSpace(key);
            string masked = WindowsCredentialStorage.MaskSecret(key);
            OnUi(() =>
            {
                if (provider != _selectedProvider || generation != _keyRequestGeneration) return;
                HasSavedKey = hasKey;
                MaskedApiKey = masked;
            });
        }
        catch
        {
            OnUi(() =>
            {
                if (provider != _selectedProvider || generation != _keyRequestGeneration) return;
                HasSavedKey = false;
                MaskedApiKey = string.Empty;
                SetStatus("Secure credential storage could not be read. Check storage access and try again.", "#FF453A", "\uEA39");
            });
        }
    }

    public async Task SaveAsync()
    {
        if (_disposed) return;
        // Capture the submitted provider and key together. A later UI selection must not receive this key.
        string provider = _selectedProvider;
        string keyInput = _apiKeyInput;
        try
        {
            if (!Providers.Contains(provider) || (string.IsNullOrWhiteSpace(_modelName) && !IsGeminiSelected && !IsLocalBrainSelected))
            {
                SetStatus("Choose a supported provider and enter a model ID from your account.", "#FF9F0A", "\uE7BA");
                return;
            }
            var updated = _settingsService.CurrentSettings with
            {
                SelectedProvider = provider,
                Model = !string.IsNullOrWhiteSpace(_modelName) ? _modelName.Trim() : AISettings.DefaultGeminiModel,
                SendStatusContextToAI = _sendStatusContextToAI,
                EnableProactiveSuggestions = _enableProactiveSuggestions,
                MemoryEnabled = _memoryEnabled,
                EnableClipboardHistory = _enableClipboardHistory
            };

            await _settingsService.SaveSettingsAsync(updated);
            if (!string.IsNullOrWhiteSpace(keyInput) && provider != AISettings.ProviderLocalBrain)
            {
                await _settingsService.SetApiKeyAsync(provider, keyInput.Trim());
                OnUi(() => { if (_selectedProvider == provider && _apiKeyInput == keyInput) ApiKeyInput = string.Empty; });
            }
            await RefreshKeyStatusAsync();
            SetStatus(IsLocalBrainSelected ? "Local Brain selected. Install a model below to chat offline." : "Settings saved. API keys use protected Windows storage.", "#30D158", "\uE73E");
        }
        catch
        {
            SetStatus("Settings or credentials could not be fully saved. Check storage access and try again.", "#FF453A", "\uEA39");
        }
    }

    public async Task ClearKeyAsync()
    {
        if (_disposed) return;
        string provider = _selectedProvider;
        try
        {
            await _settingsService.ClearApiKeyAsync(provider);
            OnUi(() => { if (_selectedProvider == provider) ApiKeyInput = string.Empty; });
            await RefreshKeyStatusAsync();
            SetStatus("API key cleared from secure storage.", "#9AA2B2", "\uE74D");
        }
        catch
        {
            SetStatus("The API key could not be deleted. Check storage access and try again.", "#FF453A", "\uEA39");
        }
    }

    public async Task TestConnectionAsync()
    {
        if (_disposed || IsTesting) return;

        IsTesting = true;
        string provider = _selectedProvider;
        string model = _modelName;
        SetStatus($"Testing connection to {provider}...", "#52CCFF", "\uE895");

        try
        {
            if (!string.IsNullOrWhiteSpace(_apiKeyInput) || _settingsService.CurrentSettings.SelectedProvider != _selectedProvider || _settingsService.CurrentSettings.Model != _modelName)
            {
                SetStatus("Save your provider, model and key before testing the connection.", "#FF9F0A", "\uE7BA");
                return;
            }

            var result = await _aiProvider.TestConnectionAsync(_lifetimeToken);
            OnUi(() =>
            {
                if (provider != _selectedProvider || model != _modelName) return;
                TestStatusGlyph = result.IsSuccessful ? "\uE73E" : "\uEA39";
                TestStatusColor = result.IsSuccessful ? "#30D158" : "#FF453A";
                TestStatusMessage = result.Message;
            });
        }
        catch (OperationCanceledException) when (_lifetimeToken.IsCancellationRequested) { }
        catch
        {
            SetStatus("The connection test failed. Check your provider, model, credentials and network.", "#FF453A", "\uEA39");
        }
        finally
        {
            OnUi(() => IsTesting = false);
        }
    }

    protected void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        if (_disposed) return;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }

    private void OnUi(Action action) => _dispatch(() => { if (!_disposed) action(); });
    private void SetStatus(string message, string color, string glyph) => OnUi(() =>
    {
        TestStatusMessage = message;
        TestStatusColor = color;
        TestStatusGlyph = glyph;
    });

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _settingsService.SettingsChanged -= OnSavedSettingsChanged;
        _keyRequestGeneration++;
        _lifetime.Cancel();
        _lifetime.Dispose();
        _apiKeyInput = string.Empty;
        _maskedApiKey = string.Empty;
    }
    private void OnSavedSettingsChanged(object? sender, AISettings settings) => OnUi(() =>
    {
        // A separate Local Brain setup action can change the active provider.
        // Do not overwrite an unsaved model edit when saving the same provider.
        if (settings.SelectedProvider == AISettings.ProviderLocalBrain && _selectedProvider != settings.SelectedProvider)
        {
            _selectedProvider = settings.SelectedProvider;
            _modelName = settings.Model;
            ApiKeyInput = string.Empty;
            foreach (var name in new[] { nameof(SelectedProvider), nameof(ModelName), nameof(CredentialLabel), nameof(IsLocalBrainSelected), nameof(IsCloudSelected), nameof(IsGeminiSelected) }) OnPropertyChanged(name);
            _ = RefreshKeyStatusAsync();
        }
    });
}
