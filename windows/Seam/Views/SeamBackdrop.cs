using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;

namespace Seam.Views;

/// <summary>
/// Tło całego okna (pasek tytułu, pasek boczny i treść). Domyślnie grafit jak na macOS: chłodne światło
/// od góry i słaba poświata akcentu. Strony funkcji przełączają je na swój kolor (<see cref="PageColor"/>),
/// z tymi samymi gradientami co tła stron na macOS (<c>*Backdrop</c> w <c>*Style.swift</c>). Bez ziarna.
/// </summary>
public sealed class SeamBackdrop : Panel
{
    public static readonly StyledProperty<PageColor> PageColorProperty =
        AvaloniaProperty.Register<SeamBackdrop, PageColor>(nameof(PageColor));

    private readonly Dictionary<PageColor, Panel> _layers = new();

    static SeamBackdrop() => PageColorProperty.Changed.AddClassHandler<SeamBackdrop>((b, _) => b.ShowLayer());

    public SeamBackdrop()
    {
        IsHitTestVisible = false;
        Children.Add(new Panel
        {
            Children =
            {
                Linear(new RelativePoint(0, 1, RelativeUnit.Relative), (Parse("#222428"), 0), (Parse("#141517"), 1)),
                Glow(Parse("#78828F"), 0.34, 0.6, -0.05, 0.72),
                Glow(Parse("#91AD8C"), 0.17, 0.55, 1.02, 0.42),
                Glow(Colors.Black, 0.4, 0, 1, 0.75),
            },
        });
        var blue = PageTheme.Blue;
        AddLayer(PageColor.Blue,
            Linear(new RelativePoint(1, 0.9, RelativeUnit.Relative), (blue.Top, 0), (blue.Edge, 1)),
            Glow(blue.Center, 0.85, 0.42, 0.42, 0.55),
            Glow(blue.Glow, 0.35, 0.6, 1.05, 0.4),
            Glow(Colors.Black, 0.35, 0, 1, 0.7));
        var magenta = PageTheme.Magenta;
        AddLayer(PageColor.Magenta,
            Linear(new RelativePoint(0, 1, RelativeUnit.Relative), (magenta.Top, 0), (magenta.Edge, 1)),
            Glow(magenta.Center, 1, 0.38, 0.48, 0.55),
            Glow(magenta.Glow, 0.9, 0.92, 1, 0.5, 0.25));
        var violet = PageTheme.Violet;
        AddLayer(PageColor.Violet,
            Linear(new RelativePoint(0, 1, RelativeUnit.Relative), (violet.Top, 0), (violet.Edge, 1)),
            Glow(violet.Center, 1, 0.58, 0.28, 0.55),
            Glow(violet.Glow, 0.7, 0.75, 1.05, 0.55, 0.2));
        var amber = PageTheme.Amber;
        AddLayer(PageColor.Amber,
            Linear(new RelativePoint(0, 1, RelativeUnit.Relative), (amber.Top, 0), (amber.Edge, 1)),
            Glow(amber.Center, 1, 0.36, 0.42, 0.55),
            Glow(amber.Glow, 0.6, 0.95, 1.05, 0.5, 0.15));
        var green = PageTheme.Green;
        AddLayer(PageColor.Green,
            Linear(new RelativePoint(0, 1, RelativeUnit.Relative), (green.Top, 0), (green.Edge, 1)),
            Glow(green.Center, 1, 0.58, 0.2, 0.65, 0.5),
            Glow(green.Glow, 0.45, 0.55, 1.08, 0.5, 0.1));
        var teal = PageTheme.Teal;
        AddLayer(PageColor.Teal,
            Linear(new RelativePoint(0, 1, RelativeUnit.Relative), (teal.Top, 0), (teal.Edge, 1)),
            Glow(teal.Center, 1, 0.5, 0.45, 0.6),
            Glow(teal.Glow, 0.45, 0.9, 1.05, 0.5, 0.15));
    }

    /// <summary>Kolor tła; <see cref="PageColor.Graphite"/> zostawia sam grafit.</summary>
    public PageColor PageColor
    {
        get => GetValue(PageColorProperty);
        set => SetValue(PageColorProperty, value);
    }

    private void AddLayer(PageColor color, params Control[] children)
    {
        var layer = new Panel { IsVisible = false };
        layer.Children.AddRange(children);
        _layers[color] = layer;
        Children.Add(layer);
    }

    private void ShowLayer()
    {
        foreach (var (color, layer) in _layers) layer.IsVisible = color == PageColor;
    }

    private static Color Parse(string hex) => Color.Parse(hex);

    private static Border Linear(RelativePoint end, params (Color Color, double Offset)[] stops)
    {
        var brush = new LinearGradientBrush { StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative), EndPoint = end };
        foreach (var (color, offset) in stops) brush.GradientStops.Add(new GradientStop(color, offset));
        return new Border { Background = brush };
    }

    /// <summary>
    /// Eliptyczna poświata (EllipticalGradient na macOS). <paramref name="middle"/> to krycie w połowie promienia,
    /// gdy gradient na macOS ma trzy przystanki; bez niego krycie spada liniowo do zera.
    /// </summary>
    private static Border Glow(Color color, double opacity, double x, double y, double radius, double? middle = null)
    {
        var brush = new RadialGradientBrush
        {
            Center = new RelativePoint(x, y, RelativeUnit.Relative),
            GradientOrigin = new RelativePoint(x, y, RelativeUnit.Relative),
            RadiusX = new RelativeScalar(radius, RelativeUnit.Relative),
            RadiusY = new RelativeScalar(radius, RelativeUnit.Relative),
        };
        // Fade to the same color at zero alpha, not to transparent black, so the edge does not darken.
        brush.GradientStops.Add(new GradientStop(Alpha(color, opacity), 0));
        if (middle is { } mid) brush.GradientStops.Add(new GradientStop(Alpha(color, mid), 0.5));
        brush.GradientStops.Add(new GradientStop(Alpha(color, 0), 1));
        return new Border { Background = brush };
    }

    private static Color Alpha(Color color, double opacity) =>
        Color.FromArgb((byte)Math.Round(opacity * 255), color.R, color.G, color.B);
}
