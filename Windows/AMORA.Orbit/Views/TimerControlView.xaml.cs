using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using AMORA.Orbit.ViewModels;

namespace AMORA.Orbit.Views;

public sealed partial class TimerControlView : UserControl
{
    public TimerControlView()
    {
        InitializeComponent();
    }

    private void OnPreset5Clicked(object sender, RoutedEventArgs e)
    {
        if (DataContext is TimerControlViewModel vm)
        {
            vm.StartPreset(5);
        }
    }

    private void OnPreset15Clicked(object sender, RoutedEventArgs e)
    {
        if (DataContext is TimerControlViewModel vm)
        {
            vm.StartPreset(15);
        }
    }

    private void OnPreset25Clicked(object sender, RoutedEventArgs e)
    {
        if (DataContext is TimerControlViewModel vm)
        {
            vm.StartPreset(25);
        }
    }

    private void OnAddOneMinuteClicked(object sender, RoutedEventArgs e)
    {
        if (DataContext is TimerControlViewModel vm)
        {
            vm.AddOneMinute();
        }
    }

    private void OnTogglePauseClicked(object sender, RoutedEventArgs e)
    {
        if (DataContext is TimerControlViewModel vm)
        {
            vm.TogglePause();
        }
    }

    private void OnCancelClicked(object sender, RoutedEventArgs e)
    {
        if (DataContext is TimerControlViewModel vm)
        {
            vm.Cancel();
        }
    }
}
