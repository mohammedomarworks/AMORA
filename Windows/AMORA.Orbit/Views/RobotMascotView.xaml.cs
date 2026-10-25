using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using AMORA.Orbit.ViewModels;

namespace AMORA.Orbit.Views;

public sealed partial class RobotMascotView : UserControl
{
    public RobotMascotView()
    {
        InitializeComponent();
    }

    private async void OnTapped(object sender, TappedRoutedEventArgs e)
    {
        if (DataContext is RobotMascotViewModel vm)
        {
            await vm.TriggerClickReactionAsync();
        }
    }
}
