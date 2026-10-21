using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Text;

namespace Seam.Display;

/// <summary>
/// Aplikacje, których okna są na Macu: nazwa i ikona dla Docka (WINVIEW_APP) oraz aktywacja
/// i zamykanie okien na prośbę Maca (WINVIEW_ACTIVATE, WINVIEW_CLOSE).
/// </summary>
[SupportedOSPlatform("windows")]
public static class WinApps
{
    public readonly record struct AppInfo(string Name, string Key, byte[] Icon);

    private const int IconSize = 256;
    private static readonly Dictionary<string, AppInfo> Cache = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>Nazwa (opis pliku exe), klucz (nazwa exe bez rozszerzenia) i ikona PNG procesu.</summary>
    public static AppInfo Describe(int pid)
    {
        var path = ImagePath(pid);
        if (path is null) return new AppInfo("Windows", $"pid{pid}", []);
        lock (Cache)
        {
            if (Cache.TryGetValue(path, out var cached)) return cached;
        }
        var key = Path.GetFileNameWithoutExtension(path);
        var name = key;
        try
        {
            var version = FileVersionInfo.GetVersionInfo(path);
            var description = version.FileDescription?.Trim();
            var product = version.ProductName?.Trim();
            if (!string.IsNullOrEmpty(description)) name = description;
            else if (!string.IsNullOrEmpty(product)) name = product;
        }
        catch (Exception)
        {
            // bez zasobu wersji zostaje nazwa pliku
        }
        if (name == key && name.Length > 0) name = char.ToUpperInvariant(name[0]) + name[1..];
        byte[] icon;
        try { icon = ExtractIcon(path); }
        catch (Exception) { icon = []; }
        var info = new AppInfo(name, key, icon);
        lock (Cache) Cache[path] = info;
        return info;
    }

    /// <summary>Okna aplikacji UWP należą do ApplicationFrameHost – liczy się proces okna w środku.</summary>
    public static int FramedProcess(IntPtr frame, int framePid)
    {
        var child = IntPtr.Zero;
        while ((child = FindWindowExW(frame, child, "Windows.UI.Core.CoreWindow", null)) != IntPtr.Zero)
        {
            GetWindowThreadProcessId(child, out var pid);
            if (pid != 0 && pid != framePid) return pid;
        }
        return framePid;
    }

    private static string? ImagePath(int pid)
    {
        var process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
        if (process == IntPtr.Zero) return null;
        try
        {
            var buffer = new StringBuilder(1024);
            var size = buffer.Capacity;
            return QueryFullProcessImageNameW(process, 0, buffer, ref size) ? buffer.ToString(0, size) : null;
        }
        finally { CloseHandle(process); }
    }

    private static byte[] ExtractIcon(string path)
    {
        if (SHDefExtractIconW(path, 0, 0, out var large, out var small, (16u << 16) | IconSize) != 0 || large == IntPtr.Zero)
        {
            if (small != IntPtr.Zero) DestroyIcon(small);
            return [];
        }
        try { return IconToPng(large); }
        finally
        {
            DestroyIcon(large);
            if (small != IntPtr.Zero) DestroyIcon(small);
        }
    }

    private static byte[] IconToPng(IntPtr icon)
    {
        if (!GetIconInfo(icon, out var info)) return [];
        try
        {
            if (info.hbmColor == IntPtr.Zero || GetObjectW(info.hbmColor, Marshal.SizeOf<BITMAP>(), out var bitmap) == 0) return [];
            int width = bitmap.bmWidth, height = bitmap.bmHeight;
            if (width <= 0 || height <= 0 || width > 1024 || height > 1024) return [];
            var pixels = ReadBits(info.hbmColor, width, height);
            if (pixels is null) return [];
            var hasAlpha = false;
            for (var i = 3; i < pixels.Length; i += 4) if (pixels[i] != 0) { hasAlpha = true; break; }
            if (!hasAlpha)
            {
                // Stare ikony bez kanału alfa: przezroczystość z maski (czarny = widoczny).
                var mask = info.hbmMask != IntPtr.Zero ? ReadBits(info.hbmMask, width, height) : null;
                for (var i = 0; i < pixels.Length; i += 4) pixels[i + 3] = mask is null || mask[i] == 0 ? (byte)255 : (byte)0;
            }
            return PngEncoder.EncodeBgra(width, height, pixels);
        }
        finally
        {
            if (info.hbmColor != IntPtr.Zero) DeleteObject(info.hbmColor);
            if (info.hbmMask != IntPtr.Zero) DeleteObject(info.hbmMask);
        }
    }

    /// <summary>Piksele BGRA od górnego wiersza.</summary>
    private static byte[]? ReadBits(IntPtr bitmap, int width, int height)
    {
        var header = new BITMAPINFOHEADER
        {
            biSize = Marshal.SizeOf<BITMAPINFOHEADER>(), biWidth = width, biHeight = -height, biPlanes = 1, biBitCount = 32,
        };
        var pixels = new byte[width * height * 4];
        var dc = GetDC(IntPtr.Zero);
        try { return GetDIBits(dc, bitmap, 0, (uint)height, pixels, ref header, 0) == height ? pixels : null; }
        finally { ReleaseDC(IntPtr.Zero, dc); }
    }

