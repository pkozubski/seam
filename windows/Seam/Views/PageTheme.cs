using Avalonia.Controls;
using Avalonia.Media;

namespace Seam.Views;

/// <summary>Kolor strony: każda strona funkcji ma własny, reszta aplikacji jest grafitowa (jak na macOS).</summary>
public enum PageColor { Graphite, Blue, Magenta, Violet, Amber, Green }

/// <summary>
/// Tokeny kolorowych stron, przepisane z macOS (<c>ConnectionStyle.swift</c>, <c>ControlStyle.swift</c>,
/// <c>AudioStyle.swift</c>, <c>ClipboardStyle.swift</c>, <c>OknaStyle.swift</c>). Tło okna rysuje
/// <see cref="SeamBackdrop"/>, a <see cref="Apply"/> podmienia zasoby kart, tekstu i przełączników strony.
/// </summary>
public sealed record PageTheme(
    Color Top, Color Edge, Color Center, Color Glow, Color Accent, Color Light, Color MutedText, Color CardBorder,
    // kula stanu połączenia: jasny refleks, środek i ciemna krawędź szkła
    Color OrbLight, Color OrbMid, Color OrbDeep, Color OrbGlow)
{
    public static readonly PageTheme Blue = new(
        Top: C("#0B1F6B"), Edge: C("#050C33"), Center: C("#1A3FD6"), Glow: C("#2FC8FF"), Accent: C("#3FB4FF"),
        Light: C("#9FE3FF"), MutedText: C("#BFD3F5"), CardBorder: C("#33A9D8FF"),
        OrbLight: C("#2FC8FF"), OrbMid: C("#1A3FD6"), OrbDeep: C("#0B1F6B"), OrbGlow: C("#2FC8FF"));

    public static readonly PageTheme Magenta = new(
        Top: C("#4A0028"), Edge: C("#33011E"), Center: C("#8C0548"), Glow: C("#E11677"), Accent: C("#E02A8A"),
        Light: C("#FF8CD1"), MutedText: C("#F2C4DA"), CardBorder: C("#38FFB8DC"),
        OrbLight: C("#FF8CD1"), OrbMid: C("#E02A8A"), OrbDeep: C("#8C0548"), OrbGlow: C("#E11677"));

    public static readonly PageTheme Violet = new(
        Top: C("#22125E"), Edge: C("#140B38"), Center: C("#3B2296"), Glow: C("#5A3ECF"), Accent: C("#866CF0"),
        Light: C("#C4B3FF"), MutedText: C("#CFC6FF"), CardBorder: C("#33C9B8FF"),
        OrbLight: C("#C4B3FF"), OrbMid: C("#866CF0"), OrbDeep: C("#22125E"), OrbGlow: C("#866CF0"));

    public static readonly PageTheme Amber = new(
        Top: C("#2A1806"), Edge: C("#120A03"), Center: C("#6E4212"), Glow: C("#C8862A"), Accent: C("#D9922C"),
        Light: C("#FFD58A"), MutedText: C("#F0D9B5"), CardBorder: C("#33FFD9A0"),
        OrbLight: C("#FFD58A"), OrbMid: C("#D9922C"), OrbDeep: C("#6E4212"), OrbGlow: C("#C8862A"));

    public static readonly PageTheme Green = new(
        Top: C("#16360C"), Edge: C("#0C1F08"), Center: C("#2F6416"), Glow: C("#8CC63F"), Accent: C("#7CC43F"),
        Light: C("#C4EC8A"), MutedText: C("#D2E6C2"), CardBorder: C("#33D8F6CA"),
        OrbLight: C("#C4EC8A"), OrbMid: C("#7CC43F"), OrbDeep: C("#2F6416"), OrbGlow: C("#8CC63F"));

    /// <summary>Tokeny koloru; grafit nie ma własnych (strony grafitowe biorą zasoby z Theme.axaml, kula jest niebieska).</summary>
    public static PageTheme? For(PageColor color) => color switch
    {
        PageColor.Blue => Blue,
        PageColor.Magenta => Magenta,
        PageColor.Violet => Violet,
        PageColor.Amber => Amber,
        PageColor.Green => Green,
        _ => null,
    };

    /// <summary>Kolor strony paska bocznego po jej znaczniku (<c>MainWindow.PageTags</c>).</summary>
    public static PageColor ForTag(string tag) => tag switch
    {
        "connection" => PageColor.Blue,
        "control" => PageColor.Magenta,
        "audio" => PageColor.Violet,
        "clipboard" => PageColor.Amber,
        "windows" => PageColor.Green,
        _ => PageColor.Graphite,
    };

    /// <summary>
    /// Szklane karty z obramowaniem w kolorze strony (TintedGlassCard na macOS), przygaszony tekst w odcieniu strony
    /// i przełączniki, suwaki oraz jasny przycisk główny w jej akcencie. Zasoby trafiają do strony, więc nie ruszają reszty okna.
    /// </summary>
    public void Apply(Control page)
    {
        var r = page.Resources;
        r["CardBackground"] = new LinearGradientBrush
        {
            StartPoint = new(0, 0, Avalonia.RelativeUnit.Relative),
            EndPoint = new(0, 1, Avalonia.RelativeUnit.Relative),
            GradientStops = { new GradientStop(Color.Parse("#17FFFFFF"), 0), new GradientStop(Color.Parse("#09FFFFFF"), 1) },
        };
        r["CardBorder"] = Brush(CardBorder);
        r["MutedText"] = Brush(MutedText);
        r["RowDivider"] = Brush(WithAlpha(CardBorder, 0.7));
        r["PillBackground"] = Brush(WithAlpha(Light, 0.16));
        r["PageAccent"] = Brush(Accent);
        r["PageLight"] = Brush(Light);
        r["ToggleSwitchFillOn"] = Brush(Accent);
        r["ToggleSwitchStrokeOn"] = Brush(Accent);
        r["ToggleSwitchFillOnPointerOver"] = Brush(Mix(Accent, Colors.White, 0.12));
        r["ToggleSwitchFillOnPressed"] = Brush(Mix(Accent, Colors.Black, 0.12));
        r["ToggleSwitchFillOff"] = Brush(WithAlpha(Light, 0.22));
        r["ToggleSwitchStrokeOff"] = Brush(WithAlpha(Light, 0.3));
        r["SliderTrackValueFill"] = Brush(Accent);
        r["SliderTrackValueFillPointerOver"] = Brush(Mix(Accent, Colors.White, 0.12));
        r["SliderTrackValueFillPressed"] = Brush(Mix(Accent, Colors.Black, 0.12));
        r["SliderThumbBackground"] = Brush(Mix(Accent, Colors.White, 0.35));
        r["SliderThumbBackgroundPointerOver"] = Brush(Mix(Accent, Colors.White, 0.5));
        r["ButtonBorderBrush"] = Brush(WithAlpha(Light, 0.26));
        r["ButtonBorderBrushPointerOver"] = Brush(WithAlpha(Light, 0.36));
        r["AccentButtonText"] = Brush(Edge);
        // Szablon FluentAvalonia dla klasy accent maluje tło z tych kluczy, nie z właściwości Background.
        r["AccentButtonBackground"] = Brush(Mix(Light, Colors.White, 0.45));
        r["AccentButtonBackgroundPointerOver"] = Brush(Mix(Light, Colors.White, 0.65));
        r["AccentButtonBackgroundPressed"] = Brush(Mix(Light, Colors.Black, 0.08));
        r["AccentButtonBorderBrush"] = Brush(Mix(Light, Colors.White, 0.45));
        r["AccentButtonBorderBrushPointerOver"] = Brush(Mix(Light, Colors.White, 0.65));
        r["AccentButtonBorderBrushPressed"] = Brush(Mix(Light, Colors.Black, 0.08));
        r["AccentButtonForeground"] = Brush(Edge);
        r["AccentButtonForegroundPointerOver"] = Brush(Edge);
        r["AccentButtonForegroundPressed"] = Brush(Edge);
    }

    private static Color C(string hex) => Color.Parse(hex);
    private static SolidColorBrush Brush(Color color) => new(color);
    private static Color WithAlpha(Color color, double alpha) =>
        Color.FromArgb((byte)Math.Round(color.A * alpha), color.R, color.G, color.B);
    private static Color Mix(Color a, Color b, double t) => Color.FromArgb(a.A,
        (byte)Math.Round(a.R + (b.R - a.R) * t), (byte)Math.Round(a.G + (b.G - a.G) * t), (byte)Math.Round(a.B + (b.B - a.B) * t));
}
