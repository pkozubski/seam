using System.Globalization;
using Avalonia;
using Avalonia.Automation;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Media;
using Seam.Localization;

namespace Seam.Views;

/// <summary>
/// Kula stanu połączenia, jak ConnectionStatusButton na macOS: świecące szkło z białym symbolem i podpisem.
/// Połączona kula bierze kolor bieżącej strony (<see cref="Palette"/>), rozłączona jest grafitowa.
/// Na Macu wisi pod oknem; tu stoi na dole obszaru treści, a strony mają pod nią wolny margines.
/// </summary>
public sealed class StatusOrb : Control
{
    public static readonly StyledProperty<PageTheme> PaletteProperty =
        AvaloniaProperty.Register<StatusOrb, PageTheme>(nameof(Palette), PageTheme.Blue);

    public static readonly StyledProperty<bool> IsConnectedProperty =
        AvaloniaProperty.Register<StatusOrb, bool>(nameof(IsConnected));

    public static readonly StyledProperty<bool> IsConnectingProperty =
        AvaloniaProperty.Register<StatusOrb, bool>(nameof(IsConnecting));

    public static readonly RoutedEvent<RoutedEventArgs> ClickEvent =
        RoutedEvent.Register<StatusOrb, RoutedEventArgs>(nameof(Click), RoutingStrategies.Bubble);

    public const double OrbSize = 84;
    /// <summary>Margines na poświatę wokół kuli.</summary>
    public const double GlowInset = 30;

    private bool _hovering;

    static StatusOrb()
    {
        AffectsRender<StatusOrb>(PaletteProperty, IsConnectedProperty, IsConnectingProperty);
        FocusableProperty.OverrideDefaultValue<StatusOrb>(true);
        CursorProperty.OverrideDefaultValue<StatusOrb>(new Cursor(StandardCursorType.Hand));
        IsConnectedProperty.Changed.AddClassHandler<StatusOrb>((orb, _) => orb.UpdateName());
        IsConnectingProperty.Changed.AddClassHandler<StatusOrb>((orb, _) => orb.UpdateName());
    }

    public StatusOrb()
    {
        Width = Height = OrbSize + GlowInset * 2;
        ToolTip.SetTip(this, L10n.T("Connection status and details", pl: "Stan i szczegóły połączenia"));
        UpdateName();
    }

    public PageTheme Palette
    {
        get => GetValue(PaletteProperty);
        set => SetValue(PaletteProperty, value);
    }

    public bool IsConnected
    {
        get => GetValue(IsConnectedProperty);
        set => SetValue(IsConnectedProperty, value);
    }

    public bool IsConnecting
    {
        get => GetValue(IsConnectingProperty);
        set => SetValue(IsConnectingProperty, value);
    }

    public event EventHandler<RoutedEventArgs> Click
    {
        add => AddHandler(ClickEvent, value);
        remove => RemoveHandler(ClickEvent, value);
    }

    private string Label => IsConnected ? L10n.T("Connected", pl: "Połączono")
        : IsConnecting ? L10n.T("Connecting", pl: "Łączenie") : L10n.T("Waiting", pl: "Oczekiwanie");

    private void UpdateName() => AutomationProperties.SetName(this, Label);

    protected override void OnPointerEntered(PointerEventArgs e)
    {
        base.OnPointerEntered(e);
        _hovering = true;
        InvalidateVisual();
    }

    protected override void OnPointerExited(PointerEventArgs e)
    {
        base.OnPointerExited(e);
        _hovering = false;
        InvalidateVisual();
    }

    protected override void OnPointerReleased(PointerReleasedEventArgs e)
    {
        base.OnPointerReleased(e);
        if (e.InitialPressMouseButton == MouseButton.Left && IsInside(e.GetPosition(this))) RaiseEvent(new RoutedEventArgs(ClickEvent));
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        base.OnKeyDown(e);
        if (e.Key is not (Key.Enter or Key.Space)) return;
        e.Handled = true;
        RaiseEvent(new RoutedEventArgs(ClickEvent));
    }

    /// <summary>Kliknięcie liczy się tylko na kuli, nie na poświacie.</summary>
    private bool IsInside(Point point)
    {
        var center = new Point(Bounds.Width / 2, Bounds.Height / 2);
        var offset = point - center;
        return offset.X * offset.X + offset.Y * offset.Y <= OrbSize * OrbSize / 4;
    }

