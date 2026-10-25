namespace AMORA.Orbit.Models;

/// <summary>
/// Role identifier for a conversation turn.
/// Matches Gemini API roles: 'user' and 'model'.
/// </summary>
public enum ChatRole
{
    User,
    Model
}

/// <summary>
/// Ephemeral, in-memory chat message turn.
/// Never written to persistent storage, configuration files, or logs.
/// </summary>
public record ChatMessage(ChatRole Role, string Content)
{
    public string RoleString => Role switch
    {
        ChatRole.User => "user",
        ChatRole.Model => "model",
        _ => "user"
    };

    public static ChatMessage User(string content) => new(ChatRole.User, content);
    public static ChatMessage Model(string content) => new(ChatRole.Model, content);
}
