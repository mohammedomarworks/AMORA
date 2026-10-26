using System.Text.Json;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.Services.Implementations;

/// <summary>A durable update failed; the requested mutation was not activated.</summary>
public sealed class AutomationPersistenceException : IOException
{
    public AutomationPersistenceException(string message) : base(message) { }
}

public class LocalAutomationService : IAutomationService, IDisposable
{
    private readonly ITimerService _timerService;
    private readonly IMediaService _mediaService;
    private readonly ISuggestionService _suggestionService;
    private readonly string _filePath;
    private readonly Func<DateTimeOffset> _clock;
    private readonly object _lock = new();
    private readonly SemaphoreSlim _operations = new(1, 1);
    private List<AmoraAutomation> _automations = new();
    private System.Threading.Timer? _schedulerTimer;
    private int _tickRunning;
    private volatile bool _isDisposed;
    private bool _loadFailed;
    private bool _schedulerErrorReported;

    public IReadOnlyList<AmoraAutomation> Automations
    {
        get { lock (_lock) return _automations.ToArray(); }
    }

    public event EventHandler<IReadOnlyList<AmoraAutomation>>? AutomationsChanged;
    public event EventHandler<AutomationExecutionResult>? AutomationFired;

    public LocalAutomationService(ITimerService timerService, IMediaService mediaService,
        ISuggestionService suggestionService, string? customFilePath = null,
        Func<DateTimeOffset>? clock = null, bool startScheduler = true)
    {
        _timerService = timerService ?? throw new ArgumentNullException(nameof(timerService));
        _mediaService = mediaService ?? throw new ArgumentNullException(nameof(mediaService));
        _suggestionService = suggestionService ?? throw new ArgumentNullException(nameof(suggestionService));
        _clock = clock ?? (() => DateTimeOffset.UtcNow);
        string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        if (string.IsNullOrWhiteSpace(localAppData)) localAppData = AppContext.BaseDirectory;
        _filePath = Path.GetFullPath(customFilePath ?? Path.Combine(localAppData, "AMORA", "automations.json"));
        if (startScheduler) _schedulerTimer = new System.Threading.Timer(OnSchedulerTick, null, 1000, 1000);
    }

    public async Task LoadAutomationsAsync()
    {
        await _operations.WaitAsync();
        try
        {
            ThrowIfDisposed();
            var loaded = new List<AmoraAutomation>();
            if (File.Exists(_filePath))
            {
                try
                {
                    var json = await File.ReadAllTextAsync(_filePath);
                    loaded = JsonSerializer.Deserialize<List<AmoraAutomation>>(json) ?? throw new JsonException();
                    if (loaded.Count > 1000 || loaded.Any(a => a == null || string.IsNullOrWhiteSpace(a.Id)
                        || string.IsNullOrWhiteSpace(a.Name) || a.Trigger == null || a.Action == null)
                        || loaded.Select(a => a.Id).Distinct(StringComparer.Ordinal).Count() != loaded.Count)
                        throw new JsonException();
                    foreach (var item in loaded) ValidateTrigger(item.Trigger);
                }
                catch (Exception ex) when (ex is JsonException or ArgumentException)
                {
                    // Preserve the original before allowing a future explicit user mutation.
                    try { File.Copy(_filePath, _filePath + ".corrupt-" + Guid.NewGuid().ToString("N")); }
                    catch { _loadFailed = true; throw new AutomationPersistenceException("Automation data could not be read or backed up. No automations were activated; repair the storage before trying again."); }
                    loaded = new();
                    _loadFailed = false;
                    lock (_lock) _automations = loaded;
                    throw new AutomationPersistenceException("Automation data was damaged. A recovery copy was preserved and no automations were activated.");
                }
                catch (IOException)
                {
                    _loadFailed = true;
                    throw new AutomationPersistenceException("Automation data could not be read. Existing data was preserved; no new schedules were activated.");
                }
                catch (UnauthorizedAccessException)
                {
                    _loadFailed = true;
                    throw new AutomationPersistenceException("Automation storage is not accessible. No new schedules were activated.");
                }
            }

            var now = _clock();
            var recovered = loaded.Select(a => RecoverSchedule(a, now)).ToList();
            if (!recovered.SequenceEqual(loaded)) await PersistAsync(recovered);
            lock (_lock) _automations = recovered;
            _loadFailed = false;
        }
        finally { _operations.Release(); }
        NotifyChanged();
    }

