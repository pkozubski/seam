using Avalonia;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Layout;
using Avalonia.Media;
using FluentAvalonia.UI.Windowing;
using Seam.Localization;

namespace Seam.Views;

/// <summary>
/// Osobne okno Ustawień (jak na macOS). Strony: licencja (karta na górze), kafelki Ogólne, Język, Aktualizacje,
/// Zaawansowane, oraz O programie; Dziennik otwiera się w oknie głównym. Panele daje <see cref="Pages.SettingsPage"/>.
/// </summary>
public partial class SettingsWindow : AppWindow
{
    private sealed record Pane(string Tag, string Title, string Glyph, Color Tint, string[] Keywords);

    private static readonly Pane[] PaneList =
    [
        new("general", L10n.T("General", pl: "Ogólne"), "", Color.Parse("#8C99B3"), ["name", "nazwa", "startup", "autostart", "tray", "zasobnik"]),
        new("language", L10n.T("Language", pl: "Język"), "", Color.Parse("#33B8B3"), ["language", "język", "english", "polski"]),
        new("updates", L10n.T("Updates", pl: "Aktualizacje"), "", Color.Parse("#408CFF"), ["update", "aktualizacja", "version", "wersja"]),
        new("advanced", L10n.T("Advanced", pl: "Zaawansowane"), "", Color.Parse("#9E73F2"), ["port", "tcp", "udp", "network", "sieć", "firewall"]),
        new("license", L10n.T("License", pl: "Licencja"), "", Color.Parse("#F59E5C"), ["pro", "license", "licencja", "key", "klucz", "trial", "buy", "kup"]),
        new("about", L10n.T("About", pl: "O programie"), "", Color.Parse("#737F9E"), ["about", "changelog", "zmiany", "privacy", "prywatność", "help", "pomoc"]),
    ];

    private readonly Dictionary<string, Button> _buttons = new();
    private string _pane = "general";

    public SettingsWindow()
    {
        InitializeComponent();
        TitleBar.ExtendsContentIntoTitleBar = true;
        _buttons["license"] = LicenseButton;
        foreach (var pane in PaneList.Where(p => p.Tag is "general" or "language" or "updates" or "advanced"))
            Tiles.Children.Add(_buttons[pane.Tag] = Tile(pane));
        Cards.Children.Add(_buttons["about"] = Row(PaneList.First(p => p.Tag == "about")));
        Search.TextChanged += (_, _) => Filter();
        L10n.Apply(this);
        Select("general");
    }

    /// <summary>Pokazuje stronę i zaznacza ją w pasku bocznym.</summary>
    public void Select(string tag)
    {
        _pane = PaneList.Any(p => p.Tag == tag) ? tag : "general";
        Panes.Show(_pane);
        PaneTitle.Text = PaneList.First(p => p.Tag == _pane).Title;
        foreach (var (key, button) in _buttons) button.Classes.Set("selected", key == _pane);
    }

    private void SelectPane(object? sender, RoutedEventArgs e)
    {
        if (sender is Control { Tag: string tag }) Select(tag);
    }

    private void OpenDiagnostics(object? sender, RoutedEventArgs e)
    {
        if (Owner is MainWindow main)
        {
            main.NavigateTo("log");
            main.Activate();
        }
    }

    /// <summary>Wpisany tekst zamienia kafelki na listę pasujących stron.</summary>
    private void Filter()
    {
        var query = Search.Text?.Trim() ?? "";
        Cards.IsVisible = query.Length == 0;
        Results.Children.Clear();
        if (query.Length == 0) return;
        var matches = PaneList.Where(p => p.Title.Contains(query, StringComparison.CurrentCultureIgnoreCase)
                                          || p.Keywords.Any(k => k.Contains(query, StringComparison.CurrentCultureIgnoreCase))).ToList();
        foreach (var pane in matches)
        {
            var row = Row(pane);
            row.Classes.Set("selected", pane.Tag == _pane);
            Results.Children.Add(row);
        }
        if (matches.Count == 0)
            Results.Children.Add(new TextBlock { Text = L10n.T("No results", pl: "Brak wyników"), Opacity = 0.6, Margin = new Thickness(8, 4) });
    }

    private Button Tile(Pane pane)
    {
        var button = new Button
        {
            Tag = pane.Tag,
            Content = new StackPanel
            {
                Spacing = 12,
                Children = { PaneIcon(pane), new TextBlock { Text = pane.Title, FontSize = 13, FontWeight = FontWeight.Medium, TextWrapping = TextWrapping.NoWrap } },
            },
        };
        button.Classes.Add("side");
        button.Click += SelectPane;
        return button;
    }

    private Button Row(Pane pane)
    {
        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,*"), ColumnSpacing = 10 };
        grid.Children.Add(PaneIcon(pane));
        var title = new TextBlock { Text = pane.Title, VerticalAlignment = VerticalAlignment.Center };
        Grid.SetColumn(title, 1);
        grid.Children.Add(title);
        var button = new Button { Tag = pane.Tag, Content = grid };
        button.Classes.Add("row");
        button.Click += (s, e) =>
        {
            SelectPane(s, e);
            if (Results.Children.Count > 0) Filter();
        };
        return button;
    }

    private static Border PaneIcon(Pane pane)
    {
        var icon = new Border
        {
            Background = new LinearGradientBrush
            {
                StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
                EndPoint = new RelativePoint(0, 1, RelativeUnit.Relative),
                GradientStops = { new GradientStop(pane.Tint, 0), new GradientStop(Color.FromArgb(0xB3, pane.Tint.R, pane.Tint.G, pane.Tint.B), 1) },
            },
            Child = new TextBlock { Text = pane.Glyph },
            HorizontalAlignment = HorizontalAlignment.Left,
        };
        icon.Classes.Add("paneIcon");
        return icon;
    }
}
