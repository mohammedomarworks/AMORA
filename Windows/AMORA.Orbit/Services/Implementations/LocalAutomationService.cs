using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.Services.Implementations;

public class LocalAutomationService : IAutomationService, IDisposable
{
    private readonly ITimerService _timerService;
    private readonly IMediaService _mediaService;
    private readonly ISuggestionService _suggestionService;
    private readonly string _filePath;
    private readonly Func<DateTimeOffset> _clock;
    private readonly object _lock = new();

    private List<AmoraAutomation> _automations = new();
    private System.Threading.Timer? _schedulerTimer;
    private bool _isEvaluating;
    private bool _isDisposed;

    public IReadOnlyList<AmoraAutomation> Automations
    {
        get
        {
            lock (_lock)
            {
                return _automations.ToList();
            }
        }
    }

    public event EventHandler<IReadOnlyList<AmoraAutomation>>? AutomationsChanged;
    public event EventHandler<AutomationExecutionResult>? AutomationFired;

    public LocalAutomationService(
        ITimerService timerService,
        IMediaService mediaService,
        ISuggestionService suggestionService,
        string? customFilePath = null,
        Func<DateTimeOffset>? clock = null)
    {
        _timerService = timerService ?? throw new ArgumentNullException(nameof(timerService));
        _mediaService = mediaService ?? throw new ArgumentNullException(nameof(mediaService));
        _suggestionService = suggestionService ?? throw new ArgumentNullException(nameof(suggestionService));
        _clock = clock ?? (() => DateTimeOffset.UtcNow);

        if (!string.IsNullOrWhiteSpace(customFilePath))
        {
            _filePath = customFilePath;
        }
        else
        {
            string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            _filePath = Path.Combine(localAppData, "AMORA", "automations.json");
        }

        // Start scheduler ticker checking every 1000ms
        _schedulerTimer = new System.Threading.Timer(OnSchedulerTick, null, 1000, 1000);
    }

    public async Task LoadAutomationsAsync()
    {
        var now = _clock();
        List<AmoraAutomation> loaded = new();

        try
        {
            if (File.Exists(_filePath))
            {
                string json = await File.ReadAllTextAsync(_filePath);
                var deserialized = JsonSerializer.Deserialize<List<AmoraAutomation>>(json);
                if (deserialized != null)
                {
                    loaded = deserialized;
                }
            }
        }
        catch
        {
            // Corrupted or missing file recovers gracefully to empty list
            loaded = new();
        }

        bool hasUpdates = false;
        for (int i = 0; i < loaded.Count; i++)
        {
            var item = loaded[i];
            if (item.IsEnabled)
            {
                // Handle missed schedules while app was offline
                if (item.NextRunAt.HasValue && item.NextRunAt.Value <= now)
                {
                    hasUpdates = true;
                    if (item.Trigger.Type == AutomationTriggerType.OneTime)
                    {
                        loaded[i] = item with
                        {
                            IsEnabled = false,
                            NextRunAt = null,
                            LastStatus = "Expired while offline"
                        };
                    }
                    else
                    {
                        var next = item.Trigger.CalculateNextRunAt(now, item.LastFiredAt);
                        loaded[i] = item with
                        {
                            NextRunAt = next,
                            LastStatus = "Missed schedule while offline; rescheduled"
                        };
                    }
                }
                else if (!item.NextRunAt.HasValue)
                {
                    hasUpdates = true;
                    var next = item.Trigger.CalculateNextRunAt(now, item.LastFiredAt);
                    loaded[i] = item with { NextRunAt = next };
                }
            }
        }

        lock (_lock)
        {
            _automations = loaded;
        }

        if (hasUpdates)
        {
            await SaveInternalAsync();
        }

        AutomationsChanged?.Invoke(this, Automations);
    }

    public async Task<AmoraAutomation> CreateAutomationAsync(
        string name,
        AutomationTrigger trigger,
        AutomationAction action,
        bool isEnabled = true)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        ArgumentNullException.ThrowIfNull(trigger);
        ArgumentNullException.ThrowIfNull(action);

        var now = _clock();
        var nextRun = isEnabled ? trigger.CalculateNextRunAt(now) : null;

