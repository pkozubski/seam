using System.Runtime.InteropServices;
using BorderlessMouse.Display;
using BorderlessMouse.Protocol;
using static BorderlessMouse.Input.NativeMethods;

internal static class WindowChecks
{
    private static RECT Rect(int x, int y, int width, int height) =>
        new() { Left = x, Top = y, Right = x + width, Bottom = y + height };

    private static void Expect(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }

    public static void Run()
    {
        var target = Rect(-1920, 0, 1920, 1080);
        var image = WindowGeometry.Fit(800, 600, target);
        Expect(image.Left == -1680 && image.Top == 0 && image.Width == 1440 && image.Height == 1080,
            "4:3 content on a 16:9 monitor keeps its aspect ratio and centres in screen coordinates");
        var portrait = WindowGeometry.Fit(1920, 1080, Rect(30, 40, 600, 900));
        Expect(portrait.Width == 600 && portrait.Height == 338 && portrait.Top == 321,
            "widescreen video fits a portrait window without horizontal stretching");
        var popup = WindowGeometry.MapRelative(Rect(100, 60, 400, 240), Rect(0, 0, 800, 600), image);
        Expect(popup.Left == -1500 && popup.Top == 108 && popup.Width == 720 && popup.Height == 432,
            "URL suggestions follow their owner's actual rendered image, including letterboxing and scale");
        Expect(WindowGeometry.CoversDisplay(Rect(0, 0, 1920, 1080), 1920, 1080)
            && !WindowGeometry.CoversDisplay(Rect(0, 0, 1920, 160), 1920, 1080)
            && !WindowGeometry.CoversDisplay(Rect(1900, 0, 1920, 1080), 1920, 1080),
            "fullscreen video fills the owner; URL bars and adjacent-screen windows do not");
        var works = new[] { Rect(-1920, -200, 1920, 1040), Rect(400, 0, 1920, 1040) };
        var gap = WindowGeometry.KeepReachable(Rect(100, 80, 180, 500), works);
        Expect(gap.Left == -180 && gap.Top == 80, "a caption in the gap between monitors is recovered");
        var removedMonitor = WindowGeometry.KeepReachable(Rect(5000, -400, 800, 600), works);
        Expect(removedMonitor.Left == 1520 && removedMonitor.Top == 0,
            "a disconnected monitor cannot strand the caption");
        var oversized = WindowGeometry.KeepReachable(Rect(6000, -500, 3000, 2000), works);
        Expect(oversized.Left == 400 && oversized.Top == 0 && oversized.Width == 3000,
            "an oversized window retains its content size but gets a reachable caption");
        var valid = Rect(-800, 50, 600, 500);
        Expect(WindowGeometry.KeepReachable(valid, works).Equals(valid), "normal multi-monitor placement is preserved");

        var queue = new VideoFrameQueue(2);
        VideoStream.VideoFrame Frame(ulong n, bool key = false) => new(2, key ? (byte)1 : (byte)0, 800, 600, n, [0, 0, 0, 1], 5);
        Expect(!queue.Enqueue(Frame(1, true)) && !queue.Enqueue(Frame(2)), "complete GOP fits the queue");
        Expect(queue.Enqueue(Frame(3)), "queue reports a dropped H.264 reference");
        var batch = queue.Drain(out var discontinuous);
        Expect(discontinuous && batch.Count == 1 && batch[0].CaptureMicros == 3,
            "the next P-frame is delivered with its required decoder reset");
        queue.Enqueue(Frame(4, true));
        batch = queue.Drain(out discontinuous);
        Expect(!discontinuous && batch.Single().IsKeyframe, "fresh keyframe resumes a clean queue");
        queue.Enqueue(Frame(5)); queue.Enqueue(Frame(6)); queue.Enqueue(Frame(7)); queue.Clear();
        Expect(queue.Drain(out discontinuous).Count == 0 && !discontinuous, "restart clears stale discontinuity state");
        Console.WriteLine("✓ Window geometry: aspect ratio, popup scale, disconnected monitors; H.264 queue recovery");
    }

    [DllImport("user32.dll")]
    private static extern IntPtr GetWindowLongPtrW(IntPtr window, int index);
    [DllImport("user32.dll")]
    private static extern IntPtr GetWindow(IntPtr window, uint command);
    [DllImport("user32.dll")]
    private static extern IntPtr GetMenu(IntPtr window);
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindow(IntPtr window);

