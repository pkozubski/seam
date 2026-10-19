using System.Runtime.InteropServices;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using Avalonia.Platform;

namespace Seam.Views;

/// <summary>
/// Grafitowe tło okna jak na macOS (SeamBackdrop): chłodne światło od góry, słaba poświata
/// akcentu pod statusem połączenia i drobne ziarno, żeby ciemne gradienty nie tworzyły pasów.
/// </summary>
public sealed class SeamBackdrop : Panel
{
    private static readonly Lazy<Bitmap> Grain = new(CreateGrain);

    public SeamBackdrop()
    {
        IsHitTestVisible = false;
        Children.Add(new Border
        {
            Background = new LinearGradientBrush
            {
                StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
                EndPoint = new RelativePoint(0, 1, RelativeUnit.Relative),
                GradientStops = { new GradientStop(Color.Parse("#222428"), 0), new GradientStop(Color.Parse("#141517"), 1) },
            },
        });
        Children.Add(Glow(Color.Parse("#78828F"), 0.34, 0.6, -0.05, 0.72));
        Children.Add(Glow(Color.Parse("#91AD8C"), 0.17, 0.55, 1.02, 0.42));
        Children.Add(Glow(Colors.Black, 0.4, 0, 1, 0.75));
        Children.Add(new Border
        {
            Background = new ImageBrush(Grain.Value)
            {
                TileMode = TileMode.Tile,
                Stretch = Stretch.Fill,
                DestinationRect = new RelativeRect(0, 0, 64, 64, RelativeUnit.Absolute),
            },
        });
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

    /// <summary>Kafelek szumu rysowany raz na uruchomienie, 1 piksel szumu na piksel ekranu przy 200%.</summary>
    private static Bitmap CreateGrain()
    {
        const int side = 128;
        var bitmap = new WriteableBitmap(new PixelSize(side, side), new Vector(192, 192), PixelFormat.Bgra8888, AlphaFormat.Premul);
        using var buffer = bitmap.Lock();
        var row = new byte[side * 4];
        for (var y = 0; y < side; y++)
        {
            for (var x = 0; x < side; x++)
            {
                var alpha = (byte)Random.Shared.Next(0, 23);
                // Premultiplied: a white speck stores its alpha as the color, a dark one stores 0.
                var value = Random.Shared.Next(2) == 0 ? alpha : (byte)0;
                row[x * 4] = value;
                row[x * 4 + 1] = value;
                row[x * 4 + 2] = value;
                row[x * 4 + 3] = alpha;
            }
            Marshal.Copy(row, 0, buffer.Address + y * buffer.RowBytes, row.Length);
        }
        return bitmap;
    }
}
