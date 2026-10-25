using System.Collections.Generic;
using AMORA.Orbit.Models;

namespace AMORA.Orbit.Services.Contracts;

/// <summary>
/// Session-only, ephemeral in-memory conversation context.
/// Strictly non-persistent: never writes to disk, logs, or diagnostics.
/// Thread-safe for multi-turn conversational exchanges and predictable trimming.
/// </summary>
public interface IConversationSession
{
    int MaxTurns { get; set; }
    int TurnCount { get; }
    IReadOnlyList<ChatMessage> GetHistory();
    void AddTurn(string userPrompt, string modelResponse);
    void Clear();
}
