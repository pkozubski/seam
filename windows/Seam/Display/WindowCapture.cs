using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using SharpGen.Runtime;
using Vortice.Direct3D11;
using Vortice.DXGI;
using static Seam.Input.NativeMethods;

namespace Seam.Display;

/// <summary>
/// Przechwytywanie pojedynczego okna przez Windows.Graphics.Capture (surowe COM/WinRT, bez CsWinRT)
/// i konwersja BGRA → NV12 (BT.709, 16–235) procesorem wideo D3D11. Wywołania z jednego wątku.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed unsafe class WindowCapture : IDisposable
{
    // ---------------- WinRT: klasy i IID (Windows SDK: windows.graphics.capture.idl/.h, *.interop.h) ----------------

    private const string ItemClass = "Windows.Graphics.Capture.GraphicsCaptureItem";
    private const string FramePoolClass = "Windows.Graphics.Capture.Direct3D11CaptureFramePool";
    private const string SessionClass = "Windows.Graphics.Capture.GraphicsCaptureSession";

    // IGraphicsCaptureItemInterop : IUnknown (windows.graphics.capture.interop.h)
    private static readonly Guid IID_IGraphicsCaptureItemInterop = new("3628E81B-3CAC-4C60-B7F4-23CE0E0C3356");
    private const int ItemInterop_CreateForWindow = 3;

    // IGraphicsCaptureItem : IInspectable – get_DisplayName(6), get_Size(7), add_Closed(8), remove_Closed(9)
    private static readonly Guid IID_IGraphicsCaptureItem = new("79C3F95B-31F7-4EC2-A464-632EF5D30760");
    private const int Item_GetSize = 7;

    // IDirect3D11CaptureFramePoolStatics2 : IInspectable – CreateFreeThreaded(6)
    private static readonly Guid IID_IDirect3D11CaptureFramePoolStatics2 = new("589B103F-6BBC-5DF5-A991-02E28B3B66D5");
    private const int FramePoolStatics2_CreateFreeThreaded = 6;

    // IDirect3D11CaptureFramePool : IInspectable – Recreate(6), TryGetNextFrame(7), add_FrameArrived(8),
    // remove_FrameArrived(9), CreateCaptureSession(10), get_DispatcherQueue(11)
    private const int FramePool_Recreate = 6;
    private const int FramePool_TryGetNextFrame = 7;
    private const int FramePool_CreateCaptureSession = 10;

    // IGraphicsCaptureSessionStatics : IInspectable – IsSupported(6)
    private static readonly Guid IID_IGraphicsCaptureSessionStatics = new("2224A540-5974-49AA-B232-0882536F4CB5");
    private const int SessionStatics_IsSupported = 6;

    // IGraphicsCaptureSession : IInspectable – StartCapture(6)
    private const int Session_StartCapture = 6;

    // IGraphicsCaptureSession2 : IInspectable – get_IsCursorCaptureEnabled(6), put_IsCursorCaptureEnabled(7)
    private static readonly Guid IID_IGraphicsCaptureSession2 = new("2C39AE40-7D2E-5044-804E-8B6799D4CF9E");
    private const int Session2_PutIsCursorCaptureEnabled = 7;

    // IGraphicsCaptureSession3 : IInspectable – get_IsBorderRequired(6), put_IsBorderRequired(7)
    private static readonly Guid IID_IGraphicsCaptureSession3 = new("F2CDD966-22AE-5EA1-9596-3A289344C3BE");
    private const int Session3_PutIsBorderRequired = 7;

    // IDirect3D11CaptureFrame : IInspectable – get_Surface(6), get_SystemRelativeTime(7), get_ContentSize(8)
    private const int Frame_GetSurface = 6;
    private const int Frame_GetContentSize = 8;

    // Windows.Foundation.IClosable : IInspectable – Close(6)
    private static readonly Guid IID_IClosable = new("30D5A829-7FA4-4026-83BB-D75BAE4EA99E");
    private const int Closable_Close = 6;

    // Windows.Graphics.DirectX.Direct3D11.IDirect3DDevice (windows.graphics.directx.direct3d11.idl)
    private static readonly Guid IID_IDirect3DDevice = new("A37624AB-8D5F-4650-9D3E-9EAE3D9BC670");

    // IDirect3DDxgiInterfaceAccess : IUnknown – GetInterface(3) (windows.graphics.directx.direct3d11.interop.h)
    private static readonly Guid IID_IDirect3DDxgiInterfaceAccess = new("A9B3D012-3DF2-4EE3-B8D1-8695F457D3C1");
    private const int DxgiAccess_GetInterface = 3;

    private static readonly Guid IID_ID3D11Texture2D = new("6F15AAF2-D208-4E89-9AB4-489535D34F9C");

    private const int IUnknown_QueryInterface = 0;
    private const int DirectXPixelFormat_B8G8R8A8UIntNormalized = 87;
    private const int BufferCount = 2;
    private const int Bucket = 64;
    private const uint DWMWA_EXTENDED_FRAME_BOUNDS = 9;

    private const int CO_E_NOTINITIALIZED = unchecked((int)0x800401F0);
    private const int RO_E_CLOSED = unchecked((int)0x80000013);
    private const int DXGI_ERROR_DEVICE_REMOVED = unchecked((int)0x887A0005);
    private const int DXGI_ERROR_DEVICE_HUNG = unchecked((int)0x887A0006);
    private const int DXGI_ERROR_DEVICE_RESET = unchecked((int)0x887A0007);
    private const uint RO_INIT_MULTITHREADED = 1;

    [StructLayout(LayoutKind.Sequential)]
    private struct SizeInt32
    {
        public int Width;
        public int Height;
    }

    private static readonly Lazy<bool> s_supported = new(ProbeSupport);

    private readonly ID3D11Device _device;
    private ID3D11DeviceContext? _context;
    private ID3D11VideoDevice? _videoDevice;
    private ID3D11VideoContext? _videoContext;

    private IntPtr _winrtDevice;
    private IntPtr _item;
    private IntPtr _framePool;
    private IntPtr _session;
    private SizeInt32 _poolSize;

    private ID3D11VideoProcessorEnumerator? _enumerator;
    private ID3D11VideoProcessor? _processor;
    private ID3D11VideoProcessorOutputView? _outputView;
    private readonly Dictionary<IntPtr, ID3D11VideoProcessorInputView> _inputViews = new();
    private int _processorInputWidth;
    private int _processorInputHeight;
    // Gdy sterownik nie przyjmie widoku wejściowego na teksturze WGC – kopiujemy do własnej.
    private bool _copyInput;
    private ID3D11Texture2D? _inputCopy;

    private ID3D11Texture2D? _nv12;
    private ID3D11Texture2D? _staging;
    private bool _hasFrame;
    private bool _disposed;

    /// <summary>WGC present (Windows 10 1903 / build 18362+) and activation factories resolve.</summary>
    public static bool IsSupported => s_supported.Value;

    public IntPtr Window { get; }
    public ID3D11Texture2D? Nv12Texture => _hasFrame ? _nv12 : null;
    public int Width { get; private set; }
    public int Height { get; private set; }
    public int ContentWidth { get; private set; }
    public int ContentHeight { get; private set; }
    public bool Closed { get; private set; }

    /// <param name="device">Wspólne urządzenie (BgraSupport|VideoSupport, multithread-protected); należy do wywołującego.</param>
    public WindowCapture(ID3D11Device device, IntPtr hwnd)
    {
        if (!IsWindow(hwnd)) throw new InvalidOperationException("The window does not exist.");
        _device = device;
        Window = hwnd;
        try
        {
            // Vortice zapamiętuje ten obiekt w urządzeniu – wspólny dla wszystkich okien i koderów, nie zwalniamy go.
            _context = device.ImmediateContext;
            _videoDevice = device.QueryInterface<ID3D11VideoDevice>();
            _videoContext = _context.QueryInterface<ID3D11VideoContext>();
            _winrtDevice = CreateWinRtDevice(device);
            _item = CreateItem(hwnd);

            SizeInt32 size;
            Check(((delegate* unmanaged[Stdcall]<IntPtr, SizeInt32*, int>)Slot(_item, Item_GetSize))(_item, &size), "GraphicsCaptureItem.Size");
            if (size.Width <= 0 || size.Height <= 0) throw new InvalidOperationException("The window has no capturable area.");
            _poolSize = size;

            var statics = GetActivationFactory(FramePoolClass, IID_IDirect3D11CaptureFramePoolStatics2);
            try
            {
                IntPtr pool;
                Check(((delegate* unmanaged[Stdcall]<IntPtr, IntPtr, int, int, SizeInt32, IntPtr*, int>)Slot(statics, FramePoolStatics2_CreateFreeThreaded))(
                    statics, _winrtDevice, DirectXPixelFormat_B8G8R8A8UIntNormalized, BufferCount, size, &pool), "Direct3D11CaptureFramePool.CreateFreeThreaded");
                _framePool = pool;
            }
            finally
            {
                Marshal.Release(statics);
            }

            IntPtr session;
            Check(((delegate* unmanaged[Stdcall]<IntPtr, IntPtr, IntPtr*, int>)Slot(_framePool, FramePool_CreateCaptureSession))(_framePool, _item, &session),
                "Direct3D11CaptureFramePool.CreateCaptureSession");
            _session = session;

            // Opcjonalne: Windows 10 2004+ (kursor) i Windows 11 (żółta ramka) – brak interfejsu ignorujemy.
            TrySetBool(_session, IID_IGraphicsCaptureSession2, Session2_PutIsCursorCaptureEnabled, false);
            TrySetBool(_session, IID_IGraphicsCaptureSession3, Session3_PutIsBorderRequired, false);

            Check(((delegate* unmanaged[Stdcall]<IntPtr, int>)Slot(_session, Session_StartCapture))(_session), "GraphicsCaptureSession.StartCapture");
        }
        catch
        {
            Dispose();
            throw;
        }
    }

    /// <summary>Polls one frame. true = a new frame was converted into Nv12Texture.</summary>
    public bool TryGetFrame()
    {
        if (_disposed || Closed) return false;
        if (!IsWindow(Window))
        {
            Closed = true;
            return false;
        }

        IntPtr frame;
        var hr = ((delegate* unmanaged[Stdcall]<IntPtr, IntPtr*, int>)Slot(_framePool, FramePool_TryGetNextFrame))(_framePool, &frame);
        if (hr < 0)
        {
            Closed = true;
            return false;
        }
        if (frame == IntPtr.Zero) return false;

        try
        {
            return ProcessFrame(frame);
        }
        catch (Exception ex) when (ex is SharpGenException or COMException && IsFatal(ex.HResult))
        {
            Closed = true;
            return false;
        }
        finally
        {
            CloseObject(frame);
            Marshal.Release(frame);
        }
    }

    /// <summary>
    /// CPU fallback: kopiuje bieżącą teksturę NV12 (Width x Height, ciasno upakowaną: Y, potem przeplatane UV).
    /// </summary>
    public bool ReadNv12(byte[] destination)
    {
        if (_disposed || !_hasFrame || _nv12 is null || _context is null) return false;
        var size = Width * Height * 3 / 2;
        if (destination.Length < size) throw new ArgumentException("Destination buffer is too small.", nameof(destination));

        _staging ??= _device.CreateTexture2D(new Texture2DDescription(Format.NV12, (uint)Width, (uint)Height, 1, 1,
            BindFlags.None, ResourceUsage.Staging, CpuAccessFlags.Read, 1, 0, ResourceOptionFlags.None));
        _context.CopyResource(_staging, _nv12);
        var mapped = _context.Map(_staging, 0, MapMode.Read, Vortice.Direct3D11.MapFlags.None);
        try
        {
            var source = (byte*)mapped.DataPointer;
            var pitch = (long)mapped.RowPitch;
            fixed (byte* target = destination)
            {
                for (var y = 0; y < Height; y++)
                    Buffer.MemoryCopy(source + y * pitch, target + (long)y * Width, Width, Width);
                var chroma = source + pitch * Height;
                var chromaTarget = target + (long)Width * Height;
                for (var y = 0; y < Height / 2; y++)
                    Buffer.MemoryCopy(chroma + y * pitch, chromaTarget + (long)y * Width, Width, Width);
            }
        }
        finally
        {
            _context.Unmap(_staging, 0);
        }
        return true;
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;

        if (_session != IntPtr.Zero)
        {
            CloseObject(_session);
            Marshal.Release(_session);
            _session = IntPtr.Zero;
        }
        if (_framePool != IntPtr.Zero)
        {
            CloseObject(_framePool);
            Marshal.Release(_framePool);
            _framePool = IntPtr.Zero;
        }
        if (_item != IntPtr.Zero)
        {
            Marshal.Release(_item);
            _item = IntPtr.Zero;
        }
        if (_winrtDevice != IntPtr.Zero)
        {
            Marshal.Release(_winrtDevice);
            _winrtDevice = IntPtr.Zero;
        }

        DisposeProcessor();
        DisposeOutput();
        _videoContext?.Dispose();
        _videoContext = null;
        _videoDevice?.Dispose();
        _videoDevice = null;
        _context = null;
    }

    // ---------------- klatka ----------------

    private bool ProcessFrame(IntPtr frame)
    {
        SizeInt32 contentSize;
        Check(((delegate* unmanaged[Stdcall]<IntPtr, SizeInt32*, int>)Slot(frame, Frame_GetContentSize))(frame, &contentSize), "Direct3D11CaptureFrame.ContentSize");
        if (contentSize.Width <= 0 || contentSize.Height <= 0) return false;

        if (contentSize.Width != _poolSize.Width || contentSize.Height != _poolSize.Height)
        {
            var hr = ((delegate* unmanaged[Stdcall]<IntPtr, IntPtr, int, int, SizeInt32, int>)Slot(_framePool, FramePool_Recreate))(
                _framePool, _winrtDevice, DirectXPixelFormat_B8G8R8A8UIntNormalized, BufferCount, contentSize);
            if (hr < 0)
            {
                Closed = true;
                return false;
            }
            _poolSize = contentSize;
            // Stare bufory puli znikają – widoki wejściowe trzymałyby je przy życiu.
            ClearInputViews();
            return false;
        }

        using var texture = GetFrameTexture(frame);
        var desc = texture.Description;
        var textureWidth = (int)desc.Width;
        var textureHeight = (int)desc.Height;
        var availableWidth = Math.Min(contentSize.Width, textureWidth);
        var availableHeight = Math.Min(contentSize.Height, textureHeight);

        ComputeCrop(contentSize, availableWidth, availableHeight, out var offsetX, out var offsetY, out var cropWidth, out var cropHeight);
        var contentWidth = cropWidth & ~1;
        var contentHeight = cropHeight & ~1;
        if (contentWidth < 2 || contentHeight < 2) return false;

        EnsureOutput(RoundUp(contentWidth), RoundUp(contentHeight));
        EnsureProcessor(textureWidth, textureHeight, desc.Format);
        ContentWidth = contentWidth;
        ContentHeight = contentHeight;

        var inputView = GetInputView(texture, desc);
        var processor = _processor!;
        var videoContext = _videoContext!;
        videoContext.VideoProcessorSetStreamSourceRect(processor, 0, true,
            new Vortice.RawRect(offsetX, offsetY, offsetX + contentWidth, offsetY + contentHeight));
        videoContext.VideoProcessorSetStreamDestRect(processor, 0, true, new Vortice.RawRect(0, 0, contentWidth, contentHeight));
        var streams = new[] { new VideoProcessorStream { Enable = true, InputSurface = inputView } };
        videoContext.VideoProcessorBlt(processor, _outputView!, 0, 1, streams).CheckError();
        _hasFrame = true;
        return true;
    }

    /// <summary>
    /// Kadr widocznej części okna: WGC może dołączać niewidzialne ramki do zmiany rozmiaru, a Mac
    /// pozycjonuje okno wg DWMWA_EXTENDED_FRAME_BOUNDS (tak raportuje tracker).
    /// </summary>
    private void ComputeCrop(SizeInt32 contentSize, int availableWidth, int availableHeight,
        out int offsetX, out int offsetY, out int cropWidth, out int cropHeight)
    {
        offsetX = 0;
        offsetY = 0;
        var visibleWidth = contentSize.Width;
        var visibleHeight = contentSize.Height;
        if (DisplayNative.DwmGetWindowAttribute(Window, DWMWA_EXTENDED_FRAME_BOUNDS, out var extended, (uint)Marshal.SizeOf<RECT>()) == 0
            && extended.Width > 0 && extended.Height > 0)
        {
            visibleWidth = extended.Width;
            visibleHeight = extended.Height;
            var matchesExtended = contentSize.Width == extended.Width && contentSize.Height == extended.Height;
            if (!matchesExtended && DisplayNative.GetWindowRect(Window, out var windowRect)
                && contentSize.Width == windowRect.Width && contentSize.Height == windowRect.Height)
            {
                offsetX = extended.Left - windowRect.Left;
                offsetY = extended.Top - windowRect.Top;
            }
        }
        offsetX = Math.Clamp(offsetX, 0, availableWidth);
        offsetY = Math.Clamp(offsetY, 0, availableHeight);
        cropWidth = Math.Max(0, Math.Min(visibleWidth, availableWidth - offsetX));
        cropHeight = Math.Max(0, Math.Min(visibleHeight, availableHeight - offsetY));
    }

    private static ID3D11Texture2D GetFrameTexture(IntPtr frame)
    {
        IntPtr surface;
        Check(((delegate* unmanaged[Stdcall]<IntPtr, IntPtr*, int>)Slot(frame, Frame_GetSurface))(frame, &surface), "Direct3D11CaptureFrame.Surface");
        try
        {
            var access = QueryInterface(surface, IID_IDirect3DDxgiInterfaceAccess);
            try
            {
                var iid = IID_ID3D11Texture2D;
                IntPtr texture;
                Check(((delegate* unmanaged[Stdcall]<IntPtr, Guid*, IntPtr*, int>)Slot(access, DxgiAccess_GetInterface))(access, &iid, &texture),
                    "IDirect3DDxgiInterfaceAccess.GetInterface");
                if (texture == IntPtr.Zero) throw new COMException("Capture surface has no texture.", unchecked((int)0x80004003)); // E_POINTER
                return new ID3D11Texture2D(texture);
            }
            finally
            {
                Marshal.Release(access);
            }
        }
        finally
        {
            Marshal.Release(surface);
        }
    }

    private ID3D11VideoProcessorInputView GetInputView(ID3D11Texture2D texture, Texture2DDescription desc)
    {
        var description = new VideoProcessorInputViewDescription
        {
            FourCC = 0,
            ViewDimension = VideoProcessorInputViewDimension.Texture2D,
            Texture2D = new Texture2DVideoProcessorInputView { MipSlice = 0, ArraySlice = 0 },
        };
        if (!_copyInput)
        {
            if (_inputViews.TryGetValue(texture.NativePointer, out var cached)) return cached;
            try
            {
                var view = _videoDevice!.CreateVideoProcessorInputView(texture, _enumerator!, description);
                // Pula ma 2 bufory; większa liczba oznacza nowe tekstury – stare widoki zwalniamy.
                if (_inputViews.Count >= BufferCount * 2) ClearInputViews();
                _inputViews[texture.NativePointer] = view;
                return view;
            }
            catch (SharpGenException ex) when (!IsFatal(ex.HResult))
            {
                _copyInput = true;
                ClearInputViews();
            }
        }

        // Widoki są czyszczone przy odtworzeniu puli – kopia może zostać bez widoku.
        if (_inputCopy is null || !_inputViews.ContainsKey(_inputCopy.NativePointer))
        {
            _inputCopy?.Dispose();
            _inputCopy = _device.CreateTexture2D(new Texture2DDescription(desc.Format, desc.Width, desc.Height, 1, 1,
                BindFlags.RenderTarget | BindFlags.ShaderResource, ResourceUsage.Default, CpuAccessFlags.None, 1, 0, ResourceOptionFlags.None));
            _inputViews[_inputCopy.NativePointer] = _videoDevice!.CreateVideoProcessorInputView(_inputCopy, _enumerator!, description);
        }
        _context!.CopyResource(_inputCopy, texture);
        return _inputViews[_inputCopy.NativePointer];
    }

    // ---------------- zasoby ----------------

    private static int RoundUp(int value) => Math.Max(Bucket, (value + Bucket - 1) / Bucket * Bucket);

    private void EnsureOutput(int width, int height)
    {
        if (_nv12 is not null && Width == width && Height == height) return;
        DisposeOutput();
        DisposeProcessor();
        Width = width;
        Height = height;
        try
        {
            _nv12 = _device.CreateTexture2D(new Texture2DDescription(Format.NV12, (uint)width, (uint)height, 1, 1,
                BindFlags.RenderTarget | BindFlags.ShaderResource, ResourceUsage.Default, CpuAccessFlags.None, 1, 0, ResourceOptionFlags.None));
        }
        catch (SharpGenException ex) when (!IsFatal(ex.HResult))
        {
            // Starsze sterowniki nie pozwalają na NV12 jako SRV.
            _nv12 = _device.CreateTexture2D(new Texture2DDescription(Format.NV12, (uint)width, (uint)height, 1, 1,
                BindFlags.RenderTarget, ResourceUsage.Default, CpuAccessFlags.None, 1, 0, ResourceOptionFlags.None));
        }
    }

    private void EnsureProcessor(int inputWidth, int inputHeight, Format inputFormat)
    {
        if (_processor is not null && _processorInputWidth == inputWidth && _processorInputHeight == inputHeight) return;
        DisposeProcessor();
        _processorInputWidth = inputWidth;
        _processorInputHeight = inputHeight;

        var content = new VideoProcessorContentDescription
        {
            InputFrameFormat = VideoFrameFormat.Progressive,
            InputWidth = (uint)inputWidth,
            InputHeight = (uint)inputHeight,
            OutputWidth = (uint)Width,
            OutputHeight = (uint)Height,
            InputFrameRate = new Rational(60, 1),
            OutputFrameRate = new Rational(60, 1),
            Usage = VideoUsage.PlaybackNormal,
        };
        var videoDevice = _videoDevice!;
        var videoContext = _videoContext!;
        _enumerator = videoDevice.CreateVideoProcessorEnumerator(content);
        if ((_enumerator.CheckVideoProcessorFormat(inputFormat) & VideoProcessorFormatSupport.Input) == 0
            || (_enumerator.CheckVideoProcessorFormat(Format.NV12) & VideoProcessorFormatSupport.Output) == 0)
            throw new InvalidOperationException("The video processor cannot convert BGRA to NV12.");
        _processor = videoDevice.CreateVideoProcessor(_enumerator, 0);

        // Wejście: pełny zakres RGB; wyjście: BT.709, zakres wideo 16–235 (tak jak czyta Mac).
        videoContext.VideoProcessorSetStreamColorSpace(_processor, 0, new VideoProcessorColorSpace { RGB_Range = 0 });
        videoContext.VideoProcessorSetOutputColorSpace(_processor, new VideoProcessorColorSpace
        {
            YCbCr_Matrix = 1,
            Nominal_Range = (uint)VideoProcessorNominalRange.Range_16_235,
        });
        videoContext.VideoProcessorSetStreamFrameFormat(_processor, 0, VideoFrameFormat.Progressive);
        videoContext.VideoProcessorSetStreamAutoProcessingMode(_processor, 0, false);
        // Tło jako czarne RGB – procesor sam przeliczy je na Y=16, UV=128 w przestrzeni wyjściowej.
        videoContext.VideoProcessorSetOutputBackgroundColor(_processor, false,
            new VideoColor { Rgba = new VideoColorRgba { R = 0, G = 0, B = 0, A = 1 } });
        videoContext.VideoProcessorSetOutputTargetRect(_processor, true, new Vortice.RawRect(0, 0, Width, Height));

        _outputView = videoDevice.CreateVideoProcessorOutputView(_nv12!, _enumerator, new VideoProcessorOutputViewDescription
        {
            ViewDimension = VideoProcessorOutputViewDimension.Texture2D,
            Texture2D = new Texture2DVideoProcessorOutputView { MipSlice = 0 },
        });
    }

    private void ClearInputViews()
    {
        foreach (var view in _inputViews.Values) view.Dispose();
        _inputViews.Clear();
    }

    private void DisposeProcessor()
    {
        ClearInputViews();
        _inputCopy?.Dispose();
        _inputCopy = null;
        _outputView?.Dispose();
        _outputView = null;
        _processor?.Dispose();
        _processor = null;
        _enumerator?.Dispose();
        _enumerator = null;
        _processorInputWidth = 0;
        _processorInputHeight = 0;
    }

    private void DisposeOutput()
    {
        _hasFrame = false;
        _staging?.Dispose();
        _staging = null;
        _nv12?.Dispose();
        _nv12 = null;
    }

    // ---------------- WinRT / COM ----------------

    private static bool ProbeSupport()
    {
        if (!OperatingSystem.IsWindowsVersionAtLeast(10, 0, 18362)) return false;
        IntPtr interop = IntPtr.Zero, statics = IntPtr.Zero, sessionStatics = IntPtr.Zero;
        try
        {
            interop = GetActivationFactory(ItemClass, IID_IGraphicsCaptureItemInterop);
            statics = GetActivationFactory(FramePoolClass, IID_IDirect3D11CaptureFramePoolStatics2);
            sessionStatics = GetActivationFactory(SessionClass, IID_IGraphicsCaptureSessionStatics);
            byte supported = 0;
            var hr = ((delegate* unmanaged[Stdcall]<IntPtr, byte*, int>)Slot(sessionStatics, SessionStatics_IsSupported))(sessionStatics, &supported);
            return hr >= 0 && supported != 0;
        }
        catch (Exception ex) when (ex is COMException or DllNotFoundException or EntryPointNotFoundException)
        {
            return false;
        }
        finally
        {
            if (interop != IntPtr.Zero) Marshal.Release(interop);
            if (statics != IntPtr.Zero) Marshal.Release(statics);
            if (sessionStatics != IntPtr.Zero) Marshal.Release(sessionStatics);
        }
    }

    private static IntPtr CreateWinRtDevice(ID3D11Device device)
    {
        using var dxgiDevice = device.QueryInterface<IDXGIDevice>();
        Check(CreateDirect3D11DeviceFromDXGIDevice(dxgiDevice.NativePointer, out var inspectable), "CreateDirect3D11DeviceFromDXGIDevice");
        try
        {
            return QueryInterface(inspectable, IID_IDirect3DDevice);
        }
        finally
        {
            Marshal.Release(inspectable);
        }
    }

    private static IntPtr CreateItem(IntPtr hwnd)
    {
        var interop = GetActivationFactory(ItemClass, IID_IGraphicsCaptureItemInterop);
        try
        {
            var iid = IID_IGraphicsCaptureItem;
            IntPtr item;
            Check(((delegate* unmanaged[Stdcall]<IntPtr, IntPtr, Guid*, IntPtr*, int>)Slot(interop, ItemInterop_CreateForWindow))(interop, hwnd, &iid, &item),
                "IGraphicsCaptureItemInterop.CreateForWindow");
            return item;
        }
        finally
        {
            Marshal.Release(interop);
        }
    }

    private static IntPtr GetActivationFactory(string className, Guid iid)
    {
        Check(WindowsCreateString(className, (uint)className.Length, out var hstring), "WindowsCreateString");
        try
        {
            IntPtr factory;
            var hr = RoGetActivationFactory(hstring, &iid, &factory);
            if (hr == CO_E_NOTINITIALIZED)
            {
                // Wątek bez apartamentu COM – dołączamy go do MTA (celowo bez RoUninitialize).
                RoInitialize(RO_INIT_MULTITHREADED);
                hr = RoGetActivationFactory(hstring, &iid, &factory);
            }
            Check(hr, className);
            return factory;
        }
        finally
        {
            WindowsDeleteString(hstring);
        }
    }

    private static void TrySetBool(IntPtr obj, Guid iid, int slot, bool value)
    {
        IntPtr target;
        if (((delegate* unmanaged[Stdcall]<IntPtr, Guid*, IntPtr*, int>)Slot(obj, IUnknown_QueryInterface))(obj, &iid, &target) < 0
            || target == IntPtr.Zero) return;
        try
        {
            _ = ((delegate* unmanaged[Stdcall]<IntPtr, byte, int>)Slot(target, slot))(target, value ? (byte)1 : (byte)0);
        }
        finally
        {
            Marshal.Release(target);
        }
    }

    private static void CloseObject(IntPtr obj)
    {
        var iid = IID_IClosable;
        IntPtr closable;
        if (((delegate* unmanaged[Stdcall]<IntPtr, Guid*, IntPtr*, int>)Slot(obj, IUnknown_QueryInterface))(obj, &iid, &closable) < 0
            || closable == IntPtr.Zero) return;
        try
        {
            _ = ((delegate* unmanaged[Stdcall]<IntPtr, int>)Slot(closable, Closable_Close))(closable);
        }
        finally
        {
            Marshal.Release(closable);
        }
    }

    private static IntPtr QueryInterface(IntPtr obj, Guid iid)
    {
        IntPtr result;
        Check(((delegate* unmanaged[Stdcall]<IntPtr, Guid*, IntPtr*, int>)Slot(obj, IUnknown_QueryInterface))(obj, &iid, &result), "QueryInterface");
        return result;
    }

    private static IntPtr Slot(IntPtr obj, int index) => (*(IntPtr**)obj)[index];

    private static void Check(int hr, string operation)
    {
        if (hr < 0) throw new COMException(operation + " failed.", hr);
    }

    private static bool IsFatal(int hr) =>
        hr is RO_E_CLOSED or DXGI_ERROR_DEVICE_REMOVED or DXGI_ERROR_DEVICE_HUNG or DXGI_ERROR_DEVICE_RESET;

    [DllImport("combase.dll", ExactSpelling = true)]
    private static extern int RoGetActivationFactory(IntPtr activatableClassId, Guid* iid, IntPtr* factory);

    [DllImport("combase.dll", ExactSpelling = true)]
    private static extern int RoInitialize(uint initType);

    [DllImport("combase.dll", ExactSpelling = true, CharSet = CharSet.Unicode)]
    private static extern int WindowsCreateString(string sourceString, uint length, out IntPtr hstring);

    [DllImport("combase.dll", ExactSpelling = true)]
    private static extern int WindowsDeleteString(IntPtr hstring);

    [DllImport("d3d11.dll", ExactSpelling = true)]
    private static extern int CreateDirect3D11DeviceFromDXGIDevice(IntPtr dxgiDevice, out IntPtr graphicsDevice);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindow(IntPtr hWnd);
}