    public override void Render(DrawingContext context)
    {
        var (light, mid, deep, glow) = IsConnected
            ? (Palette.OrbLight, Palette.OrbMid, Palette.OrbDeep, (Color?)Palette.OrbGlow)
            : (Color.FromRgb(158, 158, 158), Color.FromRgb(77, 77, 77), Color.FromRgb(26, 26, 26), null);
        var center = new Point(Bounds.Width / 2, Bounds.Height / 2);
        var radius = OrbSize / 2;
        var orb = new Rect(center.X - radius, center.Y - radius, OrbSize, OrbSize);

        if (glow is { } glowColor)
        {
            var reach = radius + GlowInset;
            context.DrawEllipse(new RadialGradientBrush
            {
                GradientStops =
                {
                    new GradientStop(Color.FromArgb((byte)(_hovering ? 240 : 200), glowColor.R, glowColor.G, glowColor.B), radius / reach * 0.7),
                    new GradientStop(Color.FromArgb(0, glowColor.R, glowColor.G, glowColor.B), 1),
                },
            }, null, center, reach, reach);
        }

        context.DrawEllipse(new RadialGradientBrush
        {
            Center = new RelativePoint(0.38, 0.22, RelativeUnit.Relative),
            GradientOrigin = new RelativePoint(0.38, 0.22, RelativeUnit.Relative),
            RadiusX = new RelativeScalar(0.78, RelativeUnit.Relative),
            RadiusY = new RelativeScalar(0.78, RelativeUnit.Relative),
            GradientStops = { new GradientStop(light, 0), new GradientStop(mid, 0.5), new GradientStop(deep, 1) },
        }, null, orb.Center, radius, radius);
        // Szklany refleks u góry.
        context.DrawEllipse(new LinearGradientBrush
        {
            StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
            EndPoint = new RelativePoint(0, 1, RelativeUnit.Relative),
            GradientStops = { new GradientStop(Color.FromArgb(_hovering ? (byte)84 : (byte)66, 255, 255, 255), 0), new GradientStop(Color.FromArgb(0, 255, 255, 255), 1) },
        }, null, new Point(center.X, center.Y - OrbSize * 0.24), OrbSize * 0.35, OrbSize * 0.21);
        context.DrawEllipse(null, new Pen(new LinearGradientBrush
        {
            StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
            EndPoint = new RelativePoint(0, 1, RelativeUnit.Relative),
            GradientStops =
            {
                new GradientStop(Color.FromArgb(191, 255, 255, 255), 0),
                new GradientStop(Color.FromArgb(64, light.R, light.G, light.B), 0.5),
                new GradientStop(Color.FromArgb(89, 255, 255, 255), 1),
            },
        }, 1.2), center, radius - 0.6, radius - 0.6);

        var ink = new SolidColorBrush(Colors.White);
        var glyphCenter = new Point(center.X, center.Y - 9);
        if (IsConnected) DrawLink(context, glyphCenter, ink);
        else DrawWaves(context, glyphCenter, ink);

        var text = new FormattedText(Label, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight,
            new Typeface(FontFamily.Default, FontStyle.Normal, FontWeight.SemiBold), 11.5, ink);
        context.DrawText(text, new Point(center.X - text.Width / 2, center.Y + 9));
    }

    /// <summary>Symbol ogniwa łańcucha: dwa zaokrąglone ogniwa pod kątem 45°, rysowane, żeby nie zależeć od czcionki ikon.</summary>
    private static void DrawLink(DrawingContext context, Point center, IBrush ink)
    {
        var pen = new Pen(ink, 2.4, lineCap: PenLineCap.Round);
        using (context.PushTransform(Matrix.CreateRotation(-Math.PI / 4) * Matrix.CreateTranslation(center.X, center.Y)))
        {
            context.DrawRectangle(null, pen, new Rect(-12, -4.5, 13, 9), 4.5, 4.5);
            context.DrawRectangle(null, pen, new Rect(-1, -4.5, 13, 9), 4.5, 4.5);
        }
    }

    /// <summary>Symbol oczekiwania: kropka z dwoma łukami fal po bokach.</summary>
    private static void DrawWaves(DrawingContext context, Point center, IBrush ink)
    {
        var pen = new Pen(ink, 2.2, lineCap: PenLineCap.Round);
        context.DrawEllipse(ink, null, center, 2.6, 2.6);
        foreach (var r in new[] { 7.0, 12.0 })
        {
            foreach (var side in new[] { -1, 1 })
            {
                var geometry = new StreamGeometry();
                using (var g = geometry.Open())
                {
                    var angle = Math.PI / 4;
                    g.BeginFigure(new Point(center.X + side * r * Math.Cos(angle), center.Y - r * Math.Sin(angle)), false);
                    g.ArcTo(new Point(center.X + side * r * Math.Cos(angle), center.Y + r * Math.Sin(angle)), new Size(r, r), 0, false,
                        side > 0 ? SweepDirection.Clockwise : SweepDirection.CounterClockwise);
                }
                context.DrawGeometry(null, pen, geometry);
            }
        }
    }
}
