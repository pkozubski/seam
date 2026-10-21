using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;

namespace Seam.Views;

/// <summary>
/// Tło całego okna (pasek tytułu, pasek boczny i treść). Domyślnie grafit jak na macOS: chłodne światło
/// od góry i słaba poświata akcentu. Zakładka Okna przełącza je na zieleń z tokenów projektu
/// (tokens.css): żółtozielona poświata nad środkiem i zielona z lewej. Bez ziarna.
/// </summary>
public sealed class SeamBackdrop : Panel
{
    public static readonly StyledProperty<bool> IsGreenProperty =
        AvaloniaProperty.Register<SeamBackdrop, bool>(nameof(IsGreen));

    private readonly Panel _green;

    static SeamBackdrop() => IsGreenProperty.Changed.AddClassHandler<SeamBackdrop>((b, _) => b._green.IsVisible = b.IsGreen);

    public SeamBackdrop()
    {
        IsHitTestVisible = false;
        Children.Add(new Panel
        {
            Children =
            {
                Linear(new RelativePoint(0, 1, RelativeUnit.Relative), ("#222428", 0), ("#141517", 1)),
                Glow(Color.Parse("#78828F"), 0.34, 0.6, -0.05, 0.72),
                Glow(Color.Parse("#91AD8C"), 0.17, 0.55, 1.02, 0.42),
                Glow(Colors.Black, 0.4, 0, 1, 0.75),
            },
        });
        _green = new Panel
        {
            IsVisible = false,
            Children =
            {
                Linear(new RelativePoint(1, 0.85, RelativeUnit.Relative), ("#064B1C", 0), ("#022F15", 0.78)),
                Glow(Color.Parse("#558B04"), 0.9, 0.54, -0.08, 0.61),
                Glow(Color.Parse("#006F24"), 0.8, 0, 0.6, 0.55),
            },
        };
        Children.Add(_green);
    }

    /// <summary>Zielone tło zakładki Okna zamiast grafitu.</summary>
    public bool IsGreen
    {
        get => GetValue(IsGreenProperty);
        set => SetValue(IsGreenProperty, value);
    }

    private static Border Linear(RelativePoint end, params (string Color, double Offset)[] stops)
    {
        var brush = new LinearGradientBrush { StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative), EndPoint = end };
        foreach (var (color, offset) in stops) brush.GradientStops.Add(new GradientStop(Color.Parse(color), offset));
        return new Border { Background = brush };
    }

    private static Border Glow(Color color, double opacity, double x, double y, double radius) => new()
    {
        Background = new RadialGradientBrush
        {
            Center = new RelativePoint(x, y, RelativeUnit.Relative),
            GradientOrigin = new RelativePoint(x, y, RelativeUnit.Relative),
            RadiusX = new RelativeScalar(radius, RelativeUnit.Relative),
            RadiusY = new RelativeScalar(radius, RelativeUnit.Relative),
            // Fade to the same color at zero alpha, not to transparent black, so the edge does not darken.
            GradientStops =
            {
                new GradientStop(Color.FromArgb((byte)(opacity * 255), color.R, color.G, color.B), 0),
                new GradientStop(Color.FromArgb(0, color.R, color.G, color.B), 1),
            },
        },
    };
}
