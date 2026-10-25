using System;
using System.Collections.Generic;
using System.Linq;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.Services.Implementations;

/// <summary>
/// Thread-safe, bounded, session-only in-memory conversation context.
/// Holds alternating user and model turns, trimming oldest turns when capacity is reached.
/// Guaranteed to never write to disk or persist sensitive conversation data.
/// </summary>
public class ConversationSession : IConversationSession
{
    private readonly object _lock = new();
    private readonly List<ChatMessage> _messages = new();
    private readonly Func<int>? _maxTurnsProvider;
    private int _fallbackMaxTurns;

    public int MaxTurns
    {
        get
        {
            if (_maxTurnsProvider != null)
            {
                int val = _maxTurnsProvider();
                return val > 0 ? val : AISettings.DefaultMaxHistoryTurns;
            }
            return _fallbackMaxTurns;
        }
        set
        {
            lock (_lock)
            {
                _fallbackMaxTurns = Math.Max(1, value);
                TrimToLimitLocked();
            }
        }
    }

    public int TurnCount
    {
        get
        {
            lock (_lock)
            {
                return _messages.Count / 2;
            }
        }
    }

    public ConversationSession(Func<int>? maxTurnsProvider = null, int defaultMaxTurns = AISettings.DefaultMaxHistoryTurns)
    {
        _maxTurnsProvider = maxTurnsProvider;
        _fallbackMaxTurns = defaultMaxTurns > 0 ? defaultMaxTurns : AISettings.DefaultMaxHistoryTurns;
    }

    public IReadOnlyList<ChatMessage> GetHistory()
    {
        lock (_lock)
        {
            return _messages.ToList().AsReadOnly();
        }
    }

    public void AddTurn(string userPrompt, string modelResponse)
    {
        if (string.IsNullOrWhiteSpace(userPrompt) || string.IsNullOrWhiteSpace(modelResponse))
        {
            return;
        }

        lock (_lock)
        {
            _messages.Add(ChatMessage.User(userPrompt.Trim()));
            _messages.Add(ChatMessage.Model(modelResponse.Trim()));

            TrimToLimitLocked();
        }
    }

    public void Clear()
    {
        lock (_lock)
        {
            _messages.Clear();
        }
    }

    private void TrimToLimitLocked()
    {
        int limit = MaxTurns;
        int maxMessages = limit * 2;

        int excess = _messages.Count - maxMessages;
        if (excess > 0)
        {
            _messages.RemoveRange(0, excess);
        }

        // Maintain strict conversation validity: Gemini history MUST start with a user message
        while (_messages.Count > 0 && _messages[0].Role != ChatRole.User)
        {
            _messages.RemoveAt(0);
        }
    }
}
