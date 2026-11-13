using Avalonia;
using Avalonia.Animation;
using Avalonia.Animation.Easings;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using Avalonia.Platform;
using Seam.Models;

namespace Seam.Views;

/// <summary>
/// Układ ekranów do przeciągania (jak Ustawienia → Monitory w systemie): ten PC na środku, Mac jako kafelek,
/// który przeciąga się na dowolną stronę. Po puszczeniu kafelek przeskakuje do najbliższego miejsca;
/// strzałki na klawiaturze robią to samo. Wybór wychodzi przez <see cref="MacSide"/>.
/// </summary>
public sealed class ScreenArrangement : Canvas
{
    public static readonly StyledProperty<MacSide> MacSideProperty =
        AvaloniaProperty.Register<ScreenArrangement, MacSide>(nameof(MacSide), MacSide.Left,
            defaultBindingMode: Avalonia.Data.BindingMode.TwoWay);
    public static readonly StyledProperty<string> MacNameProperty =
        AvaloniaProperty.Register<ScreenArrangement, string>(nameof(MacName), "Mac");
    public static readonly StyledProperty<string> PcNameProperty =
        AvaloniaProperty.Register<ScreenArrangement, string>(nameof(PcName), Environment.MachineName);

    private const double PcWidth = 220, PcHeight = 150, MacWidth = 180, MacHeight = 112, Gap = 16;

    private readonly Border _pc;
    private readonly Border _mac;
    private readonly TextBlock _macName = new() { FontSize = 14, FontWeight = FontWeight.SemiBold, TextTrimming = TextTrimming.CharacterEllipsis, HorizontalAlignment = HorizontalAlignment.Center };
    private readonly TextBlock _pcName = new() { FontSize = 15, FontWeight = FontWeight.SemiBold, TextTrimming = TextTrimming.CharacterEllipsis, HorizontalAlignment = HorizontalAlignment.Center };
    private readonly Dictionary<MacSide, Border> _targets = new();
    private Point? _dragOffset;
    private MacSide? _hover;

    public ScreenArrangement()
    {
        Height = 2 * (MacHeight + Gap) + PcHeight;
        ClipToBounds = false;
        Focusable = true;
        foreach (var side in Enum.GetValues<MacSide>())
        {
            var target = new Border
            {
                Width = MacWidth, Height = MacHeight, CornerRadius = new CornerRadius(16),
                BorderThickness = new Thickness(1.5), Opacity = 0,
                Transitions = new Transitions { new DoubleTransition { Property = OpacityProperty, Duration = TimeSpan.FromMilliseconds(150) } },
            };
            _targets[side] = target;
            Children.Add(target);
        }
        _pc = Tile(Art("hero-windows-monitor.png", 72), _pcName, Pill(Localization.L10n.T("This PC", pl: "Ten komputer")));
        _pc.Width = PcWidth;
        _pc.Height = PcHeight;
        _mac = Tile(Art("hero-windows-laptop.png", 52), _macName, Caption("Mac"));
        _mac.Width = MacWidth;
        _mac.Height = MacHeight;
        _mac.Cursor = new Cursor(StandardCursorType.SizeAll);
        _mac.PointerPressed += OnPressed;
        _mac.PointerMoved += OnMoved;
        _mac.PointerReleased += OnReleased;
        _mac.PointerCaptureLost += (_, _) => EndDrag(commit: false);
        Children.Add(_pc);
        Children.Add(_mac);
        KeyDown += OnKeyDown;
    }

    public MacSide MacSide
    {
        get => GetValue(MacSideProperty);
        set => SetValue(MacSideProperty, value);
    }

    public string MacName
    {
        get => GetValue(MacNameProperty);
        set => SetValue(MacNameProperty, value);
    }

    public string PcName
    {
        get => GetValue(PcNameProperty);
        set => SetValue(PcNameProperty, value);
    }

    protected override void OnPropertyChanged(AvaloniaPropertyChangedEventArgs change)
    {
        base.OnPropertyChanged(change);
        if (change.Property == MacSideProperty || change.Property == BoundsProperty) Place(animated: change.Property == MacSideProperty);
        if (change.Property == MacNameProperty) _macName.Text = MacName;
        if (change.Property == PcNameProperty) _pcName.Text = PcName;
    }

    protected override void OnAttachedToVisualTree(VisualTreeAttachmentEventArgs e)
    {
        base.OnAttachedToVisualTree(e);
        _macName.Text = MacName;
        _pcName.Text = PcName;
        ApplyColors();
        Place(animated: false);
    }

    /// <summary>Kolory z zasobów strony (PageTheme), żeby kafelki pasowały do jej motywu.</summary>
    private void ApplyColors()
    {
        var border = Resource("CardBorder", Color.Parse("#33FFFFFF"));
        var light = Resource("PageLight", Colors.White);
        foreach (var tile in new[] { _pc, _mac })
            tile.BorderBrush = new SolidColorBrush(tile == _mac ? Color.FromArgb(0xB0, light.R, light.G, light.B) : border);
        foreach (var target in _targets.Values)
        {
            target.BorderBrush = new SolidColorBrush(Color.FromArgb(0x99, light.R, light.G, light.B));
            target.Background = new SolidColorBrush(Color.FromArgb(0x14, light.R, light.G, light.B));
        }
    }

    private Color Resource(string key, Color fallback) =>
        this.TryFindResource(key, ActualThemeVariant, out var value) && value is ISolidColorBrush brush ? brush.Color : fallback;

    private Point Center => new(Bounds.Width / 2, Bounds.Height / 2);

