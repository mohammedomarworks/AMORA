using System.Runtime.InteropServices;
using AMORA.Orbit.Interop;
using AMORA.Orbit.Services.Contracts;

namespace AMORA.Orbit.Services.Implementations;

public class TaskbarTrayService : ITaskbarTrayService, IDisposable
{
    private const int TrayIconId = 1001;
    private IntPtr _windowHandle = IntPtr.Zero;
    private bool _isVisible;
    private string _currentTip = "AMORA Orbit";

    public bool IsVisible => _isVisible;

    public event EventHandler? ToggleRequested;
    public event EventHandler? SettingsRequested;
    public event EventHandler? ExitRequested;

    public void Initialize(IntPtr windowHandle)
    {
        _windowHandle = windowHandle;
        if (_windowHandle == IntPtr.Zero) return;

        var nid = new NativeMethods.NOTIFYICONDATA
        {
            cbSize = Marshal.SizeOf<NativeMethods.NOTIFYICONDATA>(),
            hWnd = _windowHandle,
            uID = TrayIconId,
            uFlags = NativeMethods.NIF_MESSAGE | NativeMethods.NIF_TIP,
            uCallbackMessage = NativeMethods.WM_TRAYICON,
            szTip = _currentTip
        };

        _isVisible = NativeMethods.Shell_NotifyIcon(NativeMethods.NIM_ADD, ref nid);
    }

    public void SetTooltip(string tooltip)
    {
        _currentTip = string.IsNullOrWhiteSpace(tooltip) ? "AMORA Orbit" : tooltip;
        if (!_isVisible || _windowHandle == IntPtr.Zero) return;

        var nid = new NativeMethods.NOTIFYICONDATA
        {
            cbSize = Marshal.SizeOf<NativeMethods.NOTIFYICONDATA>(),
            hWnd = _windowHandle,
            uID = TrayIconId,
            uFlags = NativeMethods.NIF_TIP,
            szTip = _currentTip
        };

        NativeMethods.Shell_NotifyIcon(NativeMethods.NIM_MODIFY, ref nid);
    }

    public void Remove()
    {
        if (_isVisible && _windowHandle != IntPtr.Zero)
        {
            var nid = new NativeMethods.NOTIFYICONDATA
            {
                cbSize = Marshal.SizeOf<NativeMethods.NOTIFYICONDATA>(),
                hWnd = _windowHandle,
                uID = TrayIconId
            };
            NativeMethods.Shell_NotifyIcon(NativeMethods.NIM_DELETE, ref nid);
            _isVisible = false;
        }
    }

    public bool TryHandleMessage(int msg, IntPtr lParam)
    {
        if (msg == NativeMethods.WM_TRAYICON)
        {
            int eventId = lParam.ToInt32();
            if (eventId == NativeMethods.WM_LBUTTONUP)
            {
                ToggleRequested?.Invoke(this, EventArgs.Empty);
                return true;
            }
            if (eventId == NativeMethods.WM_RBUTTONUP)
            {
                // Right click can toggle or request context menu/settings
                SettingsRequested?.Invoke(this, EventArgs.Empty);
                return true;
            }
        }
        return false;
    }

    public void RequestExit()
    {
        ExitRequested?.Invoke(this, EventArgs.Empty);
    }

    public void Dispose()
    {
        Remove();
        GC.SuppressFinalize(this);
    }
}
