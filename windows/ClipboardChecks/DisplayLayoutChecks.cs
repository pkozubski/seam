using Avalonia;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Input;
using Avalonia.Threading;
using Seam.Models;
using Seam.Views;

/// <summary>Układ ekranów: przeciągnięcie kafelka Maca myszą i strzałki zmieniają stronę (headless Avalonia).</summary>
internal static class DisplayLayoutChecks
{
    public static void Run()
    {
        var arrangement = new ScreenArrangement { MacSide = MacSide.Left };
        var window = new Window { Width = 900, Height = 700, Content = arrangement };
        window.Show();
        Dispatcher.UIThread.RunJobs();

        // Dzieci: cztery cele, PC, Mac (ostatni).
        var mac = (Control)arrangement.Children[^1];
        var pc = (Control)arrangement.Children[^2];
        Point Center(Control c) => arrangement.TranslatePoint(
            new Point(Canvas.GetLeft(c) + c.Bounds.Width / 2, Canvas.GetTop(c) + c.Bounds.Height / 2), window)!.Value;

        var start = Center(mac);
        var pcCenter = Center(pc);
        Expect(start.X < pcCenter.X, "Mac starts on the left of the PC");
        var below = new Point(pcCenter.X, pcCenter.Y + pc.Bounds.Height);
        window.MouseDown(start, MouseButton.Left);
        window.MouseMove(new Point((start.X + below.X) / 2, (start.Y + below.Y) / 2));
        window.MouseMove(below);
        window.MouseUp(below, MouseButton.Left);
        Dispatcher.UIThread.RunJobs();
        Expect(arrangement.MacSide == MacSide.Bottom, $"dragging the Mac below the PC puts it at the bottom (got {arrangement.MacSide})");

        // Krótkie przesunięcie bez zmiany strony zostawia wybór.
        var bottom = Center(mac);
        window.MouseDown(bottom, MouseButton.Left);
        window.MouseMove(new Point(bottom.X + 10, bottom.Y + 5));
        window.MouseUp(new Point(bottom.X + 10, bottom.Y + 5), MouseButton.Left);
        Dispatcher.UIThread.RunJobs();
        Expect(arrangement.MacSide == MacSide.Bottom, "a small nudge keeps the side");

        arrangement.Focus();
        window.KeyPressQwerty(PhysicalKey.ArrowRight, RawInputModifiers.None);
        Dispatcher.UIThread.RunJobs();
        Expect(arrangement.MacSide == MacSide.Right, $"the Right arrow moves the Mac to the right (got {arrangement.MacSide})");
        window.Close();
        Console.WriteLine("✓ Displays: dragging the Mac tile and arrow keys choose the side");
    }

    private static void Expect(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
