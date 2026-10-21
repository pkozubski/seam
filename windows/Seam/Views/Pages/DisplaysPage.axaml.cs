using System.ComponentModel;
using Avalonia.Automation;
using Avalonia.Controls;
using Avalonia.Layout;
using Seam.Localization;
using Seam.Models;
using Seam.ViewModels;

namespace Seam.Views.Pages;

/// <summary>
/// Układ ekranów: ten monitor na środku, Mac w jednym z czterech miejsc obok.
/// Kliknięcie miejsca ustawia <see cref="MainViewModel.SelectedMacSide"/>.
/// </summary>
public partial class DisplaysPage : UserControl
{
    private MainViewModel? _vm;

    public DisplaysPage()
    {
        InitializeComponent();
        ThisPcName.Text = Environment.MachineName;
        foreach (var (slot, side) in Slots)
            slot.Click += (_, _) => Select(side);
        DataContextChanged += (_, _) => Attach(DataContext as MainViewModel);
        Attach(DataContext as MainViewModel);
    }

    private IEnumerable<(Button Slot, MacSide Side)> Slots => new[]
    {
        (SlotLeft, MacSide.Left), (SlotRight, MacSide.Right), (SlotTop, MacSide.Top), (SlotBottom, MacSide.Bottom),
    };

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
        if (_vm is null) return;
        _vm.SelectedMacSide = _vm.MacSides.First(o => o.Value == side);
    }

    private void Refresh()
    {
        var current = _vm?.SelectedMacSide.Value ?? MacSide.Left;
        var macName = string.IsNullOrWhiteSpace(_vm?.PeerName) ? L10n.T("Twój Mac", "Your Mac") : _vm!.PeerName;
        foreach (var (slot, side) in Slots)
        {
            var selected = side == current;
            slot.Classes.Set("selected", selected);
            slot.Content = selected
                ? new StackPanel
                {
                    Spacing = 4,
                    HorizontalAlignment = HorizontalAlignment.Center,
                    VerticalAlignment = VerticalAlignment.Center,
                    Children =
                    {
                        new TextBlock { Text = macName, FontSize = 14, FontWeight = Avalonia.Media.FontWeight.SemiBold, HorizontalAlignment = HorizontalAlignment.Center, TextTrimming = Avalonia.Media.TextTrimming.CharacterEllipsis },
                        new TextBlock { Text = "Mac", FontSize = 11, Opacity = 0.75, HorizontalAlignment = HorizontalAlignment.Center },
                    },
                }
                : new TextBlock { Text = L10n.T("Mac tutaj", "Mac here"), FontSize = 12, Opacity = 0.6 };
            ToolTip.SetTip(slot, SideLabel(side));
            AutomationProperties.SetName(slot, SideLabel(side));
        }
        SideTitle.Text = SideLabel(current);
    }

    private static string SideLabel(MacSide side) => side switch
    {
        MacSide.Left => L10n.T("Mac stoi po lewej od tego ekranu", "The Mac is to the left of this screen"),
        MacSide.Right => L10n.T("Mac stoi po prawej od tego ekranu", "The Mac is to the right of this screen"),
        MacSide.Top => L10n.T("Mac stoi nad tym ekranem", "The Mac is above this screen"),
        _ => L10n.T("Mac stoi pod tym ekranem", "The Mac is below this screen"),
    };
}
