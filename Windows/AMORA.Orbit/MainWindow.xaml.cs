using System.Runtime.InteropServices;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Input;
using Windows.System;
using AMORA.Orbit.Interop;
using AMORA.Orbit.Services.Contracts;
using AMORA.Orbit.Services.Implementations;
using AMORA.Orbit.ViewModels;

namespace AMORA.Orbit;

public sealed partial class MainWindow : Window
{
    private readonly OrbitViewModel _viewModel;
    private readonly WindowsHotKeyService? _hotKeyService;
    private readonly TaskbarTrayService? _trayService;

    private IntPtr _hwnd = IntPtr.Zero;
    private AppWindow? _appWindow;
    private NativeMethods.WndProcDelegate? _wndProcDelegate;
    private IntPtr _oldWndProc = IntPtr.Zero;

    public MainWindow(
        OrbitViewModel viewModel,
        WindowsHotKeyService? hotKeyService = null,
        TaskbarTrayService? trayService = null)
    {
        InitializeComponent();

        _viewModel = viewModel ?? throw new ArgumentNullException(nameof(viewModel));
        _hotKeyService = hotKeyService;
        _trayService = trayService;

        CapsuleView.DataContext = _viewModel;
        _viewModel.BoundsChanged += OnBoundsChanged;

        ConfigureWindow();
    }

    private void ConfigureWindow()
    {
        _hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        var windowId = Win32Interop.GetWindowIdFromWindow(_hwnd);
        _appWindow = AppWindow.GetFromWindowId(windowId);

        if (_appWindow != null)
        {
            // Remove native title bar and system caption buttons
            _appWindow.TitleBar.ExtendsContentIntoTitleBar = true;
            _appWindow.TitleBar.ButtonBackgroundColor = Colors.Transparent;
            _appWindow.TitleBar.ButtonInactiveBackgroundColor = Colors.Transparent;

            // Configure presenter as non-resizable topmost capsule
            if (_appWindow.Presenter is OverlappedPresenter presenter)
            {
                presenter.IsAlwaysOnTop = true;
                presenter.IsResizable = false;
                presenter.IsMinimizable = false;
                presenter.IsMaximizable = false;
                presenter.SetBorderAndTitleBar(false, false);
            }
        }

        // Apply DWM attributes (immersive dark mode and rounded corners)
        int darkMode = 1;
        NativeMethods.DwmSetWindowAttribute(_hwnd, NativeMethods.DWMWA_USE_IMMERSIVE_DARK_MODE, ref darkMode, sizeof(int));
        int roundCorner = NativeMethods.DWMWCP_ROUND;
        NativeMethods.DwmSetWindowAttribute(_hwnd, NativeMethods.DWMWA_WINDOW_CORNER_PREFERENCE, ref roundCorner, sizeof(int));

        // Subclass window procedure for global messages
        SubclassWndProc();

        // Register Global HotKey & Tray Icon
        _hotKeyService?.Register(_hwnd);
        _trayService?.Initialize(_hwnd);

        // Apply initial layout positioning
        _viewModel.UpdatePosition(_hwnd);
        ApplyPosition(_viewModel.CurrentBounds);

        Closed += OnWindowClosed;
    }

    private void SubclassWndProc()
    {
        _wndProcDelegate = HookWndProc;
        IntPtr pWndProc = Marshal.GetFunctionPointerForDelegate(_wndProcDelegate);
        _oldWndProc = NativeMethods.SetWindowLongPtr(_hwnd, NativeMethods.GWL_WNDPROC, pWndProc);
    }

    private IntPtr HookWndProc(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam)
    {
        if (msg == NativeMethods.WM_HOTKEY)
        {
            if (_hotKeyService != null && _hotKeyService.TryHandleMessage((int)msg, wParam))
            {
                return IntPtr.Zero;
            }
        }
        else if (msg == NativeMethods.WM_TRAYICON)
        {
            if (_trayService != null && _trayService.TryHandleMessage((int)msg, lParam))
            {
                return IntPtr.Zero;
            }
        }
        else if (msg == NativeMethods.WM_DPICHANGED)
        {
            _viewModel.UpdatePosition(_hwnd);
        }

        return NativeMethods.CallWindowProc(_oldWndProc, hWnd, msg, wParam, lParam);
    }

    private void OnBoundsChanged(object? sender, CapsuleBounds bounds)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            ApplyPosition(bounds);
        });
    }

    private void ApplyPosition(CapsuleBounds bounds)
    {
        if (_appWindow != null)
        {
            _appWindow.MoveAndResize(new Windows.Graphics.RectInt32(
                bounds.X,
                bounds.Y,
                bounds.Width,
                bounds.Height));
        }
        else if (_hwnd != IntPtr.Zero)
        {
            NativeMethods.SetWindowPos(
                _hwnd,
                NativeMethods.HWND_TOPMOST,
                bounds.X,
                bounds.Y,
                bounds.Width,
                bounds.Height,
                NativeMethods.SWP_NOACTIVATE | NativeMethods.SWP_SHOWWINDOW);
        }
    }

    private void OnRootKeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key == VirtualKey.Escape)
        {
            _viewModel.HandleEscape();
            e.Handled = true;
        }
    }

    private void OnWindowClosed(object sender, WindowEventArgs args)
    {
        _viewModel.BoundsChanged -= OnBoundsChanged;
        _hotKeyService?.Unregister();
        _trayService?.Remove();

        if (_oldWndProc != IntPtr.Zero && _hwnd != IntPtr.Zero)
        {
            NativeMethods.SetWindowLongPtr(_hwnd, NativeMethods.GWL_WNDPROC, _oldWndProc);
            _oldWndProc = IntPtr.Zero;
        }

        _viewModel.Dispose();
    }
}
