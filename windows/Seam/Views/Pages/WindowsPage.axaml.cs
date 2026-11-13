using System.ComponentModel;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Seam.Localization;
using Seam.Models;
using Seam.ViewModels;

namespace Seam.Views.Pages;

public partial class WindowsPage : UserControl
{
    private const string HelpUrl = "https://seamdesk.app/#start";
    private static readonly string[] Watched =
    {
        nameof(MainViewModel.SelectedMacSide), nameof(MainViewModel.IsConnected), nameof(MainViewModel.SessionPro),
        nameof(MainViewModel.WindowSharingSwitch), nameof(MainViewModel.DisplayStatusText),
    };

    internal Control FullGuide => GuideContent;
    private MainViewModel? _vm;

    public WindowsPage()
    {
        InitializeComponent();
        L10n.Apply(this);
        AttachedToVisualTree += (_, _) => Attach(DataContext as MainViewModel);
        DetachedFromVisualTree += (_, _) => Attach(null);
        DataContextChanged += (_, _) => Attach(DataContext as MainViewModel);
    }

    private void Attach(MainViewModel? vm)
    {
        if (_vm is not null) _vm.PropertyChanged -= Changed;
        _vm = vm;
        if (_vm is not null)
        {
            _vm.PropertyChanged += Changed;
            Refresh();
        }
    }

    private void Changed(object? sender, PropertyChangedEventArgs e)
    {
        if (Watched.Contains(e.PropertyName)) Refresh();
    }

    private void Refresh()
    {
        if (_vm is null) return;
        // Jak status karty na macOS: bez Pro „wstrzymane”, wyłączone „Off”, inaczej stan strumienia.
        MasterStatus.Text = !_vm.SessionPro ? L10n.T("Paused — needs Seam Pro", pl: "Wstrzymane – wymaga Seam Pro")
            : !_vm.WindowSharingSwitch ? L10n.T("Off", pl: "Wyłączone")
            : _vm.DisplayStatusText;
        EdgeText.Text = (_vm.SelectedMacSide.Value switch
        {
            MacSide.Left => L10n.T("The Mac is to the left of this screen", pl: "Mac stoi po lewej od tego ekranu"),
            MacSide.Right => L10n.T("The Mac is to the right of this screen", pl: "Mac stoi po prawej od tego ekranu"),
            MacSide.Top => L10n.T("The Mac is above this screen", pl: "Mac stoi nad tym ekranem"),
            _ => L10n.T("The Mac is below this screen", pl: "Mac stoi pod tym ekranem"),
        }) + " ·";
        DisconnectedLinks.IsVisible = !_vm.IsConnected;
    }

    private void OpenDisplays(object? sender, RoutedEventArgs e)
    {
        if (TopLevel.GetTopLevel(this) is MainWindow window) window.NavigateTo("displays");
    }

    private void OpenConnection(object? sender, RoutedEventArgs e)
    {
        if (TopLevel.GetTopLevel(this) is not MainWindow window) return;
        window.NavigateTo("connection");
        (window.CurrentPage as ConnectionPage)?.ShowDetails();
    }

    private async void OpenHelp(object? sender, RoutedEventArgs e)
    {
        if (TopLevel.GetTopLevel(this) is { } top) await top.Launcher.LaunchUriAsync(new Uri(HelpUrl));
    }
}
