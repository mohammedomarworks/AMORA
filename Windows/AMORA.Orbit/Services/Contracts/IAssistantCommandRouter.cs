using AMORA.Orbit.Models;

namespace AMORA.Orbit.Services.Contracts;

public record CommandContext(
    bool IsTimerActive = false,
    bool IsTimerRunning = false,
    bool IsMediaPlaying = false,
    bool HasTrack = false
);

public interface IAssistantCommandRouter
{
    AssistantCommand Route(string input, CommandContext? context = null);
}
