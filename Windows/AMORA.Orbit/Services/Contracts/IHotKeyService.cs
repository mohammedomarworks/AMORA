namespace AMORA.Orbit.Services.Contracts;

public interface IHotKeyService
{
    bool IsRegistered { get; }
    string HotKeyDisplayString { get; }

    event EventHandler? HotKeyPressed;

    bool Register(IntPtr windowHandle);
    void Unregister();
}
