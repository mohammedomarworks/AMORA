namespace AMORA.Orbit.Models;

/// <summary>Session-only text, never persisted or supplied to an AI provider.</summary>
public sealed record ClipboardEntry(string Id, string Text, DateTimeOffset CopiedAt)
{
    public string Preview => Text.Trim().Length > 60 ? Text.Trim()[..60] + "…" : Text.Trim();
    public string TimeLabel => CopiedAt.LocalDateTime.ToString("t");
}