    [System.Runtime.Versioning.SupportedOSPlatform("windows")]
    public static void RunNative(IReadOnlyList<VideoStream.VideoFrame> frames)
    {
        using var viewer = new DisplayViewer();
        var monitor = DisplayNative.Monitors().First().Bounds;
        var keyframe = frames.First(f => f.IsKeyframe);
        string? failure = null;
        var resized = new System.Collections.Concurrent.ConcurrentQueue<(int width, int height)>();
        viewer.Failed += message => Volatile.Write(ref failure, message);
        viewer.ResizeRequested += (_, width, height) => resized.Enqueue((width, height));
        viewer.KeyframeNeeded += id =>
        {
            foreach (var stream in id is { } value ? new[] { value } : new uint[] { 101, 102 })
                viewer.Enqueue(keyframe with { Kind = 2, StreamId = stream });
        };
        void Wait(Func<bool> condition, string message)
        {
            var until = Environment.TickCount64 + 8000;
            while (!condition() && Environment.TickCount64 < until && Volatile.Read(ref failure) is null) Thread.Sleep(20);
            Expect(Volatile.Read(ref failure) is null && condition(), message + ": " + failure);
        }
        viewer.Start(monitor, true);
        viewer.SetMenu(999999, new[] { new MacMenuItem(0, "File", "", true, false, false,
            new[] { new MacMenuItem(1, "Check", "", true, false, false, Array.Empty<MacMenuItem>()) }) });
        var main = new DisplayViewer.ProxyWindow(101, 999999, Rect(monitor.Left + 80, monitor.Top + 100, 640, 480),
            Rect(0, 0, 160, 96), 1920, 1080, false, "BorderlessMouse native viewer check");
        var popup = new DisplayViewer.ProxyWindow(102, main.Pid, Rect(100, 50, 80, 48), Rect(20, 10, 80, 48),
            1920, 1080, true, "Transient check");
        viewer.UpdateWindows(new[] { main, popup });
        Wait(() => viewer.Proxies.Count == 2, "native main and transient windows present decoded frames");
        var handle = viewer.Proxies.Single(p => p.Value.Id == 101).Key;
        var transient = viewer.Proxies.Single(p => p.Value.Id == 102).Key;
        Expect(((long)GetWindowLongPtrW(handle, -16) & 0x00CF0000) == 0x00CF0000,
            "proxy has a native caption, sizing frame and minimize/maximize buttons");
        Expect(GetWindow(transient, 4) == handle, "transient HWND is owned by the application HWND");
        Expect(GetMenu(handle) != IntPtr.Zero, "application commands use a native Windows menu");
        Expect(((long)GetWindowLongPtrW(transient, -20) & 0x80) != 0, "transient is a tool window without a taskbar button");
        Expect(((long)GetWindowLongPtrW(transient, -16) & 0x00C00000) == 0 && GetMenu(transient) == IntPtr.Zero,
            "a Chrome bubble has neither a caption nor a duplicate application menu");
        viewer.UpdateWindows(new[] { main });
        Wait(() => viewer.Proxies.Count == 1 && !IsWindow(transient),
            "a dismissed popup destroys its HWND and input target");
        viewer.UpdateWindows(new[] { main, popup });
        Wait(() => viewer.Proxies.Count == 2, "reopening the same source popup creates a fresh surface");
        transient = viewer.Proxies.Single(p => p.Value.Id == 102).Key;
        Expect(GetWindow(transient, 4) == handle && GetMenu(transient) == IntPtr.Zero,
            "reopened popup remains owned and frameless");
        var client = viewer.Proxies[handle].Client;
        Expect(Math.Abs(client.Width / (double)client.Height - 160.0 / 96) < 0.01,
            "rendering and input publish the same aspect-preserving rectangle");
        viewer.UpdateWindows(new[] { main, popup with { MacPixels = Rect(0, 0, 1920, 1080) } });
        Wait(() => viewer.Proxies.TryGetValue(transient, out var p) && p.MacPixels.Width == 1920
            && p.Client.Equals(viewer.Proxies[handle].Client), "fullscreen transient replaces its owner's content");
        SetWindowPos(handle, IntPtr.Zero, 30000, 30000, 640, 480, 0x0004 | SWP_NOACTIVATE);
        DisplayNative.SendMessageW(handle, 0x007E, IntPtr.Zero, IntPtr.Zero); // WM_DISPLAYCHANGE
        DisplayNative.GetWindowRect(handle, out var recovered);
        Expect(recovered.Left < 30000 && recovered.Top < 30000, "display changes recover an off-screen native caption");
        DisplayNative.SendMessageW(handle, 0x0112, 0xF030, IntPtr.Zero); // SC_MAXIMIZE
        Wait(() => !resized.IsEmpty && DisplayNative.IsZoomed(handle), "native maximize requests source reflow");
        DisplayNative.SendMessageW(handle, 0x0112, 0xF020, IntPtr.Zero); // SC_MINIMIZE
        Wait(() => viewer.Proxies.Count == 0, "minimized application and its popup stop accepting remote input");
        DisplayNative.SendMessageW(handle, 0x0112, 0xF120, IntPtr.Zero); // SC_RESTORE
        Wait(() => viewer.Proxies.Count == 2, "restoring restores the application and its owned popup");
        Console.WriteLine("✓ Native viewer: DWM caption, popup ownership, aspect mapping, maximize/minimize/restore");
    }
}
