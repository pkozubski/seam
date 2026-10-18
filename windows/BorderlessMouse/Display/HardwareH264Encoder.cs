using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using SharpGen.Runtime;
using Vortice.Direct3D11;
using Vortice.MediaFoundation;
using ResultCode = Vortice.MediaFoundation.ResultCode;

namespace BorderlessMouse.Display;

/// <summary>
/// Sprzętowy koder H.264 (asynchroniczny MFT: NVENC, Quick Sync, AMF) dla strumienia
/// jednego okna. Wejście to tekstury NV12 na wspólnym urządzeniu D3D11, wyjście Annex B
/// bez klatek B, z SPS/PPS przed każdą klatką kluczową. Jeden wątek.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class HardwareH264Encoder : IDisposable
{
    private const uint InterlaceProgressive = 2;
    private const uint ProfileHigh = 100;
    private const uint MatrixBt709 = 1, PrimariesBt709 = 2, TransferBt709 = 5, NominalRange16To235 = 2;
    private const int EventNoWait = 1; // MF_EVENT_FLAG_NO_WAIT
    private const int TexturePoolSize = 3;
    private static readonly long EncodeTimeout = Stopwatch.Frequency / 10;

    // ICodecAPI (codecapi.h)
    private static readonly Guid LowLatencyMode = new("9c27891a-ed7a-40e1-88e8-b22727a024ee");
    private static readonly Guid RateControlMode = new("1c0608e9-370c-4710-8a58-cb6181c42423");
    private static readonly Guid MeanBitRate = new("f7222374-2144-4815-b550-a37f8e12ee52");
    private static readonly Guid MaxBitRate = new("9651eae4-39b9-4ebf-85ef-d7f444ec7465");
    private static readonly Guid QualityVsSpeed = new("98332df8-03cd-476b-89fa-3f9e442dec9f");
    private static readonly Guid GopSize = new("95f31b26-95a4-41aa-9303-246a7fc6eef1");
    private static readonly Guid BPictureCount = new("8d390aac-dc5c-4200-b57f-814d04babab2");
    private static readonly Guid ForceKeyFrame = new("398c1b98-8353-475a-9ef2-8f265d260345");
    private const uint RateControlCbr = 0, RateControlPeakConstrainedVbr = 1;

    private readonly ID3D11Device _device;
    private readonly ID3D11DeviceContext _context;
    private readonly int _framesPerSecond;
    private readonly long _frameDuration;
    private readonly int _frameBytes;
    private readonly ID3D11Texture2D?[] _textures = new ID3D11Texture2D?[TexturePoolSize];
    private readonly List<(byte[] Data, bool Keyframe)> _pending = new();
    private IMFActivate? _activate;
    private IMFTransform? _transform;
    private IMFMediaEventGenerator? _events;
    private IMFDXGIDeviceManager? _manager;
    private ICodecAPI? _codec;
    private int _nextTexture;
    private int _needInput;
    private bool _keyframeRequested;
    private bool _providesSamples;
    private int _outputBufferSize;
    private byte[]? _sequenceHeader;
    private byte[]? _parameterSets;
    private bool _disposed;

    public int Width { get; }
    public int Height { get; }

    private HardwareH264Encoder(ID3D11Device device, int width, int height, int framesPerSecond)
    {
        _device = device;
        Width = width;
        Height = height;
        _framesPerSecond = framesPerSecond;
        _frameDuration = 10_000_000L / framesPerSecond;
        _frameBytes = width * height * 3 / 2;
        MediaFactory.MFStartup(true).CheckError();
        _context = device.ImmediateContext;
    }

    /// <summary>
    /// null, gdy nie ma sprzętowego kodera H.264 albo żaden nie chce wystartować
    /// (np. wyczerpany limit sesji NVENC). Nigdy nie rzuca.
    /// </summary>
    public static HardwareH264Encoder? TryCreate(ID3D11Device device, int width, int height, int framesPerSecond, int bitrateKbps)
    {
        if (width < 16 || height < 16 || width % 2 != 0 || height % 2 != 0 || framesPerSecond <= 0 || bitrateKbps <= 0)
            return null;
        try
        {
            MediaFactory.MFStartup(true).CheckError();
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"HardwareH264Encoder: MFStartup failed: {ex.Message}");
            return null;
        }
        try
        {
            var flags = (uint)(EnumFlag.EnumFlagHardware | EnumFlag.EnumFlagSortandfilter);
            var input = new RegisterTypeInfo { GuidMajorType = MediaTypeGuids.Video, GuidSubtype = VideoFormatGuids.NV12 };
            var output = new RegisterTypeInfo { GuidMajorType = MediaTypeGuids.Video, GuidSubtype = VideoFormatGuids.H264 };
            using var activates = MediaFactory.MFTEnumEx(TransformCategoryGuids.VideoEncoder, flags, input, output);
            foreach (var activate in activates)
            {
                HardwareH264Encoder? encoder = null;
                try
                {
                    encoder = new HardwareH264Encoder(device, width, height, framesPerSecond);
                    encoder.Start(activate, bitrateKbps);
                    return encoder;
                }
                catch (Exception ex)
                {
                    Debug.WriteLine($"HardwareH264Encoder: candidate rejected: {ex.Message}");
                    encoder?.Dispose();
                }
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"HardwareH264Encoder: enumeration failed: {ex.Message}");
        }
        finally
        {
            MediaFactory.MFShutdown();
        }
        return null;
    }

    private void Start(IMFActivate activate, int bitrateKbps)
    {
        // Własna referencja – kolekcja z MFTEnumEx zwalnia swoje przy Dispose.
        _activate = activate.QueryInterface<IMFActivate>();
        _transform = _activate.ActivateObject<IMFTransform>();
        using (var attributes = _transform.Attributes)
        {
            if (MediaFactory.MFGetAttributeUInt32(attributes, TransformAttributeKeys.TransformAsync, 0) == 0)
                throw new InvalidOperationException("Hardware MFT is not asynchronous.");
            attributes.Set(TransformAttributeKeys.TransformAsyncUnlock, 1u);
        }
        _events = _transform.QueryInterface<IMFMediaEventGenerator>();

        _manager = MediaFactory.MFCreateDXGIDeviceManager();
        _manager.ResetDevice(_device).CheckError();
        _transform.ProcessMessage(TMessageType.MessageSetD3DManager, (UIntPtr)(nuint)_manager.NativePointer);

        try
        {
            _codec = Marshal.GetObjectForIUnknown(_transform.NativePointer) as ICodecAPI;
        }
        catch (InvalidCastException)
        {
            _codec = null;
        }
        // Część sterowników (Intel) czyta tryb bitrate'u tylko przed typami, część (NVENC) dopiero po – ustawiamy dwa razy.
        ConfigureCodec(bitrateKbps);

        using (var output = MediaFactory.MFCreateMediaType())
        {
            output.Set(MediaTypeAttributeKeys.MajorType, MediaTypeGuids.Video);
            output.Set(MediaTypeAttributeKeys.Subtype, VideoFormatGuids.H264);
            output.Set(MediaTypeAttributeKeys.AvgBitrate, (uint)bitrateKbps * 1000);
            output.Set(MediaTypeAttributeKeys.InterlaceMode, InterlaceProgressive);
            output.Set(MediaTypeAttributeKeys.Mpeg2Profile, ProfileHigh);
            SetColor(output);
            MediaFactory.MFSetAttributeSize(output, MediaTypeAttributeKeys.FrameSize, (uint)Width, (uint)Height);
            MediaFactory.MFSetAttributeRatio(output, MediaTypeAttributeKeys.FrameRate, (uint)_framesPerSecond, 1);
            MediaFactory.MFSetAttributeRatio(output, MediaTypeAttributeKeys.PixelAspectRatio, 1, 1);
            _transform.SetOutputType(0, output, 0);
        }
        using (var input = MediaFactory.MFCreateMediaType())
        {
            input.Set(MediaTypeAttributeKeys.MajorType, MediaTypeGuids.Video);
            input.Set(MediaTypeAttributeKeys.Subtype, VideoFormatGuids.NV12);
            input.Set(MediaTypeAttributeKeys.InterlaceMode, InterlaceProgressive);
            SetColor(input);
            MediaFactory.MFSetAttributeSize(input, MediaTypeAttributeKeys.FrameSize, (uint)Width, (uint)Height);
            MediaFactory.MFSetAttributeRatio(input, MediaTypeAttributeKeys.FrameRate, (uint)_framesPerSecond, 1);
            MediaFactory.MFSetAttributeRatio(input, MediaTypeAttributeKeys.PixelAspectRatio, 1, 1);
            _transform.SetInputType(0, input, 0);
        }
        ConfigureCodec(bitrateKbps);
        UpdateOutputInfo();

        for (var i = 0; i < _textures.Length; i++) _textures[i] = CreateTexture();

        _transform.ProcessMessage(TMessageType.MessageNotifyBeginStreaming, UIntPtr.Zero);
        _transform.ProcessMessage(TMessageType.MessageNotifyStartOfStream, UIntPtr.Zero);
    }

    private ID3D11Texture2D CreateTexture()
    {
        try
        {
            return _device.CreateTexture2D(new Texture2DDescription(Vortice.DXGI.Format.NV12, (uint)Width, (uint)Height, 1, 1,
                BindFlags.RenderTarget | BindFlags.ShaderResource, ResourceUsage.Default, CpuAccessFlags.None, 1, 0, ResourceOptionFlags.None));
        }
        catch (SharpGenException)
        {
            // starsze sterowniki nie pozwalają na NV12 jako render target
            return _device.CreateTexture2D(new Texture2DDescription(Vortice.DXGI.Format.NV12, (uint)Width, (uint)Height, 1, 1,
                BindFlags.ShaderResource, ResourceUsage.Default, CpuAccessFlags.None, 1, 0, ResourceOptionFlags.None));
        }
    }

    private static void SetColor(IMFMediaType type)
    {
        type.Set(MediaTypeAttributeKeys.YuvMatrix, MatrixBt709);
        type.Set(MediaTypeAttributeKeys.VideoPrimaries, PrimariesBt709);
        type.Set(MediaTypeAttributeKeys.TransferFunction, TransferBt709);
        type.Set(MediaTypeAttributeKeys.VideoNominalRange, NominalRange16To235);
    }

    private void ConfigureCodec(int bitrateKbps)
    {
        SetCodec(LowLatencyMode, true);
        if (SetCodec(RateControlMode, RateControlPeakConstrainedVbr) < 0) SetCodec(RateControlMode, RateControlCbr);
        SetCodec(MeanBitRate, (uint)bitrateKbps * 1000);
        SetCodec(MaxBitRate, (uint)bitrateKbps * 2000);
        SetCodec(BPictureCount, 0u);
        // Klatki kluczowe tylko na żądanie (nowy odbiorca, utrata pakietów).
        SetCodec(GopSize, (uint)_framesPerSecond * 3600);
        SetCodec(QualityVsSpeed, 50u);
    }

    /// <summary>HRESULT z ICodecAPI::SetValue; błędy pojedynczych właściwości ignorujemy.</summary>
    private int SetCodec(Guid api, object value)
    {
        if (_codec is null) return -1;
        try
        {
            var key = api;
            return _codec.SetValue(ref key, ref value);
        }
        catch (COMException ex)
        {
            return ex.HResult;
        }
    }

    private void UpdateOutputInfo()
    {
        var info = _transform!.GetOutputStreamInfo(0);
        const int provides = (int)(OutputStreamInfoFlags.OutputStreamProvidesSamples | OutputStreamInfoFlags.OutputStreamCanProvideSamples);
        _providesSamples = (info.Flags & provides) != 0;
        _outputBufferSize = Math.Max(info.Size, _frameBytes);
    }

    /// <summary>
    /// Koduje teksturę NV12 (<c>Width</c>×<c>Height</c>, to samo urządzenie). Tekstura jest
    /// kopiowana przed powrotem. Zwraca Annex B tej klatki albo null, gdy koder nic nie
    /// oddał w ~100 ms. Wymuszenie klatki kluczowej, której koder nie przyjął, przechodzi
    /// na następne wywołanie.
    /// </summary>
    public (byte[] AnnexB, bool Keyframe)? Encode(ID3D11Texture2D nv12, long timestamp100ns, bool forceKeyframe)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        var deadline = Stopwatch.GetTimestamp() + EncodeTimeout;
        _keyframeRequested |= forceKeyframe;

        var texture = _textures[_nextTexture]!;
        _nextTexture = (_nextTexture + 1) % _textures.Length;
        _context.CopyResource(texture, nv12);

        // Bez METransformNeedInput koder nie przyjmie wejścia – klatkę pomijamy.
        if (!Pump(deadline, waitForOutput: false)) return TakePending();

        if (_keyframeRequested) SetCodec(ForceKeyFrame, 1u);
        using (var buffer = MediaFactory.MFCreateDXGISurfaceBuffer(typeof(ID3D11Texture2D).GUID, texture, 0, false))
        {
            buffer.CurrentLength = ContiguousLength(buffer);
            using var sample = MediaFactory.MFCreateSample();
            sample.AddBuffer(buffer);
            sample.SampleTime = timestamp100ns;
            sample.SampleDuration = _frameDuration;
            _transform!.ProcessInput(0, sample, 0);
        }
        _needInput--;
        _keyframeRequested = false;

        Pump(deadline, waitForOutput: true);
        return TakePending();
    }

    private int ContiguousLength(IMFMediaBuffer buffer)
    {
        try
        {
            using var buffer2D = buffer.QueryInterface<IMF2DBuffer>();
            return buffer2D.ContiguousLength;
        }
        catch (SharpGenException)
        {
            return _frameBytes;
        }
    }

    /// <summary>
    /// Odbiera zdarzenia MFT bez blokowania (GetEvent z blokadą mógłby zawisnąć na zawsze)
    /// aż do wejścia/wyjścia albo terminu. false = termin minął.
    /// </summary>
    private bool Pump(long deadline, bool waitForOutput)
    {
        var started = Stopwatch.GetTimestamp();
        while (waitForOutput ? _pending.Count == 0 : _needInput <= 0)
        {
            IMFMediaEvent mediaEvent;
            try
            {
                mediaEvent = _events!.GetEvent(EventNoWait);
            }
            catch (SharpGenException ex) when (ex.ResultCode == ResultCode.NoEventsAvailable)
            {
                var now = Stopwatch.GetTimestamp();
                if (now >= deadline) return false;
                // Sleep(1) to do 15 ms przy domyślnej rozdzielczości zegara – najpierw tylko oddajemy kwant.
                if (now - started < Stopwatch.Frequency / 250) Thread.Yield();
                else Thread.Sleep(1);
                continue;
            }
            using (mediaEvent) HandleEvent(mediaEvent);
        }
        return true;
    }

    private void HandleEvent(IMFMediaEvent mediaEvent)
    {
        switch (mediaEvent.EventType)
        {
            case MediaEventTypes.TransformNeedInput:
                _needInput++;
                break;
            case MediaEventTypes.TransformHaveOutput:
                ReadOutput();
                break;
            case MediaEventTypes.Error:
                throw new InvalidOperationException($"Hardware H.264 encoder error 0x{mediaEvent.Status.Code:X8}.");
        }
    }

    private void ReadOutput()
    {
        IMFSample? own = null;
        if (!_providesSamples)
        {
            own = MediaFactory.MFCreateSample();
            using var outBuffer = MediaFactory.MFCreateMemoryBuffer(_outputBufferSize);
            own.AddBuffer(outBuffer);
        }
        var output = new OutputDataBuffer { StreamID = 0, Sample = own! };
        var result = _transform!.ProcessOutput(ProcessOutputFlags.None, 1, ref output, out _);
        output.Events?.Dispose();
        // Wrapper próbki podanej przez nas nie ma własnej referencji – zwalniamy tylko `own`.
        var produced = own ?? output.Sample;
        try
        {
            if (result == ResultCode.TransformStreamChange)
            {
                // Nowy typ wyjścia (np. dopiero teraz zna SPS/PPS); próbka przyjdzie z kolejnym METransformHaveOutput.
                using (var type = _transform.GetOutputAvailableType(0, 0)) _transform.SetOutputType(0, type, 0);
                _sequenceHeader = null;
                UpdateOutputInfo();
                return;
            }
            if (result == ResultCode.TransformNeedMoreInput) return;
            result.CheckError();
            if (produced is null) return;

            var clean = produced.GetUInt32(SampleAttributeKeys.CleanPoint, out var cleanPoint).Success && cleanPoint != 0;
            byte[] data;
            using (var contiguous = produced.ConvertToContiguousBuffer())
            {
                contiguous.Lock(out var pointer, out _, out var length);
                try
                {
                    data = new byte[length];
                    Marshal.Copy(pointer, data, 0, length);
                }
                finally
                {
                    contiguous.Unlock();
                }
            }
            if (data.Length == 0) return;
            if (H264Encoder.ContainsNal(data, 7)) _parameterSets = ExtractParameterSets(data) ?? _parameterSets;
            var keyframe = clean || H264Encoder.ContainsNal(data, 5);
            if (keyframe) data = WithParameterSets(data);
            _pending.Add((data, keyframe));
        }
        finally
        {
            produced?.Dispose();
        }
    }

    private (byte[] AnnexB, bool Keyframe)? TakePending()
    {
        if (_pending.Count == 0) return null;
        if (_pending.Count == 1)
        {
            var single = _pending[0];
            _pending.Clear();
            return (single.Data, single.Keyframe);
        }
        var total = 0;
        var keyframe = false;
        foreach (var (data, key) in _pending)
        {
            total += data.Length;
            keyframe |= key;
        }
        var result = new byte[total];
        var offset = 0;
        foreach (var (data, _) in _pending)
        {
            data.CopyTo(result, offset);
            offset += data.Length;
        }
        _pending.Clear();
        return (result, keyframe);
    }

    /// <summary>Mac tworzy dekoder z SPS/PPS – dokładamy je przed klatką kluczową, jeśli koder ich nie wstawił.</summary>
    private byte[] WithParameterSets(byte[] accessUnit)
    {
        if (H264Encoder.ContainsNal(accessUnit, 7)) return accessUnit;
        if (_sequenceHeader is null)
        {
            try
            {
                using var type = _transform!.GetOutputCurrentType(0);
                _sequenceHeader = type.GetBlob(MediaTypeAttributeKeys.MpegSequenceHeader);
            }
            catch (SharpGenException)
            {
                _sequenceHeader = Array.Empty<byte>();
            }
        }
        var header = _sequenceHeader is { Length: > 0 } ? _sequenceHeader : _parameterSets;
        if (header is not { Length: > 0 }) return accessUnit;
        var result = new byte[header.Length + accessUnit.Length];
        header.CopyTo(result, 0);
        accessUnit.CopyTo(result, header.Length);
        return result;
    }

    /// <summary>SPS i PPS (NAL 7 i 8) z Annex B, każdy z 4-bajtowym kodem startu.</summary>
    private static byte[]? ExtractParameterSets(byte[] annexB)
    {
        var starts = new List<(int Prefix, int Payload)>();
        for (var i = 0; i + 2 < annexB.Length; i++)
        {
            if (annexB[i] != 0 || annexB[i + 1] != 0 || annexB[i + 2] != 1) continue;
            starts.Add((i > 0 && annexB[i - 1] == 0 ? i - 1 : i, i + 3));
            i += 2;
        }
        using var result = new MemoryStream();
        for (var k = 0; k < starts.Count; k++)
        {
            var payload = starts[k].Payload;
            var end = k + 1 < starts.Count ? starts[k + 1].Prefix : annexB.Length;
            if (payload >= end) continue;
            var type = annexB[payload] & 0x1F;
            if (type != 7 && type != 8) continue;
            result.Write([0, 0, 0, 1]);
            result.Write(annexB, payload, end - payload);
        }
        return result.Length > 0 ? result.ToArray() : null;
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        if (_transform is not null)
        {
            try { _transform.ProcessMessage(TMessageType.MessageNotifyEndOfStream, UIntPtr.Zero); } catch (SharpGenException) { }
            try { _transform.ProcessMessage(TMessageType.MessageCommandFlush, UIntPtr.Zero); } catch (SharpGenException) { }
            try { _transform.ProcessMessage(TMessageType.MessageNotifyEndStreaming, UIntPtr.Zero); } catch (SharpGenException) { }
            if (_manager is not null)
            {
                try { _transform.ProcessMessage(TMessageType.MessageSetD3DManager, UIntPtr.Zero); } catch (SharpGenException) { }
            }
        }
        if (_codec is not null) Marshal.ReleaseComObject(_codec);
        _codec = null;
        if (_transform?.QueryInterfaceOrNull<IMFShutdown>() is { } shutdown)
        {
            try { shutdown.Shutdown(); } catch (SharpGenException) { }
            shutdown.Dispose();
        }
        _events?.Dispose();
        _transform?.Dispose();
        if (_activate is not null)
        {
            // Sprzętowe MFT zwalniają sesję kodera (np. NVENC) dopiero przy ShutdownObject.
            _activate.ShutdownObject();
            _activate.Dispose();
        }
        _manager?.Dispose();
        foreach (var texture in _textures) texture?.Dispose();
        _context.Dispose();
        _pending.Clear();
        MediaFactory.MFShutdown();
    }

    /// <summary>ICodecAPI (strmif.h) – tylko metody używane tutaj, w kolejności z vtable.</summary>
    [ComImport]
    [Guid("901db4c7-31ce-41a2-85dc-8fa0bf41b8da")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface ICodecAPI
    {
        [PreserveSig] int IsSupported(ref Guid api);
        [PreserveSig] int IsModifiable(ref Guid api);
        [PreserveSig] int GetParameterRange(ref Guid api, out object valueMin, out object valueMax, out object steppingDelta);
        [PreserveSig] int GetParameterValues(ref Guid api, out IntPtr values, out uint valuesCount);
        [PreserveSig] int GetDefaultValue(ref Guid api, out object value);
        [PreserveSig] int GetValue(ref Guid api, out object value);
        [PreserveSig] int SetValue(ref Guid api, [In] ref object value);
    }
}
