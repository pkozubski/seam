using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using Avalonia.Platform;

namespace Seam.Views;

/// <summary>
/// Grafika strony Schowek (ClipboardHero na macOS): szklany schowek, z którego wylatują karta tekstu i karta zdjęcia
/// po smugach światła. Trzy osobne obrazy; położenia są ułamkami szerokości, więc układ skaluje się z oknem.
/// </summary>
public sealed class ClipboardHero : Control
{
    private const double AspectRatio = 1.15;
    private static Bitmap? _board, _text, _photo;

    public ClipboardHero()
    {
        IsHitTestVisible = false;
        _board ??= Load("hero-clipboard-board");
        _text ??= Load("hero-clipboard-text");
        _photo ??= Load("hero-clipboard-photo");
    }

    private static Bitmap Load(string name)
    {
        using var stream = AssetLoader.Open(new Uri($"avares://Seam/Assets/{name}.png"));
        return new Bitmap(stream);
    }

    protected override Size MeasureOverride(Size availableSize)
    {
        var width = double.IsInfinity(availableSize.Width) ? 460 : availableSize.Width;
        if (!double.IsInfinity(availableSize.Height)) width = Math.Min(width, availableSize.Height * AspectRatio);
        return new Size(width, width / AspectRatio);
    }

    public override void Render(DrawingContext context)
    {
        var theme = PageTheme.Amber;
        var w = Math.Min(Bounds.Width, Bounds.Height * AspectRatio);
        var origin = new Point((Bounds.Width - w) / 2, (Bounds.Height - w / AspectRatio) / 2);
        using (context.PushTransform(Matrix.CreateTranslation(origin.X, origin.Y)))
        {
            Draw(context, _board!, w * 0.58, new Point(w * 0.33, w * 0.47), theme.Glow, 0.45);
            DrawTrails(context, w, theme.Light);
            Draw(context, _text!, w * 0.36, new Point(w * 0.80, w * 0.34), theme.Light, 0.3);
            Draw(context, _photo!, w * 0.38, new Point(w * 0.64, w * 0.62), theme.Light, 0.3);
        }
    }

    /// <summary>Obraz o szerokości <paramref name="width"/> wyśrodkowany w <paramref name="center"/>, z miękką poświatą pod spodem.</summary>
    private static void Draw(DrawingContext context, Bitmap bitmap, double width, Point center, Color glow, double glowOpacity)
    {
        var height = width * bitmap.Size.Height / bitmap.Size.Width;
        var rect = new Rect(center.X - width / 2, center.Y - height / 2, width, height);
        context.DrawEllipse(new RadialGradientBrush
        {
            GradientStops =
            {
                new GradientStop(Color.FromArgb((byte)(glowOpacity * 255), glow.R, glow.G, glow.B), 0),
                new GradientStop(Color.FromArgb(0, glow.R, glow.G, glow.B), 1),
            },
        }, null, center, width * 0.7, height * 0.7);
        context.DrawImage(bitmap, new Rect(bitmap.Size), rect);
    }

    /// <summary>Smugi światła ze środka schowka do obu kart: szerokie, półprzezroczyste pociągnięcia zamiast rozmycia, pod cienką jasną linią.</summary>
    private static void DrawTrails(DrawingContext context, double w, Color light)
    {
        var geometry = new StreamGeometry();
        using (var g = geometry.Open())
        {
            foreach (var (end, bend) in new[] { (new Point(0.70, 0.36), new Point(0.42, 0.26)),
                                               (new Point(0.56, 0.58), new Point(0.36, 0.50)),
                                               (new Point(0.66, 0.46), new Point(0.40, 0.36)) })
            {
                g.BeginFigure(new Point(w * 0.20, w * 0.56), false);
                g.QuadraticBezierTo(new Point(w * bend.X, w * bend.Y), new Point(w * end.X, w * end.Y));
                g.EndFigure(false);
            }
        }
        foreach (var (thickness, opacity) in new[] { (16.0, 0.12), (8.0, 0.22), (4.0, 0.4), (1.8, 1.0) })
        {
            var brush = new LinearGradientBrush
            {
                StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
                EndPoint = new RelativePoint(1, 0, RelativeUnit.Relative),
                GradientStops =
                {
                    new GradientStop(Color.FromArgb(0, light.R, light.G, light.B), 0),
                    new GradientStop(Color.FromArgb((byte)(0.7 * opacity * 255), light.R, light.G, light.B), 0.5),
                    new GradientStop(Color.FromArgb((byte)(0.95 * opacity * 255), 255, 255, 255), 1),
                },
            };
            context.DrawGeometry(null, new Pen(brush, thickness, lineCap: PenLineCap.Round), geometry);
        }
    }
}
