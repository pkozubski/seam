using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;
using Seam.Views.Pages;
using Seam.Localization;
using FluentAvalonia.UI.Controls;
using FluentAvalonia.UI.Windowing;

namespace Seam.Views;

public partial class MainWindow : AppWindow
{
    /// <summary>Kolejność stron w pasku bocznym – używana też przez tryb <c>--screenshot</c>.</summary>
    public static readonly IReadOnlyList<string> PageTags = new[] { "connection", "displays", "control", "audio", "clipboard", "windows", "settings", "log" };

    private ConnectionStatusWindow? _statusWindow;
    private string _activeTag = "connection";

    private readonly Dictionary<string, Control> _pages = new();

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

        // Keep the native title bar; the attached status uses its own transparent surface.
        TransparencyLevelHint = new[] { WindowTransparencyLevel.Mica, WindowTransparencyLevel.None };
        Opened += (_, _) =>
        {
            ApplyBackdrop();
            if (_statusWindow is null)
            {
                _statusWindow = new ConnectionStatusWindow { DataContext = DataContext };
                _statusWindow.DetailsRequested += () =>
                {
                    NavigateTo("connection");
                    if (PageHost.Content is ConnectionPage page) page.ShowDetails();
                    Activate();
                };
            }
            SyncStatusWindow();
        };
        PositionChanged += (_, _) => SyncStatusWindow();
        Closed += (_, _) => { _statusWindow?.Close(); _statusWindow = null; };
        PropertyChanged += (_, e) =>
        {
            if (e.Property == ActualTransparencyLevelProperty) ApplyBackdrop();
            if (e.Property == BoundsProperty || e.Property == WindowStateProperty || e.Property == IsVisibleProperty)
                SyncStatusWindow();
            if (e.Property == DataContextProperty && _statusWindow is not null) _statusWindow.DataContext = DataContext;
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

    /// <summary>Ikony paska bocznego na płytkach jak na macOS; wybrana sekcja ma płytkę w kolorze akcentu.</summary>
    private void UpdateNavIcons()
    {
        foreach (var item in NavItems)
        {
            if (item.Tag is string tag)
                item.IconSource = new ImageIconSource { Source = IconTile.Render($"icon-{tag}", ReferenceEquals(item, Nav.SelectedItem)) };
        }
    }

    private void Nav_OnSelectionChanged(object? sender, NavigationViewSelectionChangedEventArgs e)
    {
        if (e.SelectedItem is NavigationViewItem { Tag: string tag }) ShowPage(tag);
        UpdateNavIcons();
    }

    private void ShowPage(string tag)
    {
        _activeTag = tag;
        Nav.PaneDisplayMode = tag == "windows" ? NavigationViewPaneDisplayMode.LeftCompact : NavigationViewPaneDisplayMode.Left;
        Nav.IsPaneOpen = tag != "windows";
        foreach (var header in Nav.MenuItems.OfType<NavigationViewItemHeader>()) header.IsVisible = tag != "windows";
        if (Nav.PaneFooter is Control footer) footer.IsVisible = tag != "windows";
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
        SyncStatusWindow();
    }

    internal ConnectionStatusWindow? StatusWindow => _statusWindow;
    internal Control? CurrentPage => PageHost.Content as Control;

    private void SyncStatusWindow()
    {
        if (_statusWindow is null) return;
        if (!IsVisible || WindowState == WindowState.Minimized || _activeTag == "windows")
        {
            _statusWindow.Hide();
            return;
        }
        // Avalonia macOS previews use point-based screen coordinates; Windows uses pixels.
        var scale = OperatingSystem.IsMacOS() ? 1 : RenderScaling;
        var bottom = Screens.ScreenFromWindow(this)?.WorkingArea.Bottom ?? int.MaxValue;
        var x = Position.X + (int)((Bounds.Width / 2 - 63) * scale);
        var y = Math.Min(Position.Y + (int)((Bounds.Height - 78) * scale), bottom - (int)(126 * scale));
        _statusWindow.Position = new PixelPoint(x, y);
        if (!_statusWindow.IsVisible) _statusWindow.Show(this);
    }

    private void ApplyBackdrop()
    {
        // SeamBackdrop covers the window; this is only what shows before it renders.
        Background = new SolidColorBrush(Color.Parse("#141517"));
    }
}
