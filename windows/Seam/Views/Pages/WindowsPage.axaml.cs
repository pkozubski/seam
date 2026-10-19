using System.ComponentModel;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Seam.Localization;
using Seam.Models;
using Seam.ViewModels;

namespace Seam.Views.Pages;

public partial class WindowsPage : UserControl
{
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
        if (_vm is not null) _vm.PropertyChanged += Changed;
        Refresh();
    }

    private void Changed(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(MainViewModel.SelectedMacSide)) Refresh();
    }

    private void Refresh() => ArrangementLabel.Text = (_vm?.SelectedMacSide.Value ?? MacSide.Left) switch
    {
        MacSide.Left => L10n.T("Mac stoi po lewej od tego ekranu", "The Mac is to the left of this screen"),
        MacSide.Right => L10n.T("Mac stoi po prawej od tego ekranu", "The Mac is to the right of this screen"),
        MacSide.Top => L10n.T("Mac stoi nad tym ekranem", "The Mac is above this screen"),
        _ => L10n.T("Mac stoi pod tym ekranem", "The Mac is below this screen"),
    };

    private void OpenDisplays(object? sender, RoutedEventArgs e)
    {
        if (TopLevel.GetTopLevel(this) is MainWindow window) window.NavigateTo("displays");
    }

    private void OpenConnection(object? sender, RoutedEventArgs e)
    {
        if (TopLevel.GetTopLevel(this) is MainWindow window) window.NavigateTo("connection");
    }
}
