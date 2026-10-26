using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.Services.Implementations;

public sealed class SafeNavigationService : ISafeNavigationService
{
    public const string ConfirmationActionId = "open_known_folder";
    private readonly ISafeNavigationPlatform _platform;
    private readonly Func<DateTimeOffset> _clock;
    private readonly object _sync = new();
    private SafeKnownFolder? _pending;
    private DateTimeOffset _expires;

    public SafeNavigationService(ISafeNavigationPlatform? platform = null, Func<DateTimeOffset>? clock = null)
    { _platform = platform ?? new WindowsSafeNavigationPlatform(); _clock = clock ?? (() => DateTimeOffset.UtcNow); }

    public async Task<AssistantExecutionResult?> TryExecuteAsync(string input, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        CancelPending();
        var request = NavigationCommandParser.Parse(input);
        if (request == null) return null;
        if (request.Unsupported) return AssistantExecutionResult.Unsupported(
            "I can open Calculator, Notepad, Paint or Windows Settings, and the Downloads, Documents, Desktop or Home folder. Paths, commands and other apps are not enabled.");
        if (request.Folder is { } folder)
        {
            lock (_sync) { _pending = folder; _expires = _clock().AddMinutes(2); }
            return AssistantExecutionResult.NeedsConfirmation($"Open your {folder} folder in File Explorer?", ConfirmationActionId);
        }
        try
        {
            bool success = await _platform.OpenApplicationAsync(request.Application!.Value, cancellationToken);
            return success ? AssistantExecutionResult.Success($"Windows accepted the request to open {request.DisplayName}.") :
                AssistantExecutionResult.Unsupported($"{request.DisplayName} is unavailable or Windows did not confirm the launch.");
        }
        catch (OperationCanceledException) { throw; }
        catch { return AssistantExecutionResult.Failed("Windows could not open that application."); }
    }

    public async Task<AssistantExecutionResult> ConfirmAsync(CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        SafeKnownFolder? folder;
        lock (_sync)
        {
            folder = _pending.HasValue && _clock() <= _expires ? _pending : null;
            _pending = null;
        }
        if (!folder.HasValue) return AssistantExecutionResult.Information("There is no current folder request to confirm.");
        try
        {
            bool opened = await _platform.OpenKnownFolderAsync(folder.Value, cancellationToken);
            return opened ? AssistantExecutionResult.Success($"Opened your {folder} folder.") :
                AssistantExecutionResult.Unsupported("That known folder is unavailable or Windows could not open it.");
        }
        catch (OperationCanceledException) { throw; }
        catch { return AssistantExecutionResult.Failed("Windows could not open that known folder."); }
    }

    public void CancelPending() { lock (_sync) _pending = null; }
}
