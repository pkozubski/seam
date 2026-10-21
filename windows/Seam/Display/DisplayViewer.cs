using System.Collections.Concurrent;
using System.Numerics;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using Seam.Protocol;
using SharpGen.Runtime;
using Vortice;
using Vortice.DCommon;
using Vortice.Direct2D1;
using Vortice.Direct3D;
using Vortice.Direct3D11;
using Vortice.DirectComposition;
using Vortice.DirectWrite;
using Vortice.DXGI;
using Vortice.Mathematics;
using Vortice.MediaFoundation;
using static Seam.Display.DisplayNative;
using static Seam.Input.NativeMethods;
using static Seam.Localization.L10n;
using AlphaMode = Vortice.DXGI.AlphaMode;
using FeatureLevel = Vortice.Direct3D.FeatureLevel;
using FactoryType = Vortice.Direct2D1.FactoryType;
using PixelFormat = Vortice.DCommon.PixelFormat;
using BitmapInterpolationMode = Vortice.Direct2D1.BitmapInterpolationMode;

namespace Seam.Display;

/// <summary>
/// Obraz z Maca na Windowsie. Dwa tryby:
/// <list type="bullet">
/// <item>pełny pulpit – jedno okno na cały monitor ze strumieniem całego ekranu wirtualnego;</item>
/// <item>tryb okien – natywna ramka Windows z tłem Mica; tytuł i menu aplikacji Maca leżą w pasku
/// tytułu obok systemowych przycisków, a pod nim obraz okna Maca.
/// Popupy są oknami należącymi do aplikacji, bez osobnych pozycji w Alt+Tab.</item>
/// </list>
/// Dekodowanie (Media Foundation) i konwersja NV12 → RGB (procesor wideo D3D11) są wspólne.
/// Obraz i pasek tytułu składa DirectComposition/Direct2D; ramkę, przyciski i Snap obsługuje DWM.
/// Wszystko działa na jednym wątku.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class DisplayViewer : IDisposable
{
    /// <summary>
    /// Okno Maca: <paramref name="MacScreen"/> – jego miejsce przeliczone na ekran Windows
    /// (tam powstaje nowe okno), <paramref name="MacPixels"/> – położenie na ekranie wirtualnym.
    /// </summary>
    public sealed record ProxyWindow(uint Id, int Pid, RECT MacScreen, RECT MacPixels, int DisplayWidth, int DisplayHeight,
        bool Popup, string Title);

    /// <summary>
    /// Okno Windows reprezentujące okno Maca (do przeliczania kursora w hookach):
    /// obszar obrazu na ekranie Windows i odpowiadające mu okno na ekranie wirtualnym.
    /// </summary>
    public readonly record struct ProxyInfo(uint Id, int Pid, bool Popup, RECT Client, RECT MacPixels, int DisplayWidth, int DisplayHeight);

    private const string ClassName = "SeamDisplay";
    private const uint FullscreenId = 0;
    /// <summary>Tyle klatek w kolejce oznacza, że dekoder nie nadąża – odrzucamy i prosimy o klatki kluczowe.</summary>
    private const int MaxQueuedFrames = 48;
    private const uint INFINITE = 0xFFFFFFFF;
    /// <summary>Ponowienie <see cref="FollowSource"/>, dopóki rozmiar czeka na koniec lokalnej zmiany.</summary>
    private const uint PendingRetryMs = 100;
    private const uint WM_MOVE = 0x0003, WM_SIZE = 0x0005, WM_ACTIVATE = 0x0006;
    private const uint WM_ERASEBKGND = 0x0014, WM_SETICON = 0x0080, WM_TIMER = 0x0113;
    private const uint WM_CANCELMODE = 0x001F, WM_ENTERSIZEMOVE = 0x0231, WM_EXITSIZEMOVE = 0x0232;
    private const uint WM_ENTERMENULOOP = 0x0211, WM_EXITMENULOOP = 0x0212;
    private const uint WM_DPICHANGED = 0x02E0, WM_DISPLAYCHANGE = 0x007E, WM_MOVING = 0x0216;
    private const uint WM_SYSCOMMAND = 0x0112, WM_NCCALCSIZE = 0x0083, WM_NCHITTEST = 0x0084;
    private const uint WM_MOUSEMOVE = 0x0200, WM_LBUTTONDOWN = 0x0201, WM_MOUSELEAVE = 0x02A3;
    private const long SC_KEYMENU = 0xF100;
    private const long SIZE_MINIMIZED = 1;
    private const int HTCLIENT = 1, HTCAPTION = 2, HTTOP = 12;
    private const int SM_CYSIZEFRAME = 33, SM_CXPADDEDBORDER = 92;
    private const uint DWMWA_CAPTION_BUTTON_BOUNDS = 5, DWMWA_SYSTEMBACKDROP_TYPE = 38, DWMWA_MICA_EFFECT = 1029;
    private const uint TPM_RETURNCMD = 0x0100;
    private const uint WS_OVERLAPPEDWINDOW = 0x00CF0000;
    private const uint WS_EX_APPWINDOW = 0x00040000, WS_EX_NOREDIRECTIONBITMAP = 0x00200000;
    private const uint SWP_NOSIZE = 0x0001, SWP_NOMOVE = 0x0002, SWP_NOZORDER = 0x0004, SWP_FRAMECHANGED = 0x0020;
    private static readonly Color4 Background = new(41 / 255f, 41 / 255f, 43 / 255f, 1);
    // Pasek tytułu na ciemnej Mice – kolory tekstu i wypełnień jak w Windows 11 (WinUI).
    private static readonly Color4 HeaderText = new(1, 1, 1, 1);
    private static readonly Color4 HeaderInactiveText = new(1, 1, 1, 0.5f);
    private static readonly Color4 HeaderDisabledText = new(1, 1, 1, 0.36f);
    private static readonly Color4 HeaderHover = new(1, 1, 1, 0.06f);
    private static readonly Color4 HeaderOpen = new(1, 1, 1, 0.09f);

    /// <summary>Kształty kursora z Maca (CursorTracker.Shape) → kursory systemowe Windows.</summary>
    private static readonly int[] CursorIds = { 32512, 32513, 32649, 32644, 32645, 32515, 32648, 32649, 32646, 32642, 32643, 32514 };

    private readonly VideoFrameQueue _frames = new(MaxQueuedFrames);
    private readonly ConcurrentQueue<Action> _commands = new();
    private readonly AutoResetEvent _wake = new(false);
    private readonly WndProcDelegate _wndProc;
    private Thread? _thread;
    private volatile bool _running;
    private long _framesPresented;
    private long _lastKeyframeRequestTicks;
    private volatile uint _movingWindowId;
    private IntPtr _movingHandle;
    private volatile bool _menuLoopActive;
    private volatile bool _hasWindows;
    private volatile IReadOnlyDictionary<IntPtr, ProxyInfo> _proxies = new Dictionary<IntPtr, ProxyInfo>();

    // tylko wątek wyświetlania
    private RECT _monitor;
    private bool _windowMode;
    private bool _wantFullscreenVisible;
    private int _cursorShape;
    private ID3D11Device? _device;
    private ID3D11DeviceContext? _context;
    private ID3D11VideoDevice? _videoDevice;
    private ID3D11VideoContext? _videoContext;
    private IDXGIFactory2? _factory;
    private ID2D1Factory1? _d2dFactory;
    private ID2D1Device? _d2dDevice;
    private ID2D1DeviceContext? _d2d;
    private IDCompositionDevice? _composition;
    private IDWriteFactory? _dwrite;
    private readonly Dictionary<uint, Surface> _surfaces = new();
    private readonly Dictionary<IntPtr, Surface> _byHandle = new();
    private readonly Dictionary<int, IntPtr> _icons = new();
    private readonly Dictionary<int, IReadOnlyList<MacMenuItem>> _menus = new();
    // Bufory DecodePending używane w każdym obiegu; czyszczone po nim.
    private readonly List<VideoStream.VideoFrame> _batch = new();
    private readonly Dictionary<uint, int> _lastIndex = new();
    private bool _decoding;

    /// <summary>Błąd, po którym podgląd nie działa (wątek wyświetlania).</summary>
    public event Action<string>? Failed;
    /// <summary>Strumień potrzebuje klatki kluczowej; null = wszystkie.</summary>
    public event Action<uint?>? KeyframeNeeded;
    /// <summary>Okno Maca aktywowane (true) albo dezaktywowane na Windowsie.</summary>
    public event Action<uint, bool>? WindowActivated;
    /// <summary>Przycisk zamknięcia, Alt+F4, zamknięcie z paska zadań.</summary>
    public event Action<uint>? CloseRequested;
    /// <summary>Maksymalizacja lub przywrócenie – nowy rozmiar obrazu okna w pikselach Windows.</summary>
    public event Action<uint, int, int>? ResizeRequested;
    /// <summary>Wybrano pozycję menu aplikacji (pid, numer pozycji).</summary>
    public event Action<int, int>? MenuInvoked;
    /// <summary>Menu jest rozwijane – warto odświeżyć je z Maca (wyszarzenia, zaznaczenia).</summary>
    public event Action<int>? MenuOpening;

    public long FramesPresented => Interlocked.Read(ref _framesPresented);
    public bool UsesGpuDecoding { get; private set; }

    /// <summary>Okna Windows reprezentujące okna Maca – bezpieczne do odczytu z dowolnego wątku.</summary>
    public IReadOnlyDictionary<IntPtr, ProxyInfo> Proxies => _proxies;
    public bool HasWindows => _hasWindows;

    /// <summary>Okno Maca przeciągane teraz za pasek menu (0 = żadne).</summary>
    public uint MovingWindowId => _movingWindowId;
    public bool NativeInteractionActive => _movingHandle != IntPtr.Zero || _menuLoopActive;

    /// <summary>Przerywa przeciąganie okna (np. gdy przechodzi na ekran Maca). Dowolny wątek.</summary>
    public void CancelMove()
    {
        var handle = _movingHandle;
        if (handle != IntPtr.Zero) PostMessageW(handle, WM_CANCELMODE, IntPtr.Zero, IntPtr.Zero);
    }

    public DisplayViewer()
    {
        _wndProc = WndProc;
    }

    public void Start(RECT monitor, bool windowMode)
    {
        Stop();
        _monitor = monitor;
        _windowMode = windowMode;
        _running = true;
        _thread = new Thread(Run) { IsBackground = true, Name = "blm-display", Priority = ThreadPriority.AboveNormal };
        _thread.SetApartmentState(ApartmentState.STA); // TrackPopupMenu i DirectComposition
        _thread.Start();
    }

    public void Stop()
    {
        _running = false;
        _wake.Set();
        var thread = _thread;
        if (thread is not null && thread != Thread.CurrentThread) thread.Join(TimeSpan.FromSeconds(3));
        _thread = null;
        _frames.Clear();
        _commands.Clear();
        _hasWindows = false;
        _proxies = new Dictionary<IntPtr, ProxyInfo>();
    }

    /// <summary>Wątek odbiornika.</summary>
    public void Enqueue(VideoStream.VideoFrame frame)
    {
        if (!_running) return;
        _frames.Enqueue(frame);
        _wake.Set();
    }

    public void SetWindowMode(bool windowMode) => Post(() =>
    {
        if (_windowMode == windowMode) return;
        _windowMode = windowMode;
        foreach (var surface in _surfaces.Values.ToList()) DestroySurface(surface);
        if (!windowMode) CreateFullscreenSurface();
        PublishProxies();
    });

    /// <summary>Pełny pulpit: obraz Maca przykrywa monitor tylko podczas sterowania Makiem.</summary>
    public void SetVisible(bool visible) => Post(() =>
    {
        _wantFullscreenVisible = visible;
        if (_surfaces.TryGetValue(FullscreenId, out var surface)) ApplyVisibility(surface);
    });

    /// <summary>Tryb okien: aktualna lista okien Maca (od najwyższego).</summary>
    public void UpdateWindows(IReadOnlyList<ProxyWindow> windows) => Post(() =>
    {
        if (!_windowMode || _device is null) return;
        var wanted = windows.ToDictionary(w => w.Id);
        foreach (var surface in _surfaces.Values.Where(s => !wanted.ContainsKey(s.Id)).ToList()) DestroySurface(surface);
        // Najpierw zwykłe okna – menu i podpowiedzi są ustawiane względem nich.
        foreach (var window in windows.OrderBy(w => w.Popup))
        {
            if (_surfaces.TryGetValue(window.Id, out var existing) && (existing.Kind == SurfaceKind.Popup) != window.Popup)
                DestroySurface(existing);
            if (_surfaces.TryGetValue(window.Id, out var surface)) UpdateSurface(surface, window);
            else CreateWindowSurface(window);
        }
        PublishProxies();
    });

    /// <summary>Ikona aplikacji Maca (PNG) dla okien tego procesu.</summary>
    public void SetIcon(int pid, byte[] png) => Post(() =>
    {
        var icon = CreateIconFromResourceEx(png, (uint)png.Length, true, 0x00030000, 0, 0, 0);
        if (icon == IntPtr.Zero) return;
        if (_icons.Remove(pid, out var old)) DestroyIcon(old);
        _icons[pid] = icon;
        foreach (var surface in _surfaces.Values.Where(s => s.Pid == pid)) ApplyIcon(surface);
    });

    /// <summary>Menu aplikacji Maca – pokazywane w pasku nad jej oknami.</summary>
    public void SetMenu(int pid, IReadOnlyList<MacMenuItem> items) => Post(() =>
    {
        _menus[pid] = items;
        foreach (var surface in _surfaces.Values.Where(s => s.Pid == pid && s.Kind == SurfaceKind.Window))
        {
            surface.MenuDirty = true;
            ApplyMenu(surface);
        }
    });

    /// <summary>Kształt kursora Maca nad jego oknem (strzałka, kursor tekstowy, rączka…).</summary>
    public void SetCursorShape(int shape) => Post(() =>
    {
        _cursorShape = shape is >= 0 and < 12 ? shape : 0;
        // Kursor stojący nad oknem Maca zmienia się od razu, bez czekania na ruch myszy.
        GetCursorPos(out var point);
        var root = GetAncestor(WindowFromPoint(point), GA_ROOT);
        if (_byHandle.TryGetValue(root, out var surface) && surface.Kind != SurfaceKind.Fullscreen && Contains(surface.Client, point.X, point.Y))
            SetCursor(LoadCursorW(IntPtr.Zero, CursorIds[_cursorShape]));
    });

    private void Post(Action action)
    {
        _commands.Enqueue(action);
        _wake.Set();
    }

    // ---------------- wątek wyświetlania ----------------

    private void Run()
    {
        try
        {
            RegisterWindowClass();
            CreateDevice();
            if (!_windowMode) CreateFullscreenSurface();
            PublishProxies();
            var handles = new[] { _wake.SafeWaitHandle.DangerousGetHandle() };
            while (_running)
            {
                MsgWaitForMultipleObjectsEx(1, handles, WaitTimeout(), QS_ALLINPUT, MWMO_INPUTAVAILABLE);
                while (PeekMessageW(out var msg, IntPtr.Zero, 0, 0, PM_REMOVE))
                {
                    TranslateMessage(ref msg);
                    DispatchMessageW(ref msg);
                }
                Pump();
            }
        }
        catch (Exception ex)
        {
            if (_running) Failed?.Invoke(T("Podgląd ekranu Maca: ", "Mac display viewer: ") + ex.Message);
        }
        finally
        {
            Cleanup();
        }
    }

    /// <summary>
    /// Klatki, polecenia i Stop budzą pętlę zdarzeniem <see cref="_wake"/>, a zmiany okien – komunikatem, po którym
    /// zawsze działa <see cref="Pump"/>. Odliczanie zostaje tylko dla rozmiaru czekającego na koniec lokalnej zmiany
    /// (<see cref="Surface.LocalResizeUntil"/>): ten koniec nie przychodzi żadnym komunikatem.
    /// Maksymalizacja i minimalizacja kończą się WM_SIZE, więc dla nich wątek może spać.
    /// </summary>
    private uint WaitTimeout()
    {
        foreach (var surface in _surfaces.Values)
            if (surface.SourceSizePending && !IsZoomed(surface.Handle) && !IsIconic(surface.Handle)) return PendingRetryMs;
        return INFINITE;
    }

    /// <summary>Polecenia i dekodowanie – także z pętli modalnej (przeciąganie, menu), inaczej obraz by stał.</summary>
    private void Pump()
    {
        while (_commands.TryDequeue(out var command)) command();
        // Lista okien przychodzi tylko przy zmianie – rozmiar z okresu zmiany lokalnej dogania się tutaj.
        if (AnySourceSizePending())
            foreach (var surface in _surfaces.Values.Where(s => s.SourceSizePending).ToList()) FollowSource(surface, surface.MacScreen);
        DecodePending();
    }

    private bool AnySourceSizePending()
    {
        foreach (var surface in _surfaces.Values)
            if (surface.SourceSizePending) return true;
        return false;
    }

    private void DecodePending()
    {
        // Zagnieżdżone wywołanie (pętla modalna w trakcie dekodowania) dostaje własne bufory,
        // żeby nie wyczyścić ich zewnętrznemu obiegowi.
        var nested = _decoding;
        var batch = nested ? new List<VideoStream.VideoFrame>() : _batch;
        var lastIndex = nested ? new Dictionary<uint, int>() : _lastIndex;
        var discontinuous = _frames.Drain(batch);
        if (batch.Count == 0 && !discontinuous) return;
        _decoding = true;
        try
        {
            if (discontinuous)
            {
                foreach (var surface in _surfaces.Values)
                {
                    DisposeDecoder(surface);
                    surface.AwaitingKeyframe = true;
                    // A throttled request before overflow may itself have been discarded.
                    RequestKeyframe(surface.Id);
                }
            }
            // Przy zaległościach każda powierzchnia pokazuje tylko swoją najnowszą klatkę.
            for (var i = 0; i < batch.Count; i++) lastIndex[batch[i].StreamId] = i;

            for (var i = 0; i < batch.Count; i++)
            {
                var frame = batch[i];
                if (!_surfaces.TryGetValue(frame.StreamId, out var surface)) continue; // okno jeszcze bez listy
                if (surface.AwaitingKeyframe && !frame.IsKeyframe) continue;
                var present = lastIndex[frame.StreamId] == i;
                try
                {
                    if (!EnsureDecoder(surface, frame)) continue;
                    surface.AwaitingKeyframe = false;
                    var decoder = surface.Decoder!;
                    decoder.Decode(frame.Payload, sample =>
                    {
                        if (present) Present(surface, decoder, sample, frame.Width, frame.Height);
                    });
                }
                catch (SharpGenException ex)
                {
                    // Uszkodzony strumień albo reset sterownika: nowy dekoder od następnej klatki kluczowej.
                    DisposeDecoder(surface);
                    surface.AwaitingKeyframe = true;
                    RequestKeyframe(surface.Id);
                    if (ex.ResultCode == Vortice.DXGI.ResultCode.DeviceRemoved || ex.ResultCode == Vortice.DXGI.ResultCode.DeviceReset)
                    {
                        RecreateDevice();
                        return;
                    }
                }
            }
        }
        finally
        {
            // Bufory klatek nie mogą żyć dłużej niż ten obieg.
            batch.Clear();
            lastIndex.Clear();
            _decoding = nested;
        }
    }

    private bool EnsureDecoder(Surface surface, VideoStream.VideoFrame frame)
    {
        // Rozmiar strumienia zmienia się tylko razem z klatką kluczową.
        if (surface.Decoder is not null && surface.DecoderWidth == frame.Width && surface.DecoderHeight == frame.Height) return true;
        if (!frame.IsKeyframe)
        {
            surface.AwaitingKeyframe = true;
            RequestKeyframe(surface.Id);
            return false;
        }
        DisposeDecoder(surface);
        // Mac koduje wymiary parzyste, najmniej 16 px.
        surface.Decoder = new H264Decoder(_device, Math.Max(16, (frame.Width + 1) & ~1), Math.Max(16, (frame.Height + 1) & ~1));
        surface.DecoderWidth = frame.Width;
        surface.DecoderHeight = frame.Height;
        UsesGpuDecoding = surface.Decoder.UsesGpu;
        return true;
    }

    /// <summary>Zdekodowana klatka → obraz okna (NV12 → RGB), z zachowaniem proporcji.</summary>
    private void Present(Surface surface, H264Decoder decoder, IMFSample sample, int frameWidth, int frameHeight)
    {
        if (_videoDevice is null || _videoContext is null || surface.SwapChain is null || surface.Width <= 0 || surface.Height <= 0) return;
        ID3D11Texture2D texture;
        uint slice;
        if (decoder.UsesGpu)
        {
            using var buffer = sample.GetBufferByIndex(0);
            using var dxgiBuffer = buffer.QueryInterface<IMFDXGIBuffer>();
            texture = new ID3D11Texture2D(dxgiBuffer.GetResource(typeof(ID3D11Texture2D).GUID));
            slice = dxgiBuffer.SubresourceIndex;
        }
        else
        {
            texture = Upload(surface, decoder, sample);
            slice = 0;
        }
        var pictureChanged = false;
        using (texture)
        {
            var description = texture.Description;
            EnsureProcessor(surface, (int)description.Width, (int)description.Height);
            var key = (texture.NativePointer, slice);
            if (!surface.InputViews.TryGetValue(key, out var inputView))
            {
                inputView = _videoDevice.CreateVideoProcessorInputView(texture, surface.Enumerator!, new VideoProcessorInputViewDescription
                {
                    FourCC = 0,
                    ViewDimension = VideoProcessorInputViewDimension.Texture2D,
                    Texture2D = new Texture2DVideoProcessorInputView { MipSlice = 0, ArraySlice = slice },
                });
                surface.InputViews[key] = inputView;
            }
            var width = surface.Width;
            var height = surface.Height;
            var visibleWidth = Math.Min(frameWidth, (int)description.Width);
            var visibleHeight = Math.Min(frameHeight, (int)description.Height);
            var area = new RECT { Right = width, Bottom = height };
            var fitted = surface.Kind == SurfaceKind.Fullscreen
                ? WindowGeometry.Fit(visibleWidth, visibleHeight, area)
                : WindowGeometry.FitWithin(visibleWidth, visibleHeight, area);
            var destination = new RawRect(fitted.Left, fitted.Top, fitted.Right, fitted.Bottom);
            pictureChanged = surface.PictureWidth != visibleWidth || surface.PictureHeight != visibleHeight;
            surface.PictureWidth = visibleWidth;
            surface.PictureHeight = visibleHeight;
            _videoContext.VideoProcessorSetStreamSourceRect(surface.Processor!, 0, true, new RawRect(0, 0, visibleWidth, visibleHeight));
            _videoContext.VideoProcessorSetStreamDestRect(surface.Processor!, 0, true, destination);
            _videoContext.VideoProcessorSetOutputTargetRect(surface.Processor!, true, new RawRect(0, 0, width, height));
            var streams = new[] { new VideoProcessorStream { Enable = true, InputSurface = inputView } };
            _videoContext.VideoProcessorBlt(surface.Processor!, surface.OutputView!, 0, 1, streams).CheckError();
        }
        surface.HasVideo = true;
        // Z klatki do Proxies trafia tylko rozmiar obrazu (ImageClient; pierwsza klatka też go zmienia).
        // Położenie, widoczność i minimalizację publikują SyncClient, ApplyVisibility i WM_SIZE, listę okien UpdateWindows.
        if (pictureChanged) PublishProxies();
        if (surface.Kind == SurfaceKind.Fullscreen) surface.SwapChain.Present(0, PresentFlags.None).CheckError();
        else Compose(surface);
        Interlocked.Increment(ref _framesPresented);
        if (!surface.HasPicture)
        {
            surface.HasPicture = true;
            ApplyVisibility(surface);
        }
    }

    /// <summary>
    /// Obraz klienta kopiowany bez ponownego skalowania; pasek tytułu ma osobną warstwę.
    /// </summary>
    private void Compose(Surface surface)
    {
        if (surface.Kind == SurfaceKind.Fullscreen || _d2d is null || surface.SwapChain is null || !surface.HasVideo) return;
        surface.Target ??= CreateTargetBitmap(surface.SwapChain);
        _d2d.Target = surface.Target;
        _d2d.BeginDraw();
        _d2d.Clear(Background);
        if (surface.VideoBitmap is not null)
        {
            var bounds = new Rect(0, 0, surface.Width, surface.Height);
            // The video processor already scaled the image; this is a pixel-for-pixel copy.
            _d2d.DrawBitmap(surface.VideoBitmap, bounds, 1, BitmapInterpolationMode.NearestNeighbor, bounds);
        }
        var result = _d2d.EndDraw();
        _d2d.Target = null;
        if (result.Failure) return;
        surface.SwapChain.Present(0, PresentFlags.None);
    }

    private ID2D1Bitmap1 CreateTargetBitmap(IDXGISwapChain1 swapChain)
    {
        using var surface = swapChain.GetBuffer<IDXGISurface>(0);
        return _d2d!.CreateBitmapFromDxgiSurface(surface, new BitmapProperties1(
            new PixelFormat(Format.B8G8R8A8_UNorm, Vortice.DCommon.AlphaMode.Premultiplied), 96, 96,
            BitmapOptions.Target | BitmapOptions.CannotDraw));
    }

    /// <summary>Tryb programowy: NV12 z pamięci → tekstura GPU (przez teksturę staging).</summary>
    private ID3D11Texture2D Upload(Surface surface, H264Decoder decoder, IMFSample sample)
    {
        var width = (uint)decoder.OutputWidth;
        var height = (uint)decoder.OutputHeight;
        if (surface.UploadTexture is null || surface.UploadTexture.Description.Width != width || surface.UploadTexture.Description.Height != height)
        {
            surface.UploadStaging?.Dispose();
            surface.UploadTexture?.Dispose();
            foreach (var view in surface.InputViews.Values) view.Dispose();
            surface.InputViews.Clear();
            var staging = new Texture2DDescription(Format.NV12, width, height, 1, 1, BindFlags.None,
                ResourceUsage.Staging, CpuAccessFlags.Write, 1, 0, ResourceOptionFlags.None);
            surface.UploadStaging = _device!.CreateTexture2D(in staging);
            var target = new Texture2DDescription(Format.NV12, width, height, 1, 1, BindFlags.ShaderResource,
                ResourceUsage.Default, CpuAccessFlags.None, 1, 0, ResourceOptionFlags.None);
            surface.UploadTexture = _device.CreateTexture2D(in target);
        }
        var nv12 = decoder.CopyNv12(sample);
        var mapped = _context!.Map(surface.UploadStaging!, 0, MapMode.Write, Vortice.Direct3D11.MapFlags.None);
        try
        {
            var stride = decoder.OutputStride;
            var rows = (int)height * 3 / 2;
            for (var row = 0; row < rows && (row + 1) * stride <= nv12.Length; row++)
            {
                Marshal.Copy(nv12, row * stride, mapped.DataPointer + row * (int)mapped.RowPitch, (int)width);
            }
        }
        finally
        {
            _context.Unmap(surface.UploadStaging!, 0);
        }
        _context.CopyResource(surface.UploadTexture!, surface.UploadStaging!);
        // Osobny wrapper z własną referencją: wywołujący zwalnia go jak teksturę dekodera.
        surface.UploadTexture!.AddRef();
        return new ID3D11Texture2D(surface.UploadTexture.NativePointer);
    }

    /// <summary>
    /// Procesor wideo pisze do łańcucha wymiany (pełny pulpit) albo do tekstury obrazu okna,
    /// z której Direct2D kopiuje gotowy obraz klienta.
    /// </summary>
    private void EnsureProcessor(Surface surface, int inputWidth, int inputHeight)
    {
        if (surface.Processor is not null && surface.ProcessorInputWidth == inputWidth && surface.ProcessorInputHeight == inputHeight
            && surface.ProcessorOutputWidth == surface.Width && surface.ProcessorOutputHeight == surface.Height) return;
        DisposeProcessor(surface);
        var content = new VideoProcessorContentDescription
        {
            InputFrameFormat = VideoFrameFormat.Progressive,
            InputWidth = (uint)inputWidth,
            InputHeight = (uint)inputHeight,
            OutputWidth = (uint)surface.Width,
            OutputHeight = (uint)surface.Height,
            InputFrameRate = new Rational(60, 1),
            OutputFrameRate = new Rational(60, 1),
            Usage = VideoUsage.PlaybackNormal,
        };
        surface.Enumerator = _videoDevice!.CreateVideoProcessorEnumerator(content);
        surface.Processor = _videoDevice.CreateVideoProcessor(surface.Enumerator, 0);
        // Koder Maca: BT.709, zakres wideo 16–235; wyjście: pełny zakres RGB.
        var input = new VideoProcessorColorSpace { YCbCr_Matrix = 1, Nominal_Range = (uint)VideoProcessorNominalRange.Range_16_235 };
        _videoContext!.VideoProcessorSetStreamColorSpace(surface.Processor, 0, input);
        _videoContext.VideoProcessorSetOutputColorSpace(surface.Processor, new VideoProcessorColorSpace { RGB_Range = 0 });
        _videoContext.VideoProcessorSetStreamFrameFormat(surface.Processor, 0, VideoFrameFormat.Progressive);
        _videoContext.VideoProcessorSetStreamAutoProcessingMode(surface.Processor, 0, false);
        _videoContext.VideoProcessorSetOutputBackgroundColor(surface.Processor, false,
            new VideoColor { Rgba = new VideoColorRgba { R = Background.R, G = Background.G, B = Background.B, A = 1 } });
        ID3D11Texture2D output;
        if (surface.Kind == SurfaceKind.Fullscreen)
        {
            output = surface.SwapChain!.GetBuffer<ID3D11Texture2D>(0);
        }
        else
        {
            var description = new Texture2DDescription(Format.B8G8R8A8_UNorm, (uint)surface.Width, (uint)surface.Height, 1, 1,
                BindFlags.RenderTarget | BindFlags.ShaderResource, ResourceUsage.Default, CpuAccessFlags.None, 1, 0, ResourceOptionFlags.None);
            surface.VideoTexture = _device!.CreateTexture2D(in description);
            using var dxgiSurface = surface.VideoTexture.QueryInterface<IDXGISurface>();
            surface.VideoBitmap = _d2d!.CreateBitmapFromDxgiSurface(dxgiSurface, new BitmapProperties1(
                new PixelFormat(Format.B8G8R8A8_UNorm, Vortice.DCommon.AlphaMode.Ignore), 96, 96, BitmapOptions.None));
            output = surface.VideoTexture;
            output.AddRef();
        }
        using (output)
        {
            surface.OutputView = _videoDevice.CreateVideoProcessorOutputView(output, surface.Enumerator, new VideoProcessorOutputViewDescription
            {
                ViewDimension = VideoProcessorOutputViewDimension.Texture2D,
                Texture2D = new Texture2DVideoProcessorOutputView { MipSlice = 0 },
            });
        }
        surface.ProcessorInputWidth = inputWidth;
        surface.ProcessorInputHeight = inputHeight;
        surface.ProcessorOutputWidth = surface.Width;
        surface.ProcessorOutputHeight = surface.Height;
    }

    // ---------------- powierzchnie ----------------

    private enum SurfaceKind { Fullscreen, Window, Popup }

    private sealed class Surface
    {
        public uint Id;
        public SurfaceKind Kind;
        public IntPtr Handle;
        public IntPtr Owner;
        public bool InMenuLoop, ApplyingPlacement, MenuDirty, Active;
        /// <summary>Wysokość paska tytułu z menu (część obszaru klienta, nad obrazem).</summary>
        public int HeaderHeight;
        public int HoverItem = -1, OpenItem = -1, SwitchToItem = -1, ClosedItem = -1;
        public long MenuClosedAt;
        public readonly List<(int Left, int Right)> ItemBounds = new();
        public IDXGISwapChain1? HeaderChain;
        public ID2D1Bitmap1? HeaderTarget;
        public IDCompositionVisual? HeaderVisual, RootVisual;
        public int HeaderWidth, HeaderChainHeight;
        public long LocalResizeUntil;
        /// <summary>Okno Maca zmieniło się, gdy okno Windows nie mogło za nim pójść (zmiana lokalna, maksymalizacja).</summary>
        public bool SourceSizePending;
        public long LastResizeRequest;
        public int RequestedWidth, RequestedHeight;
        public int PictureWidth, PictureHeight;
        public int Pid;
        public string Title = "";
        /// <summary>Okno Maca przeliczone na ekran Windows (z ostatniej listy).</summary>
        public RECT MacScreen;
        public RECT MacPixels;
        public int DisplayWidth, DisplayHeight;
        /// <summary>Obszar obrazu okna Maca na ekranie Windows (pod paskiem tytułu).</summary>
        public RECT Client;
        /// <summary>Rozmiar obrazu okna (bez paska) w pikselach.</summary>
        public int Width, Height;
        public bool InSizeMove;
        public bool AwaitingKeyframe = true;
        public bool HasPicture;
        public bool HasVideo;
        public bool Visible;
        public IDXGISwapChain1? SwapChain;
        public IDCompositionTarget? CompositionTarget;
        public IDCompositionVisual? Visual;
        public ID2D1Bitmap1? Target;
        public ID3D11Texture2D? VideoTexture;
        public ID2D1Bitmap1? VideoBitmap;
        public H264Decoder? Decoder;
        public int DecoderWidth, DecoderHeight;
        public ID3D11VideoProcessorEnumerator? Enumerator;
        public ID3D11VideoProcessor? Processor;
        public ID3D11VideoProcessorOutputView? OutputView;
        public int ProcessorInputWidth, ProcessorInputHeight, ProcessorOutputWidth, ProcessorOutputHeight;
        public readonly Dictionary<(IntPtr, uint), ID3D11VideoProcessorInputView> InputViews = new();
        public ID3D11Texture2D? UploadStaging;
        public ID3D11Texture2D? UploadTexture;
    }

    private void CreateFullscreenSurface()
    {
        var handle = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_NOACTIVATE, ClassName, "Seam – Mac", WS_POPUP,
            _monitor.Left, _monitor.Top, _monitor.Width, _monitor.Height, IntPtr.Zero, IntPtr.Zero, GetModuleHandle(null), IntPtr.Zero);
        if (handle == IntPtr.Zero) throw new InvalidOperationException($"CreateWindowEx failed: {Marshal.GetLastWin32Error()}");
        var surface = new Surface
        {
            Id = FullscreenId, Kind = SurfaceKind.Fullscreen, Handle = handle, Client = _monitor,
            Width = _monitor.Width, Height = _monitor.Height,
        };
        var description = new SwapChainDescription1((uint)surface.Width, (uint)surface.Height, Format.B8G8R8A8_UNorm, false,
            Usage.RenderTargetOutput, 2, Scaling.Stretch, SwapEffect.FlipDiscard, AlphaMode.Ignore, SwapChainFlags.None);
        surface.SwapChain = _factory!.CreateSwapChainForHwnd(_device!, handle, description, null, null);
        _factory.MakeWindowAssociation(handle, WindowAssociationFlags.IgnoreAll);
        Register(surface);
    }

    private void CreateWindowSurface(ProxyWindow window)
    {
        var kind = window.Popup ? SurfaceKind.Popup : SurfaceKind.Window;
        var surface = new Surface
        {
            Id = window.Id, Kind = kind, Pid = window.Pid, Title = window.Title,
            MacScreen = window.MacScreen, MacPixels = window.MacPixels,
            DisplayWidth = window.DisplayWidth, DisplayHeight = window.DisplayHeight,
        };
        // Nowe okno powstaje tam, gdzie leży okno Maca; menu i podpowiedzi – przy swoim oknie.
        var client = kind == SurfaceKind.Popup ? PopupClient(surface) : window.MacScreen;
        // DWM draws the native frame and caption buttons; DirectComposition supplies the title row
        // (title and Mac menu) and the client image. Transparent pixels show the Mica backdrop.
        var style = kind == SurfaceKind.Window ? WS_OVERLAPPEDWINDOW : WS_POPUP;
        var exStyle = WS_EX_NOREDIRECTIONBITMAP | (kind == SurfaceKind.Window ? WS_EX_APPWINDOW : WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE);
        surface.Handle = CreateWindowExW(exStyle, ClassName, window.Title, style, client.Left, client.Top,
            Math.Max(1, client.Width), Math.Max(1, client.Height), IntPtr.Zero, IntPtr.Zero, GetModuleHandle(null), IntPtr.Zero);
        if (surface.Handle == IntPtr.Zero) return;
        Register(surface);
        // Zmiana ramki niżej zmienia obszar klienta (o ramkę i wiersz tytułu). To nie jest zmiana
        // rozmiaru przez użytkownika – wysłana na Maca zmniejszała okno, a obraz był potem rozciągany.
        surface.ApplyingPlacement = true;
        if (kind == SurfaceKind.Window)
        {
            // DWM supplies the real Windows 11 caption, buttons, rounded frame and Snap layouts.
            // Unsupported attributes are harmless on Windows 10, which retains its native frame.
            var dark = 1;
            DwmSetWindowAttribute(surface.Handle, 20, ref dark, sizeof(int));
            var corners = 2;
            DwmSetWindowAttribute(surface.Handle, 33, ref corners, sizeof(int));
            // Mica: DWMSBT_MAINWINDOW from Windows 11 22H2, the undocumented attribute on 21H2.
            var backdrop = 2;
            if (DwmSetWindowAttribute(surface.Handle, DWMWA_SYSTEMBACKDROP_TYPE, ref backdrop, sizeof(int)) != 0)
            {
                var mica = 1;
                DwmSetWindowAttribute(surface.Handle, DWMWA_MICA_EFFECT, ref mica, sizeof(int));
            }
            // The backdrop covers the whole client; the caption becomes client area in WM_NCCALCSIZE.
            var margins = new MARGINS { Left = -1, Right = -1, Top = -1, Bottom = -1 };
            DwmExtendFrameIntoClientArea(surface.Handle, ref margins);
            surface.HeaderHeight = HeaderHeightFor(surface.Handle, GetDpiForWindow(surface.Handle));
            SetWindowPos(surface.Handle, IntPtr.Zero, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
        }
        else UpdatePopupOwner(surface);
        surface.ApplyingPlacement = false;
        Place(surface, client);
        surface.RequestedWidth = surface.Width;
        surface.RequestedHeight = surface.Height;
        CreateComposition(surface);
        ApplyIcon(surface);
        // Klatki mogły przyjść przed listą okien – prosimy o pełny obraz.
        RequestKeyframe(surface.Id);
    }

    /// <summary>Łańcuch wymiany z przezroczystością, podpięty do okna przez DirectComposition.</summary>
    private void CreateComposition(Surface surface)
    {
        var description = new SwapChainDescription1((uint)surface.Width, (uint)surface.Height, Format.B8G8R8A8_UNorm,
            false, Usage.RenderTargetOutput, 2, Scaling.Stretch, SwapEffect.FlipSequential, AlphaMode.Premultiplied, SwapChainFlags.None);
        surface.SwapChain = _factory!.CreateSwapChainForComposition(_device!, description, null);
        _composition!.CreateTargetForHwnd(surface.Handle, true, out surface.CompositionTarget).CheckError();
        surface.Visual = _composition.CreateVisual();
        surface.Visual.SetContent(surface.SwapChain).CheckError();
        if (surface.HeaderHeight <= 0)
        {
            surface.CompositionTarget!.SetRoot(surface.Visual).CheckError();
            _composition.Commit().CheckError();
            return;
        }
        // Pasek tytułu: osobna przezroczysta warstwa na Mice, obraz okna tuż pod nią.
        surface.HeaderChain = _factory.CreateSwapChainForComposition(_device!, description with
        {
            Width = (uint)surface.Width, Height = (uint)surface.HeaderHeight,
        }, null);
        surface.HeaderWidth = surface.Width;
        surface.HeaderChainHeight = surface.HeaderHeight;
        surface.HeaderVisual = _composition.CreateVisual();
        surface.HeaderVisual.SetContent(surface.HeaderChain).CheckError();
        surface.Visual.SetOffsetY(surface.HeaderHeight).CheckError();
        surface.RootVisual = _composition.CreateVisual();
        surface.RootVisual.AddVisual(surface.Visual, false, null).CheckError();
        surface.RootVisual.AddVisual(surface.HeaderVisual, true, surface.Visual).CheckError();
        surface.CompositionTarget!.SetRoot(surface.RootVisual).CheckError();
        _composition.Commit().CheckError();
        DrawHeader(surface);
    }

    private void UpdateSurface(Surface surface, ProxyWindow window)
    {
        if (surface.Title != window.Title)
        {
            surface.Title = window.Title;
            SetWindowTextW(surface.Handle, window.Title);
            DrawHeader(surface);
        }
        var previous = surface.MacScreen;
        surface.MacScreen = window.MacScreen;
        surface.MacPixels = window.MacPixels;
        surface.DisplayWidth = window.DisplayWidth;
        surface.DisplayHeight = window.DisplayHeight;
        if (surface.Kind == SurfaceKind.Popup)
        {
            UpdatePopupOwner(surface);
            Place(surface, PopupClient(surface));
            ApplyVisibility(surface);
            return;
        }
        FollowSource(surface, previous);
    }

    /// <summary>
    /// Okno na Windowsie żyje własnym położeniem (można je przenieść nawet na inny monitor).
    /// Przesunięcie okna na Macu (za jego pasek tytułu) przesuwa je o tyle samo, a rozmiar wraca do
    /// rozmiaru okna Maca, więc obraz jest 1:1 – także gdy Mac nie przyjął żądanego rozmiaru
    /// (rozmiar minimalny, Terminal w krokach znaków). Gdy użytkownik właśnie zmienia okno, jest ono
    /// zmaksymalizowane albo Mac jeszcze wykonuje zmianę rozmiaru, rozmiar dogania je później (<see cref="Pump"/>).
    /// </summary>
    private void FollowSource(Surface surface, RECT previous)
    {
        if (surface.InSizeMove || IsZoomed(surface.Handle) || IsIconic(surface.Handle)
            || Environment.TickCount64 < surface.LocalResizeUntil)
        {
            surface.SourceSizePending = true;
            return;
        }
        surface.SourceSizePending = false;
        var dx = surface.MacScreen.Left - previous.Left;
        var dy = surface.MacScreen.Top - previous.Top;
        var width = surface.MacScreen.Width;
        var height = surface.MacScreen.Height;
        if (dx == 0 && dy == 0 && width == surface.Width && height == surface.Height) return;
        Place(surface, new RECT
        {
            Left = surface.Client.Left + dx, Top = surface.Client.Top + dy,
            Right = surface.Client.Left + dx + width, Bottom = surface.Client.Top + dy + height,
        });
        // Ten rozmiar ma już okno Maca – nie odsyłamy go jako nowej prośby.
        surface.RequestedWidth = surface.Width;
        surface.RequestedHeight = surface.Height;
    }

    /// <summary>Menu i podpowiedzi: to samo przesunięcie względem okna aplikacji co na Macu.</summary>
    private Surface? PopupOwner(Surface popup) => _surfaces.Values
        .Where(s => s.Kind == SurfaceKind.Window && s.Pid == popup.Pid)
        .OrderByDescending(s => Contains(s.MacPixels, popup.MacPixels.Left, popup.MacPixels.Top))
        .ThenByDescending(s => s.Handle == GetForegroundWindow())
        .FirstOrDefault();

    private void UpdatePopupOwner(Surface popup)
    {
        var owner = PopupOwner(popup)?.Handle ?? IntPtr.Zero;
        if (owner == popup.Owner) return;
        SetWindowOwner(popup.Handle, -8, owner); // GWLP_HWNDPARENT: owned top-level window, not a child HWND
        popup.Owner = owner;
    }

    private RECT PopupClient(Surface popup)
    {
        var owner = PopupOwner(popup);
        // Browsers may implement fullscreen video as a new transient surface. It replaces
        // the owner's content instead of becoming an oversized, independently positioned window.
        if (owner is not null && WindowGeometry.CoversDisplay(popup.MacPixels, popup.DisplayWidth, popup.DisplayHeight))
            return owner.Client;
        return owner is null ? popup.MacScreen : WindowGeometry.MapRelative(popup.MacPixels, owner.MacPixels, ImageClient(owner));
    }

    private static bool Contains(RECT r, int x, int y) => x >= r.Left && x < r.Right && y >= r.Top && y < r.Bottom;

    private static RECT ImageClient(Surface surface) => WindowGeometry.FitWithin(
        surface.PictureWidth > 0 ? surface.PictureWidth : surface.MacPixels.Width,
        surface.PictureHeight > 0 ? surface.PictureHeight : surface.MacPixels.Height, surface.Client);

    /// <summary>Position the client image; Windows owns the side and bottom frame, the title row is ours.</summary>
    private void Place(Surface surface, RECT client)
    {
        if (client.Width <= 0 || client.Height <= 0) return;
        var frame = client;
        if (surface.Kind == SurfaceKind.Window)
        {
            AdjustWindowRectExForDpi(ref frame, WS_OVERLAPPEDWINDOW, false, WS_EX_APPWINDOW, GetDpiForWindow(surface.Handle));
            frame.Top = client.Top - surface.HeaderHeight;
            frame = WindowGeometry.KeepReachable(frame, Monitors().Select(m => m.WorkArea).ToArray());
        }
        surface.ApplyingPlacement = true;
        try
        {
            SetWindowPos(surface.Handle, IntPtr.Zero, frame.Left, frame.Top, frame.Width, frame.Height, SWP_NOZORDER | SWP_NOACTIVATE);
            SyncClient(surface);
        }
        finally { surface.ApplyingPlacement = false; }
    }

    private void KeepReachable(Surface surface)
    {
        if (surface.Kind != SurfaceKind.Window || IsIconic(surface.Handle) || IsZoomed(surface.Handle)
            || !GetWindowRect(surface.Handle, out var frame)) return;
        var safe = WindowGeometry.KeepReachable(frame, Monitors().Select(m => m.WorkArea).ToArray());
        if (safe.Left == frame.Left && safe.Top == frame.Top) return;
        SetWindowPos(surface.Handle, IntPtr.Zero, safe.Left, safe.Top, safe.Width, safe.Height, SWP_NOZORDER | SWP_NOACTIVATE);
    }

    private void SyncClient(Surface surface)
    {
        if (surface.Kind == SurfaceKind.Fullscreen || IsIconic(surface.Handle)) return;
        if (!GetClientRect(surface.Handle, out var client)) return;
        var origin = new POINT();
        ClientToScreen(surface.Handle, ref origin);
        surface.Client = new RECT
        {
            Left = origin.X, Top = origin.Y + surface.HeaderHeight, Right = origin.X + client.Width, Bottom = origin.Y + client.Height,
        };
        var width = Math.Max(1, client.Width);
        var height = Math.Max(1, client.Height - surface.HeaderHeight);
        ResizeHeader(surface, width);
        if (width != surface.Width || height != surface.Height)
        {
            surface.Width = width;
            surface.Height = height;
            if (surface.SwapChain is not null)
            {
                DisposeProcessor(surface);
                surface.Target?.Dispose();
                surface.Target = null;
                surface.SwapChain.ResizeBuffers(2, (uint)width, (uint)height, Format.B8G8R8A8_UNorm).CheckError();
                surface.HasVideo = false;
                RequestKeyframe(surface.Id);
            }
        }
        PublishProxies();
        if (surface.Kind == SurfaceKind.Window)
            foreach (var popup in _surfaces.Values.Where(s => s.Kind == SurfaceKind.Popup && s.Owner == surface.Handle).ToList())
                Place(popup, PopupClient(popup));
    }

    private void RequestResize(Surface surface)
    {
        if (surface.ApplyingPlacement || surface.Kind != SurfaceKind.Window || IsIconic(surface.Handle)) return;
        if (surface.RequestedWidth == surface.Width && surface.RequestedHeight == surface.Height) return;
        surface.RequestedWidth = surface.Width;
        surface.RequestedHeight = surface.Height;
        // AX may move the source while resizing. Do not echo that transient position/size back.
        surface.LocalResizeUntil = Environment.TickCount64 + 1200;
        surface.LastResizeRequest = Environment.TickCount64;
        ResizeRequested?.Invoke(surface.Id, surface.Width, surface.Height);
    }

    private void ApplyVisibility(Surface surface)
    {
        var show = surface.HasPicture && (surface.Kind != SurfaceKind.Fullscreen || _wantFullscreenVisible);
        if (surface.Kind == SurfaceKind.Popup)
            show &= surface.Owner != IntPtr.Zero && !IsIconic(surface.Owner);
        if (show == surface.Visible) return;
        surface.Visible = show;
        if (!show)
        {
            ShowWindow(surface.Handle, SW_HIDE);
            PublishProxies();
            return;
        }
        if (surface.Kind == SurfaceKind.Window)
        {
            ShowWindow(surface.Handle, SW_SHOWNOACTIVATE);
            SyncClient(surface);
        }
        else
        {
            SetWindowPos(surface.Handle, surface.Kind == SurfaceKind.Fullscreen ? HWND_TOPMOST : IntPtr.Zero,
                surface.Client.Left, surface.Client.Top, surface.Width, surface.Height,
                SWP_NOACTIVATE | SWP_SHOWWINDOW | (surface.Kind == SurfaceKind.Popup ? SWP_NOZORDER : 0));
            ShowWindow(surface.Handle, SW_SHOWNOACTIVATE);
        }
        // Ukryte okno mogło nie zachować obrazu, a statyczny obraz nie przyjdzie sam z siebie.
        PublishProxies();
        RequestKeyframe(surface.Id);
    }

    private void ApplyIcon(Surface surface)
    {
        if (surface.Kind != SurfaceKind.Window || !_icons.TryGetValue(surface.Pid, out var icon)) return;
        SendMessageW(surface.Handle, WM_SETICON, 0, icon);
        SendMessageW(surface.Handle, WM_SETICON, 1, icon);
    }

    private void Register(Surface surface)
    {
        _surfaces[surface.Id] = surface;
        _byHandle[surface.Handle] = surface;
    }

    private void DestroySurface(Surface surface)
    {
        if (!_surfaces.ContainsKey(surface.Id)) return;
        // Windows destroys owned windows with their owner; release their GPU state first.
        foreach (var popup in _surfaces.Values.Where(s => s.Owner == surface.Handle).ToList()) DestroySurface(popup);
        if (_movingHandle == surface.Handle) { _movingHandle = IntPtr.Zero; _movingWindowId = 0; }
        if (surface.InMenuLoop) _menuLoopActive = false;
        DisposeGpu(surface);
        _surfaces.Remove(surface.Id);
        _byHandle.Remove(surface.Handle);
        DestroyWindow(surface.Handle);
    }

    private void PublishProxies()
    {
        _hasWindows = _surfaces.Values.Any(s => s.Kind != SurfaceKind.Fullscreen);
        _proxies = _surfaces.Values.Where(s => s.Kind != SurfaceKind.Fullscreen && s.Visible && !IsIconic(s.Handle))
            .ToDictionary(s => s.Handle, s => new ProxyInfo(s.Id, s.Pid, s.Kind == SurfaceKind.Popup, ImageClient(s), s.MacPixels,
                s.DisplayWidth, s.DisplayHeight));
    }

    // ---------------- pasek tytułu z menu aplikacji ----------------

    /// <summary>Wiersz tytułu Windows 11 (32 epx), nie niższy niż systemowe przyciski podpisu.</summary>
    private static int HeaderHeightFor(IntPtr handle, uint dpi)
    {
        var height = (int)Math.Round(32 * dpi / 96.0);
        if (DwmGetWindowAttribute(handle, DWMWA_CAPTION_BUTTON_BOUNDS, out var buttons, (uint)Marshal.SizeOf<RECT>()) == 0)
            height = Math.Max(height, buttons.Height);
        return height;
    }

    private static int FrameThickness(IntPtr handle)
    {
        var dpi = GetDpiForWindow(handle);
        return GetSystemMetricsForDpi(SM_CYSIZEFRAME, dpi) + GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
    }

    /// <summary>Lewa krawędź przycisków podpisu w układzie klienta – menu kończy się przed nimi.</summary>
    private static float CaptionButtonsLeft(Surface surface, float scale)
    {
        if (DwmGetWindowAttribute(surface.Handle, DWMWA_CAPTION_BUTTON_BOUNDS, out var buttons, (uint)Marshal.SizeOf<RECT>()) == 0
            && GetWindowRect(surface.Handle, out var frame))
        {
            var origin = new POINT();
            ClientToScreen(surface.Handle, ref origin);
            return buttons.Left - (origin.X - frame.Left);
        }
        return surface.HeaderWidth - 3 * 46 * scale;
    }

    private void ResizeHeader(Surface surface, int width)
    {
        if (surface.HeaderChain is null || (surface.HeaderWidth == width && surface.HeaderChainHeight == surface.HeaderHeight)) return;
        surface.HeaderTarget?.Dispose();
        surface.HeaderTarget = null;
        surface.HeaderChain.ResizeBuffers(2, (uint)width, (uint)surface.HeaderHeight, Format.B8G8R8A8_UNorm).CheckError();
        if (surface.HeaderChainHeight != surface.HeaderHeight)
        {
            surface.Visual?.SetOffsetY(surface.HeaderHeight);
            _composition?.Commit();
        }
        surface.HeaderWidth = width;
        surface.HeaderChainHeight = surface.HeaderHeight;
        DrawHeader(surface);
    }

    private IReadOnlyList<MacMenuItem> HeaderItems(Surface surface) =>
        _menus.TryGetValue(surface.Pid, out var items) ? items : Array.Empty<MacMenuItem>();

    private static int HeaderItemAt(Surface surface, int x)
    {
        for (var i = 0; i < surface.ItemBounds.Count; i++)
            if (x >= surface.ItemBounds[i].Left && x < surface.ItemBounds[i].Right) return i;
        return -1;
    }

    private IDWriteTextFormat CreateHeaderFormat(float size)
    {
        // Windows 11 draws its caption in Segoe UI Variable; Windows 10 has only Segoe UI.
        var family = Environment.OSVersion.Version.Build >= 22000 ? "Segoe UI Variable Text" : "Segoe UI";
        var format = _dwrite!.CreateTextFormat(family, FontWeight.Normal, FontStyle.Normal, size);
        format.ParagraphAlignment = ParagraphAlignment.Center;
        format.WordWrapping = WordWrapping.NoWrap;
        return format;
    }

    /// <summary>Tytuł okna i menu aplikacji Maca na przezroczystym tle (Mica), przed przyciskami podpisu.</summary>
    private void DrawHeader(Surface surface)
    {
        if (_d2d is null || _dwrite is null || surface.HeaderChain is null) return;
        surface.HeaderTarget ??= CreateTargetBitmap(surface.HeaderChain);
        var d2d = _d2d;
        var height = surface.HeaderHeight;
        var scale = GetDpiForWindow(surface.Handle) / 96f;
        var limit = Math.Min(surface.HeaderWidth, CaptionButtonsLeft(surface, scale)) - 8 * scale;
        var items = HeaderItems(surface);
        surface.ItemBounds.Clear();
        d2d.Target = surface.HeaderTarget;
        d2d.BeginDraw();
        d2d.Clear(new Color4(0, 0, 0, 0));
        using (var format = CreateHeaderFormat(12 * scale))
        using (var text = d2d.CreateSolidColorBrush(surface.Active ? HeaderText : HeaderInactiveText))
        using (var disabled = d2d.CreateSolidColorBrush(HeaderDisabledText))
        using (var hover = d2d.CreateSolidColorBrush(HeaderHover))
        using (var open = d2d.CreateSolidColorBrush(HeaderOpen))
        {
            var x = 16 * scale;
            if (surface.Title.Length > 0)
            {
                // Długi tytuł zostawia miejsce na menu: najwyżej 40% paska, z wielokropkiem.
                using var titleFormat = CreateHeaderFormat(12 * scale);
                using var ellipsis = _dwrite.CreateEllipsisTrimmingSign(titleFormat);
                titleFormat.SetTrimming(new Trimming { Granularity = TrimmingGranularity.Character }, ellipsis);
                var available = Math.Max(0, limit - x);
                var maxWidth = items.Count > 0 ? available * 0.4f : available;
                using var layout = _dwrite.CreateTextLayout(surface.Title, titleFormat, maxWidth, height);
                d2d.DrawTextLayout(new Vector2(x, 0), layout, text);
                x += Math.Min(layout.Metrics.Width, maxWidth) + 8 * scale;
            }
            var padding = 10 * scale;
            var inset = 4 * scale;
            for (var i = 0; i < items.Count; i++)
            {
                using var layout = _dwrite.CreateTextLayout(items[i].Title, format, 1000, height);
                var width = layout.Metrics.Width + 2 * padding;
                if (x + width > limit) break; // wąskie okno – reszta menu się nie mieści
                if (i == surface.OpenItem || i == surface.HoverItem)
                    d2d.FillRoundedRectangle(new RoundedRectangle(new System.Drawing.RectangleF(x, inset, width, height - 2 * inset),
                        4 * scale, 4 * scale), i == surface.OpenItem ? open : hover);
                d2d.DrawTextLayout(new Vector2(x + padding, 0), layout, items[i].Enabled ? text : disabled);
                surface.ItemBounds.Add(((int)x, (int)(x + width)));
                x += width;
            }
        }
        var result = d2d.EndDraw();
        d2d.Target = null;
        if (result.Failure) return;
        surface.HeaderChain.Present(0, PresentFlags.None);
    }

    private void SetHover(Surface surface, int item)
    {
        if (surface.HoverItem == item) return;
        surface.HoverItem = item;
        DrawHeader(surface);
    }

    /// <summary>Rozwija menu pozycji paska; przesunięcie kursora na sąsiednią pozycję przełącza menu jak w pasku Windows.</summary>
    private void ShowHeaderMenu(Surface surface, int index)
    {
        while (index >= 0 && _surfaces.ContainsKey(surface.Id))
        {
            var items = HeaderItems(surface);
            if (index >= items.Count || index >= surface.ItemBounds.Count || items[index].Children.Count == 0) break;
            MenuOpening?.Invoke(surface.Pid);
            var menu = CreatePopupMenu();
            AppendItems(menu, items[index].Children);
            var origin = new POINT { X = surface.ItemBounds[index].Left, Y = surface.HeaderHeight };
            ClientToScreen(surface.Handle, ref origin);
            surface.OpenItem = index;
            surface.SwitchToItem = -1;
            DrawHeader(surface);
            SetForegroundWindow(surface.Handle);
            var command = TrackPopupMenuEx(menu, TPM_RETURNCMD, origin.X, origin.Y, surface.Handle, IntPtr.Zero);
            DestroyMenu(menu);
            surface.OpenItem = -1;
            surface.ClosedItem = index;
            surface.MenuClosedAt = Environment.TickCount64;
            index = command > 0 ? -1 : surface.SwitchToItem;
            surface.SwitchToItem = -1;
            if (command > 0) MenuInvoked?.Invoke(surface.Pid, command - 1);
        }
        if (!_surfaces.ContainsKey(surface.Id)) return;
        GetCursorPos(out var cursor);
        ScreenToClient(surface.Handle, ref cursor);
        surface.HoverItem = cursor.Y >= 0 && cursor.Y < surface.HeaderHeight ? HeaderItemAt(surface, cursor.X) : -1;
        DrawHeader(surface);
    }

    /// <summary>Wywoływane z licznika pętli menu: kursor nad inną pozycją paska zamyka bieżące menu.</summary>
    private void TrackMenuSwitch(Surface surface)
    {
        GetCursorPos(out var cursor);
        ScreenToClient(surface.Handle, ref cursor);
        if (cursor.Y < 0 || cursor.Y >= surface.HeaderHeight) return;
        var item = HeaderItemAt(surface, cursor.X);
        var items = HeaderItems(surface);
        if (item < 0 || item == surface.OpenItem || item >= items.Count || items[item].Children.Count == 0) return;
        surface.SwitchToItem = item;
        EndMenu();
    }

    private void ApplyMenu(Surface surface)
    {
        if (!surface.MenuDirty || surface.InMenuLoop || !_surfaces.ContainsKey(surface.Id)) return;
        surface.MenuDirty = false;
        DrawHeader(surface);
    }

    private static void AppendItems(IntPtr menu, IReadOnlyList<MacMenuItem> items)
    {
        foreach (var item in items)
        {
            if (item.Separator)
            {
                AppendMenuW(menu, MF_SEPARATOR, UIntPtr.Zero, null);
                continue;
            }
            var text = item.Title.Replace("&", "&&") + (item.Shortcut.Length > 0 ? "\t" + item.Shortcut : "");
            var flags = (item.Enabled ? 0u : MF_GRAYED) | (item.Checked ? MF_CHECKED : 0u);
            if (item.Children.Count > 0)
            {
                var sub = CreatePopupMenu();
                AppendItems(sub, item.Children);
                AppendMenuW(menu, MF_STRING | MF_POPUP | flags, (UIntPtr)(nuint)sub, text);
            }
            else
            {
                AppendMenuW(menu, MF_STRING | flags, (UIntPtr)(uint)(item.Index + 1), text);
            }
        }
    }

    // ---------------- okno i urządzenie ----------------

    private void RegisterWindowClass()
    {
        var namePtr = Marshal.StringToHGlobalUni(ClassName);
        try
        {
            var wc = new WNDCLASSEXW
            {
                cbSize = (uint)Marshal.SizeOf<WNDCLASSEXW>(),
                lpfnWndProc = Marshal.GetFunctionPointerForDelegate(_wndProc),
                hInstance = GetModuleHandle(null),
                hCursor = IntPtr.Zero,
                lpszClassName = namePtr,
            };
            if (RegisterClassExW(ref wc) == 0)
            {
                var error = Marshal.GetLastWin32Error();
                if (error != 1410) throw new InvalidOperationException($"RegisterClassEx failed: {error}");
            }
        }
        finally
        {
            Marshal.FreeHGlobal(namePtr);
        }
    }

    private void CreateDevice()
    {
        var levels = new[] { FeatureLevel.Level_11_1, FeatureLevel.Level_11_0, FeatureLevel.Level_10_1 };
        const DeviceCreationFlags flags = DeviceCreationFlags.BgraSupport | DeviceCreationFlags.VideoSupport;
        var result = D3D11.D3D11CreateDevice(null, DriverType.Hardware, flags, levels, out ID3D11Device? device, out ID3D11DeviceContext? context);
        if (result.Failure || device is null)
            result = D3D11.D3D11CreateDevice(null, DriverType.Warp, flags, levels, out device, out context);
        result.CheckError();
        _device = device!;
        _context = context!;
        using (var multithread = _device.QueryInterface<ID3D11Multithread>())
        {
            multithread.SetMultithreadProtected(true);
        }
        _videoDevice = _device.QueryInterface<ID3D11VideoDevice>();
        _videoContext = _context.QueryInterface<ID3D11VideoContext>();
        using var dxgiDevice = _device.QueryInterface<IDXGIDevice1>();
        dxgiDevice.MaximumFrameLatency = 1;
        using (var adapter = dxgiDevice.GetAdapter())
        {
            _factory = adapter.GetParent<IDXGIFactory2>();
        }
        // Okna Maca: Direct2D (pasek, maska rogów) i DirectComposition (przezroczystość).
        _d2dFactory = D2D1.D2D1CreateFactory<ID2D1Factory1>(FactoryType.SingleThreaded, DebugLevel.None);
        _d2dDevice = _d2dFactory.CreateDevice(dxgiDevice);
        _d2d = _d2dDevice.CreateDeviceContext(DeviceContextOptions.None);
        _d2d.AntialiasMode = AntialiasMode.PerPrimitive;
        _d2d.TextAntialiasMode = Vortice.Direct2D1.TextAntialiasMode.Grayscale;
        _composition = DComp.DCompositionCreateDevice<IDCompositionDevice>(dxgiDevice);
        _dwrite ??= DWrite.DWriteCreateFactory<IDWriteFactory>(Vortice.DirectWrite.FactoryType.Shared);
    }

    /// <summary>Utrata urządzenia (np. aktualizacja sterownika): nowe urządzenie i łańcuchy wymiany.</summary>
    private void RecreateDevice()
    {
        var surfaces = _surfaces.Values.ToList();
        foreach (var surface in surfaces) DisposeGpu(surface);
        DisposeDevice();
        CreateDevice();
        foreach (var surface in surfaces)
        {
            if (surface.Kind == SurfaceKind.Fullscreen)
            {
                DestroySurface(surface);
                CreateFullscreenSurface();
                continue;
            }
            CreateComposition(surface);
            surface.AwaitingKeyframe = true;
        }
        _frames.Clear();
        RequestKeyframe(null);
    }

    private IntPtr WndProc(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam)
    {
        _byHandle.TryGetValue(hWnd, out var surface);
        var window = surface is { Kind: SurfaceKind.Window };
        // Przyciski podpisu w rozszerzonej ramce obsługuje DWM (najechanie, kliknięcie, układy Snap).
        if (window && DwmDefWindowProc(hWnd, msg, wParam, lParam, out var dwmResult)) return dwmResult;
        switch (msg)
        {
            case WM_NCCALCSIZE when window && wParam != IntPtr.Zero:
            {
                // Boki i dół zostają systemową ramką; wiersz tytułu staje się obszarem klienta.
                var top = Marshal.PtrToStructure<RECT>(lParam).Top;
                DefWindowProcW(hWnd, msg, wParam, lParam);
                var rect = Marshal.PtrToStructure<RECT>(lParam);
                // Zmaksymalizowane okno wystaje poza monitor o grubość ramki.
                rect.Top = top + (IsZoomed(hWnd) ? FrameThickness(hWnd) : 0);
                Marshal.StructureToPtr(rect, lParam, false);
                return IntPtr.Zero;
            }
            case WM_NCHITTEST when window:
            {
                var hit = DefWindowProcW(hWnd, msg, wParam, lParam);
                if ((long)hit != HTCLIENT) return hit;
                var point = new POINT { X = (short)((long)lParam & 0xFFFF), Y = (short)(((long)lParam >> 16) & 0xFFFF) };
                ScreenToClient(hWnd, ref point);
                if (!IsZoomed(hWnd) && point.Y < GetSystemMetricsForDpi(SM_CYSIZEFRAME, GetDpiForWindow(hWnd))) return HTTOP;
                if (point.Y < surface!.HeaderHeight) return HeaderItemAt(surface, point.X) >= 0 ? HTCLIENT : HTCAPTION;
                return hit;
            }
            case WM_MOUSEMOVE when window:
            {
                var x = (short)((long)lParam & 0xFFFF);
                var y = (short)(((long)lParam >> 16) & 0xFFFF);
                SetHover(surface!, y < surface!.HeaderHeight ? HeaderItemAt(surface, x) : -1);
                var track = new TRACKMOUSEEVENT { cbSize = (uint)Marshal.SizeOf<TRACKMOUSEEVENT>(), dwFlags = TME_LEAVE, hwndTrack = hWnd };
                TrackMouseEvent(ref track);
                break;
            }
            case WM_MOUSELEAVE when window:
                SetHover(surface!, -1);
                break;
            case WM_LBUTTONDOWN when window:
            {
                var x = (short)((long)lParam & 0xFFFF);
                var y = (short)(((long)lParam >> 16) & 0xFFFF);
                if (y >= surface!.HeaderHeight) break;
                var item = HeaderItemAt(surface, x);
                // Kliknięcie, które zamknęło menu tej pozycji, nie otwiera go od razu ponownie.
                var reopen = item == surface.ClosedItem && Environment.TickCount64 - surface.MenuClosedAt < 250;
                if (item >= 0 && !reopen) ShowHeaderMenu(surface, item);
                return IntPtr.Zero;
            }
            case WM_SETCURSOR:
            {
                if (surface?.Kind == SurfaceKind.Fullscreen)
                {
                    SetCursor(IntPtr.Zero); // kursor Maca jest w obrazie
                    return 1;
                }
                if (((long)lParam & 0xFFFF) != HTCLIENT) break; // native resize/caption cursor
                // Nad obrazem okna Maca – kształt kursora z Maca.
                GetCursorPos(out var cursor);
                var overImage = surface is not null && Contains(surface.Client, cursor.X, cursor.Y);
                SetCursor(LoadCursorW(IntPtr.Zero, overImage ? CursorIds[_cursorShape] : CursorIds[0]));
                return 1;
            }
            case WM_ENTERMENULOOP when window:
                surface!.InMenuLoop = true;
                _menuLoopActive = true;
                SetTimer(hWnd, (UIntPtr)1, 15, IntPtr.Zero);
                break;
            case WM_EXITMENULOOP when window:
                surface!.InMenuLoop = false;
                _menuLoopActive = false;
                KillTimer(hWnd, (UIntPtr)1);
                Post(() => ApplyMenu(surface));
                break;
            case WM_MOUSEACTIVATE when surface is not null && surface.Kind != SurfaceKind.Window:
                return MA_NOACTIVATE;
            case WM_ACTIVATE when window:
                surface!.Active = ((long)wParam & 0xFFFF) != 0;
                DrawHeader(surface);
                WindowActivated?.Invoke(surface.Id, surface.Active);
                break;
            case WM_ENTERSIZEMOVE when window:
                surface!.InSizeMove = true;
                _movingHandle = hWnd;
                _movingWindowId = 0; // only WM_MOVING is a transfer, not edge resizing
                // Pętla przeciągania jest modalna – licznik czasu pozwala dalej dekodować obraz.
                SetTimer(hWnd, (UIntPtr)1, 15, IntPtr.Zero);
                break;
            case WM_EXITSIZEMOVE when window:
                surface!.InSizeMove = false;
                KillTimer(hWnd, (UIntPtr)1);
                _movingWindowId = 0;
                _movingHandle = IntPtr.Zero;
                SyncClient(surface);
                KeepReachable(surface);
                RequestResize(surface);
                break;
            case WM_MOVING when window:
                _movingWindowId = surface!.Id;
                break;
            case WM_TIMER when window && (surface!.InSizeMove || surface.InMenuLoop):
                Pump();
                if (surface!.OpenItem >= 0) TrackMenuSwitch(surface);
                if (surface.InSizeMove && Environment.TickCount64 - surface.LastResizeRequest >= 100)
                    RequestResize(surface);
                return IntPtr.Zero;
            case WM_MOVE when window:
                SyncClient(surface!);
                break;
            case WM_SIZE when window:
                if ((long)wParam != SIZE_MINIMIZED)
                {
                    SyncClient(surface!);
                    if (!surface!.InSizeMove) RequestResize(surface);
                }
                foreach (var popup in _surfaces.Values.Where(s => s.Owner == hWnd).ToList()) ApplyVisibility(popup);
                PublishProxies();
                break;
            case WM_DPICHANGED when window:
                var suggested = Marshal.PtrToStructure<RECT>(lParam);
                SetWindowPos(hWnd, IntPtr.Zero, suggested.Left, suggested.Top, suggested.Width, suggested.Height,
                    SWP_NOZORDER | SWP_NOACTIVATE);
                surface!.HeaderHeight = HeaderHeightFor(hWnd, (uint)(((long)wParam >> 16) & 0xFFFF));
                KeepReachable(surface!);
                SyncClient(surface!);
                RequestResize(surface!);
                return IntPtr.Zero;
            case WM_DISPLAYCHANGE:
                foreach (var s in _surfaces.Values.ToList()) KeepReachable(s);
                break;
            case WM_ERASEBKGND:
                return 1;
            case WM_SYSCOMMAND when ((long)wParam & 0xFFF0) == SC_KEYMENU:
                return IntPtr.Zero; // Alt/Option belongs to the Mac; menus can be opened with the mouse.
            case WM_CLOSE:
                if (window) CloseRequested?.Invoke(surface!.Id);
                return IntPtr.Zero;
        }
        return DefWindowProcW(hWnd, msg, wParam, lParam);
    }

    private void RequestKeyframe(uint? streamId)
    {
        if (streamId is null)
        {
            var now = Environment.TickCount64;
            if (now - Interlocked.Read(ref _lastKeyframeRequestTicks) < 300) return;
            Interlocked.Exchange(ref _lastKeyframeRequestTicks, now);
        }
        KeyframeNeeded?.Invoke(streamId);
    }

    private static void DisposeDecoder(Surface surface)
    {
        DisposeProcessor(surface);
        surface.Decoder?.Dispose();
        surface.Decoder = null;
        surface.DecoderWidth = surface.DecoderHeight = 0;
    }

    private static void DisposeProcessor(Surface surface)
    {
        foreach (var view in surface.InputViews.Values) view.Dispose();
        surface.InputViews.Clear();
        surface.OutputView?.Dispose();
        surface.OutputView = null;
        surface.Processor?.Dispose();
        surface.Processor = null;
        surface.Enumerator?.Dispose();
        surface.Enumerator = null;
        surface.VideoBitmap?.Dispose();
        surface.VideoBitmap = null;
        surface.VideoTexture?.Dispose();
        surface.VideoTexture = null;
        surface.ProcessorInputWidth = surface.ProcessorInputHeight = surface.ProcessorOutputWidth = surface.ProcessorOutputHeight = 0;
    }

    private static void DisposeGpu(Surface surface)
    {
        DisposeDecoder(surface);
        surface.UploadStaging?.Dispose();
        surface.UploadStaging = null;
        surface.UploadTexture?.Dispose();
        surface.UploadTexture = null;
        surface.Target?.Dispose();
        surface.Target = null;
        surface.HeaderTarget?.Dispose();
        surface.HeaderTarget = null;
        surface.HeaderVisual?.Dispose();
        surface.HeaderVisual = null;
        surface.RootVisual?.Dispose();
        surface.RootVisual = null;
        surface.HeaderChain?.Dispose();
        surface.HeaderChain = null;
        surface.Visual?.Dispose();
        surface.Visual = null;
        surface.CompositionTarget?.Dispose();
        surface.CompositionTarget = null;
        surface.SwapChain?.Dispose();
        surface.SwapChain = null;
        surface.HasVideo = false;
    }

    private void DisposeDevice()
    {
        _composition?.Dispose();
        _composition = null;
        _d2d?.Dispose();
        _d2d = null;
        _d2dDevice?.Dispose();
        _d2dDevice = null;
        _d2dFactory?.Dispose();
        _d2dFactory = null;
        _factory?.Dispose();
        _factory = null;
        _videoContext?.Dispose();
        _videoContext = null;
        _videoDevice?.Dispose();
        _videoDevice = null;
        _context?.Dispose();
        _context = null;
        _device?.Dispose();
        _device = null;
    }

    private void Cleanup()
    {
        foreach (var surface in _surfaces.Values.ToList()) DestroySurface(surface);
        _proxies = new Dictionary<IntPtr, ProxyInfo>();
        _hasWindows = false;
        DisposeDevice();
        _dwrite?.Dispose();
        _dwrite = null;
        foreach (var icon in _icons.Values) DestroyIcon(icon);
        _icons.Clear();
        _menus.Clear();
        _wantFullscreenVisible = false;
        _movingHandle = IntPtr.Zero;
        _movingWindowId = 0;
        _menuLoopActive = false;
        // Klasa wskazuje na procedurę tej instancji – nie może przeżyć okien.
        UnregisterClassW(ClassName, GetModuleHandle(null));
    }

    public void Dispose()
    {
        Stop();
        _wake.Dispose();
    }
}
