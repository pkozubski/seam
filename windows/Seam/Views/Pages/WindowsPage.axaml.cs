using System.ComponentModel;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Seam.Localization;
using Seam.Models;
using Seam.ViewModels;

namespace Seam.Views.Pages;

public partial class WindowsPage : UserControl
{
    private const string HelpUrl = "https://github.com/pkozubski/seam#uruchomienie-krok-po-kroku";
    private static readonly string[] Watched =
    {
        nameof(MainViewModel.SelectedMacSide), nameof(MainViewModel.IsConnected), nameof(MainViewModel.IsConnecting),
        nameof(MainViewModel.PeerName), nameof(MainViewModel.WindowSharingEnabled), nameof(MainViewModel.WindowSharingSwitch),
    };

    internal Control FullGuide => GuideContent;
    private MainViewModel? _vm;
    private readonly Border _macTile = ScreenTile("Mac");
    private readonly Border _pcTile = ScreenTile("PC");

    public WindowsPage()
    {
        InitializeComponent();
        L10n.Apply(this);
        LayoutTiles.RowSpacing = LayoutTiles.ColumnSpacing = 4;
        LayoutTiles.Children.Add(_macTile);
        LayoutTiles.Children.Add(_pcTile);
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
        var side = _vm?.SelectedMacSide.Value ?? MacSide.Left;
        var mac = string.IsNullOrWhiteSpace(_vm?.PeerName) ? "Mac" : _vm!.PeerName;
        var pc = Environment.MachineName;

        MasterLabel.Text = _vm?.WindowSharingSwitch ?? false
            ? L10n.T("Window moving is on", pl: "Przenoszenie okien włączone")
            : L10n.T("Window moving is off", pl: "Przenoszenie okien wyłączone");

        MacName.Text = mac;
        PcName.Text = pc;
        (ConnectionTitle.Text, ConnectionSubtitle.Text) = (_vm?.IsConnected, _vm?.IsConnecting) switch
        {
            (true, _) => (L10n.T("Your devices are connected", pl: "Urządzenia są połączone"),
                          L10n.T($"{mac} and {pc} are ready.", pl: $"{mac} i {pc} są gotowe.")),
            (_, true) => (L10n.T("Connecting to the Mac…", pl: "Łączenie z Makiem…"),
                          L10n.T("Both computers will be ready in a moment.", pl: "Za chwilę oba komputery będą gotowe.")),
            _ => (L10n.T("Your devices are not connected", pl: "Urządzenia nie są połączone"),
                  L10n.T("Start Seam on the Mac or check the address in connection settings.",
                         pl: "Uruchom Seam na Macu albo sprawdź adres w ustawieniach połączenia.")),
        };

        ArrangementLabel.Text = side switch
        {
            MacSide.Left => L10n.T("The Mac is to the left of this screen", pl: "Mac stoi po lewej od tego ekranu"),
            MacSide.Right => L10n.T("The Mac is to the right of this screen", pl: "Mac stoi po prawej od tego ekranu"),
            MacSide.Top => L10n.T("The Mac is above this screen", pl: "Mac stoi nad tym ekranem"),
            _ => L10n.T("The Mac is below this screen", pl: "Mac stoi pod tym ekranem"),
        };
        BuildLayoutTiles(side);
    }

    private static Border ScreenTile(string label)
    {
        var tile = new Border { Child = new TextBlock { Text = label } };
        tile.Classes.Add("screenTile");
        return tile;
    }

    /// <summary>
    /// Dwa kafle ekranów (screen-layout.svg) ustawione tak jak w zakładce Ekrany. Kafle powstają raz;
    /// tu zmienia się tylko ich miejsce w siatce, bez dodawania kontrolek w trakcie odpinania strony.
    /// </summary>
    private void BuildLayoutTiles(MacSide side)
    {
        var vertical = side is MacSide.Top or MacSide.Bottom;
        var macFirst = side is MacSide.Left or MacSide.Top;
        LayoutTiles.RowDefinitions = vertical ? new RowDefinitions("Auto,Auto") : new RowDefinitions();
        LayoutTiles.ColumnDefinitions = vertical ? new ColumnDefinitions() : new ColumnDefinitions("Auto,Auto");
        foreach (var (tile, first) in new[] { (_macTile, macFirst), (_pcTile, !macFirst) })
        {
            Grid.SetRow(tile, vertical && !first ? 1 : 0);
            Grid.SetColumn(tile, !vertical && !first ? 1 : 0);
        }
    }

    private void ShowHow(object? sender, RoutedEventArgs e) => HowSection.BringIntoView();

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
