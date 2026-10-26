using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using AMORA.Orbit.ViewModels;
using AMORA.Orbit.Models;
using System.ComponentModel;
using Microsoft.UI.Xaml.Media;
using System.Collections.Specialized;
using Windows.ApplicationModel.DataTransfer;

namespace AMORA.Orbit.Views;

public sealed partial class OrbitCapsuleView : UserControl
{
    private OrbitViewModel? _model;
    private bool _animationsEnabled;
    private bool _talkOpen;
    private string? _utilityPage;
    private TimerStatus _lastTimerStatus;
    private bool _updatingPage;
    public OrbitCapsuleView()
    {
        InitializeComponent();
        // Buttons/text editors may handle these routed events before they reach
        // the island. Observe them without taking over their normal behavior.
        IslandRoot.AddHandler(UIElement.PointerPressedEvent, new PointerEventHandler(OnIslandInteraction), handledEventsToo: true);
        IslandRoot.AddHandler(UIElement.KeyDownEvent, new KeyEventHandler(OnIslandKeyDown), handledEventsToo: true);
        Loaded += OnLoaded;
        DataContextChanged += OnDataContextChanged;
        Unloaded += (_, _) => { BreathingGlowStoryboard.Stop(); OpenStoryboard.Stop(); DetachModel(); };
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        if (_model == null && DataContext is OrbitViewModel vm) AttachModel(vm);
        // Loading must honor both the saved AMORA preference and Windows motion
        // settings, using the same path as live preference changes.
        ApplyPresentation();
    }

    private void OnDataContextChanged(FrameworkElement sender, DataContextChangedEventArgs args)
    {
        DetachModel();
        if (args.NewValue is OrbitViewModel vm)
        {
            AttachModel(vm);
        }
    }

    private void AttachModel(OrbitViewModel vm)
    {
        _model = vm;
        vm.PropertyChanged += OnModelChanged;
        vm.Timer.PropertyChanged += OnTimerChanged;
        vm.Assistant.Transcript.CollectionChanged += OnTranscriptChanged;
        if (vm.Settings != null) vm.Settings.PropertyChanged += OnDrawerChanged;
        if (vm.Automations != null) vm.Automations.PropertyChanged += OnDrawerChanged;
        UpdatePage();
        ApplyPresentation();
    }

    private void DetachModel()
    {
        if (_model == null) return;
        _model.PropertyChanged -= OnModelChanged;
        _model.Timer.PropertyChanged -= OnTimerChanged;
        _model.Assistant.Transcript.CollectionChanged -= OnTranscriptChanged;
        if (_model.Settings != null) _model.Settings.PropertyChanged -= OnDrawerChanged;
        if (_model.Automations != null) _model.Automations.PropertyChanged -= OnDrawerChanged;
        _model = null;
    }

