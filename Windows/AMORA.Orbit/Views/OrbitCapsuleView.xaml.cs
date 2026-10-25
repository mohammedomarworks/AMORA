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
}
