using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Security.Cryptography;
using BorderlessMouse.Protocol;
using SharpGen.Runtime;
using Vortice.Direct3D;
using Vortice.Direct3D11;
using Vortice.DXGI;
using static BorderlessMouse.Localization.L10n;
using FeatureLevel = Vortice.Direct3D.FeatureLevel;

namespace BorderlessMouse.Display;

/// <summary>
/// Strumień okien Windows z monitora wirtualnego do Maca: każde okno ma własne nagrywanie
/// (Windows.Graphics.Capture) i własny strumień H.264 (kind 2, streamID = HWND), jak w kierunku
/// Mac → Windows. Geometria okien idzie kanałem sterowania (WINVIEW_WINDOWS), nie w klatkach.
/// Zaszyfrowane rekordy jak strumień ekranu Maca. Działa na własnym wątku.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class WinViewStreamer : IDisposable
{
    private const int FramesPerSecond = 60;
    private static readonly TimeSpan FailedRetry = TimeSpan.FromSeconds(2);
    private static readonly bool IsWindows11 = Environment.OSVersion.Version.Build >= 22000;

    private readonly object _windowsLock = new();
    private readonly AutoResetEvent _wake = new(false);
    private IReadOnlyList<(IntPtr Handle, bool Popup)> _windows = [];
    private int _windowsVersion;
    private Thread? _thread;
    private volatile bool _running;
    private volatile bool _keyframeRequested;
    private TcpClient? _tcp;
    private long _framesSent;
    private long _bytesSent;
    private bool _encodersChanged; // wątek strumienia

    /// <summary>Strumień przerwany (wątek strumienia).</summary>
    public event Action<string>? Failed;

    public long FramesSent => Interlocked.Read(ref _framesSent);
    public long BytesSent => Interlocked.Read(ref _bytesSent);
    /// <summary>true = co najmniej jedno okno kodowane sprzętowo.</summary>
    public bool UsesGpu { get; private set; }

    /// <summary>Okna najwyższego poziomu na monitorze wirtualnym (od góry kolejności Z). Dowolny wątek.</summary>
    public void UpdateWindows(IReadOnlyList<(IntPtr Handle, bool Popup)> windows)
    {
        var copy = windows.ToArray();
        lock (_windowsLock)
        {
            _windows = copy;
            _windowsVersion++;
        }
        _wake.Set();
    }

    public void Start(string gdiDeviceName, IPAddress mac, int port, byte[] key, byte[] token)
    {
        Stop();
        if (key.Length != VideoStream.KeyBytes || token.Length != VideoStream.TokenBytes)
            throw new ArgumentException(T("Nieprawidłowe klucze strumienia okien.", "Invalid window stream keys."));
        var keyCopy = key.ToArray();
        var tokenCopy = token.ToArray();
        Interlocked.Exchange(ref _framesSent, 0);
        Interlocked.Exchange(ref _bytesSent, 0);
        _running = true;
        _keyframeRequested = false;
        _thread = new Thread(() => Run(gdiDeviceName, mac, port, keyCopy, tokenCopy))
        {
            IsBackground = true,
            Name = "blm-winview-tx",
            Priority = ThreadPriority.AboveNormal,
        };
        _thread.Start();
    }

    public void RequestKeyframe()
    {
        _keyframeRequested = true;
        _wake.Set();
    }

    public void Stop()
    {
        _running = false;
        _wake.Set();
        try { _tcp?.Close(); } catch { /* ignore */ }
        var thread = _thread;
        if (thread is not null && thread != Thread.CurrentThread) thread.Join(TimeSpan.FromSeconds(3));
        _thread = null;
    }

    public void Dispose() => Stop();

    /// <summary>Nagrywanie i koder jednego okna.</summary>
    private sealed class Session(IntPtr handle, WindowCapture capture) : IDisposable
    {
        public IntPtr Handle { get; } = handle;
        public WindowCapture Capture { get; } = capture;
        public HardwareH264Encoder? Hw;
        public H264Encoder? Sw;
        public byte[]? Nv12Cpu;
        public bool NeedKeyframe = true;
        public bool HasFrame;
        public bool HasCpuFrame;
        public bool Popup;
        public int EncWidth, EncHeight;

        public void DisposeEncoder()
        {
            Hw?.Dispose(); Hw = null;
            Sw?.Dispose(); Sw = null;
            Nv12Cpu = null;
            HasCpuFrame = false;
            EncWidth = EncHeight = 0;
        }

        public void Dispose()
        {
            DisposeEncoder();
            Capture.Dispose();
        }
    }

    private void Run(string deviceName, IPAddress mac, int port, byte[] key, byte[] token)
    {
        string? failure = null;
        var sessions = new Dictionary<IntPtr, Session>();
        ID3D11Device? device = null;
        TcpClient? tcp = null;
        NetworkStream? stream = null;
        VideoStream.Sealer? sealer = null;
        var timerPeriod = false;
        try
        {
            tcp = new TcpClient(mac.AddressFamily) { NoDelay = true, SendBufferSize = 4 * 1024 * 1024 };
            _tcp = tcp;
            if (!tcp.ConnectAsync(mac, port).Wait(TimeSpan.FromSeconds(4)))
                throw new IOException(T("Mac nie przyjął połączenia strumienia okien.", "The Mac did not accept the window stream connection."));
            tcp.Client.SendTimeout = 5000;
            stream = tcp.GetStream();
            stream.Write(token);
            sealer = new VideoStream.Sealer(key);
            device = CreateDevice(deviceName);
            if (!WindowCapture.IsSupported)
            {
                failure = T("Ten system nie obsługuje nagrywania pojedynczych okien (Windows.Graphics.Capture).",
                    "This system does not support capturing individual windows (Windows.Graphics.Capture).");
            }
            else
            {
                // Bez tego Sleep/Wait(1) śpi ~15 ms i 60 kl./s jest nieosiągalne.
                timerPeriod = timeBeginPeriod(1) == 0;
                Loop(device, sessions, stream, sealer);
            }
        }
        catch (Exception ex) when (ex is IOException or SocketException or ObjectDisposedException or AggregateException
                                       or SharpGenException or InvalidOperationException or COMException)
        {
            if (_running) failure = T("Strumień okien: ", "Window stream: ") + (ex.InnerException ?? ex).Message;
        }
        catch (Exception ex)
        {
            // Nieoczekiwany błąd kończy strumień (z opisem w Dzienniku), a nie całą aplikację.
            CrashLog.Write(ex);
            if (_running) failure = T("Strumień okien – nieoczekiwany błąd: ", "Window stream — unexpected error: ") + ex.GetType().Name + ": " + ex.Message;
        }
        finally
        {
            if (timerPeriod) timeEndPeriod(1);
            foreach (var session in sessions.Values) session.DisposeEncoder();
            foreach (var session in sessions.Values) session.Capture.Dispose();
            sessions.Clear();
            device?.Dispose();
            sealer?.Dispose();
            stream?.Dispose();
            tcp?.Dispose();
            CryptographicOperations.ZeroMemory(key);
            CryptographicOperations.ZeroMemory(token);
            _tcp = null;
        }
        if (_running)
        {
            _running = false;
            Failed?.Invoke(failure ?? T("Strumień okien zakończony.", "The window stream ended."));
        }
    }

    private void Loop(ID3D11Device device, Dictionary<IntPtr, Session> sessions, NetworkStream stream, VideoStream.Sealer sealer)
    {
        var failed = new Dictionary<IntPtr, TimeSpan>();
        var clock = Stopwatch.StartNew();
        var seenVersion = -1;
        var lastSync = TimeSpan.Zero;
        while (_running)
        {
            var now = clock.Elapsed;
            int version;
            IReadOnlyList<(IntPtr Handle, bool Popup)> windows;
            lock (_windowsLock)
            {
                version = _windowsVersion;
                windows = _windows;
            }
            // Ponowna próba okien odrzuconych przez WGC – najwyżej co 2 s.
            if (version != seenVersion || (failed.Count > 0 && now - lastSync >= FailedRetry))
            {
                seenVersion = version;
                lastSync = now;
                SyncSessions(device, sessions, failed, windows, now);
                _encodersChanged = true;
            }

            if (_keyframeRequested)
            {
                _keyframeRequested = false;
                foreach (var session in sessions.Values) session.NeedKeyframe = true;
            }

            var sent = false;
            List<IntPtr>? closed = null;
            foreach (var session in sessions.Values)
            {
                if (!_running) return;
                bool fresh;
                try
                {
                    if (session.Capture.Closed)
                    {
                        (closed ??= []).Add(session.Handle);
                        failed[session.Handle] = now;
                        continue;
                    }
                    fresh = session.Capture.TryGetFrame();
                }
                catch (Exception ex) when (ex is SharpGenException or COMException or InvalidOperationException or ObjectDisposedException)
                {
                    // Okno zniknęło w trakcie – zamykamy tylko jego sesję.
                    (closed ??= []).Add(session.Handle);
                    failed[session.Handle] = now;
                    continue;
                }
                if (fresh) session.HasFrame = true;
                // Prośba o klatkę kluczową przy nieruchomym oknie: kodujemy ostatni obraz jeszcze raz.
                if (!fresh && !(session.NeedKeyframe && session.HasFrame)) continue;
                if (SendFrame(device, session, fresh, clock, stream, sealer)) sent = true;
            }
            if (closed is not null)
            {
                foreach (var handle in closed)
                {
                    if (!sessions.Remove(handle, out var session)) continue;
                    session.Dispose();
                }
            }
            if (closed is not null || _encodersChanged) RefreshUsesGpu(sessions);
            if (!sent && _running) _wake.WaitOne(2);
        }
    }

    private static void SyncSessions(ID3D11Device device, Dictionary<IntPtr, Session> sessions, Dictionary<IntPtr, TimeSpan> failed,
        IReadOnlyList<(IntPtr Handle, bool Popup)> windows, TimeSpan now)
    {
        var wanted = new Dictionary<IntPtr, bool>(windows.Count);
        foreach (var (handle, popup) in windows) wanted[handle] = popup;

        foreach (var handle in sessions.Keys.Where(h => !wanted.ContainsKey(h)).ToList())
        {
            sessions[handle].Dispose();
            sessions.Remove(handle);
        }
        foreach (var handle in failed.Keys.Where(h => !wanted.ContainsKey(h)).ToList()) failed.Remove(handle);

        foreach (var (handle, popup) in wanted)
        {
            if (sessions.TryGetValue(handle, out var existing))
            {
                existing.Popup = popup;
                continue;
            }
            if (failed.TryGetValue(handle, out var since) && now - since < FailedRetry) continue;
            try
            {
                sessions[handle] = new Session(handle, new WindowCapture(device, handle)) { Popup = popup };
                failed.Remove(handle);
            }
            catch (Exception)
            {
                // WGC nie nagrywa części okien (menu, podpowiedzi) – pomijamy je.
                failed[handle] = now;
            }
        }
    }

    /// <summary>Koduje i wysyła klatkę okna; true = coś wysłano.</summary>
    private bool SendFrame(ID3D11Device device, Session session, bool fresh, Stopwatch clock, NetworkStream stream, VideoStream.Sealer sealer)
    {
        var capture = session.Capture;
        if (capture.Width <= 0 || capture.Height <= 0 || capture.ContentWidth <= 0 || capture.ContentHeight <= 0) return false;
        if (session.EncWidth != capture.Width || session.EncHeight != capture.Height)
            CreateEncoder(device, session, preferHardware: true);

        var now = clock.Elapsed;
        var force = session.NeedKeyframe;
        (byte[] AnnexB, bool Keyframe)? encoded = null;
        if (session.Hw is not null)
        {
            if (capture.Nv12Texture is not { } texture) return false;
            try
            {
                encoded = session.Hw.Encode(texture, now.Ticks, force);
            }
            catch (Exception ex) when (ex is SharpGenException or COMException or InvalidOperationException)
            {
                // Koder sprzętowy zawiódł – to okno przechodzi na koder programowy.
                CreateEncoder(device, session, preferHardware: false);
                force = true;
            }
        }
        if (session.Sw is not null)
        {
            // Po zmianie kodera bufor CPU jest pusty – trzeba go wypełnić także dla starej klatki.
            if ((fresh || !session.HasCpuFrame) && !capture.ReadNv12(session.Nv12Cpu!)) return false;
            session.HasCpuFrame = true;
            encoded = session.Sw.Encode(session.Nv12Cpu!, now.Ticks, force);
        }
        // Wymuszenie zostało przekazane koderowi – nawet gdy ten oddaje klatkę z opóźnieniem,
        // nie kodujemy tego samego obrazu w kółko.
        session.NeedKeyframe = false;
        if (encoded is not { } frame) return false;

        var clear = VideoStream.EncodeWindowFrame(frame.Keyframe, capture.ContentWidth, capture.ContentHeight, (ulong)(now.Ticks / 10),
            (uint)(long)session.Handle, CornerRadius(session), frame.AnnexB);
        var record = sealer.Seal(clear);
        stream.Write(record);
        Interlocked.Increment(ref _framesSent);
        Interlocked.Add(ref _bytesSent, record.Length);
        return true;
    }

    private void CreateEncoder(ID3D11Device device, Session session, bool preferHardware)
    {
        var capture = session.Capture;
        session.DisposeEncoder();
        // ~0,12 bita na piksel przy 60 kl./s, w granicach 3–40 Mb/s.
        var bits = (double)capture.ContentWidth * capture.ContentHeight * FramesPerSecond * 0.12;
        var kbps = (int)Math.Clamp(bits / 1000, 3_000, 40_000);
        // Brak sprzętu albo limit sesji kodera (NVIDIA ~8) – koder programowy dla tego okna.
        session.Hw = preferHardware ? HardwareH264Encoder.TryCreate(device, capture.Width, capture.Height, FramesPerSecond, kbps) : null;
        if (session.Hw is null)
        {
            session.Sw = new H264Encoder(capture.Width, capture.Height, FramesPerSecond, kbps);
            session.Nv12Cpu = new byte[capture.Width * capture.Height * 3 / 2];
        }
        session.EncWidth = capture.Width;
        session.EncHeight = capture.Height;
        session.NeedKeyframe = true;
        _encodersChanged = true;
    }

    private void RefreshUsesGpu(Dictionary<IntPtr, Session> sessions)
    {
        _encodersChanged = false;
        if (sessions.Count > 0) UsesGpu = sessions.Values.Any(s => s.Hw is not null);
    }

    /// <summary>Zaokrąglenie rogów jak w Windows 11 (8 px przy 96 DPI); menu, okna zmaksymalizowane i Windows 10 – 0.</summary>
    private static ushort CornerRadius(Session session)
    {
        if (!IsWindows11 || session.Popup || DisplayNative.IsZoomed(session.Handle)) return 0;
        var dpi = DisplayNative.GetDpiForWindow(session.Handle);
        if (dpi == 0) dpi = 96;
        return (ushort)(8 * dpi / 96);
    }

    /// <summary>Urządzenie D3D11 na karcie, do której należy monitor wirtualny.</summary>
    private static ID3D11Device CreateDevice(string deviceName)
    {
        using var factory = DXGI.CreateDXGIFactory1<IDXGIFactory1>();
        for (uint a = 0; factory.EnumAdapters1(a, out var adapter).Success; a++)
        {
            using (adapter)
            {
                for (uint o = 0; adapter.EnumOutputs(o, out var output).Success; o++)
                {
                    using (output)
                    {
                        if (!string.Equals(output.Description.DeviceName, deviceName, StringComparison.OrdinalIgnoreCase)) continue;
                        var levels = new[] { FeatureLevel.Level_11_1, FeatureLevel.Level_11_0, FeatureLevel.Level_10_1 };
                        D3D11.D3D11CreateDevice(adapter, DriverType.Unknown, DeviceCreationFlags.BgraSupport | DeviceCreationFlags.VideoSupport,
                            levels, out ID3D11Device device, out ID3D11DeviceContext context).CheckError();
                        context.Dispose();
                        try
                        {
                            // Urządzenie dzielą WGC (wątek puli), procesor wideo i kodery.
                            using var multithread = device.QueryInterface<ID3D11Multithread>();
                            multithread.SetMultithreadProtected(true);
                        }
                        catch
                        {
                            device.Dispose();
                            throw;
                        }
                        return device;
                    }
                }
            }
        }
        throw new InvalidOperationException(T("Nie znaleziono monitora wirtualnego w DXGI.", "The virtual monitor was not found in DXGI."));
    }

    [DllImport("winmm.dll")]
    private static extern uint timeBeginPeriod(uint period);

    [DllImport("winmm.dll")]
    private static extern uint timeEndPeriod(uint period);
}

