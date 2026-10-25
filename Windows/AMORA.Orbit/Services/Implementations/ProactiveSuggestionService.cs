using System.Collections.Concurrent;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.Services.Implementations;

public class ProactiveSuggestionService : ISuggestionService, IDisposable
{
    private ProactiveSuggestion? _activeSuggestion;
    private readonly object _lock = new();
    private readonly ConcurrentDictionary<string, DateTimeOffset> _snoozedUntil = new();
    private readonly ConcurrentBag<string> _dismissedIds = new();
    private CancellationTokenSource? _snoozeCts;

    public ProactiveSuggestion? ActiveSuggestion
    {
        get
        {
            lock (_lock)
            {
                return _activeSuggestion;
            }
        }
        private set
        {
            lock (_lock)
            {
                if (_activeSuggestion == value) return;
                _activeSuggestion = value;
            }
            ActiveSuggestionChanged?.Invoke(this, value);
        }
    }

    public event EventHandler<ProactiveSuggestion?>? ActiveSuggestionChanged;

    public void PresentSuggestion(ProactiveSuggestion suggestion)
    {
        ArgumentNullException.ThrowIfNull(suggestion);

        if (_dismissedIds.Contains(suggestion.Id))
        {
            return;
        }

        if (_snoozedUntil.TryGetValue(suggestion.Id, out var resumeTime))
        {
            if (DateTimeOffset.UtcNow < resumeTime)
            {
                return;
            }
            _snoozedUntil.TryRemove(suggestion.Id, out _);
        }

        ActiveSuggestion = suggestion;
    }

    public async Task ExecuteActiveActionAsync()
    {
        ProactiveSuggestion? current;
        lock (_lock)
        {
            current = _activeSuggestion;
        }

        if (current?.OnAction != null)
        {
            try
            {
                await current.OnAction();
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"Failed to execute suggestion action: {ex.Message}");
            }
        }

        DismissActive();
    }

    public void SnoozeActive(TimeSpan duration)
    {
        ProactiveSuggestion? current;
        lock (_lock)
        {
            current = _activeSuggestion;
            if (current == null) return;
            _snoozedUntil[current.Id] = DateTimeOffset.UtcNow.Add(duration);
            _activeSuggestion = null;
        }

        ActiveSuggestionChanged?.Invoke(this, null);

        // Schedule wake-up
        _snoozeCts?.Cancel();
        _snoozeCts = new CancellationTokenSource();
        var token = _snoozeCts.Token;

        _ = Task.Run(async () =>
        {
            try
            {
                await Task.Delay(duration, token);
                if (!token.IsCancellationRequested && !_dismissedIds.Contains(current.Id))
                {
                    PresentSuggestion(current);
                }
            }
            catch (TaskCanceledException)
            {
                // Snooze was cancelled or renewed
            }
        }, token);
    }

    public void DismissActive()
    {
        ProactiveSuggestion? current;
        lock (_lock)
        {
            current = _activeSuggestion;
            if (current == null) return;
            _dismissedIds.Add(current.Id);
            _activeSuggestion = null;
        }

        ActiveSuggestionChanged?.Invoke(this, null);
    }

    public void Dispose()
    {
        _snoozeCts?.Cancel();
        _snoozeCts?.Dispose();
    }
}
