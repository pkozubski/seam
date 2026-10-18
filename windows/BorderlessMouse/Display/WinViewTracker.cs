using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Text;
using BorderlessMouse.Input;
using BorderlessMouse.Protocol;

namespace BorderlessMouse.Display;

/// <summary>
/// Śledzi okna leżące na wirtualnym monitorze (lista dla Maca – od razu po zdarzeniu okna,
/// najwyżej co ~4 ms, plus zapasowy odczyt co ~100 ms) i kursor Windows na tym monitorze
/// (pozycja i kształt, co ~8 ms). Działa na własnym wątku z pętlą komunikatów (haki WinEvent);
/// funkcja wysyłająca musi być bezpieczna wątkowo.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class WinViewTracker : IDisposable
{
    /// <summary>Nakładki powłoki Windows, które nie są oknami aplikacji.</summary>
    private static readonly HashSet<string> IgnoredClasses = new(StringComparer.OrdinalIgnoreCase)
    {
        "Progman", "WorkerW", "Shell_TrayWnd", "Shell_SecondaryTrayWnd", "Windows.UI.Core.CoreWindow",
        "ApplicationFrameWindow_Hidden", "IME", "MSCTFIME UI",
        // Snap Layouts / Snap Assist, podgląd przyciągania, Alt+Tab, Win+Tab
        "XamlExplorerHostIslandWindow", "XamlExplorerHostIslandWindow_WASDK", "MultitaskingViewFrame",
        "TaskSwitcherWnd", "ForegroundStaging", "Shell_InputSwitchTopLevelWindow", "EdgeUiInputTopWndClass",
        "EdgeUiInputWndClass", "NativeHWNDHost", "SnapAssistFlyout", "Shell_LightDismissOverlay",
        "TaskListThumbnailWnd", "TaskListOverlayWnd", "TopLevelWindowForOverflowXamlIsland",
        "NotifyIconOverflowWindow", "Windows.Internal.Shell.TabProxyWindow", "PseudoConsoleWindow",
    };

    private const int CursorIntervalMs = 8;
    private const int FallbackIntervalMs = 100;
    private const int CoalesceMs = 4;

    private static readonly uint[] HookedEvents =
    [
        EVENT_OBJECT_LOCATIONCHANGE, EVENT_OBJECT_SHOW, EVENT_OBJECT_HIDE, EVENT_OBJECT_DESTROY, EVENT_OBJECT_NAMECHANGE,
        EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_MOVESIZESTART, EVENT_SYSTEM_MOVESIZEEND, EVENT_SYSTEM_MINIMIZESTART,
        EVENT_SYSTEM_MINIMIZEEND, EVENT_SYSTEM_MENUPOPUPSTART, EVENT_SYSTEM_MENUPOPUPEND,
    ];

    private readonly Action<byte[]> _send;
    private readonly NativeMethods.RECT _monitor;
    private readonly int _ownProcess = Environment.ProcessId;
    // Delegat musi żyć tak długo jak haki – inaczej GC zwolni go pod natywnym wywołaniem.
    private readonly WinEventProc _hookProc;
    private Thread? _thread;
    private volatile bool _running;
    private volatile bool _resend;
    private volatile bool _dirty;
    /// <summary>Prostokąty okien (współrzędne ekranu) z ostatnio wysłanej listy – do decyzji kursora.</summary>
    private volatile NativeMethods.RECT[] _rects = [];
    private IReadOnlyList<WinWindow> _lastWindows = [];
    private IReadOnlyList<(IntPtr Handle, bool Popup)> _lastHandles = [];
    private HashSet<IntPtr> _lastHandleSet = [];
    private (int x, int y, byte shape, bool visible, bool buttons)? _lastCursor;
    private readonly Dictionary<IntPtr, byte> _cursorShapes = new();

    /// <summary>
    /// Lista okien na monitorze (kolejność z, najwyższe pierwsze) po zmianie zbioru albo kolejności
    /// okien (nie przy samym przesunięciu) i po <see cref="Resend"/>. Wywoływane na wątku śledzenia.
    /// </summary>
    public event Action<IReadOnlyList<(IntPtr Handle, bool Popup)>>? WindowsChanged;

    public WinViewTracker(NativeMethods.RECT monitor, Action<byte[]> send)
    {
        _monitor = monitor;
        _send = send;
        _hookProc = OnWinEvent;
        // Kursory systemowe są współdzielone – porównujemy uchwyty (numeracja jak CURSOR_SHAPE).
        (int id, byte shape)[] cursors =
        [
            (32512, 0), (32513, 1), (32649, 2), (32644, 3), (32645, 4), (32515, 5), (32648, 6),
            (32646, 8), (32642, 9), (32643, 10), (32514, 11), (32650, 0),
        ];
        foreach (var (id, shape) in cursors)
        {
            var handle = LoadCursorW(IntPtr.Zero, (IntPtr)id);
            if (handle != IntPtr.Zero) _cursorShapes[handle] = shape;
        }
    }

    public NativeMethods.RECT Monitor => _monitor;

    /// <summary>Jakieś okno Windows jest teraz na Macu.</summary>
    public bool HasWindows => _rects.Length > 0;

    /// <summary>Czy punkt ekranu leży w którymś oknie widocznym na Macu.</summary>
    public bool WindowAt(NativeMethods.POINT point)
    {
        foreach (var r in _rects)
        {
            if (point.X >= r.Left && point.X < r.Right && point.Y >= r.Top && point.Y < r.Bottom) return true;
        }
        return false;
    }

    /// <summary>Punkt ekranu → piksel wirtualnego monitora.</summary>
    public (int x, int y) ToMonitor(NativeMethods.POINT point) => (point.X - _monitor.Left, point.Y - _monitor.Top);

    public bool Contains(NativeMethods.POINT point) =>
        point.X >= _monitor.Left && point.X < _monitor.Right && point.Y >= _monitor.Top && point.Y < _monitor.Bottom;

    /// <summary>Mac prosi o pełny stan (np. po klatce kluczowej); ponownie wysyła też <see cref="WindowsChanged"/>.</summary>
    public void Resend() => _resend = true;

    public void Start()
    {
        if (_running) return;
        _running = true;
        _resend = true;
        _thread = new Thread(Run) { IsBackground = true, Name = "blm-winview-tracker" };
        _thread.Start();
    }

    public void Stop()
    {
        _running = false;
        var thread = _thread;
        if (thread is not null && thread != Thread.CurrentThread) thread.Join(TimeSpan.FromSeconds(1));
        _thread = null;
    }

    public void Dispose() => Stop();

    private void Run()
    {
        var hooks = new List<IntPtr>();
        foreach (var e in HookedEvents)
        {
            var hook = SetWinEventHook(e, e, IntPtr.Zero, _hookProc, 0, 0, WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);
            if (hook != IntPtr.Zero) hooks.Add(hook);
        }
        // Domyślny zegar systemu (~15,6 ms) nie pozwala czekać 4–8 ms.
        var timerPeriod = timeBeginPeriod(1) == 0;
        var clock = Stopwatch.StartNew();
        long nextCursor = 0, nextPoll = 0, lastWindows = -CoalesceMs;
        try
        {
            while (_running)
            {
                try
                {
                    var now = clock.ElapsedMilliseconds;
                    if (_resend || now >= nextPoll || (_dirty && now - lastWindows >= CoalesceMs))
                    {
                        _dirty = false;
                        PollWindows();
                        lastWindows = now;
                        nextPoll = now + FallbackIntervalMs;
                    }
                    if (now >= nextCursor)
                    {
                        PollCursor();
                        nextCursor = now + CursorIntervalMs;
                    }
                    now = clock.ElapsedMilliseconds;
                    var wake = Math.Min(nextCursor, nextPoll);
                    if (_dirty) wake = Math.Min(wake, lastWindows + CoalesceMs);
                    var wait = (uint)Math.Clamp(wake - now, 0, FallbackIntervalMs);
                    DisplayNative.MsgWaitForMultipleObjectsEx(0, [], wait, DisplayNative.QS_ALLINPUT, DisplayNative.MWMO_INPUTAVAILABLE);
                    // Zdarzenia WinEvent (poza kontekstem) docierają przez kolejkę komunikatów tego wątku.
                    while (DisplayNative.PeekMessageW(out var msg, IntPtr.Zero, 0, 0, DisplayNative.PM_REMOVE))
                    {
                        DisplayNative.TranslateMessage(ref msg);
                        DisplayNative.DispatchMessageW(ref msg);
                    }
                }
                catch (Exception ex)
                {
                    // Pojedynczy nieudany odczyt nie przerywa śledzenia – i nie może zamknąć aplikacji.
                    CrashLog.Write(ex);
                    Thread.Sleep(500);
                }
            }
        }
        finally
        {
            foreach (var hook in hooks) UnhookWinEvent(hook);
            if (timerPeriod) timeEndPeriod(1);
        }
    }

    private void OnWinEvent(IntPtr hook, uint eventType, IntPtr hwnd, int idObject, int idChild, uint thread, uint time)
    {
        try
        {
            if (hwnd == IntPtr.Zero || _dirty) return;
            if (eventType >= EVENT_OBJECT_DESTROY)
            {
                // Zdarzenia obiektów: tylko same okna najwyższego poziomu (bez kursora, karetki, kontrolek).
                if (idObject != OBJID_WINDOW || idChild != CHILDID_SELF) return;
                if (eventType == EVENT_OBJECT_DESTROY || eventType == EVENT_OBJECT_HIDE)
                {
                    // zniszczone okno nie ma już przodka – liczy się, czy było na liście
                    if (!_lastHandleSet.Contains(hwnd)) return;
                }
                else if (DisplayNative.GetAncestor(hwnd, DisplayNative.GA_ROOT) != hwnd) return;
            }
            _dirty = true;
        }
        catch
        {
            // wyjątek nie może przejść przez natywne wywołanie zwrotne
        }
    }

    private void PollWindows()
    {
        var (windows, handles) = Snapshot();
        var resend = _resend;
        _resend = false;
        var orderChanged = !handles.SequenceEqual(_lastHandles);
        if (!resend && !orderChanged && windows.SequenceEqual(_lastWindows)) return;
        _lastWindows = windows;
        _rects = windows.Select(w => new NativeMethods.RECT
        {
            Left = _monitor.Left + w.X, Top = _monitor.Top + w.Y,
            Right = _monitor.Left + w.X + w.Width, Bottom = _monitor.Top + w.Y + w.Height,
        }).ToArray();
        _send(Frame.WinViewWindows(_monitor.Width, _monitor.Height, windows));
        if (orderChanged || resend)
        {
            _lastHandles = handles;
            _lastHandleSet = handles.Select(h => h.Handle).ToHashSet();
            WindowsChanged?.Invoke(handles);
        }
    }

    /// <summary>Lista okien do jednorazowego odczytu z innego wątku.</summary>
    public byte[] SnapshotPayload() => Frame.WinViewWindowsPayload(_monitor.Width, _monitor.Height, Snapshot().Windows);

    private (List<WinWindow> Windows, List<(IntPtr Handle, bool Popup)> Handles) Snapshot()
    {
        var list = new List<WinWindow>();
        var handles = new List<(IntPtr Handle, bool Popup)>();
        var foreground = GetForegroundWindow();
        var className = new StringBuilder(128);
        var title = new StringBuilder(256);
        EnumWindows((hwnd, _) =>
        {
            try
            {
                return Visit(hwnd);
            }
            catch
            {
                // wyjątek nie może przejść przez natywne wywołanie zwrotne (zamknąłby proces)
                return true;
            }
        }, IntPtr.Zero);
        return (list, handles);

        bool Visit(IntPtr hwnd)
        {
            if (list.Count >= 64) return false;
            if (!IsWindowVisible(hwnd) || IsIconic(hwnd)) return true;
            if (DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, out int cloaked, sizeof(int)) == 0 && cloaked != 0) return true;
            GetWindowThreadProcessId(hwnd, out var pid);
            if (pid == _ownProcess) return true;
            className.Clear();
            GetClassNameW(hwnd, className, className.Capacity);
            if (IgnoredClasses.Contains(className.ToString())) return true;
            if (DwmGetWindowAttribute(hwnd, DWMWA_EXTENDED_FRAME_BOUNDS, out NativeMethods.RECT bounds, Marshal.SizeOf<NativeMethods.RECT>()) != 0
                && !GetWindowRect(hwnd, out bounds)) return true;
            if (bounds.Width < 4 || bounds.Height < 4) return true;
            if (bounds.Right <= _monitor.Left || bounds.Left >= _monitor.Right || bounds.Bottom <= _monitor.Top || bounds.Top >= _monitor.Bottom) return true;
            var style = (long)GetWindowLongPtrW(hwnd, GWL_STYLE);
            var exStyle = (long)GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
            // Menu, podpowiedzi, listy rozwijane: na Macu zawsze nad oknami, bez cienia.
            var cls = className.ToString();
            var popup = cls == "#32768" || cls.Contains("tooltips", StringComparison.OrdinalIgnoreCase)
                        || ((exStyle & WS_EX_TOOLWINDOW) != 0 && (exStyle & WS_EX_APPWINDOW) == 0)
                        || ((style & WS_POPUP) != 0 && (style & (WS_CAPTION | WS_THICKFRAME)) == 0 && GetWindow(hwnd, GW_OWNER) != IntPtr.Zero);
            byte flags = 0;
            if (hwnd == foreground) flags |= WinWindow.Foreground;
            if (popup) flags |= WinWindow.Popup;
            title.Clear();
            // InternalGetWindowText nie wysyła komunikatu do aplikacji (zajęta aplikacja nas nie zablokuje).
            InternalGetWindowText(hwnd, title, title.Capacity);
            list.Add(new WinWindow(unchecked((uint)(long)hwnd), bounds.Left - _monitor.Left, bounds.Top - _monitor.Top,
                bounds.Width, bounds.Height, flags, title.ToString()));
            handles.Add((hwnd, popup));
            return true;
        }
    }

    private void PollCursor()
    {
        var info = new CURSORINFO { cbSize = Marshal.SizeOf<CURSORINFO>() };
        if (!GetCursorInfo(ref info)) return;
        var point = info.ptScreenPos;
        if (!Contains(point))
        {
            _lastCursor = null;
            return;
        }
        var shape = _cursorShapes.TryGetValue(info.hCursor, out var known) ? known : (byte)0;
        var buttons = GetAsyncKeyState(VK_LBUTTON) < 0 || GetAsyncKeyState(VK_RBUTTON) < 0 || GetAsyncKeyState(VK_MBUTTON) < 0;
        var current = (point.X - _monitor.Left, point.Y - _monitor.Top, shape, (info.flags & CURSOR_SHOWING) != 0, buttons);
        if (_lastCursor == current) return;
        _lastCursor = current;
        _send(Frame.WinViewCursor(current.Item1, current.Item2, current.shape, current.Item4, buttons));
    }

    // ---------------- Win32 ----------------

    private const int DWMWA_EXTENDED_FRAME_BOUNDS = 9;
    private const int DWMWA_CLOAKED = 14;
    private const int GWL_STYLE = -16;
    private const int GWL_EXSTYLE = -20;
    private const long WS_POPUP = 0x80000000L;
    private const long WS_CAPTION = 0x00C00000L;
    private const long WS_THICKFRAME = 0x00040000L;
    private const long WS_EX_TOOLWINDOW = 0x00000080L;
    private const long WS_EX_APPWINDOW = 0x00040000L;
    private const uint GW_OWNER = 4;
    private const int CURSOR_SHOWING = 0x00000001;
    private const uint EVENT_SYSTEM_FOREGROUND = 0x0003;
    private const uint EVENT_SYSTEM_MENUPOPUPSTART = 0x0006;
    private const uint EVENT_SYSTEM_MENUPOPUPEND = 0x0007;
    private const uint EVENT_SYSTEM_MOVESIZESTART = 0x000A;
    private const uint EVENT_SYSTEM_MOVESIZEEND = 0x000B;
    private const uint EVENT_SYSTEM_MINIMIZESTART = 0x0016;
    private const uint EVENT_SYSTEM_MINIMIZEEND = 0x0017;
    private const uint EVENT_OBJECT_DESTROY = 0x8001;
    private const uint EVENT_OBJECT_SHOW = 0x8002;
    private const uint EVENT_OBJECT_HIDE = 0x8003;
    private const uint EVENT_OBJECT_LOCATIONCHANGE = 0x800B;
    private const uint EVENT_OBJECT_NAMECHANGE = 0x800C;
    private const uint WINEVENT_OUTOFCONTEXT = 0x0000;
    private const uint WINEVENT_SKIPOWNPROCESS = 0x0002;
    private const int OBJID_WINDOW = 0;
    private const int CHILDID_SELF = 0;
    private const int VK_LBUTTON = 0x01, VK_RBUTTON = 0x02, VK_MBUTTON = 0x04;

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int key);

    private delegate void WinEventProc(IntPtr hook, uint eventType, IntPtr hwnd, int idObject, int idChild, uint thread, uint time);

    [DllImport("user32.dll")]
    private static extern IntPtr SetWinEventHook(uint eventMin, uint eventMax, IntPtr module, WinEventProc callback,
        uint processId, uint threadId, uint flags);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWinEvent(IntPtr hook);

    [DllImport("winmm.dll")]
    private static extern uint timeBeginPeriod(uint period);

    [DllImport("winmm.dll")]
    private static extern uint timeEndPeriod(uint period);

    [StructLayout(LayoutKind.Sequential)]
    private struct CURSORINFO
    {
        public int cbSize;
        public int flags;
        public IntPtr hCursor;
        public NativeMethods.POINT ptScreenPos;
    }

    private delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindowVisible(IntPtr hwnd);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsIconic(IntPtr hwnd);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern IntPtr GetWindow(IntPtr hwnd, uint command);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out int processId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassNameW(IntPtr hwnd, StringBuilder name, int capacity);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int InternalGetWindowText(IntPtr hwnd, StringBuilder text, int capacity);

    [DllImport("user32.dll")]
    private static extern IntPtr GetWindowLongPtrW(IntPtr hwnd, int index);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetWindowRect(IntPtr hwnd, out NativeMethods.RECT rect);

    [DllImport("dwmapi.dll")]
    private static extern int DwmGetWindowAttribute(IntPtr hwnd, int attribute, out NativeMethods.RECT value, int size);

    [DllImport("dwmapi.dll")]
    private static extern int DwmGetWindowAttribute(IntPtr hwnd, int attribute, out int value, int size);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetCursorInfo(ref CURSORINFO info);

    [DllImport("user32.dll")]
    private static extern IntPtr LoadCursorW(IntPtr instance, IntPtr name);
}