/// <summary>BGRA (pełny zakres) → NV12 BT.709, zakres wideo 16–235, na CPU.</summary>
public static class Nv12Converter
{
    public static unsafe void FromBgra(byte[] source, int pitch, int width, int height, byte[] nv12)
    {
        if (source.Length < pitch * height || nv12.Length < width * height * 3 / 2 || width % 2 != 0 || height % 2 != 0)
            throw new ArgumentException("Invalid BGRA or NV12 buffer size.");
        fixed (byte* pointer = source) FromBgra(pointer, pitch, width, height, nv12);
    }

    public static unsafe void FromBgra(byte* source, int pitch, int width, int height, byte[] nv12)
    {
        fixed (byte* target = nv12)
        {
            var chroma = target + (long)width * height;
            for (var y = 0; y < height; y++)
            {
                var row = source + (long)y * pitch;
                var luma = target + (long)y * width;
                for (var x = 0; x < width; x++)
                {
                    int b = row[x * 4], g = row[x * 4 + 1], r = row[x * 4 + 2];
                    luma[x] = (byte)(16 + ((47 * r + 157 * g + 16 * b + 128) >> 8));
                }
                if ((y & 1) != 0) continue;
                var next = y + 1 < height ? row + pitch : row;
                var uv = chroma + (long)(y / 2) * width;
                for (var x = 0; x < width; x += 2)
                {
                    // Średnia z bloku 2×2.
                    int b = row[x * 4] + row[x * 4 + 4] + next[x * 4] + next[x * 4 + 4];
                    int g = row[x * 4 + 1] + row[x * 4 + 5] + next[x * 4 + 1] + next[x * 4 + 5];
                    int r = row[x * 4 + 2] + row[x * 4 + 6] + next[x * 4 + 2] + next[x * 4 + 6];
                    uv[x] = (byte)Math.Clamp(128 + ((-26 * r - 86 * g + 112 * b + 512) >> 10), 16, 240);
                    uv[x + 1] = (byte)Math.Clamp(128 + ((112 * r - 102 * g - 10 * b + 512) >> 10), 16, 240);
                }
            }
        }
    }
}
