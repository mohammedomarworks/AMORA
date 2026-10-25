namespace AMORA.Orbit.Services.Contracts;

public interface ITaskbarTrayService
{
    bool IsVisible { get; }

    event EventHandler? ToggleRequested;
    event EventHandler? SettingsRequested;
    event EventHandler? ExitRequested;

    void Initialize(IntPtr windowHandle);
    void SetTooltip(string tooltip);
    void Remove();
}
