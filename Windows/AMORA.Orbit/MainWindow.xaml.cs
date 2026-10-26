using System.Runtime.InteropServices;
using System.ComponentModel;
using System.Diagnostics;
using Microsoft.UI.Dispatching;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Input;
using VirtualKey = Windows.System.VirtualKey;
using AMORA.Orbit.Interop;
using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;
using AMORA.Orbit.Services.Implementations;
using AMORA.Orbit.ViewModels;
using AMORA.Orbit.Views;

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
    private DispatcherQueueTimer? _displayTimer;
    private DispatcherQueueTimer? _transitionTimer;
    private CapsuleBounds _transitionStart = new(0, 0, 1, 1);
    private CapsuleBounds _transitionTarget = new(0, 0, 1, 1);
    private long _transitionTimestamp;
    private bool _nativeVisible = true;
    private bool _closed;
    private uint _taskbarCreatedMessage;
    private SettingsWindow? _settingsWindow;
    private readonly WindowsFeedbackSoundService? _sounds;

    public MainWindow(
        OrbitViewModel viewModel,
        WindowsHotKeyService? hotKeyService = null,
        TaskbarTrayService? trayService = null,
        WindowsFeedbackSoundService? sounds = null)
    {
        InitializeComponent();

        _viewModel = viewModel ?? throw new ArgumentNullException(nameof(viewModel));
        _hotKeyService = hotKeyService;
        _trayService = trayService;
        _sounds = sounds;
        _viewModel.SetDispatcher(action =>
        {
            if (DispatcherQueue.HasThreadAccess) action();
            else DispatcherQueue.TryEnqueue(() => action());
        });

        CapsuleView.DataContext = _viewModel;
        _viewModel.BoundsChanged += OnBoundsChanged;
        _viewModel.PropertyChanged += OnViewModelPropertyChanged;
        _viewModel.ActivationRequested += OnActivationRequested;
        _viewModel.SettingsRequested += OnSettingsRequested;
        if (_viewModel.Presentation != null) _viewModel.Presentation.PreviewChanged += OnPresentationChanged;

        ConfigureWindow();
        ApplyPresentation();
    }

    private void ConfigureWindow()
    {
        _hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        var windowId = Win32Interop.GetWindowIdFromWindow(_hwnd);
        _appWindow = AppWindow.GetFromWindowId(windowId);
        _taskbarCreatedMessage = NativeMethods.RegisterWindowMessage("TaskbarCreated");
        // Retain normal switcher/accessibility discovery for keyboard and assistive
        // tools; the borderless presenter still supplies the compact island shape.

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
        if (_hotKeyService != null && !_hotKeyService.Register(_hwnd))
            _viewModel.Mascot.StatusSubtext = "Ctrl+Alt+O is unavailable. Use the capsule or tray.";
        _trayService?.Initialize(_hwnd);

        // Apply initial layout positioning
        ApplyPosition(_viewModel.CurrentBounds);
        _viewModel.UpdatePosition(_hwnd);
        ApplyPosition(_viewModel.CurrentBounds);

        // Poll only foreground bounds and display geometry. No window titles,
        // contents, screenshots or keyboard input are collected.
        _displayTimer = DispatcherQueue.CreateTimer();
        _displayTimer.Interval = TimeSpan.FromSeconds(1);
        _displayTimer.Tick += OnDisplayTick;
        _displayTimer.Start();
        Activated += OnWindowActivated;

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
        else if (msg == NativeMethods.WM_DPICHANGED || msg == NativeMethods.WM_DISPLAYCHANGE || msg == NativeMethods.WM_SETTINGCHANGE)
        {
            // Let WinUI process its DPI change first, then compute with the new DPI.
            DispatcherQueue.TryEnqueue(() =>
            {
                if (!_closed) _viewModel.UpdatePosition(_hwnd);
            });
        }
        else if (_taskbarCreatedMessage != 0 && msg == _taskbarCreatedMessage)
        {
            _trayService?.Initialize(_hwnd);
        }

        return NativeMethods.CallWindowProc(_oldWndProc, hWnd, msg, wParam, lParam);
    }

    private void OnBoundsChanged(object? sender, CapsuleBounds bounds)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            if (_closed) return;
            AnimatePosition(bounds);
        });
    }

    private void OnDisplayTick(DispatcherQueueTimer sender, object args)
    {
        if (_closed) return;
        _viewModel.UpdatePosition(_hwnd);
        _viewModel.Mascot.UpdateAmbientState(_viewModel.Timer.IsRunning, _viewModel.Media.IsPlaying, _viewModel.Assistant.IsProcessing);
        _viewModel.Mascot.RefreshIdleState();
        _viewModel.RefreshCompanion();
    }
    private void OnSettingsRequested(object? sender, EventArgs e)
    {
        if (_closed || _sounds == null) return;
        // The island is topmost. Keep its expanded surface from obscuring the
        // settings window's header when the two windows share a display.
        _viewModel.IsExpanded = false;
        if (_settingsWindow == null)
        {
            _settingsWindow = new SettingsWindow(_viewModel, page => { Activate(); CapsuleView.NavigateTo(page); }, _sounds);
            _settingsWindow.Closed += (_, _) => _settingsWindow = null;
        }
        _settingsWindow.Activate();
    }
    private void OnPresentationChanged(object? sender, EventArgs e) => ApplyPresentation();
    private void ApplyPresentation()
    {
        var preferences = _viewModel.Presentation;
        if (preferences == null) return;
        static Windows.UI.Color Parse(string value) => Windows.UI.Color.FromArgb(255, Convert.ToByte(value.Substring(1,2),16), Convert.ToByte(value.Substring(3,2),16), Convert.ToByte(value.Substring(5,2),16));
        void Color(string name, Windows.UI.Color value) { if (Application.Current.Resources[name] is Microsoft.UI.Xaml.Media.SolidColorBrush brush) brush.Color = value; }
        Color("OrbitCyanAccentBrush", Parse(preferences.AccentHex));
        Color("OrbitCyanGlowBrush", Parse(preferences.AccentHex));
        var surface = Parse(preferences.Theme switch { "Ocean"=>"#17262A", "Bubblegum"=>"#281C26", "Matrix"=>"#17251D", "Minimal"=>"#24262B", _=>"#1C1F24" });
        surface.A = (byte)Math.Round(255 * preferences.SurfaceOpacity);
        Color("OrbitSurfaceBrush", surface);
        _viewModel.Mascot.SleepModeEnabled = preferences.SleepMode;
        _viewModel.Mascot.IdleTimeout = TimeSpan.FromSeconds(preferences.IdleTimeoutSeconds);
        _viewModel.Mascot.AnimationIntensity = preferences.MotionIntensity;
        CapsuleView.ApplyPresentation();
    }

    private void OnWindowActivated(object sender, WindowActivatedEventArgs args)
    {
        if (args.WindowActivationState == WindowActivationState.Deactivated)
            _viewModel.HasKeyboardFocus = false;
    }

    private void OnActivationRequested(object? sender, EventArgs args)
    {
        if (!_closed && _viewModel.IsVisible) Activate();
    }

    private void OnViewModelPropertyChanged(object? sender, PropertyChangedEventArgs args)
    {
        if (args.PropertyName != nameof(OrbitViewModel.IsVisible)) return;
        DispatcherQueue.TryEnqueue(() =>
        {
            if (_closed || _appWindow == null || _nativeVisible == _viewModel.IsVisible) return;
            _nativeVisible = _viewModel.IsVisible;
            if (_nativeVisible)
            {
                ApplyPosition(_viewModel.CurrentBounds);
                _appWindow.Show(false);
            }
            else
            {
                _transitionTimer?.Stop();
                _appWindow.Hide();
            }
        });
    }

    private void AnimatePosition(CapsuleBounds bounds)
    {
        bool animate;
        try { animate = new Windows.UI.ViewManagement.UISettings().AnimationsEnabled && _viewModel.Presentation?.MotionIntensity != 0; }
        catch { animate = false; }
        if (!animate || !_nativeVisible || _appWindow == null)
        {
            _transitionTimer?.Stop();
            ApplyPosition(bounds);
            return;
        }

        _transitionStart = new CapsuleBounds(_appWindow.Position.X, _appWindow.Position.Y,
            _appWindow.Size.Width, _appWindow.Size.Height);
        _transitionTarget = bounds;
        _transitionTimestamp = Stopwatch.GetTimestamp();
        if (_transitionTimer == null)
        {
            _transitionTimer = DispatcherQueue.CreateTimer();
            _transitionTimer.Interval = TimeSpan.FromMilliseconds(16);
            _transitionTimer.Tick += OnTransitionTick;
        }
        _transitionTimer.Start();
    }

    private void OnTransitionTick(DispatcherQueueTimer sender, object args)
    {
        var progress = Math.Clamp(Stopwatch.GetElapsedTime(_transitionTimestamp).TotalMilliseconds / 180, 0, 1);
        var eased = 1 - Math.Pow(1 - progress, 3);
        int Between(int start, int end) => (int)Math.Round(start + (end - start) * eased);
        ApplyPosition(new CapsuleBounds(Between(_transitionStart.X, _transitionTarget.X),
            Between(_transitionStart.Y, _transitionTarget.Y),
            Between(_transitionStart.Width, _transitionTarget.Width),
            Between(_transitionStart.Height, _transitionTarget.Height)));
        if (progress >= 1) sender.Stop();
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
        _closed = true;
        Activated -= OnWindowActivated;
        if (_displayTimer != null)
        {
            _displayTimer.Stop();
            _displayTimer.Tick -= OnDisplayTick;
        }
        if (_transitionTimer != null)
        {
            _transitionTimer.Stop();
            _transitionTimer.Tick -= OnTransitionTick;
        }
        _viewModel.BoundsChanged -= OnBoundsChanged;
        _viewModel.PropertyChanged -= OnViewModelPropertyChanged;
        _viewModel.ActivationRequested -= OnActivationRequested;
        _viewModel.SettingsRequested -= OnSettingsRequested;
        if (_viewModel.Presentation != null) _viewModel.Presentation.PreviewChanged -= OnPresentationChanged;
        _settingsWindow?.Close();
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
