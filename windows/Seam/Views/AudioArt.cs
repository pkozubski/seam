using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;

namespace Seam.Views;

/// <summary>Fala dźwięku za słuchawkami: symetryczne świecące paski, najwyższe przy środku (AudioWaveBackdrop na macOS).</summary>
public sealed class AudioWave : Control
{
    private const int BarCount = 46;

    public override void Render(DrawingContext context)
    {
        var size = Bounds.Size;
        if (size.Width <= 0 || size.Height <= 0) return;
        var theme = PageTheme.Violet;
        var step = size.Width / BarCount;
        var barWidth = Math.Max(2, step * 0.38);
        for (var index = 0; index < BarCount; index++)
        {
            // Pozycja od środka (0) do krawędzi (1); wysokość z dwóch sinusów, żeby fala nie była regularna.
            var t = Math.Abs(index - (BarCount - 1) / 2.0) / (BarCount / 2.0);
            var ripple = 0.55 + 0.45 * Math.Abs(Math.Sin(index * 0.9) * Math.Cos(index * 0.37));
            var height = size.Height * Math.Pow(1 - t, 1.4) * ripple + 4;
            // Maska jak na macOS: paski gasną w skrajnych tercjach szerokości.
            var u = (index + 0.5) / BarCount;
            var fade = Math.Clamp(Math.Min(u, 1 - u) * 3, 0, 1);
            var opacity = (0.25 + 0.55 * (1 - t)) * fade;
            var x = index * step + (step - barWidth) / 2;
            var y = (size.Height - height) / 2;
            // Poświata pod paskiem zamiast rozmycia cienia.
            context.DrawRectangle(new SolidColorBrush(theme.Accent, 0.22 * fade), null,
                new Rect(x - barWidth, y - 4, barWidth * 3, height + 8), barWidth * 1.5, barWidth * 1.5);
            context.DrawRectangle(new SolidColorBrush(theme.Light, opacity), null,
                new Rect(x, y, barWidth, height), barWidth / 2, barWidth / 2);
        }
    }
}

/// <summary>Miernik poziomu z pasków: zapala tyle pasków, ile wynosi bieżący poziom dźwięku (AudioBarMeter na macOS).</summary>
public sealed class AudioBarMeter : Control
{
    public static readonly StyledProperty<double> LevelProperty =
        AvaloniaProperty.Register<AudioBarMeter, double>(nameof(Level));

    public static readonly StyledProperty<bool> IsActiveProperty =
        AvaloniaProperty.Register<AudioBarMeter, bool>(nameof(IsActive));

    private const int BarCount = 48;
    private const double Spacing = 4;

    static AudioBarMeter() => AffectsRender<AudioBarMeter>(LevelProperty, IsActiveProperty);

    public double Level
    {
        get => GetValue(LevelProperty);
        set => SetValue(LevelProperty, value);
    }

    public bool IsActive
    {
        get => GetValue(IsActiveProperty);
        set => SetValue(IsActiveProperty, value);
    }

    protected override Size MeasureOverride(Size availableSize) => new(0, 30);

    public override void Render(DrawingContext context)
    {
        var theme = PageTheme.Violet;
        var size = Bounds.Size;
        var barWidth = (size.Width - Spacing * (BarCount - 1)) / BarCount;
        if (barWidth <= 0) return;
        var value = IsActive ? Math.Clamp(Level, 0, 1) : 0;
        var lit = (int)Math.Ceiling(value * BarCount);
        var on = new LinearGradientBrush
        {
            StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
            EndPoint = new RelativePoint(0, 1, RelativeUnit.Relative),
            GradientStops = { new GradientStop(theme.Light, 0), new GradientStop(theme.Accent, 1) },
        };
        var glow = new SolidColorBrush(theme.Accent, 0.28);
        var off = new SolidColorBrush(Colors.White, 0.08);
        for (var index = 0; index < BarCount; index++)
        {
            var rect = new Rect(index * (barWidth + Spacing), 0, barWidth, size.Height);
            if (index < lit) context.DrawRectangle(glow, null, rect.Inflate(2), barWidth / 2 + 2, barWidth / 2 + 2);
            context.DrawRectangle(index < lit ? on : off, null, rect, barWidth / 2, barWidth / 2);
        }
    }
}
