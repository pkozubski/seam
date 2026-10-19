using System.ComponentModel;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;
using Seam.ViewModels;
using Seam.Views.Pages;
using Seam.Localization;
using FluentAvalonia.UI.Controls;
using FluentAvalonia.UI.Windowing;

namespace Seam.Views;

public partial class MainWindow : AppWindow
{
    /// <summary>Kolejność stron w pasku bocznym – używana też przez tryb <c>--screenshot</c>.</summary>
    public static readonly IReadOnlyList<string> PageTags = new[] { "connection", "displays", "control", "audio", "clipboard", "windows", "settings", "log" };

    private readonly Dictionary<string, Control> _pages = new();
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
        TitleBar.ExtendsContentIntoTitleBar = true;
        TitleBar.TitleBarHitTestType = TitleBarHitTestType.Complex;

        TransparencyLevelHint = new[] { WindowTransparencyLevel.Mica, WindowTransparencyLevel.None };
        Opened += (_, _) => ApplyBackdrop();
        PropertyChanged += (_, e) =>
        {
            if (e.Property == ActualTransparencyLevelProperty) ApplyBackdrop();
        };
        DataContextChanged += (_, _) =>
        {
            if (_vm is not null) _vm.PropertyChanged -= ViewModelChanged;
            _vm = DataContext as MainViewModel;
            if (_vm is not null) _vm.PropertyChanged += ViewModelChanged;
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
    }

    /// <summary>Wybiera stronę w pasku bocznym po jej znaczniku.</summary>
    public void NavigateTo(string tag)
    {
        var item = NavItems.FirstOrDefault(i => (string?)i.Tag == tag);
        if (item is null) return;
        if (!ReferenceEquals(Nav.SelectedItem, item)) Nav.SelectedItem = item;
        ShowPage(tag);
        UpdateNavIcons();
    }

    private IEnumerable<NavigationViewItem> NavItems =>
        Nav.MenuItems.OfType<NavigationViewItem>().Concat(Nav.FooterMenuItems.OfType<NavigationViewItem>());

    private void ViewModelChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(MainViewModel.StatusBrush) or nameof(MainViewModel.StatusText)) UpdateNavIcons();
    }

    /// <summary>
    /// Ikony paska bocznego bez płytek; wybraną sekcję wyróżnia zielony kafel NavigationView.
    /// Połączenie niesie kropkę stanu: to cały status, zwinięty do paska bocznego.
    /// </summary>
    private void UpdateNavIcons()
    {
        var status = (_vm?.StatusBrush as ISolidColorBrush)?.Color;
        foreach (var item in NavItems)
        {
            if (item.Tag is string tag)
                item.IconSource = new ImageIconSource { Source = IconTile.RenderNav(tag, ReferenceEquals(item, Nav.SelectedItem), tag == "connection" ? status : null) };
            if (item.Tag is "connection" && _vm is not null) ToolTip.SetTip(item, _vm.StatusText);
        }
    }

    private void Nav_OnSelectionChanged(object? sender, NavigationViewSelectionChangedEventArgs e)
    {
        if (e.SelectedItem is NavigationViewItem { Tag: string tag }) ShowPage(tag);
        UpdateNavIcons();
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
