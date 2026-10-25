using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using AMORA.Orbit.ViewModels;

namespace AMORA.Orbit.Views;

public sealed partial class SuggestionBannerView : UserControl
{
    public SuggestionBannerView()
    {
        InitializeComponent();
    }

    private async void OnExecuteActionClicked(object sender, RoutedEventArgs e)
    {
        if (DataContext is SuggestionViewModel vm)
        {
            await vm.ExecuteActionAsync();
        }
    }

    private void OnSnoozeClicked(object sender, RoutedEventArgs e)
    {
        if (DataContext is SuggestionViewModel vm)
        {
            vm.Snooze();
        }
    }

    private void OnDismissClicked(object sender, RoutedEventArgs e)
    {
        if (DataContext is SuggestionViewModel vm)
        {
            vm.Dismiss();
        }
    }
}
