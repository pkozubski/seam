using System.ComponentModel;
using Avalonia.Controls;
using Seam.Localization;
using Seam.Models;
using Seam.ViewModels;
using Seam.Views;

namespace Seam.Views.Pages;

/// <summary>
/// Układ ekranów: ten monitor na środku, Mac przeciągany na jedną z czterech stron
/// (<see cref="ScreenArrangement"/>). Wybór ustawia <see cref="MainViewModel.SelectedMacSide"/>.
/// </summary>
public partial class DisplaysPage : UserControl
{
    private MainViewModel? _vm;

    public DisplaysPage()
    {
        InitializeComponent();
        Arrangement.PcName = Environment.MachineName;
        Arrangement.PropertyChanged += (_, e) =>
        {
            if (e.Property == ScreenArrangement.MacSideProperty) Select(Arrangement.MacSide);
        };
        DataContextChanged += (_, _) => Attach(DataContext as MainViewModel);
        Attach(DataContext as MainViewModel);
    }

    private void Attach(MainViewModel? vm)
    {
        if (ReferenceEquals(vm, _vm)) return;
        if (_vm is not null) _vm.PropertyChanged -= OnViewModelChanged;
        _vm = vm;
        if (_vm is not null) _vm.PropertyChanged += OnViewModelChanged;
        Refresh();
    }

    private void OnViewModelChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(MainViewModel.SelectedMacSide) or nameof(MainViewModel.PeerName)) Refresh();
    }

    private void Select(MacSide side)
    {
        if (_vm is null || _vm.SelectedMacSide.Value == side) return;
        _vm.SelectedMacSide = _vm.MacSides.First(o => o.Value == side);
    }

    private void Refresh()
    {
        var current = _vm?.SelectedMacSide.Value ?? MacSide.Left;
        Arrangement.MacSide = current;
        Arrangement.MacName = string.IsNullOrWhiteSpace(_vm?.PeerName) ? L10n.T("Your Mac", pl: "Twój Mac") : _vm!.PeerName;
        SideTitle.Text = current switch
        {
            MacSide.Left => L10n.T("The Mac is to the left of this screen", pl: "Mac stoi po lewej od tego ekranu"),
            MacSide.Right => L10n.T("The Mac is to the right of this screen", pl: "Mac stoi po prawej od tego ekranu"),
            MacSide.Top => L10n.T("The Mac is above this screen", pl: "Mac stoi nad tym ekranem"),
            _ => L10n.T("The Mac is below this screen", pl: "Mac stoi pod tym ekranem"),
        };
    }
}
