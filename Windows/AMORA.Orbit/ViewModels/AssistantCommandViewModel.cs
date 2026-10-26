using System;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Threading;
using System.Threading.Tasks;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.ViewModels;

public class AssistantCommandViewModel : INotifyPropertyChanged, IDisposable
{
    private readonly IAssistantEngine _engine;
    private string _inputText = string.Empty;
    private bool _isProcessing;
    private string _statusMessage = string.Empty;
    private AssistantResultStatus? _lastStatus;
    private bool _hasPendingConfirmation;
    private string? _confirmationPrompt;
    private CancellationTokenSource? _activeCts;

    public AssistantCommandViewModel(IAssistantEngine engine)
    {
        _engine = engine ?? throw new ArgumentNullException(nameof(engine));
    }

    public string InputText
    {
        get => _inputText;
        set
        {
            if (_inputText != value)
            {
                _inputText = value;
                OnPropertyChanged();
                OnPropertyChanged(nameof(CanSubmit));
                OnPropertyChanged(nameof(HasText));
            }
        }
    }

    public bool IsProcessing
    {
        get => _isProcessing;
        private set
        {
            if (_isProcessing != value)
            {
                _isProcessing = value;
                OnPropertyChanged();
                OnPropertyChanged(nameof(CanSubmit));
            }
        }
    }

    public string StatusMessage
    {
        get => _statusMessage;
        private set
        {
            if (_statusMessage != value)
            {
                _statusMessage = value;
                OnPropertyChanged();
                OnPropertyChanged(nameof(HasStatus));
            }
        }
    }

    public AssistantResultStatus? LastStatus
    {
        get => _lastStatus;
        private set
        {
            if (_lastStatus != value)
            {
                _lastStatus = value;
                OnPropertyChanged();
                OnPropertyChanged(nameof(StatusColor));
                OnPropertyChanged(nameof(StatusGlyph));
            }
        }
    }

    public bool HasPendingConfirmation
    {
        get => _hasPendingConfirmation;
        private set
        {
            if (_hasPendingConfirmation != value)
            {
                _hasPendingConfirmation = value;
                OnPropertyChanged();
                OnPropertyChanged(nameof(PendingActionDescription));
            }
        }
    }

    public string? ConfirmationPrompt
    {
        get => _confirmationPrompt;
        private set
        {
            if (_confirmationPrompt != value)
            {
                _confirmationPrompt = value;
                OnPropertyChanged();
                OnPropertyChanged(nameof(PendingActionDescription));
            }
        }
    }

    public string? PendingActionDescription => _confirmationPrompt;

    public bool CanSubmit => !string.IsNullOrWhiteSpace(_inputText) && !_isProcessing;
    public bool HasText => !string.IsNullOrEmpty(_inputText);
    public bool HasStatus => !string.IsNullOrWhiteSpace(_statusMessage);

    public string StatusColor => _isProcessing
        ? "#52CCFF"
        : _lastStatus switch
        {
            AssistantResultStatus.Success => "#30D158",            // Green
            AssistantResultStatus.Failed => "#FF453A",             // Coral Red
            AssistantResultStatus.NeedsConfirmation => "#FF9F0A",  // Amber
            AssistantResultStatus.Information => "#52CCFF",        // Electric Cyan
            AssistantResultStatus.Unsupported => "#FF9F0A",        // Amber
            _ => "#9AA2B2"                                         // Muted text
        };

    public string StatusGlyph => _isProcessing
        ? "\uF16A"                                                // Sparkles / Thinking
        : _lastStatus switch
        {
            AssistantResultStatus.Success => "\uE73E",            // CheckMark
            AssistantResultStatus.Failed => "\uEA39",             // ErrorCircle
            AssistantResultStatus.NeedsConfirmation => "\uE7BA",  // Warning
            AssistantResultStatus.Information => "\uE946",        // Info
            AssistantResultStatus.Unsupported => "\uE897",        // Help
            _ => "\uE946"
        };

    public event EventHandler<AssistantExecutionResult>? ResultReceived;
    public event PropertyChangedEventHandler? PropertyChanged;

    public async Task<AssistantExecutionResult> SubmitAsync()
    {
        if (string.IsNullOrWhiteSpace(_inputText) || _isProcessing)
        {
            return AssistantExecutionResult.Failed("Command cannot be empty.");
        }

        string commandToRun = _inputText.Trim();
        InputText = string.Empty;

        _activeCts?.Cancel();
        _activeCts?.Dispose();
        _activeCts = new CancellationTokenSource();
        var token = _activeCts.Token;

        IsProcessing = true;
        StatusMessage = "AMORA is thinking...";
        LastStatus = AssistantResultStatus.Information;
        ResultReceived?.Invoke(this, AssistantExecutionResult.Information("AMORA is thinking...", MascotMood.Thinking));

        try
        {
            var result = await _engine.ExecuteAsync(commandToRun, token);
            ApplyResult(result);
            return result;
        }
        catch (OperationCanceledException)
        {
            var cancelResult = AssistantExecutionResult.Information("Request cancelled.", MascotMood.Idle);
            ApplyResult(cancelResult);
            return cancelResult;
        }
        catch (Exception ex)
        {
            var errorResult = AssistantExecutionResult.Failed($"Error: {ex.Message}");
            ApplyResult(errorResult);
            return errorResult;
        }
        finally
        {
            IsProcessing = false;
        }
    }

    public async Task<AssistantExecutionResult> ConfirmAsync()
    {
        if (!HasPendingConfirmation || _isProcessing)
        {
            return AssistantExecutionResult.Failed("No confirmation is pending.");
        }

        IsProcessing = true;
        try
        {
            var result = await _engine.ConfirmPendingActionAsync();
            ApplyResult(result);
            return result;
        }
        catch (Exception ex)
        {
            var errorResult = AssistantExecutionResult.Failed($"Confirmation error: {ex.Message}");
            ApplyResult(errorResult);
            return errorResult;
        }
        finally
        {
            IsProcessing = false;
        }
    }

    public void CancelConfirmation()
    {
        _engine.CancelPendingAction();
        HasPendingConfirmation = false;
        ConfirmationPrompt = null;
        StatusMessage = "Action cancelled.";
        LastStatus = AssistantResultStatus.Information;

        var cancelResult = AssistantExecutionResult.Information("Action cancelled.", MascotMood.Idle);
        ResultReceived?.Invoke(this, cancelResult);
    }

    public void CancelActiveRequest()
    {
        if (_isProcessing)
        {
            _activeCts?.Cancel();
        }
    }

    public void Clear()
    {
        CancelActiveRequest();
        InputText = string.Empty;
        StatusMessage = string.Empty;
        LastStatus = null;
        HasPendingConfirmation = false;
        ConfirmationPrompt = null;
    }

    public void ResetConversation()
    {
        CancelActiveRequest();
        _engine.ResetConversation();
        Clear();
        StatusMessage = "Conversation reset.";
        LastStatus = AssistantResultStatus.Information;
        ResultReceived?.Invoke(this, AssistantExecutionResult.Information("Conversation reset.", MascotMood.Idle));
    }

    public void Dispose()
    {
        _activeCts?.Cancel();
        _activeCts?.Dispose();
        _activeCts = null;
    }

    private void ApplyResult(AssistantExecutionResult result)
    {
        StatusMessage = result.Message;
        LastStatus = result.Status;
        HasPendingConfirmation = result.RequiresConfirmation;
        ConfirmationPrompt = result.RequiresConfirmation ? result.Message : null;

        ResultReceived?.Invoke(this, result);
    }

    protected void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