    /// <summary>Uchwyt okna z numeru na liście (HWND ma znaczące 32 bity, rozszerzane znakiem).</summary>
    public static IntPtr Handle(uint id) => new(unchecked((int)id));

    /// <summary>Okno wybrane na Macu (Dock, Cmd+Tab) staje się aktywnym oknem Windows.</summary>
    public static void Activate(IntPtr hwnd)
    {
        if (!IsWindow(hwnd)) return;
        if (IsIconic(hwnd)) ShowWindow(hwnd, SW_RESTORE);
        if (SetForegroundWindow(hwnd) && GetForegroundWindow() == hwnd) return;
        // Seam nie jest teraz aktywny: na chwilę dzielimy kolejkę wejścia z aktywnym wątkiem.
        var current = GetCurrentThreadId();
        var foreground = GetWindowThreadProcessId(GetForegroundWindow(), out _);
        var attached = foreground != 0 && foreground != current && AttachThreadInput(current, foreground, true);
        try
        {
            BringWindowToTop(hwnd);
            SetForegroundWindow(hwnd);
        }
        finally
        {
            if (attached) AttachThreadInput(current, foreground, false);
        }
        if (GetForegroundWindow() != hwnd) SwitchToThisWindow(hwnd, true);
    }

    /// <summary>„Zakończ” na Macu: zamknięcie jak przyciskiem × (aplikacja może zapytać o zapis).</summary>
    public static void Close(IntPtr hwnd)
    {
        if (IsWindow(hwnd)) PostMessageW(hwnd, WM_SYSCOMMAND, SC_CLOSE, IntPtr.Zero);
    }

    // ---------------- Win32 ----------------

    private const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
    private const int SW_RESTORE = 9;
    private const uint WM_SYSCOMMAND = 0x0112;
    private static readonly IntPtr SC_CLOSE = 0xF060;

    [StructLayout(LayoutKind.Sequential)]
    private struct ICONINFO
    {
        [MarshalAs(UnmanagedType.Bool)] public bool fIcon;
        public int xHotspot;
        public int yHotspot;
        public IntPtr hbmMask;
        public IntPtr hbmColor;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct BITMAP
    {
        public int bmType;
        public int bmWidth;
        public int bmHeight;
        public int bmWidthBytes;
        public ushort bmPlanes;
        public ushort bmBitsPixel;
        public IntPtr bmBits;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct BITMAPINFOHEADER
    {
        public int biSize;
        public int biWidth;
        public int biHeight;
        public ushort biPlanes;
        public ushort biBitCount;
        public uint biCompression;
        public uint biSizeImage;
        public int biXPelsPerMeter;
        public int biYPelsPerMeter;
        public uint biClrUsed;
        public uint biClrImportant;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(uint access, [MarshalAs(UnmanagedType.Bool)] bool inherit, int pid);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool QueryFullProcessImageNameW(IntPtr process, int flags, StringBuilder name, ref int size);

    [DllImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseHandle(IntPtr handle);

    [DllImport("kernel32.dll")]
    private static extern uint GetCurrentThreadId();

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SHDefExtractIconW(string path, int index, uint flags, out IntPtr large, out IntPtr small, uint sizes);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyIcon(IntPtr icon);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetIconInfo(IntPtr icon, out ICONINFO info);

    [DllImport("gdi32.dll", EntryPoint = "GetObjectW")]
    private static extern int GetObjectW(IntPtr handle, int size, out BITMAP bitmap);

    [DllImport("gdi32.dll")]
    private static extern int GetDIBits(IntPtr dc, IntPtr bitmap, uint start, uint lines, [Out] byte[] bits, ref BITMAPINFOHEADER info, uint usage);

    [DllImport("gdi32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DeleteObject(IntPtr handle);

    [DllImport("user32.dll")]
    private static extern IntPtr GetDC(IntPtr hwnd);

    [DllImport("user32.dll")]
    private static extern int ReleaseDC(IntPtr hwnd, IntPtr dc);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr FindWindowExW(IntPtr parent, IntPtr after, string? className, string? title);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out int processId);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindow(IntPtr hwnd);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsIconic(IntPtr hwnd);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ShowWindow(IntPtr hwnd, int command);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetForegroundWindow(IntPtr hwnd);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool BringWindowToTop(IntPtr hwnd);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool AttachThreadInput(uint attach, uint attachTo, [MarshalAs(UnmanagedType.Bool)] bool attachFlag);

    [DllImport("user32.dll")]
    private static extern void SwitchToThisWindow(IntPtr hwnd, [MarshalAs(UnmanagedType.Bool)] bool altTab);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool PostMessageW(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);
}
