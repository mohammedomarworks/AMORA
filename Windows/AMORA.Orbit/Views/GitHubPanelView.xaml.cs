using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using System.ComponentModel;
using AMORA.Orbit.ViewModels;
using AMORA.Orbit.Models;
namespace AMORA.Orbit.Views;

public sealed partial class GitHubPanelView : UserControl
{
    private GitHubActivityViewModel? _model;
    public GitHubPanelView()
    {
        InitializeComponent();
        DataContextChanged += (_, e) => Attach(e.NewValue as GitHubActivityViewModel);
        Loaded += (_, _) => Attach(DataContext as GitHubActivityViewModel);
        Unloaded += (_, _) => Attach(null);
    }
    private void Attach(GitHubActivityViewModel? model)
    {
        if (_model != null) _model.PropertyChanged -= Changed;
        _model = model;
        if (_model != null) _model.PropertyChanged += Changed;
        Update();
    }
    private void Changed(object? sender, PropertyChangedEventArgs e) => Update();
    private void Update()
    {
        bool connected = _model?.IsConnected == true;
        ConnectPanel.Visibility = connected ? Visibility.Collapsed : Visibility.Visible;
        ProfilePanel.Visibility = DataPanel.Visibility = connected ? Visibility.Visible : Visibility.Collapsed;
    }
    private async void OnConnect(object sender, RoutedEventArgs e) { if (_model != null) { await _model.ConnectAsync(); TokenBox.Password = ""; } }
    private async void OnSaved(object sender, RoutedEventArgs e) { if (_model != null) await _model.ConnectSavedAsync(); }
    private async void OnRefresh(object sender, RoutedEventArgs e) { if (_model != null) await _model.RefreshAsync(); }
    private async void OnDisconnect(object sender, RoutedEventArgs e) { if (_model != null) await _model.DisconnectAsync(); }
    private void OnTokenChanged(object sender, RoutedEventArgs e) { if (_model != null) _model.TokenInput = TokenBox.Password; }
    private async void OnOpenProfile(object sender, RoutedEventArgs e) { if (_model != null) await _model.OpenLinkAsync(_model.ProfileUrl); }
    private async void OnLink(object sender, RoutedEventArgs e) { if (_model != null && sender is FrameworkElement { Tag: string url }) await _model.OpenLinkAsync(url); }
    private void OnDayClicked(object sender, RoutedEventArgs e) { if (_model != null && sender is FrameworkElement { Tag: GitHubContributionDay day }) _model.SelectDay(day); }
    private void Select(int page)
    {
        ActivityPanel.Visibility = page == 0 ? Visibility.Visible : Visibility.Collapsed;
        ReposPanel.Visibility = page == 1 ? Visibility.Visible : Visibility.Collapsed;
        PrsPanel.Visibility = page == 2 ? Visibility.Visible : Visibility.Collapsed;
        var tabs = new[] { ActivityTab, RepositoriesTab, PullRequestsTab };
        for (int i = 0; i < tabs.Length; i++) tabs[i].Background = new Microsoft.UI.Xaml.Media.SolidColorBrush(i == page ? Windows.UI.Color.FromArgb(255,44,48,53) : Microsoft.UI.Colors.Transparent);
    }
    private void OnActivity(object sender, RoutedEventArgs e) => Select(0);
    private void OnRepositories(object sender, RoutedEventArgs e) => Select(1);
    private void OnPullRequests(object sender, RoutedEventArgs e) => Select(2);
}
