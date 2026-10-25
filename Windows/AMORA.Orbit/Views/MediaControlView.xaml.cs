using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using AMORA.Orbit.ViewModels;

namespace AMORA.Orbit.Views;

public sealed partial class MediaControlView : UserControl
{
    public MediaControlView()
    {
        InitializeComponent();
    }

    private async void OnPlayPauseClicked(object sender, RoutedEventArgs e)
    {
        if (DataContext is MediaControlViewModel vm)
        {
            await vm.TogglePlayPauseAsync();
        }
    }

    private async void OnNextClicked(object sender, RoutedEventArgs e)
    {
        if (DataContext is MediaControlViewModel vm)
        {
            await vm.NextTrackAsync();
        }
    }

    private async void OnPreviousClicked(object sender, RoutedEventArgs e)
    {
        if (DataContext is MediaControlViewModel vm)
        {
            await vm.PreviousTrackAsync();
        }
    }
}
