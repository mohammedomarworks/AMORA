using AMORA.Orbit.Interop;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.Services.Implementations;

public class WindowsHotKeyService : IHotKeyService, IDisposable
{
    private const int HotKeyId = 9001;
    private const uint VkKeyO = 0x4F; // 'O' key
    private IntPtr _windowHandle = IntPtr.Zero;

    public bool IsRegistered { get; private set; }
    public string HotKeyDisplayString => "Ctrl + Alt + O";

    public event EventHandler? HotKeyPressed;

    public bool Register(IntPtr windowHandle)
    {
        if (windowHandle == IntPtr.Zero)
        {
            return false;
        }

        if (IsRegistered)
        {
            Unregister();
        }

        _windowHandle = windowHandle;
        uint modifiers = NativeMethods.MOD_CONTROL | NativeMethods.MOD_ALT | NativeMethods.MOD_NOREPEAT;

        bool success = NativeMethods.RegisterHotKey(_windowHandle, HotKeyId, modifiers, VkKeyO);
        IsRegistered = success;
        return success;
    }

    public void Unregister()
    {
        if (IsRegistered && _windowHandle != IntPtr.Zero)
        {
            NativeMethods.UnregisterHotKey(_windowHandle, HotKeyId);
            IsRegistered = false;
            _windowHandle = IntPtr.Zero;
        }
    }

    public bool TryHandleMessage(int msg, IntPtr wParam)
    {
        if (msg == NativeMethods.WM_HOTKEY && wParam.ToInt32() == HotKeyId)
        {
            HotKeyPressed?.Invoke(this, EventArgs.Empty);
            return true;
        }
        return false;
    }

    public void Dispose()
    {
        Unregister();
        GC.SuppressFinalize(this);
    }
}