    private void OnModelChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(OrbitViewModel.IsExpanded))
        {
            if (_model?.IsExpanded == true)
            {
                if (_animationsEnabled) OpenStoryboard.Begin();
                HomeButton.Focus(FocusState.Programmatic);
            }
            else { OpenStoryboard.Stop(); IslandContents.Opacity = 1; CloseQuickMenu(); }
        }
        if (!_updatingPage && e.PropertyName == nameof(OrbitViewModel.IsWorkspaceOpen) && _model?.IsWorkspaceOpen == false)
        {
            _talkOpen = false;
            _utilityPage = null;
            UpdatePage();
        }
    }

    private void OnTimerChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName != nameof(TimerControlViewModel.Status) || _model == null) return;
        if (_lastTimerStatus == _model.Timer.Status) return;
        _lastTimerStatus = _model.Timer.Status;
        if (_model.Assistant.IsProcessing) return;
        switch (_model.Timer.Status)
        {
            case TimerStatus.Running: _model.Mascot.SetMood(MascotMood.Focused); _model.Mascot.StatusSubtext = "One thing at a time. You've got this."; break;
            case TimerStatus.Paused: _model.Mascot.SetMood(MascotMood.Curious); _model.Mascot.StatusSubtext = "Take your time. I'll keep your place."; break;
            case TimerStatus.Completed: _model.Mascot.SetMood(MascotMood.Celebrating); _model.Mascot.StatusSubtext = "Time's up. A little break?"; break;
            default: _model.Mascot.SetMood(MascotMood.Idle); _model.Mascot.StatusSubtext = "Here when you need me."; break;
        }
    }

    private void OnDrawerChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == "IsOpen") UpdatePage();
    }

    private void OnTranscriptChanged(object? sender, NotifyCollectionChangedEventArgs e)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            if (_model == null || XamlRoot == null) return;
            ChatWelcome.Visibility = _model.Assistant.Transcript.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
            ConversationScroll.UpdateLayout();
            ConversationScroll.ChangeView(null, ConversationScroll.ScrollableHeight, null, true);
        });
    }

    private void UpdatePage()
    {
        if (_model == null || _updatingPage) return;
        _updatingPage = true;
        bool drawer = _model.Automations?.IsOpen == true;
        HomePanel.Visibility = !_talkOpen && _utilityPage == null && !drawer ? Visibility.Visible : Visibility.Collapsed;
        TalkPanel.Visibility = _talkOpen && !drawer && _utilityPage == null ? Visibility.Visible : Visibility.Collapsed;
        ClipboardPanel.Visibility = _utilityPage == "clipboard" && !drawer ? Visibility.Visible : Visibility.Collapsed;
        NotesPanel.Visibility = _utilityPage == "notes" && !drawer ? Visibility.Visible : Visibility.Collapsed;
        FilesPanel.Visibility = _utilityPage == "files" && !drawer ? Visibility.Visible : Visibility.Collapsed;
        TimerPanel.Visibility = _utilityPage == "timer" && !drawer ? Visibility.Visible : Visibility.Collapsed;
        GitHubPanel.Visibility = _utilityPage == "github" && !drawer ? Visibility.Visible : Visibility.Collapsed;
        AutomationsScroll.Visibility = drawer ? Visibility.Visible : Visibility.Collapsed;
        bool tall = _utilityPage is "notes" or "files" or "clipboard" or "github" || drawer;
        _model.ActivePage = _talkOpen ? "talk" : _utilityPage ?? "home";
        _model.SetWorkspaceOpen(_talkOpen || _utilityPage != null || drawer, tall ? 460 : 280);
        _model.RefreshCompanion();
        HomeButton.Background = new SolidColorBrush(!_talkOpen && _utilityPage == null && !drawer ? Windows.UI.Color.FromArgb(255,51,53,57) : Microsoft.UI.Colors.Transparent);
        TalkButton.Background = new SolidColorBrush(_talkOpen ? Windows.UI.Color.FromArgb(255,51,53,57) : Microsoft.UI.Colors.Transparent);
        ChatWelcome.Visibility = _model.Assistant.Transcript.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        CloseQuickMenu();
        _updatingPage = false;
    }

    private void OnHomeClicked(object sender, RoutedEventArgs e)
    {
        _talkOpen = false;
        _utilityPage = null;
        if (_model?.Settings != null) _model.Settings.IsOpen = false;
        if (_model?.Automations != null) _model.Automations.IsOpen = false;
        UpdatePage();
    }

    private void OnTalkClicked(object sender, RoutedEventArgs e)
    {
        if (_model?.Settings != null) _model.Settings.IsOpen = false;
        if (_model?.Automations != null) _model.Automations.IsOpen = false;
        _utilityPage = null;
        _talkOpen = true;
        UpdatePage();
        AssistantInputBox.Focus(FocusState.Programmatic);
    }

    private void OpenUtility(string page)
    {
        if (_model?.Settings != null) _model.Settings.IsOpen = false;
        if (_model?.Automations != null) _model.Automations.IsOpen = false;
        _talkOpen = false;
        _utilityPage = page;
        UpdatePage();
    }
    private void OnTimerPageClicked(object sender, RoutedEventArgs e) => OpenUtility("timer");
    private void OnGitHubClicked(object sender, RoutedEventArgs e) => OpenUtility("github");
    private void OnQuickMenuToggle(object sender, RoutedEventArgs e)
    {
        bool open = QuickMenuLayer.Visibility != Visibility.Visible;
        QuickMenuLayer.Visibility = open ? Visibility.Visible : Visibility.Collapsed;
        if (_model != null) _model.IsTransientOpen = open;
    }
    private void CloseQuickMenu() { QuickMenuLayer.Visibility = Visibility.Collapsed; if (_model != null) _model.IsTransientOpen = false; }
    private void OnCloseQuickMenu(object sender, RoutedEventArgs e) => CloseQuickMenu();
    private void OnIslandInteraction(object sender, PointerRoutedEventArgs e) => _model?.Mascot.NoteInteraction();
    private void OnIslandSizeChanged(object sender, SizeChangedEventArgs e) => IslandRoot.Clip = new RectangleGeometry { Rect = new Windows.Foundation.Rect(0, 0, e.NewSize.Width, e.NewSize.Height) };
    public void ApplyPresentation()
    {
        var prefs = _model?.Presentation;
        if (prefs == null) return;
        MascotSizer.Height = 58 * prefs.MascotSize / 32;
        HomeMedia.Visibility = prefs.MusicEnabled ? Visibility.Visible : Visibility.Collapsed;
        HomeTimer.Visibility = prefs.TimerEnabled ? Visibility.Visible : Visibility.Collapsed;
        HomeSystemStatus.SetModuleVisibility(prefs.BatteryEnabled, prefs.SystemMonitorEnabled);
        bool animate;
        try { animate = new Windows.UI.ViewManagement.UISettings().AnimationsEnabled && prefs.MotionIntensity > 0; } catch { animate = false; }
        _animationsEnabled = animate;
        if (animate) BreathingGlowStoryboard.Begin(); else { BreathingGlowStoryboard.Stop(); PillGlowDot.Opacity = 1; }
    }
    public async void NavigateTo(string page)
    {
        _model?.Expand();
        if (page == "automations") { if (_model?.Automations != null) _model.Automations.IsOpen = true; }
        else if (page == "memory")
        {
            OnTalkClicked(this, new RoutedEventArgs());
            if (_model != null) { _model.Assistant.InputText = "list memories"; await _model.Assistant.SubmitAsync(); }
        }
        else OpenUtility(page);
    }
    private async void OnSoundClicked(object sender, RoutedEventArgs e)
    { if (_model?.Presentation != null) { _model.Presentation.SoundEnabled = !_model.Presentation.SoundEnabled; await _model.Presentation.SaveAsync(); } }
    private async void OnChatChipClicked(object sender, RoutedEventArgs e)
    { if (_model != null && sender is FrameworkElement { Tag: string command }) { _model.Assistant.InputText = command; await _model.Assistant.SubmitAsync(); } }
    private void OnNotesClicked(object sender, RoutedEventArgs e) => OpenUtility("notes");
    private void OnQuickMenuOpening(object sender, object e) { if (_model != null) _model.IsTransientOpen = true; }
    private void OnQuickMenuClosed(object sender, object e) { if (_model != null) _model.IsTransientOpen = false; }
    private void OnFilesClicked(object sender, RoutedEventArgs e) => OpenUtility("files");
    private void OnClipboardClicked(object sender, RoutedEventArgs e) => OpenUtility("clipboard");
    private void OnClearClipboardClicked(object sender, RoutedEventArgs e) => _model?.Clipboard?.Clear();
    private void OnRemoveClipboardClicked(object sender, RoutedEventArgs e)
    { if (sender is FrameworkElement { Tag: string id }) _model?.Clipboard?.Remove(id); }
    private async void OnCopyClipboardClicked(object sender, RoutedEventArgs e)
    { if (sender is FrameworkElement { Tag: string id } && _model?.Clipboard != null) await _model.Clipboard.CopyAsync(id); }
    private void OnNewNoteClicked(object sender, RoutedEventArgs e) => _model?.Workspace?.NewNote();
    private void OnNoteSearchChanged(object sender, TextChangedEventArgs e) => _model?.Workspace?.SearchNotes();
    private void OnSelectNoteClicked(object sender, RoutedEventArgs e)
    { if (sender is FrameworkElement { Tag: Guid id }) _model?.Workspace?.SelectNote(id); }
    private async void OnSaveNoteClicked(object sender, RoutedEventArgs e)
    { if (_model?.Workspace != null) await _model.Workspace.SaveNoteAsync(); }
    private async void OnPinNoteClicked(object sender, RoutedEventArgs e)
    { if (_model?.Workspace?.SelectedNoteId is Guid id) await _model.Workspace.ToggleNotePinAsync(id); }
    private async void OnDeleteNoteClicked(object sender, RoutedEventArgs e)
    {
        if (_model?.Workspace?.SelectedNoteId is Guid id && await ConfirmDeleteAsync("Delete this note?", "This removes the selected local note."))
            await _model.Workspace.DeleteNoteAsync(id);
    }
    private async Task<bool> ConfirmDeleteAsync(string title, string content)
    {
        var dialog = new ContentDialog { XamlRoot = XamlRoot, RequestedTheme = ElementTheme.Dark,
            Title = title, Content = content, PrimaryButtonText = "Delete", CloseButtonText = "Cancel", DefaultButton = ContentDialogButton.Close };
        return await dialog.ShowAsync() == ContentDialogResult.Primary;
    }
    private async void OnAddFileClicked(object sender, RoutedEventArgs e)
    { if (_model?.Workspace != null) await _model.Workspace.AddPathAsync(); }
    private async void OnOpenFileClicked(object sender, RoutedEventArgs e)
    { if (sender is FrameworkElement { Tag: Guid id } && _model?.Workspace != null) await _model.Workspace.OpenShelfAsync(id); }
    private async void OnRevealFileClicked(object sender, RoutedEventArgs e)
    { if (sender is FrameworkElement { Tag: Guid id } && _model?.Workspace != null) await _model.Workspace.RevealShelfAsync(id); }
    private async void OnPinFileClicked(object sender, RoutedEventArgs e)
    { if (sender is FrameworkElement { Tag: Guid id } && _model?.Workspace != null) await _model.Workspace.ToggleShelfPinAsync(id); }
    private async void OnRemoveFileClicked(object sender, RoutedEventArgs e)
    { if (sender is FrameworkElement { Tag: Guid id } && _model?.Workspace != null) await _model.Workspace.RemoveShelfAsync(id); }
    private void OnFilesDragOver(object sender, DragEventArgs e)
    {
        e.AcceptedOperation = e.DataView.Contains(StandardDataFormats.StorageItems) ? DataPackageOperation.Link : DataPackageOperation.None;
        e.Handled = true;
    }
    private async void OnFilesDrop(object sender, DragEventArgs e)
    {
        var deferral = e.GetDeferral();
        try
        {
            if (_model?.Workspace != null && e.DataView.Contains(StandardDataFormats.StorageItems))
            {
                var items = await e.DataView.GetStorageItemsAsync();
                await _model.Workspace.AddPathsAsync(items.Select(item => item.Path));
            }
        }
        catch { /* The source canceled the drag or revoked access; no reference was added. */ }
        finally { deferral.Complete(); }
    }

    private void OnCollapsedPillClicked(object sender, RoutedEventArgs e) => _model?.Expand();
    private void OnStopClicked(object sender, RoutedEventArgs e) => _model?.Assistant.CancelActiveRequest();
    private void OnIslandGotFocus(object sender, RoutedEventArgs e)
    {
        if (_model != null) _model.HasKeyboardFocus = e.OriginalSource is TextBox or PasswordBox;
    }
    private void OnIslandLostFocus(object sender, RoutedEventArgs e)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            if (_model != null) _model.HasKeyboardFocus = FocusManager.GetFocusedElement(XamlRoot) is TextBox or PasswordBox;
        });
    }
    private void OnIslandKeyDown(object sender, KeyRoutedEventArgs e)
    {
        _model?.Mascot.NoteInteraction();
        if (e.Handled) return;
        if (e.Key == Windows.System.VirtualKey.Escape && QuickMenuLayer.Visibility == Visibility.Visible) { CloseQuickMenu(); e.Handled = true; return; }
        var alt = Microsoft.UI.Input.InputKeyboardSource.GetKeyStateForCurrentThread(Windows.System.VirtualKey.Menu);
        if ((alt & Windows.UI.Core.CoreVirtualKeyStates.Down) == 0) return;
        if (e.Key == Windows.System.VirtualKey.Number1) { OnHomeClicked(sender, e); e.Handled = true; }
        if (e.Key == Windows.System.VirtualKey.Number2) { OnTalkClicked(sender, e); e.Handled = true; }
    }

    private void OnHomeAcceleratorInvoked(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs e)
    {
        if (_model == null) return;
        e.Handled = true;
        _model.Mascot.NoteInteraction();
        _model.Expand();
        OnHomeClicked(this, new RoutedEventArgs());
        HomeButton.Focus(FocusState.Keyboard);
    }

    private void OnTalkAcceleratorInvoked(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs e)
    {
        if (_model == null) return;
        e.Handled = true;
        _model.Mascot.NoteInteraction();
        _model.Expand();
        OnTalkClicked(this, new RoutedEventArgs());
    }

    private void OnCollapsedPillTapped(object sender, TappedRoutedEventArgs e)
    {
        if (DataContext is OrbitViewModel vm)
        {
            vm.ToggleExpanded();
        }
    }

    private void OnContainerPointerEntered(object sender, PointerRoutedEventArgs e)
    {
        if (DataContext is OrbitViewModel vm)
        {
            vm.OnPointerEntered();
        }
    }

    private void OnContainerPointerExited(object sender, PointerRoutedEventArgs e)
    {
        if (DataContext is OrbitViewModel vm)
        {
            vm.OnPointerExited();
        }
    }

    private void OnPinToggleClicked(object sender, RoutedEventArgs e)
    {
        if (DataContext is OrbitViewModel vm)
        {
            vm.TogglePin();
        }
    }

    private void OnCollapseClicked(object sender, RoutedEventArgs e)
    {
        if (DataContext is OrbitViewModel vm)
        {
            vm.Assistant.CancelActiveRequest();
            vm.IsPinned = false;
            vm.IsExpanded = false;
        }
    }

    private async void OnLeftPrimaryActionClicked(object sender, RoutedEventArgs e)
    {
        if (DataContext is OrbitViewModel vm)
        {
            await vm.Suggestion.ExecuteActionAsync();
        }
    }

    private void OnLeftSnoozeClicked(object sender, RoutedEventArgs e)
    {
        if (DataContext is OrbitViewModel vm)
        {
            vm.Suggestion.Snooze();
        }
    }

    private void OnLeftDismissClicked(object sender, RoutedEventArgs e)
    {
        if (DataContext is OrbitViewModel vm)
        {
            vm.Suggestion.Dismiss();
        }
    }

    private async void OnCommandInputKeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key == Windows.System.VirtualKey.Enter)
        {
            if (DataContext is OrbitViewModel vm && vm.Assistant.CanSubmit)
            {
                e.Handled = true;
                await vm.Assistant.SubmitAsync();
                AssistantInputBox.Focus(FocusState.Programmatic);
            }
        }
        else if (e.Key == Windows.System.VirtualKey.Escape)
        {
            if (DataContext is OrbitViewModel vm)
            {
                e.Handled = true;
                if (vm.Assistant.HasText)
                {
                    vm.Assistant.InputText = string.Empty;
                }
                else
                {
                    vm.HandleEscape();
                }
            }
        }
    }

    private async void OnSubmitCommandClicked(object sender, RoutedEventArgs e)
    {
        if (DataContext is OrbitViewModel vm && vm.Assistant.CanSubmit)
        {
            await vm.Assistant.SubmitAsync();
            AssistantInputBox.Focus(FocusState.Programmatic);
        }
    }

    private void OnClearCommandClicked(object sender, RoutedEventArgs e)
    {
        if (DataContext is OrbitViewModel vm)
        {
            vm.Assistant.Clear();
        }
    }

    private void OnResetConversationClicked(object sender, RoutedEventArgs e)
    {
        if (DataContext is OrbitViewModel vm)
        {
            vm.Assistant.ResetConversation();
            OnTalkClicked(sender, e);
        }
    }

    private async void OnConfirmCommandClicked(object sender, RoutedEventArgs e)
    {
        if (DataContext is OrbitViewModel vm)
        {
            await vm.Assistant.ConfirmAsync();
        }
    }

    private void OnCancelConfirmationClicked(object sender, RoutedEventArgs e)
    {
        if (DataContext is OrbitViewModel vm)
        {
            vm.Assistant.CancelConfirmation();
        }
    }

    private void OnSettingsToggleClicked(object sender, RoutedEventArgs e)
    {
        CloseQuickMenu();
        _model?.RequestSettings();
    }

    private void OnCloseSettingsClicked(object sender, RoutedEventArgs e)
    {
        if (DataContext is OrbitViewModel vm && vm.Settings != null)
        {
            vm.Settings.IsOpen = false;
        }
    }

    private void OnAutomationsToggleClicked(object sender, RoutedEventArgs e)
    {
        if (DataContext is OrbitViewModel vm && vm.Automations != null)
        {
            vm.Automations.ToggleOpen();
        }
    }

    private void OnCloseAutomationsClicked(object sender, RoutedEventArgs e)
    {
        if (DataContext is OrbitViewModel vm && vm.Automations != null)
        {
            vm.Automations.IsOpen = false;
        }
    }

    private async void OnCreateAutomationClicked(object sender, RoutedEventArgs e)
    {
        if (DataContext is OrbitViewModel vm && vm.Automations != null)
        {
            await vm.Automations.CreateAutomationAsync();
        }
    }

    private async void OnAutomationToggled(object sender, RoutedEventArgs e)
    {
        if (DataContext is OrbitViewModel vm && vm.Automations != null && sender is FrameworkElement fe && fe.Tag is string id)
        {
            // Loading or refreshing a OneWay binding must never change persisted enablement.
            var item = vm.Automations.Items.FirstOrDefault(x => x.Id == id);
            if (sender is ToggleSwitch toggle && item != null && toggle.IsOn != item.IsEnabled)
                await vm.Automations.ToggleEnabledAsync(id);
        }
    }

    private async void OnDeleteAutomationClicked(object sender, RoutedEventArgs e)
    {
        if (DataContext is OrbitViewModel vm && vm.Automations != null && sender is FrameworkElement fe && fe.Tag is string id)
        {
            if (await ConfirmDeleteAsync("Delete this automation?", "This removes the local schedule."))
                await vm.Automations.DeleteAsync(id);
        }
    }

    private async void OnRunAutomationNowClicked(object sender, RoutedEventArgs e)
    {
        if (DataContext is OrbitViewModel vm && vm.Automations != null && sender is FrameworkElement fe && fe.Tag is string id)
        {
            await vm.Automations.RunNowAsync(id);
        }
    }
}
