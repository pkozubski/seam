using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Shapes;
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
    private static readonly Dictionary<(string, bool), IImage> Rendered = new();

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
    /// Płytka jako obraz dla ikon NavigationView, które przyjmują tylko IImage.
    /// Margines wokół płytki mieści jej cień.
    /// </summary>
    public static IImage Render(string icon, bool active, double size = 30, double margin = 3)
    {
        if (Rendered.TryGetValue((icon, active), out var cached)) return cached;
        // FAImageIcon draws with a source rect in DIPs, which Avalonia reads as pixels, so a
        // high-DPI bitmap gets cropped. Render a 3× scaled tile into a 96 DPI bitmap instead;
        // the NavigationView icon box scales it back down.
        const double scale = 3;
        var canvas = (size + margin * 2) * scale;
        var host = new LayoutTransformControl
        {
            LayoutTransform = new ScaleTransform(scale, scale),
            Child = new IconTile { Icon = icon, IsActive = active, TileSize = size, Margin = new Thickness(margin) },
        };
        host.Measure(new Size(canvas, canvas));
        host.Arrange(new Rect(0, 0, canvas, canvas));
        var bitmap = new RenderTargetBitmap(new PixelSize((int)canvas, (int)canvas), new Vector(96, 96));
        bitmap.Render(host);
        Rendered[(icon, active)] = bitmap;
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
