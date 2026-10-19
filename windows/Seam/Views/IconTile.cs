using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Shapes;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using Avalonia.Platform;

namespace Seam.Views;

/// <summary>
/// Srebrna ikona na grafitowej płytce z gradientem, jak SeamIconTile na macOS. Gradientowa maska
/// rozjaśnia górę ikony, a jej dół wtapia się w płytkę; aktywna płytka przyjmuje kolor akcentu.
/// </summary>
public sealed class IconTile : Panel
{
    public static readonly StyledProperty<string> IconProperty =
        AvaloniaProperty.Register<IconTile, string>(nameof(Icon), "");

    public static readonly StyledProperty<bool> IsActiveProperty =
        AvaloniaProperty.Register<IconTile, bool>(nameof(IsActive));

    public static readonly StyledProperty<double> TileSizeProperty =
        AvaloniaProperty.Register<IconTile, double>(nameof(TileSize), 30);

    private static readonly Color[] GraphitePlate = { Color.Parse("#595D66"), Color.Parse("#1F2024") };
    private static readonly Color[] ActivePlate = { Color.Parse("#6E856B"), Color.Parse("#2B382D") };
    private static readonly Dictionary<string, Bitmap?> Artwork = new();
    private static readonly Dictionary<(string, bool, Color?), IImage> Rendered = new();

    static IconTile()
    {
        IconProperty.Changed.AddClassHandler<IconTile>((tile, _) => tile.Build());
        IsActiveProperty.Changed.AddClassHandler<IconTile>((tile, _) => tile.Build());
        TileSizeProperty.Changed.AddClassHandler<IconTile>((tile, _) => tile.Build());
    }

    public IconTile() => Build();

    /// <summary>Nazwa pliku z Assets bez rozszerzenia, np. <c>icon-control</c>.</summary>
    public string Icon
    {
        get => GetValue(IconProperty);
        set => SetValue(IconProperty, value);
    }

    public bool IsActive
    {
        get => GetValue(IsActiveProperty);
        set => SetValue(IsActiveProperty, value);
    }

    public double TileSize
    {
        get => GetValue(TileSizeProperty);
        set => SetValue(TileSizeProperty, value);
    }

    /// <summary>
    /// Ikona paska bocznego bez płytki: <c>nav-{tag}</c> (wyrównane optycznie, z marginesem w pliku),
    /// a gdyby jej zabrakło, dawna <c>icon-{tag}</c>. Ikony są przygaszone, żeby wtapiały się w tło;
    /// zaznaczona jest jaśniejsza (pigułkę rysuje NavigationView). <paramref name="badge"/> dodaje
    /// kropkę stanu w prawym górnym rogu, zawsze w pełnym kolorze.
    /// </summary>
    public static IImage RenderNav(string tag, bool selected, Color? badge = null, double size = 30, double glyph = 23)
    {
        var key = (tag, selected, badge);
        if (Rendered.TryGetValue(key, out var cached)) return cached;
        const double scale = 3;
        var canvas = size * scale;
        var content = new Panel { Width = size, Height = size };
        if ((Load($"nav-{tag}") ?? Load($"icon-{tag}")) is { } artwork)
            content.Children.Add(new Image
            {
                Source = artwork, Width = glyph, Height = glyph, Stretch = Stretch.Uniform, Opacity = selected ? 0.95 : 0.68,
                HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
            });
        if (badge is { } color)
            content.Children.Add(new Ellipse
            {
                Width = 10, Height = 10,
                HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top,
                Fill = new SolidColorBrush(color),
                Stroke = new SolidColorBrush(Color.Parse("#99000000")), StrokeThickness = 1.5,
            });
        var host = new LayoutTransformControl { LayoutTransform = new ScaleTransform(scale, scale), Child = content };
        host.Measure(new Size(canvas, canvas));
        host.Arrange(new Rect(0, 0, canvas, canvas));
        var bitmap = new RenderTargetBitmap(new PixelSize((int)canvas, (int)canvas), new Vector(96, 96));
        bitmap.Render(host);
        Rendered[key] = bitmap;
        return bitmap;
    }

    private void Build()
    {
        Children.Clear();
        var size = TileSize;
        Width = size;
        Height = size;
        var radius = new CornerRadius(size * 0.3);
        var inset = new Thickness(size * 0.1);

        Children.Add(new Border
        {
            CornerRadius = radius,
            Background = Vertical(IsActive ? ActivePlate : GraphitePlate),
            BorderBrush = Vertical(Color.FromArgb(0x3D, 255, 255, 255), Color.FromArgb(0x08, 255, 255, 255)),
            BorderThickness = new Thickness(0.75),
            BoxShadow = BoxShadows.Parse("0 1.5 5 0 #59000000"),
        });
        Children.Add(new Border
        {
            CornerRadius = radius,
            Background = new RadialGradientBrush
            {
                Center = new RelativePoint(0.5, 0, RelativeUnit.Relative),
                GradientOrigin = new RelativePoint(0.5, 0, RelativeUnit.Relative),
                RadiusX = new RelativeScalar(0.85, RelativeUnit.Relative),
                RadiusY = new RelativeScalar(0.85, RelativeUnit.Relative),
                GradientStops = { new GradientStop(Color.FromArgb(0x29, 255, 255, 255), 0), new GradientStop(Color.FromArgb(0, 255, 255, 255), 1) },
            },
        });

        if (Load(Icon) is not { } artwork) return;
        Children.Add(new Image { Source = artwork, Margin = inset, Stretch = Stretch.Uniform });
        Children.Add(new Rectangle
        {
            Margin = inset,
            Fill = new LinearGradientBrush
            {
                StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
                EndPoint = new RelativePoint(0, 1, RelativeUnit.Relative),
                GradientStops =
                {
                    new GradientStop(Color.FromArgb(0x47, 255, 255, 255), 0),
                    new GradientStop(Color.FromArgb(0, 128, 128, 128), 0.5),
                    new GradientStop(Color.FromArgb(0x47, 0, 0, 0), 1),
                },
            },
            OpacityMask = new ImageBrush(artwork) { Stretch = Stretch.Uniform },
        });
    }

    private static LinearGradientBrush Vertical(params Color[] colors) => new()
    {
        StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
        EndPoint = new RelativePoint(0, 1, RelativeUnit.Relative),
        GradientStops = { new GradientStop(colors[0], 0), new GradientStop(colors[1], 1) },
    };

    /// <summary>Źródła mają ~1250 px; dekodujemy mniejszą kopię, która wystarcza do 4× skali.</summary>
    private static Bitmap? Load(string icon)
    {
        if (string.IsNullOrEmpty(icon)) return null;
        if (Artwork.TryGetValue(icon, out var cached)) return cached;
        Bitmap? bitmap = null;
        try
        {
            using var stream = AssetLoader.Open(new Uri($"avares://Seam/Assets/{icon}.png"));
            bitmap = Bitmap.DecodeToWidth(stream, 160, BitmapInterpolationMode.HighQuality);
        }
        catch (FileNotFoundException)
        {
        }
        Artwork[icon] = bitmap;
        return bitmap;
    }
}
