using Microsoft.UI.Xaml.Controls;

namespace AMORA.Orbit.Views;

public sealed partial class SystemStatusView : UserControl
{
    public SystemStatusView()
    {
        InitializeComponent();
    }
    public void SetModuleVisibility(bool battery, bool telemetry)
    {
        BatteryCard.Visibility = battery ? Microsoft.UI.Xaml.Visibility.Visible : Microsoft.UI.Xaml.Visibility.Collapsed;
        TelemetryCard.Visibility = telemetry ? Microsoft.UI.Xaml.Visibility.Visible : Microsoft.UI.Xaml.Visibility.Collapsed;
    }
}