        var automation = new AmoraAutomation(
            Id: Guid.NewGuid().ToString("N"),
            Name: name.Trim(),
            Trigger: trigger,
            Action: action,
            IsEnabled: isEnabled,
            NextRunAt: nextRun,
            CreatedAt: now,
            LastStatus: isEnabled ? "Scheduled" : "Disabled"
        );

        lock (_lock)
        {
            _automations.Add(automation);
        }

        await SaveInternalAsync();
        AutomationsChanged?.Invoke(this, Automations);

        return automation;
    }

    public async Task<bool> UpdateAutomationAsync(AmoraAutomation automation)
    {
        ArgumentNullException.ThrowIfNull(automation);

        var now = _clock();
        bool found = false;

        lock (_lock)
        {
            int index = _automations.FindIndex(a => a.Id == automation.Id);
            if (index >= 0)
            {
                var nextRun = automation.IsEnabled
                    ? automation.Trigger.CalculateNextRunAt(now, automation.LastFiredAt)
                    : null;

                _automations[index] = automation with
                {
                    NextRunAt = nextRun,
                    LastStatus = automation.IsEnabled ? "Active" : "Disabled"
                };
                found = true;
            }
        }

        if (found)
        {
            await SaveInternalAsync();
            AutomationsChanged?.Invoke(this, Automations);
        }

        return found;
    }

    public async Task<bool> ToggleEnabledAsync(string id)
    {
        if (string.IsNullOrWhiteSpace(id)) return false;

        var now = _clock();
        bool found = false;

        lock (_lock)
        {
            int index = _automations.FindIndex(a => a.Id == id);
            if (index >= 0)
            {
                var current = _automations[index];
                bool newEnabled = !current.IsEnabled;
                var nextRun = newEnabled
                    ? current.Trigger.CalculateNextRunAt(now, current.LastFiredAt)
                    : null;

                _automations[index] = current with
                {
                    IsEnabled = newEnabled,
                    NextRunAt = nextRun,
                    LastStatus = newEnabled ? "Enabled by user" : "Disabled by user"
                };
                found = true;
            }
        }

        if (found)
        {
            await SaveInternalAsync();
            AutomationsChanged?.Invoke(this, Automations);
        }

        return found;
    }

    public async Task<bool> DeleteAutomationAsync(string id)
    {
        if (string.IsNullOrWhiteSpace(id)) return false;

        bool removed = false;
        lock (_lock)
        {
            int index = _automations.FindIndex(a => a.Id == id);
            if (index >= 0)
            {
                _automations.RemoveAt(index);
                removed = true;
            }
        }

        if (removed)
        {
            await SaveInternalAsync();
            AutomationsChanged?.Invoke(this, Automations);
        }

        return removed;
    }

    public async Task<AutomationExecutionResult> RunManuallyAsync(string id)
    {
        AmoraAutomation? target = null;
        lock (_lock)
        {
            target = _automations.FirstOrDefault(a => a.Id == id);
        }

        if (target == null)
        {
            return AutomationExecutionResult.Failure(id, "Unknown", "Automation not found.");
        }

        var result = await ExecuteActionInternalAsync(target);
        var now = _clock();

        lock (_lock)
        {
            int index = _automations.FindIndex(a => a.Id == id);
            if (index >= 0)
            {
                _automations[index] = _automations[index] with
                {
                    LastFiredAt = now,
                    LastStatus = $"Manual run: {result.Message}"
                };
            }
        }

        await SaveInternalAsync();
        AutomationFired?.Invoke(this, result);
        AutomationsChanged?.Invoke(this, Automations);

        return result;
    }

    private async void OnSchedulerTick(object? state)
    {
        if (_isDisposed || _isEvaluating) return;

        _isEvaluating = true;
        try
        {
            await EvaluateDueAutomationsAsync();
        }
        catch
        {
            // Do not crash scheduler timer loop
        }
        finally
        {
            _isEvaluating = false;
        }
    }

    public async Task EvaluateDueAutomationsAsync()
    {
        var now = _clock();
        List<(AmoraAutomation Automation, int Index)> due = new();

        lock (_lock)
        {
            for (int i = 0; i < _automations.Count; i++)
            {
                var a = _automations[i];
                if (a.IsEnabled && a.NextRunAt.HasValue && now >= a.NextRunAt.Value)
                {
                    // Duplicate prevention: suppress if fired in the last 2 seconds
                    if (a.LastFiredAt.HasValue && (now - a.LastFiredAt.Value).TotalSeconds < 2)
                    {
                        continue;
                    }
                    due.Add((a, i));
                }
            }
        }

        if (due.Count == 0) return;

        bool hasChanges = false;
        foreach (var (automation, index) in due)
        {
            var result = await ExecuteActionInternalAsync(automation);
            hasChanges = true;

            var nextRun = automation.Trigger.CalculateNextRunAt(now, now);
            bool stillEnabled = automation.IsEnabled;
            if (automation.Trigger.Type == AutomationTriggerType.OneTime)
            {
                stillEnabled = false;
                nextRun = null;
            }

            lock (_lock)
            {
                if (index < _automations.Count && _automations[index].Id == automation.Id)
                {
                    _automations[index] = automation with
                    {
                        LastFiredAt = now,
                        NextRunAt = nextRun,
                        IsEnabled = stillEnabled,
                        LastStatus = result.Message
                    };
                }
            }

            AutomationFired?.Invoke(this, result);
        }

        if (hasChanges)
        {
            await SaveInternalAsync();
            AutomationsChanged?.Invoke(this, Automations);
        }
    }

    private async Task<AutomationExecutionResult> ExecuteActionInternalAsync(AmoraAutomation automation)
    {
        var now = _clock();
        try
        {
            switch (automation.Action.Type)
            {
                case AutomationActionType.ShowReminder:
                    var suggestion = new ProactiveSuggestion(
                        Id: $"auto-remind-{automation.Id}",
                        Title: automation.Name,
                        Message: automation.Action.Message ?? "Scheduled reminder.",
                        ActionLabel: "Acknowledge",
                        Category: "Automation",
                        Priority: SuggestionPriority.Normal,
                        OnAction: () => Task.CompletedTask,
                        CooldownDuration: TimeSpan.FromSeconds(30)
                    );
                    _suggestionService.PresentSuggestion(suggestion);
                    return AutomationExecutionResult.Success(
                        automation.Id,
                        automation.Name,
                        $"Reminder presented: \"{automation.Action.Message}\""
                    );

                case AutomationActionType.StartTimer:
                    var duration = automation.Action.Duration ?? TimeSpan.FromMinutes(25);
                    var label = automation.Action.Label ?? automation.Name;
                    _timerService.Start(duration, label);
                    return AutomationExecutionResult.Success(
                        automation.Id,
                        automation.Name,
                        $"Started {(int)duration.TotalMinutes}m timer ({label})"
                    );

                case AutomationActionType.MediaPlay:
                    await _mediaService.PlayAsync();
                    return AutomationExecutionResult.Success(
                        automation.Id,
                        automation.Name,
                        "Resumed media playback"
                    );

                case AutomationActionType.MediaPause:
                    await _mediaService.PauseAsync();
                    return AutomationExecutionResult.Success(
                        automation.Id,
                        automation.Name,
                        "Paused media playback"
                    );

                default:
                    return AutomationExecutionResult.Failure(
                        automation.Id,
                        automation.Name,
                        "Unapproved action type rejected."
                    );
            }
        }
        catch (Exception ex)
        {
            return AutomationExecutionResult.Failure(
                automation.Id,
                automation.Name,
                $"Execution failed: {ex.Message}"
            );
        }
    }

    private async Task SaveInternalAsync()
    {
        try
        {
            string dir = Path.GetDirectoryName(_filePath)!;
            Directory.CreateDirectory(dir);

            List<AmoraAutomation> snapshot;
            lock (_lock)
            {
                snapshot = _automations.ToList();
            }

            string json = JsonSerializer.Serialize(snapshot, new JsonSerializerOptions
            {
                WriteIndented = true
            });
            await File.WriteAllTextAsync(_filePath, json);
        }
        catch
        {
            // Transient write failure; in-memory automations remain active
        }
    }

    public void Dispose()
    {
        if (_isDisposed) return;
        _isDisposed = true;

        _schedulerTimer?.Change(Timeout.Infinite, Timeout.Infinite);
        _schedulerTimer?.Dispose();
        _schedulerTimer = null;
    }
}
