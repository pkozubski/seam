using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;
using BorderlessMouse.Views.Pages;
using BorderlessMouse.Localization;
using FluentAvalonia.UI.Controls;
using FluentAvalonia.UI.Windowing;

namespace BorderlessMouse.Views;

public partial class MainWindow : AppWindow
{
    /// <summary>Kolejność stron w pasku bocznym – używana też przez tryb <c>--screenshot</c>.</summary>
    public static readonly IReadOnlyList<string> PageTags = new[] { "connection", "control", "audio", "clipboard", "windows", "settings", "log" };

    private ConnectionStatusWindow? _statusWindow;

    private readonly Dictionary<string, Control> _pages = new();

    public MainWindow()
    {
        InitializeComponent();
        L10n.Apply(this);
        foreach (var item in Nav.MenuItems.OfType<NavigationViewItem>()
                     .Concat(Nav.FooterMenuItems.OfType<NavigationViewItem>()))
        {
            if (item.Content is string label) item.Content = L10n.TranslateText(label);
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
        var item = Nav.MenuItems.OfType<NavigationViewItem>()
            .Concat(Nav.FooterMenuItems.OfType<NavigationViewItem>())
            .FirstOrDefault(i => (string?)i.Tag == tag);
        if (item is null) return;
        if (!ReferenceEquals(Nav.SelectedItem, item)) Nav.SelectedItem = item;
        ShowPage(tag);
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
                "control" => new ControlPage(),
                "audio" or "clipboard" or "windows" => new ControlPage(tag),
                "settings" => new SettingsPage(),
                "log" => new LogPage(),
                _ => new ConnectionPage(),
            };
            _pages[tag] = page;
            L10n.Apply(page);
        }
        PageHost.Content = page;
    }

    internal ConnectionStatusWindow? StatusWindow => _statusWindow;

    private void SyncStatusWindow()
    {
        if (_statusWindow is null) return;
        if (!IsVisible || WindowState == WindowState.Minimized)
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
        Background = new SolidColorBrush(Color.Parse("#1D1F21"));
    }
}
