using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Threading.Tasks;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.ViewModels;

public class AutomationItemViewModel : INotifyPropertyChanged
{
    private AmoraAutomation _automation;

    public AmoraAutomation Automation
    {
        get => _automation;
        internal set
        {
            if (_automation != value)
            {
                _automation = value;
                OnPropertyChanged(nameof(Id));
                OnPropertyChanged(nameof(Name));
                OnPropertyChanged(nameof(IsEnabled));
                OnPropertyChanged(nameof(TriggerText));
                OnPropertyChanged(nameof(ActionText));
                OnPropertyChanged(nameof(StatusText));
                OnPropertyChanged(nameof(LastStatus));
            }
        }
    }

    public AutomationItemViewModel(AmoraAutomation automation)
    {
        _automation = automation ?? throw new ArgumentNullException(nameof(automation));
    }

    public string Id => _automation.Id;
    public string Name => _automation.Name;
    public bool IsEnabled => _automation.IsEnabled;
    public string TriggerText => _automation.Trigger.DisplayText;
    public string ActionText => _automation.Action.DisplayText;
    public string StatusText => _automation.StatusText;
    public string LastStatus => _automation.LastStatus ?? "Ready";

    public event PropertyChangedEventHandler? PropertyChanged;

    protected void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}

public class AutomationsViewModel : INotifyPropertyChanged, IDisposable
{
    private readonly IAutomationService _automationService;
    private readonly Action<Action> _dispatch;
    private bool _disposed;
    private bool _isOpen;
    private string _newName = "Daily Focus";
    private int _newTriggerTypeIndex = 0; // 0: Daily, 1: Every 30m, 2: Every 60m
    private int _newHour = 9;
    private int _newMinute = 0;
    private int _newActionTypeIndex = 0; // 0: Reminder, 1: 25m Timer, 2: Pause Media
    private string _newReminderMessage = "Time to start focus session!";
    private string? _statusMessage;
    private string? _statusColor;
    private string? _statusGlyph;

    public ObservableCollection<AutomationItemViewModel> Items { get; } = new();

