using System.ComponentModel;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;
using Seam.ViewModels;
using Seam.Views.Pages;
using Seam.Localization;
using Seam.Net;
using FluentAvalonia.UI.Controls;
using FluentAvalonia.UI.Windowing;

namespace Seam.Views;

public partial class MainWindow : AppWindow
{
    /// <summary>Kolejność stron w pasku bocznym – używana też przez tryb <c>--screenshot</c>.</summary>
    public static readonly IReadOnlyList<string> PageTags = new[] { "connection", "displays", "control", "audio", "clipboard", "windows", "settings", "log" };

    private readonly Dictionary<string, Control> _pages = new();
    // Stan, z którego zbudowano ikonę każdej pozycji – przebudowujemy tylko pozycje, które się zmieniły.
    private readonly Dictionary<NavigationViewItem, (double Scaling, Color? Badge)> _navIconState = new();
    private string _currentTag = PageTags[0];
    private MainViewModel? _vm;

    public MainWindow()
    {
        InitializeComponent();
        L10n.Apply(this);
        foreach (var item in NavItems)
        {
            if (item.Content is string label) item.Content = L10n.TranslateText(label);
        }
        foreach (var header in Nav.MenuItems.OfType<NavigationViewItemHeader>())
        {
            if (header.Content is string label) header.Content = L10n.TranslateText(label);
        }
        VersionText.Text = $"seam · {Updater.CurrentVersion}";
        TitleBar.ExtendsContentIntoTitleBar = true;
        TitleBar.TitleBarHitTestType = TitleBarHitTestType.Complex;

        TransparencyLevelHint = new[] { WindowTransparencyLevel.Mica, WindowTransparencyLevel.None };
        Opened += (_, _) => ApplyBackdrop();
        // ikony paska bocznego są renderowane w pikselach ekranu, więc po zmianie skali od nowa
        ScalingChanged += (_, _) => UpdateNavIcons();
        PropertyChanged += (_, e) =>
        {
            if (e.Property == ActualTransparencyLevelProperty) ApplyBackdrop();
            else if (e.Property == IsVisibleProperty || e.Property == WindowStateProperty) ReportVisibility();
        };
        DataContextChanged += (_, _) =>
        {
            if (_vm is not null) _vm.PropertyChanged -= ViewModelChanged;
            _vm = DataContext as MainViewModel;
            if (_vm is not null) _vm.PropertyChanged += ViewModelChanged;
            _vm?.SetVisiblePage(_currentTag);
            ReportVisibility();
            UpdateNavIcons();
        };

        Closing += (_, e) =>
        {
            // zamknięcie okna = schowanie do zasobnika; wyjście przez menu ikony
            if (App.Current is App app && !app.IsExiting)
            {
                e.Cancel = true;
                Hide();
            }
        };

        NavigateTo(PageTags[0]);
        UpdateNavIcons();
    }

    /// <summary>Wybiera stronę w pasku bocznym po jej znaczniku.</summary>
    public void NavigateTo(string tag)
    {
        var item = NavItems.FirstOrDefault(i => (string?)i.Tag == tag);
        if (item is null) return;
        if (!ReferenceEquals(Nav.SelectedItem, item)) Nav.SelectedItem = item;
        ShowPage(tag);
    }

    private IEnumerable<NavigationViewItem> NavItems =>
        Nav.MenuItems.OfType<NavigationViewItem>().Concat(Nav.FooterMenuItems.OfType<NavigationViewItem>());

    private void ViewModelChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(MainViewModel.StatusBrush) or nameof(MainViewModel.StatusText)) UpdateNavIcons();
    }

    /// <summary>Statystyki odświeżamy tylko, gdy okno jest na ekranie (nie w zasobniku i nie zminimalizowane).</summary>
    private void ReportVisibility() => _vm?.SetWindowVisible(IsVisible && WindowState != WindowState.Minimized);

    /// <summary>
    /// Ikony paska bocznego bez płytek; wybraną sekcję wyróżnia szklana pigułka NavigationView.
    /// Połączenie niesie kropkę stanu: to cały status, zwinięty do paska bocznego.
    /// Nowe źródło ikony dostaje tylko pozycja, której wygląd się zmienił (skala, kolor kropki),
    /// bo każde przypisanie IconSource przebudowuje szablon pozycji.
    /// </summary>
    private void UpdateNavIcons()
    {
        var status = (_vm?.StatusBrush as ISolidColorBrush)?.Color;
        foreach (var item in NavItems)
        {
            if (item.Tag is string tag)
            {
                var state = (Scaling: RenderScaling, Badge: tag == "connection" ? status : null);
                if (!_navIconState.TryGetValue(item, out var applied) || applied != state)
                {
                    _navIconState[item] = state;
                    item.IconSource = new ImageIconSource { Source = IconTile.RenderNav(tag, state.Scaling, state.Badge) };
                }
            }
            if (item.Tag is "connection" && _vm is not null && !Equals(ToolTip.GetTip(item), _vm.StatusText))
                ToolTip.SetTip(item, _vm.StatusText);
        }
    }

    private void Nav_OnSelectionChanged(object? sender, NavigationViewSelectionChangedEventArgs e)
    {
        if (e.SelectedItem is NavigationViewItem { Tag: string tag }) ShowPage(tag);
    }

    private void ShowPage(string tag)
    {
        if (!_pages.TryGetValue(tag, out var page))
        {
            page = tag switch
            {
                "connection" => new ConnectionPage(),
                "displays" => new DisplaysPage(),
                "control" => new ControlPage(),
                "audio" or "clipboard" => new ControlPage(tag),
                "windows" => new WindowsPage(),
                "settings" => new SettingsPage(),
                "log" => new LogPage(),
                _ => new ConnectionPage(),
            };
            _pages[tag] = page;
            L10n.Apply(page);
        }
        PageHost.Content = page;
        _currentTag = tag;
        _vm?.SetVisiblePage(tag);
        Backdrop.IsGreen = tag == "windows";
        PageTitle.Text = NavItems.FirstOrDefault(i => (string?)i.Tag == tag)?.Content as string;
    }

    internal Control? CurrentPage => PageHost.Content as Control;

    private void ApplyBackdrop()
    {
        // SeamBackdrop covers the window; this is only what shows before it renders.
        Background = new SolidColorBrush(Color.Parse("#141517"));
    }
}
