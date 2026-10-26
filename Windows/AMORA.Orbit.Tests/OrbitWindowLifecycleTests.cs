using AMORA.Orbit.Models;
using AMORA.Orbit.Services.Contracts;
using AMORA.Orbit.Services.Implementations;
using AMORA.Orbit.ViewModels;
using Xunit;

namespace AMORA.Orbit.Tests;

public sealed class OrbitWindowLifecycleTests : IDisposable
{
    private readonly RecordingPositioning _positioning = new();
    private readonly StandardTimerService _timer = new();
    private readonly ProactiveSuggestionService _suggestions = new();
    private readonly OrbitViewModel _viewModel;

    public OrbitWindowLifecycleTests()
    {
        var media = new PreviewMediaService();
        var battery = new PreviewBatteryService();
        var telemetry = new PreviewSystemTelemetryService();
        var engine = new AssistantEngine(new DeterministicCommandRouter(), _timer,
            media, battery, telemetry, new LocalStubAIProvider());
        _viewModel = new OrbitViewModel(_positioning, new RobotMascotViewModel(),
            new MediaControlViewModel(media), new TimerControlViewModel(_timer),
            new SuggestionViewModel(_suggestions), new SystemStatusViewModel(battery, telemetry),
            new AssistantCommandViewModel(engine));
    }

    [Fact]
    public void ExpandAndCollapse_RetainNativeWindowHandle()
    {
        var handle = new IntPtr(42);
        _viewModel.UpdatePosition(handle);
        _viewModel.Expand();
        Assert.Equal(handle, _positioning.LastHandle);
        Assert.Equal(860, _viewModel.CurrentBounds.Width);
        _viewModel.Collapse();
        Assert.Equal(handle, _positioning.LastHandle);
        Assert.Equal(176, _viewModel.CurrentBounds.Width);
    }

    [Fact]
    public void WorkspaceAndEscape_UseThreeStageNavigation()
    {
        _viewModel.SetWorkspaceOpen(true);
        Assert.True(_viewModel.IsExpanded);
        Assert.Equal(520, _viewModel.CurrentBounds.Height);
        _viewModel.HandleEscape();
        Assert.True(_viewModel.IsExpanded);
        Assert.False(_viewModel.IsWorkspaceOpen);
        Assert.Equal(300, _viewModel.CurrentBounds.Height);
        _viewModel.HandleEscape();
        Assert.False(_viewModel.IsExpanded);
        Assert.Equal(34, _viewModel.CurrentBounds.Height);
    }

    [Fact]
    public void FullscreenSuppression_RestoresVisibilityWhenForegroundReturns()
    {
        _viewModel.UpdatePosition(new IntPtr(42));
        _positioning.Fullscreen = true;
        _viewModel.UpdatePosition();
        Assert.False(_viewModel.IsVisible);
        _positioning.Fullscreen = false;
        _viewModel.UpdatePosition();
        Assert.True(_viewModel.IsVisible);
        Assert.Equal(new IntPtr(42), _positioning.LastHandle);
    }

    [Fact]
    public void UnchangedDisplayPolling_DoesNotRestartWindowAnimation()
    {
        var changes = 0;
        _viewModel.BoundsChanged += (_, _) => changes++;
        _viewModel.UpdatePosition(new IntPtr(42));
        _viewModel.UpdatePosition();
        _viewModel.UpdatePosition();
        Assert.Equal(0, changes);
        _viewModel.Expand();
        Assert.Equal(1, changes);
    }

    [Fact]
    public async Task KeyboardFocusAndWorkspace_PreventHoverCollapse()
    {
        _viewModel.Expand();
        _viewModel.HasKeyboardFocus = true;
        _viewModel.OnPointerExited();
        await Task.Delay(500);
        Assert.True(_viewModel.IsExpanded);
        _viewModel.HasKeyboardFocus = false;
        _viewModel.SetWorkspaceOpen(true);
        _viewModel.OnPointerExited();
        await Task.Delay(500);
        Assert.True(_viewModel.IsExpanded);
    }