    private Point SlotOrigin(MacSide side)
    {
        var c = Center;
        return side switch
        {
            MacSide.Left => new(c.X - PcWidth / 2 - Gap - MacWidth, c.Y - MacHeight / 2),
            MacSide.Right => new(c.X + PcWidth / 2 + Gap, c.Y - MacHeight / 2),
            MacSide.Top => new(c.X - MacWidth / 2, c.Y - PcHeight / 2 - Gap - MacHeight),
            _ => new(c.X - MacWidth / 2, c.Y + PcHeight / 2 + Gap),
        };
    }

    private void Place(bool animated)
    {
        if (Bounds.Width <= 0) return;
        SetLeft(_pc, Center.X - PcWidth / 2);
        SetTop(_pc, Center.Y - PcHeight / 2);
        foreach (var (side, target) in _targets)
        {
            var origin = SlotOrigin(side);
            SetLeft(target, origin.X);
            SetTop(target, origin.Y);
        }
        if (_dragOffset is not null) return;
        ResetTargets();
        _mac.Transitions = animated ? SnapTransitions : null;
        var slot = SlotOrigin(MacSide);
        SetLeft(_mac, slot.X);
        SetTop(_mac, slot.Y);
    }

    private static Transitions SnapTransitions => new()
    {
        new DoubleTransition { Property = LeftProperty, Duration = TimeSpan.FromMilliseconds(260), Easing = new CubicEaseOut() },
        new DoubleTransition { Property = TopProperty, Duration = TimeSpan.FromMilliseconds(260), Easing = new CubicEaseOut() },
    };

    private void OnPressed(object? sender, PointerPressedEventArgs e)
    {
        if (!e.GetCurrentPoint(_mac).Properties.IsLeftButtonPressed) return;
        _mac.Transitions = null;
        _dragOffset = e.GetPosition(_mac);
        e.Pointer.Capture(_mac);
        Focus();
        foreach (var (side, target) in _targets) target.Opacity = side == MacSide ? 0 : 0.6;
        e.Handled = true;
    }

    private void OnMoved(object? sender, PointerEventArgs e)
    {
        if (_dragOffset is not { } offset) return;
        var p = e.GetPosition(this);
        SetLeft(_mac, p.X - offset.X);
        SetTop(_mac, p.Y - offset.Y);
        var nearest = Nearest(new Point(p.X - offset.X + MacWidth / 2, p.Y - offset.Y + MacHeight / 2));
        if (nearest == _hover) return;
        _hover = nearest;
        foreach (var (side, target) in _targets) target.Opacity = side == nearest ? 1 : 0.45;
    }

    private void OnReleased(object? sender, PointerReleasedEventArgs e)
    {
        if (_dragOffset is null) return;
        // Najpierw zapis: zwolnienie przechwycenia wywołuje PointerCaptureLost, które kończy przeciąganie bez zmiany.
        EndDrag(commit: true);
        e.Pointer.Capture(null);
    }

    private void EndDrag(bool commit)
    {
        if (_dragOffset is null) return;
        _dragOffset = null;
        var chosen = commit && _hover is { } hover ? hover : MacSide;
        _hover = null;
        if (chosen != MacSide) MacSide = chosen; // przeskok z animacją w OnPropertyChanged
        else Place(animated: true);
    }

    /// <summary>Wolne miejsca widać zawsze lekko, żeby było jasne, gdzie można upuścić Maca.</summary>
    private void ResetTargets()
    {
        foreach (var (side, target) in _targets) target.Opacity = side == MacSide ? 0 : 0.3;
    }

    private MacSide Nearest(Point macCenter) =>
        _targets.Keys.MinBy(side =>
        {
            var o = SlotOrigin(side);
            var dx = o.X + MacWidth / 2 - macCenter.X;
            var dy = o.Y + MacHeight / 2 - macCenter.Y;
            return dx * dx + dy * dy;
        });

    private void OnKeyDown(object? sender, KeyEventArgs e)
    {
        MacSide? side = e.Key switch
        {
            Key.Left => MacSide.Left,
            Key.Right => MacSide.Right,
            Key.Up => MacSide.Top,
            Key.Down => MacSide.Bottom,
            _ => null,
        };
        if (side is null) return;
        MacSide = side.Value;
        e.Handled = true;
    }

    private static Border Tile(params Control[] content)
    {
        var stack = new StackPanel { Spacing = 6, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        stack.Children.AddRange(content);
        return new Border
        {
            CornerRadius = new CornerRadius(18),
            BorderThickness = new Thickness(1),
            Padding = new Thickness(12),
            Background = new LinearGradientBrush
            {
                StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
                EndPoint = new RelativePoint(0, 1, RelativeUnit.Relative),
                GradientStops = { new GradientStop(Color.Parse("#26FFFFFF"), 0), new GradientStop(Color.Parse("#0DFFFFFF"), 1) },
            },
            Child = stack,
        };
    }

    private static Image Art(string asset, double height) => new()
    {
        Source = new Bitmap(AssetLoader.Open(new Uri($"avares://Seam/Assets/{asset}"))),
        Height = height,
        HorizontalAlignment = HorizontalAlignment.Center,
    };

    private static Border Pill(string text) => new()
    {
        Classes = { "pill" },
        HorizontalAlignment = HorizontalAlignment.Center,
        Child = new TextBlock { Text = text, FontSize = 11 },
    };

    private static TextBlock Caption(string text) => new()
    {
        Text = text, FontSize = 11, Opacity = 0.75, HorizontalAlignment = HorizontalAlignment.Center,
    };
}
