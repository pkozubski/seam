using static BorderlessMouse.Input.NativeMethods;

namespace BorderlessMouse.Display;

/// <summary>Geometry shared by rendering, input and monitor recovery (physical pixels).</summary>
internal static class WindowGeometry
{
    public static bool CoversDisplay(RECT rect, int width, int height) => width > 0 && height > 0
        && Math.Max(0, Math.Min(rect.Right, width) - Math.Max(0, rect.Left)) >= width * 0.9
        && Math.Max(0, Math.Min(rect.Bottom, height) - Math.Max(0, rect.Top)) >= height * 0.9;

    public static RECT Fit(int sourceWidth, int sourceHeight, RECT target)
    {
        if (sourceWidth <= 0 || sourceHeight <= 0 || target.Width <= 0 || target.Height <= 0) return target;
        var scale = Math.Min(target.Width / (double)sourceWidth, target.Height / (double)sourceHeight);
        var width = Math.Clamp((int)Math.Round(sourceWidth * scale), 1, target.Width);
        var height = Math.Clamp((int)Math.Round(sourceHeight * scale), 1, target.Height);
        var left = target.Left + (target.Width - width) / 2;
        var top = target.Top + (target.Height - height) / 2;
        return new RECT { Left = left, Top = top, Right = left + width, Bottom = top + height };
    }

    /// <summary>
    /// A window picture is never enlarged: any non-integer upscale blurs text. While the source catches up
    /// with a resize it sits 1:1 at the top left like a native window's content; a larger one shrinks to fit.
    /// </summary>
    public static RECT FitWithin(int sourceWidth, int sourceHeight, RECT target)
    {
        if (sourceWidth <= 0 || sourceHeight <= 0 || target.Width <= 0 || target.Height <= 0) return target;
        var scale = Math.Min(1, Math.Min(target.Width / (double)sourceWidth, target.Height / (double)sourceHeight));
        var width = Math.Clamp((int)Math.Round(sourceWidth * scale), 1, target.Width);
        var height = Math.Clamp((int)Math.Round(sourceHeight * scale), 1, target.Height);
        return new RECT { Left = target.Left, Top = target.Top, Right = target.Left + width, Bottom = target.Top + height };
    }

    /// <summary>Keep the caption reachable on one real monitor, including disjoint layouts.</summary>
    public static RECT KeepReachable(RECT frame, IReadOnlyList<RECT> workAreas)
    {
        if (workAreas.Count == 0) return frame;
        var visibleWidth = Math.Min(160, frame.Width);
        if (workAreas.Any(a => frame.Top >= a.Top && frame.Top + 32 <= a.Bottom
            && Math.Min(frame.Right, a.Right) - Math.Max(frame.Left, a.Left) >= visibleWidth)) return frame;
        static double Distance(RECT a, RECT b)
        {
            var dx = Math.Max(0L, Math.Max((long)a.Left - b.Right, (long)b.Left - a.Right));
            var dy = Math.Max(0L, Math.Max((long)a.Top - b.Bottom, (long)b.Top - a.Bottom));
            return (double)dx * dx + (double)dy * dy;
        }
        var work = workAreas.OrderBy(a => Distance(frame, a)).First();
        var x = Math.Clamp(frame.Left, work.Left, Math.Max(work.Left, work.Right - frame.Width));
        var y = Math.Clamp(frame.Top, work.Top, Math.Max(work.Top, work.Bottom - frame.Height));
        return new RECT { Left = x, Top = y, Right = x + frame.Width, Bottom = y + frame.Height };
    }

    public static RECT MapRelative(RECT child, RECT source, RECT target)
    {
        int X(int x) => target.Left + (int)Math.Round((x - source.Left) * (double)target.Width / Math.Max(1, source.Width));
        int Y(int y) => target.Top + (int)Math.Round((y - source.Top) * (double)target.Height / Math.Max(1, source.Height));
        return new RECT { Left = X(child.Left), Top = Y(child.Top), Right = X(child.Right), Bottom = Y(child.Bottom) };
    }
}