    [Fact]
    public async Task DelayedHoverCollapse_IsDispatchedAndCanBeCancelledByReentry()
    {
        Action? pending = null;
        _viewModel.SetDispatcher(action => pending = action);
        _viewModel.Expand();
        _viewModel.OnPointerExited();
        await Task.Delay(550);
        Assert.True(_viewModel.IsExpanded);
        Assert.NotNull(pending);
        _viewModel.OnPointerEntered();
        pending!();
        Assert.True(_viewModel.IsExpanded);
    }

    [Fact]
    public async Task Disposal_IgnoresQueuedHoverCallbacks()
    {
        Action? pending = null;
        _viewModel.SetDispatcher(action => pending = action);
        _viewModel.Expand();
        _viewModel.OnPointerExited();
        await Task.Delay(550);
        Assert.NotNull(pending);
        _viewModel.Dispose();
        pending!();
        Assert.True(_viewModel.IsExpanded);
    }

    [Fact]
    public async Task EnteringOwnFlyout_PreventsPendingPointerExitCollapse()
    {
        Action? pending = null;
        _viewModel.SetDispatcher(action => pending = action);
        _viewModel.Expand();
        _viewModel.OnPointerExited();
        _viewModel.IsTransientOpen = true;
        await Task.Delay(550);
        Assert.NotNull(pending);
        pending!();
        Assert.True(_viewModel.IsExpanded);
    }