    private static AmoraAutomation RecoverSchedule(AmoraAutomation item, DateTimeOffset now)
    {
        if (!item.IsEnabled) return item with { NextRunAt = null };
        if (item.NextRunAt.HasValue && item.NextRunAt.Value > now) return item;
        if (item.Trigger.Type == AutomationTriggerType.OneTime)
        {
            var next = item.Trigger.CalculateNextRunAt(now);
            return next.HasValue ? item with { NextRunAt = next }
                : item with { IsEnabled = false, NextRunAt = null, LastStatus = "Expired while offline" };
        }
        return item with
        {
            NextRunAt = item.Trigger.CalculateNextRunAt(now, item.LastFiredAt),
            LastStatus = item.NextRunAt.HasValue ? "Missed schedule while offline; rescheduled" : "Scheduled"
        };
    }

    public async Task<AmoraAutomation> CreateAutomationAsync(string name, AutomationTrigger trigger,
        AutomationAction action, bool isEnabled = true)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        ArgumentNullException.ThrowIfNull(action);
        ValidateTrigger(trigger);
        if (name.Length > 120) throw new ArgumentException("Automation names must be 120 characters or fewer.");
        var now = _clock();
        var automation = new AmoraAutomation(Guid.NewGuid().ToString("N"), name.Trim(), trigger, action,
            IsEnabled: isEnabled, NextRunAt: isEnabled ? trigger.CalculateNextRunAt(now) : null,
            CreatedAt: now, LastStatus: isEnabled ? "Scheduled" : "Disabled");
        await MutateAsync(list => { if (list.Count >= 1000) throw new InvalidOperationException("Automation limit reached."); list.Add(automation); return true; });
        return automation;
    }

    public Task<bool> UpdateAutomationAsync(AmoraAutomation automation)
    {
        ArgumentNullException.ThrowIfNull(automation);
        ArgumentException.ThrowIfNullOrWhiteSpace(automation.Name);
        ArgumentNullException.ThrowIfNull(automation.Action);
        ValidateTrigger(automation.Trigger);
        return MutateAsync(list =>
        {
            int index = list.FindIndex(a => a.Id == automation.Id);
            if (index < 0) return false;
            // Preserve execution metadata from the latest stored item, not a stale UI copy.
            var current = list[index];
            list[index] = automation with
            {
                LastFiredAt = current.LastFiredAt, CreatedAt = current.CreatedAt,
                NextRunAt = automation.IsEnabled ? automation.Trigger.CalculateNextRunAt(_clock(), current.LastFiredAt) : null,
                LastStatus = automation.IsEnabled ? "Active" : "Disabled"
            };
            return true;
        });
    }

    public Task<bool> ToggleEnabledAsync(string id) => MutateAsync(list =>
    {
        int index = list.FindIndex(a => a.Id == id);
        if (index < 0) return false;
        var current = list[index];
        bool enabled = !current.IsEnabled;
        list[index] = current with
        {
            IsEnabled = enabled,
            NextRunAt = enabled ? current.Trigger.CalculateNextRunAt(_clock(), current.LastFiredAt) : null,
            LastStatus = enabled ? "Enabled by user" : "Disabled by user"
        };
        return true;
    });

    public Task<bool> DeleteAutomationAsync(string id) => MutateAsync(list => list.RemoveAll(a => a.Id == id) > 0);

    private async Task<bool> MutateAsync(Func<List<AmoraAutomation>, bool> mutation)
    {
        bool changed;
        await _operations.WaitAsync();
        try
        {
            ThrowIfDisposed();
            if (_loadFailed) throw new AutomationPersistenceException("Automation storage needs recovery before changes can be saved. No changes were applied.");
            var candidate = Automations.ToList();
            changed = mutation(candidate);
            if (changed) await CommitAsync(candidate);
        }
        finally { _operations.Release(); }
        if (changed) NotifyChanged();
        return changed;
    }

    public async Task<AutomationExecutionResult> RunManuallyAsync(string id)
    {
        AutomationExecutionResult result;
        await _operations.WaitAsync();
        try
        {
            ThrowIfDisposed();
            var target = Automations.FirstOrDefault(a => a.Id == id);
            result = target == null ? AutomationExecutionResult.Failure(id, "Unknown", "Automation not found.")
                : await ExecuteReservedAsync(target, manual: true);
        }
        finally { _operations.Release(); }
        AutomationFired?.Invoke(this, result);
        NotifyChanged();
        return result;
    }

    private async void OnSchedulerTick(object? state)
    {
        if (_isDisposed || Interlocked.Exchange(ref _tickRunning, 1) != 0) return;
        try { await EvaluateDueAutomationsAsync(); _schedulerErrorReported = false; }
        catch (Exception)
        {
            if (!_isDisposed && !_schedulerErrorReported)
            {
                _schedulerErrorReported = true;
                AutomationFired?.Invoke(this, AutomationExecutionResult.Failure("scheduler", "Scheduler",
                    "Scheduled actions could not be safely recorded. No unrecorded action was executed."));
            }
        }
        finally { Volatile.Write(ref _tickRunning, 0); }
    }

    public async Task EvaluateDueAutomationsAsync()
    {
        var results = new List<AutomationExecutionResult>();
        await _operations.WaitAsync();
        try
        {
            if (_isDisposed || _loadFailed) return;
            var now = _clock();
            var due = Automations.Where(a => a.IsEnabled && a.NextRunAt.HasValue && now >= a.NextRunAt.Value
                && (!a.LastFiredAt.HasValue || (now - a.LastFiredAt.Value).TotalSeconds >= 2)).ToArray();
            foreach (var automation in due)
            {
                if (_isDisposed) break;
                results.Add(await ExecuteReservedAsync(automation, manual: false));
            }
        }
        finally { _operations.Release(); }
        foreach (var result in results) AutomationFired?.Invoke(this, result);
        if (results.Count > 0) NotifyChanged();
    }

    private async Task<AutomationExecutionResult> ExecuteReservedAsync(AmoraAutomation automation, bool manual)
    {
        if (_loadFailed) return AutomationExecutionResult.Failure(automation.Id, automation.Name, "Automation storage needs recovery. Nothing was executed.");
        var now = _clock();
        var candidate = Automations.ToList();
        int index = candidate.FindIndex(a => a.Id == automation.Id);
        if (index < 0) return AutomationExecutionResult.Failure(automation.Id, automation.Name, "Automation no longer exists.");
        bool oneTime = automation.Trigger.Type == AutomationTriggerType.OneTime;
        candidate[index] = automation with
        {
            LastFiredAt = now,
            NextRunAt = manual ? automation.NextRunAt : oneTime ? null : automation.Trigger.CalculateNextRunAt(now, now),
            IsEnabled = manual ? automation.IsEnabled : !oneTime && automation.IsEnabled,
            LastStatus = "Run recorded; result pending"
        };
        // Durable reservation precedes every side effect. A crash cannot replay this occurrence.
        try { await CommitAsync(candidate); }
        catch (AutomationPersistenceException)
        {
            return AutomationExecutionResult.Failure(automation.Id, automation.Name, "The run could not be saved. Nothing was executed.");
        }
        if (_isDisposed) return AutomationExecutionResult.Failure(automation.Id, automation.Name, "AMORA closed before the action started.");
        var result = await ExecuteActionInternalAsync(automation);
        candidate[index] = candidate[index] with { LastStatus = (manual ? "Manual run: " : "") + result.Message };
        try { await CommitAsync(candidate); }
        catch (AutomationPersistenceException)
        {
            return AutomationExecutionResult.Failure(automation.Id, automation.Name,
                result.IsSuccess ? "The action ran, but its result could not be saved. Its schedule was already recorded to prevent a duplicate."
                    : "The action failed and its result could not be saved. Its schedule was already recorded to prevent a duplicate.");
        }
        return result;
    }

    private async Task<AutomationExecutionResult> ExecuteActionInternalAsync(AmoraAutomation automation)
    {
        try
        {
            switch (automation.Action.Type)
            {
                case AutomationActionType.ShowReminder:
                    var reminder = new ProactiveSuggestion($"auto-remind-{automation.Id}-{Guid.NewGuid():N}", automation.Name,
                        automation.Action.Message ?? "Scheduled reminder.", "Acknowledge", "Automation",
                        OnAction: () => Task.CompletedTask);
                    return _suggestionService.PresentReminder(reminder)
                        ? AutomationExecutionResult.Success(automation.Id, automation.Name, "Reminder delivered to AMORA.")
                        : AutomationExecutionResult.Failure(automation.Id, automation.Name, "The reminder could not be displayed or queued.");
                case AutomationActionType.StartTimer:
                    var duration = automation.Action.Duration ?? TimeSpan.FromMinutes(25);
                    if (duration <= TimeSpan.Zero || duration > TimeSpan.FromDays(1))
                        return AutomationExecutionResult.Failure(automation.Id, automation.Name, "Timer duration must be greater than zero and no more than 24 hours.");
                    var label = automation.Action.Label ?? automation.Name;
                    _timerService.Start(duration, label);
                    return AutomationExecutionResult.Success(automation.Id, automation.Name, $"Started {(int)duration.TotalMinutes}m timer ({label})");
                case AutomationActionType.MediaPlay:
                    await _mediaService.PlayAsync();
                    return AutomationExecutionResult.Success(automation.Id, automation.Name, "Resumed media playback");
                case AutomationActionType.MediaPause:
                    await _mediaService.PauseAsync();
                    return AutomationExecutionResult.Success(automation.Id, automation.Name, "Paused media playback");
                default:
                    return AutomationExecutionResult.Failure(automation.Id, automation.Name, "Unapproved action type rejected.");
            }
        }
        catch
        {
            return AutomationExecutionResult.Failure(automation.Id, automation.Name, "The requested action failed or is unavailable. Check the connected service and try again.");
        }
    }

    private async Task CommitAsync(List<AmoraAutomation> candidate)
    {
        await PersistAsync(candidate);
        lock (_lock) _automations = candidate;
    }

    private async Task PersistAsync(List<AmoraAutomation> candidate)
    {
        string? temporaryPath = null;
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_filePath)!);
            temporaryPath = _filePath + ".tmp-" + Guid.NewGuid().ToString("N");
            byte[] json = JsonSerializer.SerializeToUtf8Bytes(candidate, new JsonSerializerOptions { WriteIndented = true });
            using (var stream = new FileStream(temporaryPath, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                await stream.WriteAsync(json);
                stream.Flush(flushToDisk: true);
            }
            File.Move(temporaryPath, _filePath, overwrite: true);
        }
        catch
        {
            throw new AutomationPersistenceException("AMORA could not save the automation change. No unsaved changes were activated; check storage access and try again.");
        }
        finally
        {
            if (temporaryPath != null)
            {
                try { File.Delete(temporaryPath); } catch { }
            }
        }
    }

    private static void ValidateTrigger(AutomationTrigger trigger)
    {
        ArgumentNullException.ThrowIfNull(trigger);
        bool valid = trigger.Type switch
        {
            AutomationTriggerType.Daily => trigger.Hour is >= 0 and <= 23 && trigger.Minute is >= 0 and <= 59,
            AutomationTriggerType.Interval => trigger.Interval.HasValue && trigger.Interval.Value >= TimeSpan.FromSeconds(1)
                && trigger.Interval.Value <= TimeSpan.FromDays(365),
            AutomationTriggerType.OneTime => trigger.TargetTime.HasValue,
            _ => false
        };
        if (!valid) throw new ArgumentException("The automation schedule is invalid.");
    }

    private void NotifyChanged() { if (!_isDisposed) AutomationsChanged?.Invoke(this, Automations); }
    private void ThrowIfDisposed() => ObjectDisposedException.ThrowIf(_isDisposed, this);

    public void Dispose()
    {
        _isDisposed = true;
        _schedulerTimer?.Dispose();
        _schedulerTimer = null;
        // The gate is intentionally retained until already-running async work has unwound.
        GC.SuppressFinalize(this);
    }
}
