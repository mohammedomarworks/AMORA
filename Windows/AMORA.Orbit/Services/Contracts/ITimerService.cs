using AMORA.Orbit.Models;

namespace AMORA.Orbit.Services.Contracts;

public interface ITimerService
{
    TimerSnapshot CurrentTimer { get; }
    TimerSnapshot CurrentSnapshot => CurrentTimer;

    event EventHandler<TimerSnapshot>? TimerUpdated;
    event EventHandler<TimerSnapshot>? TimerFinished;
    event EventHandler? TimerCompleted;

    void Start(TimeSpan duration, string label = "Focus");
    void StartTimer(int seconds) => Start(TimeSpan.FromSeconds(seconds), "Focus");
    void Pause();
    void PauseTimer() => Pause();
    void Resume();
    void ResumeTimer() => Resume();
    void Cancel();
    void CancelTimer() => Cancel();
    void AddMinute();
    void AddTime(int seconds) => AddMinute();
}
