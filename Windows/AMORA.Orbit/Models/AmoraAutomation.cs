using System;
using System.Text.Json.Serialization;

namespace AMORA.Orbit.Models;

public enum AutomationTriggerType
{
    Daily,
    Interval,
    OneTime
}

public record AutomationTrigger(
    AutomationTriggerType Type,
    int? Hour = null,
    int? Minute = null,
    TimeSpan? Interval = null,
    DateTimeOffset? TargetTime = null
)
{
    public static AutomationTrigger Daily(int hour, int minute) =>
        new(AutomationTriggerType.Daily, Hour: Math.Clamp(hour, 0, 23), Minute: Math.Clamp(minute, 0, 59));

    public static AutomationTrigger IntervalTrigger(TimeSpan interval) =>
        new(AutomationTriggerType.Interval, Interval: interval > TimeSpan.Zero ? interval : TimeSpan.FromMinutes(1));

    public static AutomationTrigger OneTime(DateTimeOffset targetTime) =>
        new(AutomationTriggerType.OneTime, TargetTime: targetTime);

    public string DisplayText => Type switch
    {
        AutomationTriggerType.Daily => FormatDaily(Hour ?? 9, Minute ?? 0),
        AutomationTriggerType.Interval => FormatInterval(Interval ?? TimeSpan.FromMinutes(30)),
        AutomationTriggerType.OneTime => TargetTime.HasValue ? $"At {TargetTime.Value.ToLocalTime():yyyy-MM-dd HH:mm}" : "One-time",
        _ => "Custom"
    };

    private static string FormatDaily(int h, int m)
    {
        string period = h >= 12 ? "PM" : "AM";
        int hour12 = h % 12 == 0 ? 12 : h % 12;
        return $"Daily at {hour12}:{m:D2} {period}";
    }

    private static string FormatInterval(TimeSpan s)
    {
        if (s.TotalHours >= 1)
        {
            int hours = (int)s.TotalHours;
            return $"Every {hours} hour{(hours == 1 ? "" : "s")}";
        }
        int mins = (int)s.TotalMinutes;
        return $"Every {mins} minute{(mins == 1 ? "" : "s")}";
    }

    public DateTimeOffset? CalculateNextRunAt(DateTimeOffset referenceTime, DateTimeOffset? lastRunAt = null)
    {
        switch (Type)
        {
            case AutomationTriggerType.OneTime:
                if (TargetTime.HasValue && TargetTime.Value > referenceTime)
                {
                    return TargetTime.Value;
                }
                return null;

            case AutomationTriggerType.Daily:
                int h = Hour ?? 9;
                int m = Minute ?? 0;
                var localRef = referenceTime.ToLocalTime();
                var todayTargetLocal = new DateTimeOffset(localRef.Year, localRef.Month, localRef.Day, h, m, 0, localRef.Offset);

                if (todayTargetLocal > referenceTime)
                {
                    return todayTargetLocal;
                }
                return todayTargetLocal.AddDays(1);

            case AutomationTriggerType.Interval:
                var interval = Interval ?? TimeSpan.FromMinutes(30);
                if (interval <= TimeSpan.Zero) return null;

                if (lastRunAt.HasValue)
                {
                    var next = lastRunAt.Value.Add(interval);
                    if (next > referenceTime)
                    {
                        return next;
                    }
                    // If one or more intervals passed while offline, choose the next strictly future boundary.
                    var elapsed = referenceTime - lastRunAt.Value;
                    var intervalsPassed = elapsed.Ticks / interval.Ticks + 1;
                    return lastRunAt.Value.AddTicks(intervalsPassed * interval.Ticks);
                }
                return referenceTime.Add(interval);

            default:
                return null;
        }
    }
}

public enum AutomationActionType
{
    ShowReminder,
    StartTimer,
    MediaPlay,
    MediaPause
}

public record AutomationAction(
    AutomationActionType Type,
    string? Message = null,
    TimeSpan? Duration = null,
    string? Label = null
)
{
    public static AutomationAction Reminder(string message) =>
        new(AutomationActionType.ShowReminder, Message: message);

    public static AutomationAction Timer(TimeSpan duration, string label = "Focus") =>
        new(AutomationActionType.StartTimer, Duration: duration, Label: label);

    public static AutomationAction PlayMedia() =>
        new(AutomationActionType.MediaPlay);

    public static AutomationAction PauseMedia() =>
        new(AutomationActionType.MediaPause);

    public string DisplayText => Type switch
    {
        AutomationActionType.ShowReminder => $"Reminder: \"{Message}\"",
        AutomationActionType.StartTimer => Duration.HasValue ? $"Start {(int)Duration.Value.TotalMinutes}m {Label ?? "Focus"} timer" : "Start timer",
        AutomationActionType.MediaPlay => "Play media",
        AutomationActionType.MediaPause => "Pause media",
        _ => "Custom action"
    };
}

public record AmoraAutomation(
    string Id,
    string Name,
    AutomationTrigger Trigger,
    AutomationAction Action,
    bool IsEnabled = true,
    DateTimeOffset? LastFiredAt = null,
    DateTimeOffset? NextRunAt = null,
    string? LastStatus = null,
    DateTimeOffset? CreatedAt = null
)
{
    public DateTimeOffset CreatedAtTime => CreatedAt ?? DateTimeOffset.UtcNow;

    public string StatusText => !IsEnabled
        ? "Disabled"
        : (NextRunAt.HasValue
            ? $"Next: {NextRunAt.Value.ToLocalTime():g}"
            : "No upcoming run");
}

public record AutomationExecutionResult(
    string AutomationId,
    string AutomationName,
    bool IsSuccess,
    string Message,
    DateTimeOffset ExecutedAt
)
{
    public static AutomationExecutionResult Success(string id, string name, string message) =>
        new(id, name, true, message, DateTimeOffset.UtcNow);

    public static AutomationExecutionResult Failure(string id, string name, string message) =>
        new(id, name, false, message, DateTimeOffset.UtcNow);
}