    public AutomationsViewModel(IAutomationService automationService, Action<Action>? dispatch = null)
    {
        _dispatch = dispatch ?? (action => action());
        _automationService = automationService ?? throw new ArgumentNullException(nameof(automationService));

        _automationService.AutomationsChanged += OnAutomationsChanged;
        _automationService.AutomationFired += OnAutomationFired;

        ReloadItems();
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
            }
        }
    }

    public bool HasAutomations => Items.Count > 0;

    public string NewName
    {
        get => _newName;
        set
        {
            if (_newName != value)
            {
                _newName = value;
                OnPropertyChanged();
            }
        }
    }

    public int NewTriggerTypeIndex
    {
        get => _newTriggerTypeIndex;
        set
        {
            if (_newTriggerTypeIndex != value)
            {
                _newTriggerTypeIndex = value;
                OnPropertyChanged();
                OnPropertyChanged(nameof(IsDailyTriggerSelected));
            }
        }
    }

    public bool IsDailyTriggerSelected => _newTriggerTypeIndex == 0;

    public int NewHour
    {
        get => _newHour;
        set
        {
            if (_newHour != value)
            {
                _newHour = Math.Clamp(value, 0, 23);
                OnPropertyChanged();
            }
        }
    }

    public int NewMinute
    {
        get => _newMinute;
        set
        {
            if (_newMinute != value)
            {
                _newMinute = Math.Clamp(value, 0, 59);
                OnPropertyChanged();
            }
        }
    }

    public int NewActionTypeIndex
    {
        get => _newActionTypeIndex;
        set
        {
            if (_newActionTypeIndex != value)
            {
                _newActionTypeIndex = value;
                OnPropertyChanged();
                OnPropertyChanged(nameof(IsReminderActionSelected));
            }
        }
    }

    public bool IsReminderActionSelected => _newActionTypeIndex == 0;

    public string NewReminderMessage
    {
        get => _newReminderMessage;
        set
        {
            if (_newReminderMessage != value)
            {
                _newReminderMessage = value;
                OnPropertyChanged();
            }
        }
    }

    public string? StatusMessage
    {
        get => _statusMessage;
        private set
        {
            if (_statusMessage != value)
            {
                _statusMessage = value;
                OnPropertyChanged();
                OnPropertyChanged(nameof(HasStatusMessage));
            }
        }
    }

    public bool HasStatusMessage => !string.IsNullOrWhiteSpace(_statusMessage);

    public string? StatusColor
    {
        get => _statusColor;
        private set
        {
            if (_statusColor != value)
            {
                _statusColor = value;
                OnPropertyChanged();
            }
        }
    }

    public string? StatusGlyph
    {
        get => _statusGlyph;
        private set
        {
            if (_statusGlyph != value)
            {
                _statusGlyph = value;
                OnPropertyChanged();
            }
        }
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public void ToggleOpen() => IsOpen = !IsOpen;

    public async Task LoadAsync()
    {
        if (_disposed) return;
        try { await _automationService.LoadAutomationsAsync(); }
        catch (System.IO.IOException)
        {
            ShowStorageFailure("Automation data could not be loaded safely. No schedules were activated; check the recovery file.");
        }
        catch (ObjectDisposedException) when (_disposed) { }
    }

    public async Task CreateAutomationAsync()
    {
        if (_disposed) return;
        try
        {
            if (string.IsNullOrWhiteSpace(_newName))
            {
                PublishStatus("Please provide an automation name.", "#FF453A", "\uE7BA");
                return;
            }

            AutomationTrigger trigger = _newTriggerTypeIndex switch
            {
                1 => AutomationTrigger.IntervalTrigger(TimeSpan.FromMinutes(30)),
                2 => AutomationTrigger.IntervalTrigger(TimeSpan.FromMinutes(60)),
                _ => AutomationTrigger.Daily(_newHour, _newMinute)
            };

            AutomationAction action = _newActionTypeIndex switch
            {
                1 => AutomationAction.Timer(TimeSpan.FromMinutes(25), "Focus"),
                2 => AutomationAction.PauseMedia(),
                _ => AutomationAction.Reminder(!string.IsNullOrWhiteSpace(_newReminderMessage) ? _newReminderMessage.Trim() : "Scheduled reminder")
            };

            var created = await _automationService.CreateAutomationAsync(_newName.Trim(), trigger, action, isEnabled: true);
            PublishStatus($"Created '{created.Name}'. Next: {created.NextRunAt?.ToLocalTime():g}", "#30D158", "\uE73E");
        }
        catch (System.IO.IOException)
        {
            ShowStorageFailure();
        }
        catch (ArgumentException)
        {
            PublishStatus("Check the schedule and use an automation name of 120 characters or fewer. Nothing was created.", "#FF453A", "\uE7BA");
        }
        catch (InvalidOperationException)
        {
            PublishStatus("The automation could not be created. Check the automation limit and try again.", "#FF453A", "\uE7BA");
        }
    }

    public async Task ToggleEnabledAsync(string id)
    {
        if (_disposed) return;
        try
        {
            bool success = await _automationService.ToggleEnabledAsync(id);
            if (success) PublishStatus("Automation toggled.", "#52CCFF", "\uE895");
        }
        catch (System.IO.IOException) { ShowStorageFailure(); }
        catch (ObjectDisposedException) when (_disposed) { }
    }

    public async Task DeleteAsync(string id)
    {
        if (_disposed) return;
        try
        {
            bool success = await _automationService.DeleteAutomationAsync(id);
            if (success) PublishStatus("Automation deleted.", "#9AA2B2", "\uE74D");
        }
        catch (System.IO.IOException) { ShowStorageFailure(); }
        catch (ObjectDisposedException) when (_disposed) { }
    }

    public async Task RunNowAsync(string id)
    {
        if (_disposed) return;
        try
        {
            var result = await _automationService.RunManuallyAsync(id);
            PublishStatus(result.Message, result.IsSuccess ? "#30D158" : "#FF453A", result.IsSuccess ? "\uE73E" : "\uE7BA");
        }
        catch (System.IO.IOException) { ShowStorageFailure(); }
        catch (ObjectDisposedException) when (_disposed) { }
    }

    private void ShowStorageFailure(string message = "Automation could not be saved safely. Existing schedules are unchanged.")
    {
        _dispatch(() =>
        {
            if (_disposed) return;
            // Rebind any toggle that the native control optimistically changed before the failed save.
            ReloadItems();
            StatusGlyph = "\uEA39";
            StatusColor = "#FF453A";
            StatusMessage = message;
        });
    }

    private void PublishStatus(string message, string color, string glyph)
    {
        _dispatch(() =>
        {
            if (_disposed) return;
            StatusGlyph = glyph;
            StatusColor = color;
            StatusMessage = message;
        });
    }

    private void ReloadItems()
    {
        var list = _automationService.Automations;
        Items.Clear();
        foreach (var a in list)
        {
            Items.Add(new AutomationItemViewModel(a));
        }
        OnPropertyChanged(nameof(HasAutomations));
    }

    private void OnAutomationsChanged(object? sender, IReadOnlyList<AmoraAutomation> automations)
    {
        _dispatch(() => { if (!_disposed) ReloadItems(); });
    }

    private void OnAutomationFired(object? sender, AutomationExecutionResult result)
    {
        PublishStatus($"Automation: {result.Message}", result.IsSuccess ? "#30D158" : "#FF453A", result.IsSuccess ? "\uE73E" : "\uE7BA");
    }

    protected void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));

    public void Dispose()
    {
        _disposed = true;
        _automationService.AutomationsChanged -= OnAutomationsChanged;
        _automationService.AutomationFired -= OnAutomationFired;
    }
}