    [Fact]
    public async Task EnabledHoverWaitsForDwellAndUiDispatchBeforeExpanding()
    {
        using var presentation = CreatePresentation(hoverEnabled: true);
        using var vm = CreateWithPresentation(presentation);
        var queued = new TaskCompletionSource<(Action Callback, TimeSpan Elapsed)>(TaskCreationOptions.RunContinuationsAsynchronously);
        var start = System.Diagnostics.Stopwatch.GetTimestamp();
        vm.SetDispatcher(action => queued.TrySetResult((action, System.Diagnostics.Stopwatch.GetElapsedTime(start))));

        vm.OnPointerEntered();
        Assert.True(vm.IsHovered);
        Assert.False(vm.IsExpanded); // Pointer entry must not immediately steal the click target.
        var dispatch = await queued.Task.WaitAsync(TimeSpan.FromSeconds(3));
        Assert.True(dispatch.Elapsed >= TimeSpan.FromMilliseconds(300), "The 350 ms dwell must occur before expansion is queued.");
        Assert.False(vm.IsExpanded); // A worker timer must not mutate the window directly.
        dispatch.Callback();
        Assert.True(vm.IsExpanded);
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public async Task ExplicitExpandBeforeOrAfterHoverCallbackIsStable(bool clickBeforeDwell)
    {
        using var presentation = CreatePresentation(hoverEnabled: true);
        using var vm = CreateWithPresentation(presentation);
        var queued = new TaskCompletionSource<Action>(TaskCreationOptions.RunContinuationsAsynchronously);
        var boundsChanges = 0;
        vm.BoundsChanged += (_, _) => boundsChanges++;
        vm.SetDispatcher(action => queued.TrySetResult(action));

        vm.OnPointerEntered();
        if (clickBeforeDwell) vm.Expand(); // The collapsed capsule's click uses explicit expansion.
        var callback = await queued.Task.WaitAsync(TimeSpan.FromSeconds(3));
        callback();
        if (!clickBeforeDwell) vm.Expand();

        Assert.True(vm.IsExpanded);
        Assert.Equal(1, boundsChanges); // Hover and click cannot toggle each other closed or animate twice.
    }

    [Fact]
    public async Task LeavingBeforeHoverDwellCancelsExpansion()
    {
        using var presentation = CreatePresentation(hoverEnabled: true);
        using var vm = CreateWithPresentation(presentation);
        var callbacks = new System.Collections.Concurrent.ConcurrentQueue<Action>();
        vm.SetDispatcher(callbacks.Enqueue);

        vm.OnPointerEntered();
        vm.OnPointerExited();
        await Task.Delay(500);

        Assert.False(vm.IsHovered);
        Assert.False(vm.IsExpanded);
        Assert.Empty(callbacks);
    }

    [Fact]
    public async Task LeavingAfterHoverDwellInvalidatesAlreadyQueuedExpansion()
    {
        using var presentation = CreatePresentation(hoverEnabled: true);
        using var vm = CreateWithPresentation(presentation);
        var queued = new TaskCompletionSource<Action>(TaskCreationOptions.RunContinuationsAsynchronously);
        vm.SetDispatcher(action => queued.TrySetResult(action));

        vm.OnPointerEntered();
        var callback = await queued.Task.WaitAsync(TimeSpan.FromSeconds(3));
        vm.OnPointerExited();
        callback();

        Assert.False(vm.IsExpanded);
    }

    [Fact]
    public async Task DisabledHoverPreferenceLeavesExplicitClickAvailable()
    {
        using var presentation = CreatePresentation(hoverEnabled: false);
        using var vm = CreateWithPresentation(presentation);
        var callbacks = new System.Collections.Concurrent.ConcurrentQueue<Action>();
        vm.SetDispatcher(callbacks.Enqueue);

        vm.OnPointerEntered();
        await Task.Delay(500);
        Assert.False(vm.IsExpanded);
        Assert.Empty(callbacks);
        vm.Expand();
        Assert.True(vm.IsExpanded);
    }

    [Fact]
    public async Task DisablingHoverPreferenceInvalidatesAlreadyQueuedExpansion()
    {
        using var presentation = CreatePresentation(hoverEnabled: true);
        using var vm = CreateWithPresentation(presentation);
        var queued = new TaskCompletionSource<Action>(TaskCreationOptions.RunContinuationsAsynchronously);
        vm.SetDispatcher(action => queued.TrySetResult(action));

        vm.OnPointerEntered();
        var callback = await queued.Task.WaitAsync(TimeSpan.FromSeconds(3));
        presentation.HoverToExpand = false;
        callback();

        Assert.False(vm.IsExpanded);
    }

    private static PresentationViewModel CreatePresentation(bool hoverEnabled) =>
        new(new PresentationPreferencesStore(Path.Combine(Path.GetTempPath(), "AmoraHoverTests", Guid.NewGuid().ToString("N"), "presentation.json")))
        { HoverToExpand = hoverEnabled }; // No save: never reads or writes the user's actual preferences.

    private OrbitViewModel CreateWithPresentation(PresentationViewModel presentation)
    {
        var media = new PreviewMediaService();
        var battery = new PreviewBatteryService();
        var telemetry = new PreviewSystemTelemetryService();
        var engine = new AssistantEngine(new DeterministicCommandRouter(), _timer,
            media, battery, telemetry, new LocalStubAIProvider());
        return new OrbitViewModel(new RecordingPositioning(), new RobotMascotViewModel(),
            new MediaControlViewModel(media), new TimerControlViewModel(_timer),
            new SuggestionViewModel(_suggestions), new SystemStatusViewModel(battery, telemetry),
            new AssistantCommandViewModel(engine), presentation: presentation);
    }

    public void Dispose()
    {
        _viewModel.Dispose();
        _suggestions.Dispose();
        _timer.Dispose();
    }

    private sealed class RecordingPositioning : IWindowPositioningService
    {
        public IntPtr LastHandle { get; private set; }
        public bool Fullscreen { get; set; }
        public DisplayWorkArea GetCurrentWorkArea(IntPtr handle) => new(0, 0, 1920, 1080, 96, 1);
        public CapsuleBounds CalculateCapsuleBounds(IntPtr handle, bool isExpanded,
            int collapsedWidth = 176, int collapsedHeight = 34,
            int expandedWidth = 860, int expandedHeight = 300)
        {
            LastHandle = handle;
            return WindowsWindowPositioningService.CalculateCapsuleBoundsFromWorkArea(
                0, 0, 1920, 1080, 1, isExpanded, collapsedWidth, collapsedHeight, expandedWidth, expandedHeight);
        }
        public bool IsForegroundAppFullscreen(IntPtr handle)
        {
            LastHandle = handle;
            return Fullscreen;
        }
    }
}
