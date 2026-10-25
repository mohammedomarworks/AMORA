using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using AMORA.Orbit.ViewModels;

namespace AMORA.Orbit.Views;

public sealed partial class OrbitCapsuleView : UserControl
{
    public OrbitCapsuleView()
    {
        InitializeComponent();
        Loaded += OnLoaded;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        BreathingGlowStoryboard.Begin();
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
            vm.Collapse();
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
            }
        }
    }

    private async void OnSubmitCommandClicked(object sender, RoutedEventArgs e)
    {
        if (DataContext is OrbitViewModel vm && vm.Assistant.CanSubmit)
        {
            await vm.Assistant.SubmitAsync();
        }
    }

    private void OnClearCommandClicked(object sender, RoutedEventArgs e)
    {
        if (DataContext is OrbitViewModel vm)
        {
            vm.Assistant.Clear();
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
}
