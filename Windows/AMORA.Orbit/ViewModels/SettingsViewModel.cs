using System;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Threading.Tasks;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;
using AMORA.Orbit.Services.Implementations;

namespace AMORA.Orbit.ViewModels;

public class SettingsViewModel : INotifyPropertyChanged
{
    private readonly IAISettingsService _settingsService;
    private readonly IAIProvider _aiProvider;

    private bool _isOpen;
    private string _selectedProvider;
    private string _modelName;
    private bool _sendStatusContextToAI;
    private string _apiKeyInput = string.Empty;
    private string _maskedApiKey = string.Empty;
    private bool _hasSavedKey;
    private bool _isTesting;
    private string? _testStatusMessage;
    private string? _testStatusColor;
    private string? _testStatusGlyph;

    public SettingsViewModel(IAISettingsService settingsService, IAIProvider aiProvider)
    {
        _settingsService = settingsService ?? throw new ArgumentNullException(nameof(settingsService));
        _aiProvider = aiProvider ?? throw new ArgumentNullException(nameof(aiProvider));

        var settings = _settingsService.CurrentSettings;
        _selectedProvider = settings.SelectedProvider;
        _modelName = settings.Model;
        _sendStatusContextToAI = settings.SendStatusContextToAI;

        _ = RefreshKeyStatusAsync();
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
                OnPropertyChanged();
                OnPropertyChanged(nameof(IsGeminiSelected));
                _ = RefreshKeyStatusAsync();
            }
        }
    }

    public bool IsGeminiSelected => _selectedProvider == AISettings.ProviderGemini;

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

    public bool CanTest => !_isTesting;

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
        string? key = await _settingsService.GetApiKeyAsync(_selectedProvider);
        HasSavedKey = !string.IsNullOrWhiteSpace(key);
        MaskedApiKey = WindowsCredentialStorage.MaskSecret(key);
    }

    public async Task SaveAsync()
    {
        var updated = _settingsService.CurrentSettings with
        {
            SelectedProvider = _selectedProvider,
            Model = !string.IsNullOrWhiteSpace(_modelName) ? _modelName.Trim() : AISettings.DefaultGeminiModel,
            SendStatusContextToAI = _sendStatusContextToAI
        };

        await _settingsService.SaveSettingsAsync(updated);

        if (!string.IsNullOrWhiteSpace(_apiKeyInput))
        {
            await _settingsService.SetApiKeyAsync(_selectedProvider, _apiKeyInput.Trim());
            ApiKeyInput = string.Empty;
        }

        await RefreshKeyStatusAsync();

        TestStatusGlyph = "\uE73E"; // Checkmark
        TestStatusColor = "#30D158"; // Green
        TestStatusMessage = "Settings saved securely via DPAPI.";
    }

    public async Task ClearKeyAsync()
    {
        await _settingsService.ClearApiKeyAsync(_selectedProvider);
        ApiKeyInput = string.Empty;
        await RefreshKeyStatusAsync();

        TestStatusGlyph = "\uE74D"; // Delete/Info
        TestStatusColor = "#9AA2B2";
        TestStatusMessage = "API key cleared from secure storage.";
    }

    public async Task TestConnectionAsync()
    {
        if (IsTesting) return;

        IsTesting = true;
        TestStatusGlyph = "\uE895"; // Sync/Loading
        TestStatusColor = "#52CCFF"; // Cyan
        TestStatusMessage = "Testing connection to Gemini API...";

        try
        {
            // If user typed a new key into input box but hasn't saved yet, temporarily save it
            if (!string.IsNullOrWhiteSpace(_apiKeyInput))
            {
                await _settingsService.SetApiKeyAsync(_selectedProvider, _apiKeyInput.Trim());
                ApiKeyInput = string.Empty;
                await RefreshKeyStatusAsync();
            }

            var result = await _aiProvider.TestConnectionAsync();
            if (result.IsSuccessful)
            {
                TestStatusGlyph = "\uE73E"; // Checkmark
                TestStatusColor = "#30D158"; // Green
                TestStatusMessage = result.Message;
            }
            else
            {
                TestStatusGlyph = "\uEA39"; // Error
                TestStatusColor = "#FF453A"; // Red
                TestStatusMessage = result.Message;
            }
        }
        catch (Exception ex)
        {
            TestStatusGlyph = "\uEA39";
            TestStatusColor = "#FF453A";
            TestStatusMessage = $"Test failed: {ex.Message}";
        }
        finally
        {
            IsTesting = false;
        }
    }

    protected void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
