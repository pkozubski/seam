using Avalonia;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Media.Imaging;
using Avalonia.Platform;
using Seam.ViewModels;

namespace Seam.Views.Pages;

public partial class ConnectionPage : UserControl
{
    private static readonly Uri HeroUri = new("avares://Seam/Assets/seam-windows.png");
    /// <summary>Źródło seam-windows.png ma 1254×1254 px.</summary>
    private const int HeroSourceWidth = 1254;
    /// <summary>
    /// W domyślnym oknie ilustracja ma ~500 DIP, więc 1024 px wystarcza przy 200 % i w zrzutach --screenshot (2×).
    /// Pełne źródło dekodujemy dopiero, gdy na ekranie potrzeba więcej pikseli (większe okno lub skalowanie).
    /// </summary>
    private const int HeroInitialWidth = 1024;
    private static Bitmap? _hero;
    private static int _heroWidth;
    private TopLevel? _topLevel;

    private void OpenWindows_OnClick(object? sender, RoutedEventArgs e)
    {
        if (TopLevel.GetTopLevel(this) is MainWindow window) window.NavigateTo("windows");
    }

    public void ShowDetails()
    {
        ConnectionDetails.IsExpanded = true;
        ConnectionDetails.UpdateLayout();
        ConnectionDetails.BringIntoView();
    }

    public ConnectionPage()
    {
        InitializeComponent();
        Localization.L10n.Apply(this);
        HeroImage.Source = LoadHero(HeroInitialWidth);
        HeroImage.SizeChanged += (_, _) => EnsureHeroResolution();
        // Adres, ping i kursor w szczegółach odświeża licznik statystyk tylko, gdy szczegóły są rozwinięte.
        ConnectionDetails.PropertyChanged += (_, e) =>
        {
            if (e.Property == Expander.IsExpandedProperty) ReportDetailsVisibility();
        };
        DataContextChanged += (_, _) => ReportDetailsVisibility();
    }

    protected override void OnAttachedToVisualTree(VisualTreeAttachmentEventArgs e)
    {
        base.OnAttachedToVisualTree(e);
        _topLevel = TopLevel.GetTopLevel(this);
        if (_topLevel is not null) _topLevel.ScalingChanged += OnScalingChanged;
        EnsureHeroResolution();
    }

    protected override void OnDetachedFromVisualTree(VisualTreeAttachmentEventArgs e)
    {
        if (_topLevel is not null) _topLevel.ScalingChanged -= OnScalingChanged;
        _topLevel = null;
        base.OnDetachedFromVisualTree(e);
    }

    private void OnScalingChanged(object? sender, EventArgs e) => EnsureHeroResolution();

    private void ReportDetailsVisibility() =>
        (DataContext as MainViewModel)?.SetConnectionDetailsVisible(ConnectionDetails.IsExpanded);

    private void EnsureHeroResolution()
    {
        if (_heroWidth >= HeroSourceWidth || _topLevel is null) return;
        if (HeroImage.Bounds.Width * _topLevel.RenderScaling > _heroWidth) HeroImage.Source = LoadHero(HeroSourceWidth);
    }

    /// <summary>Kopia wspólna dla stron; rośnie tylko raz, do pełnego źródła (stara zostaje dla GC – może ją jeszcze rysować kompozytor).</summary>
    private static Bitmap LoadHero(int width)
    {
        if (_hero is not null && _heroWidth >= width) return _hero;
        using var stream = AssetLoader.Open(HeroUri);
        _hero = width >= HeroSourceWidth ? new Bitmap(stream) : Bitmap.DecodeToWidth(stream, width, BitmapInterpolationMode.HighQuality);
        _heroWidth = Math.Min(width, HeroSourceWidth);
        return _hero;
    }
}
