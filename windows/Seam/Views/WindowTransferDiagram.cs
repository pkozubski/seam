using System.Globalization;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using Avalonia.Platform;
using Seam.Localization;
using Seam.Models;

namespace Seam.Views;

/// <summary>Native, scale-independent guide; only the two wallpapers are bitmap assets.</summary>
public sealed class WindowTransferDiagram : Control
{
    public static readonly StyledProperty<MacSide> MacSideProperty =
        AvaloniaProperty.Register<WindowTransferDiagram, MacSide>(nameof(MacSide), MacSide.Left);
    public static readonly StyledProperty<double> ProgressProperty =
        AvaloniaProperty.Register<WindowTransferDiagram, double>(nameof(Progress), 0.5);
    public static readonly StyledProperty<bool> ShowWindowProperty =
        AvaloniaProperty.Register<WindowTransferDiagram, bool>(nameof(ShowWindow), true);
    public MacSide MacSide { get => GetValue(MacSideProperty); set => SetValue(MacSideProperty, value); }
    public double Progress { get => GetValue(ProgressProperty); set => SetValue(ProgressProperty, value); }
    public bool ShowWindow { get => GetValue(ShowWindowProperty); set => SetValue(ShowWindowProperty, value); }

    private static readonly Lazy<Bitmap> MacWallpaper = new(() => Load("window-desktop-mac"));
    private static readonly Lazy<Bitmap> PcWallpaper = new(() => Load("window-desktop-pc"));
    private static readonly IBrush Accent = Brush.Parse("#B0DFA7");
    private static readonly IBrush Subtle = Brush.Parse("#A6FFFFFF");

    static WindowTransferDiagram() => AffectsRender<WindowTransferDiagram>(MacSideProperty, ProgressProperty, ShowWindowProperty);

    public WindowTransferDiagram() { IsHitTestVisible = false; }

    public override void Render(DrawingContext context)
    {
        base.Render(context);
        var w = Bounds.Width;
        var h = Bounds.Height;
        if (w <= 0 || h <= 0) return;
        var vertical = MacSide is MacSide.Top or MacSide.Bottom;
        var reversed = MacSide is MacSide.Right or MacSide.Bottom;
        var sw = vertical ? w * 0.64 : (w - 4) / 2;
        var sh = vertical ? (h - 4) / 2 : h;
        var first = new Rect(vertical ? (w - sw) / 2 : 0, 0, sw, sh);
        var second = new Rect(vertical ? (w - sw) / 2 : w - sw, vertical ? h - sh : 0, sw, sh);
        Desktop(context, first, !reversed);
        Desktop(context, second, reversed);
        var source = (reversed ? second : first).Center;
        var destination = (reversed ? first : second).Center;
        context.DrawLine(new Pen(Accent, 2),
            vertical ? new Point(first.Left, h / 2) : new Point(w / 2, 0),
            vertical ? new Point(first.Right, h / 2) : new Point(w / 2, h));
        if (!ShowWindow) return;
        var progress = Math.Clamp(Progress, 0, 1);
        var large = h >= 200;
        var point = source + (destination - source) * progress;
        // Na małym diagramie okno schodzi nieco niżej, żeby nie zasłaniać podpisów „Mac” i „Windows”
        if (!large && !vertical) point = point.WithY(point.Y + Math.Min(6, sh * 0.07));
        var ww = vertical ? sw * 0.64 : w * 0.34;
        var wh = Math.Min(sh * 0.64, ww * 0.63);
        var window = new Rect(point.X - ww / 2, point.Y - wh / 2, ww, wh);
        using (context.PushClip(new RoundedRect(window, 7)))
        {
            context.DrawRectangle(Brush.Parse("#F1F3EF"), null, window);
            context.DrawRectangle(Brush.Parse("#293538"), null, new Rect(window.X, window.Y, ww, large ? 26 : 13));
            var radius = large ? 3 : 1.8;
            for (var i = 0; i < 3; i++)
                context.DrawEllipse(Brush.Parse(new[] { "#F26960", "#F5C347", "#5BC668" }[i]), null,
                    new Point(window.X + (large ? 12 : 7) + i * radius * 3, window.Y + (large ? 13 : 6.5)), radius, radius);
            if (large) Text(context, L10n.T("Plan projektu", "Project plan"), new Point(window.X + ww * 0.4, window.Y + 7), 10, Brushes.White);
            for (var i = 0; i < 3; i++)
            {
                var y = window.Y + wh * (0.4 + 0.19 * i);
                context.DrawRectangle(i == 0 ? Brush.Parse("#4A8B7E") : null, new Pen(Brush.Parse("#869A96"), 1),
                    new Rect(window.X + ww * 0.08, y - 3, large ? 7 : 4, large ? 7 : 4), 1, 1);
                context.DrawRectangle(Brush.Parse("#C2CCC7"), null,
                    new Rect(window.X + ww * 0.19, y, ww * (i == 1 ? 0.58 : 0.72), large ? 5 : 3), 2, 2);
            }
        }
        if (large)
        {
            var direction = vertical ? new Vector(0, reversed ? -1 : 1) : new Vector(reversed ? -1 : 1, 0);
            var a = vertical ? new Point(window.Right + 16, point.Y - direction.Y * 12)
                             : new Point(point.X - direction.X * 12, window.Top - 16);
            var b = a + direction * 30;
            var normal = new Vector(-direction.Y, direction.X);
            context.DrawLine(new Pen(Accent, 2), a, b);
            context.DrawLine(new Pen(Accent, 2), b, b - direction * 7 + normal * 5);
            context.DrawLine(new Pen(Accent, 2), b, b - direction * 7 - normal * 5);
        }
    }

    private static void Desktop(DrawingContext context, Rect rect, bool mac)
    {
        var bitmap = mac ? MacWallpaper.Value : PcWallpaper.Value;
        var source = new Rect(bitmap.Size);
        var desiredRatio = rect.Width / rect.Height;
        if (source.Width / source.Height > desiredRatio)
            source = new Rect((source.Width - source.Height * desiredRatio) / 2, 0, source.Height * desiredRatio, source.Height);
        else
            source = new Rect(0, (source.Height - source.Width / desiredRatio) / 2, source.Width, source.Width / desiredRatio);
        context.DrawImage(bitmap, source, rect);
        context.DrawRectangle(null, new Pen(Brush.Parse("#50FFFFFF"), 1), rect, 8, 8);
        Text(context, mac ? "Mac" : "Windows", new Point(rect.X + 8, rect.Y + 6), 10, Subtle);
    }

    private static void Text(DrawingContext context, string text, Point position, double size, IBrush brush) =>
        context.DrawText(new FormattedText(text, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight,
                                          new Typeface(FontFamily.Default), size, brush), position);

    private static Bitmap Load(string name)
    {
        using var stream = AssetLoader.Open(new Uri($"avares://Seam/Assets/{name}.png"));
        return new Bitmap(stream);
    }
}
