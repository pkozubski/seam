using System.Buffers.Binary;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using static Seam.Input.NativeMethods;

namespace Seam.Input;

/// <summary>
/// Ukryte, natywne okno Win32 (bez Avalonii) o dwóch zadaniach:
/// 1) odbiera Raw Input myszy (WM_INPUT, RIDEV_INPUTSINK) – surowe delty ruchu,
///    niezależne od pozycji kursora i od zablokowania zdarzeń przez hook
///    (rejestrowany tylko na czas sterowania Makiem);
/// 2) jako "hider" z pustym kursorem klasy pokazuje się pod zaparkowanym kursorem,
///    żeby kursor Windows znikł podczas sterowania Makiem (technika Synergy/Barrier).
/// Musi być tworzone i używane na wątku z pętlą komunikatów (wątek UI).
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class NativeInputWindow : IDisposable
{
    private const string ClassName = "SeamInputSink";
    private const int WM_INPUT = 0x00FF;
    private const int WM_SETCURSOR = 0x0020;
    private const uint RIM_TYPEMOUSE = 0;
    private const uint RID_INPUT = 0x10000003;
    private const ushort MOUSE_MOVE_ABSOLUTE = 0x01;
    private const ushort MOUSE_VIRTUAL_DESKTOP = 0x02;

    private readonly WndProcDelegate _wndProc; // trzymany w polu – GC nie może go zebrać
    private readonly IntPtr _classNamePtr;
    private IntPtr _hwnd;
    private bool _rawRegistered;
    private bool _haveAbsolute;
    private int _lastAbsX, _lastAbsY;
    private readonly byte[] _rawBuffer = new byte[128];
    /// <summary>Rozmiar RAWINPUTHEADER liczony raz (WM_INPUT przychodzi do 8000 razy na sekundę).</summary>
    private static readonly int HeaderSize = Marshal.SizeOf<RAWINPUTHEADER>();

    /// <summary>Surowa delta ruchu myszy (wątek UI).</summary>
    public event Action<int, int>? RawMouseMove;

    /// <summary>Raw Input jest teraz zarejestrowany (InputCapture robi to tylko na czas sterowania Makiem).</summary>
    public bool IsRawInputActive => _rawRegistered;
    public bool IsCreated => _hwnd != IntPtr.Zero;

    public NativeInputWindow()
    {
        _wndProc = WndProc;
        _classNamePtr = Marshal.StringToHGlobalUni(ClassName);
        var wc = new WNDCLASSEXW
        {
            cbSize = (uint)Marshal.SizeOf<WNDCLASSEXW>(),
            lpfnWndProc = Marshal.GetFunctionPointerForDelegate(_wndProc),
            hInstance = GetModuleHandle(null),
            hCursor = IntPtr.Zero, // brak kursora = kursor znika nad tym oknem
            lpszClassName = _classNamePtr,
        };
        if (RegisterClassExW(ref wc) == 0)
        {
            var err = Marshal.GetLastWin32Error();
            if (err != 1410) throw new InvalidOperationException($"RegisterClassEx failed: {err}"); // 1410 = klasa już istnieje
        }
        _hwnd = CreateWindowExW(
            WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_LAYERED | WS_EX_NOACTIVATE,
            ClassName, "Seam", WS_POPUP,
            0, 0, 1, 1, IntPtr.Zero, IntPtr.Zero, GetModuleHandle(null), IntPtr.Zero);
        if (_hwnd == IntPtr.Zero)
        {
            throw new InvalidOperationException($"CreateWindowEx failed: {Marshal.GetLastWin32Error()}");
        }
        // praktycznie niewidoczne (alfa 1/255), ale nadal "pod kursorem" dla WM_SETCURSOR
        SetLayeredWindowAttributes(_hwnd, 0, 1, LWA_ALPHA);
    }

    // ---------------- Raw Input ----------------

    /// <summary>
    /// Sprawdza, czy Raw Input myszy działa: rejestruje i od razu wyrejestrowuje (gdy był
    /// już zarejestrowany, zostaje). Stała rejestracja budziłaby wątek UI przy każdym
    /// raporcie myszy także wtedy, gdy kursor jest lokalnie.
    /// </summary>
    public bool ProbeRawMouse()
    {
        if (_rawRegistered) return true;
        if (!RegisterRawMouse()) return false;
        UnregisterRawMouse();
        return true;
    }

    /// <summary>Rejestruje Raw Input (RIDEV_INPUTSINK). Idempotentne; true = zarejestrowany.</summary>
    public bool RegisterRawMouse()
    {
        if (_rawRegistered || _hwnd == IntPtr.Zero) return _rawRegistered;
        var rid = new RAWINPUTDEVICE { usUsagePage = 0x01, usUsage = 0x02, dwFlags = RIDEV_INPUTSINK, hwndTarget = _hwnd };
        _rawRegistered = RegisterRawInputDevices(ref rid, 1, (uint)Marshal.SizeOf<RAWINPUTDEVICE>());
        _haveAbsolute = false;
        return _rawRegistered;
    }

    /// <summary>Wyrejestrowuje Raw Input (RIDEV_REMOVE). Idempotentne.</summary>
    public void UnregisterRawMouse()
    {
        if (!_rawRegistered) return;
        var rid = new RAWINPUTDEVICE { usUsagePage = 0x01, usUsage = 0x02, dwFlags = RIDEV_REMOVE, hwndTarget = IntPtr.Zero };
        RegisterRawInputDevices(ref rid, 1, (uint)Marshal.SizeOf<RAWINPUTDEVICE>());
        _rawRegistered = false;
    }

    // ---------------- Hider ----------------

    /// <summary>Pokazuje okno-hider wycentrowane na punkcie (piksele fizyczne), bez aktywacji.</summary>
    public void ShowHiderAt(int x, int y, int size = 64)
    {
        if (_hwnd == IntPtr.Zero) return;
        SetWindowPos(_hwnd, HWND_TOPMOST, x - size / 2, y - size / 2, size, size, SWP_NOACTIVATE | SWP_SHOWWINDOW);
    }

    public void HideHider()
    {
        if (_hwnd == IntPtr.Zero) return;
        ShowWindow(_hwnd, SW_HIDE);
    }

    // ---------------- WndProc ----------------

    private IntPtr WndProc(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam)
    {
        switch (msg)
        {
            case WM_SETCURSOR:
                SetCursor(IntPtr.Zero);
                return 1;
            case WM_INPUT:
                HandleRawInput(lParam);
                break; // DefWindowProc musi zobaczyć WM_INPUT (sprzątanie)
        }
        return DefWindowProcW(hWnd, msg, wParam, lParam);
    }

    private void HandleRawInput(IntPtr hRawInput)
    {
        var size = (uint)_rawBuffer.Length;
        uint got;
        unsafe
        {
            fixed (byte* p = _rawBuffer)
            {
                got = GetRawInputData(hRawInput, RID_INPUT, (IntPtr)p, ref size, (uint)HeaderSize);
            }
        }
        if (got == unchecked((uint)-1) || got == 0) return;
        var span = _rawBuffer.AsSpan();
        var type = BinaryPrimitives.ReadUInt32LittleEndian(span);
        if (type != RIM_TYPEMOUSE) return;
        var mouse = span[HeaderSize..];
        var flags = BinaryPrimitives.ReadUInt16LittleEndian(mouse);
        var lastX = BinaryPrimitives.ReadInt32LittleEndian(mouse[12..]);
        var lastY = BinaryPrimitives.ReadInt32LittleEndian(mouse[16..]);

        int dx, dy;
        if ((flags & MOUSE_MOVE_ABSOLUTE) != 0)
        {
            // urządzenia absolutne (RDP, tablety): delta z poprzedniej pozycji
            var x = lastX;
            var y = lastY;
            if ((flags & MOUSE_VIRTUAL_DESKTOP) != 0)
            {
                x = (int)((long)lastX * GetSystemMetrics(SM_CXVIRTUALSCREEN) / 65535);
                y = (int)((long)lastY * GetSystemMetrics(SM_CYVIRTUALSCREEN) / 65535);
            }
            if (!_haveAbsolute) { _haveAbsolute = true; _lastAbsX = x; _lastAbsY = y; return; }
            dx = x - _lastAbsX;
            dy = y - _lastAbsY;
            _lastAbsX = x;
            _lastAbsY = y;
        }
        else
        {
            dx = lastX;
            dy = lastY;
        }
        if (dx != 0 || dy != 0) RawMouseMove?.Invoke(dx, dy);
    }

    public void Dispose()
    {
        UnregisterRawMouse();
        if (_hwnd != IntPtr.Zero)
        {
            DestroyWindow(_hwnd);
            _hwnd = IntPtr.Zero;
        }
        UnregisterClassW(ClassName, GetModuleHandle(null));
        Marshal.FreeHGlobal(_classNamePtr);
    }
}
