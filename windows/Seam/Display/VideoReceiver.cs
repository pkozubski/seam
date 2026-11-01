using System.Buffers.Binary;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using Seam.Protocol;
using static Seam.Localization.L10n;

namespace Seam.Display;

/// <summary>
/// Odbiera zaszyfrowany strumień ekranu z Maca. Łączy się z jednorazowym portem
/// z DISPLAY_READY, przedstawia się tokenem i od tej chwili tylko czyta rekordy.
/// Działa na własnym wątku; zdarzenia są wywoływane na tym wątku.
/// </summary>
public sealed class VideoReceiver : IDisposable
{
    private TcpClient? _tcp;
    private Thread? _thread;
    private volatile bool _running;
    private long _framesReceived;
    private long _bytesReceived;

    public event Action<VideoStream.VideoFrame>? FrameReceived;
    /// <summary>Połączenie zakończone; null = zatrzymane lokalnie.</summary>
    public event Action<string?>? Closed;

    public long FramesReceived => Interlocked.Read(ref _framesReceived);
    public long BytesReceived => Interlocked.Read(ref _bytesReceived);

    public void Start(IPAddress address, int port, byte[] key, byte[] token)
    {
        Stop();
        if (key.Length != VideoStream.KeyBytes || token.Length != VideoStream.TokenBytes)
            throw new ArgumentException(T("Invalid display stream keys.", pl: "Nieprawidłowe klucze strumienia ekranu."));
        var keyCopy = key.ToArray();
        var tokenCopy = token.ToArray();
        Interlocked.Exchange(ref _framesReceived, 0);
        Interlocked.Exchange(ref _bytesReceived, 0);
        _running = true;
        _thread = new Thread(() => Run(address, port, keyCopy, tokenCopy))
        {
            IsBackground = true,
            Name = "blm-video-rx",
            Priority = ThreadPriority.AboveNormal,
        };
        _thread.Start();
    }

    public void Stop()
    {
        _running = false;
        var tcp = _tcp;
        var thread = _thread;
        try { tcp?.Close(); } catch { /* ignore */ }
        if (thread is not null && thread != Thread.CurrentThread) thread.Join(TimeSpan.FromSeconds(2));
        _tcp = null;
        _thread = null;
    }

    private void Run(IPAddress address, int port, byte[] key, byte[] token)
    {
        string? reason = null;
        try
        {
            using var tcp = new TcpClient(address.AddressFamily) { NoDelay = true, ReceiveBufferSize = 4 * 1024 * 1024 };
            _tcp = tcp;
            if (!tcp.ConnectAsync(address, port).Wait(TimeSpan.FromSeconds(4)))
                throw new IOException(T("The Mac did not accept the video connection.", pl: "Mac nie przyjął połączenia wideo."));
            using var stream = tcp.GetStream();
            stream.Write(token);
            using var opener = new VideoStream.Opener(key);
            var header = new byte[VideoStream.LengthBytes];
            var body = new byte[1024 * 1024];
            while (_running)
            {
                if (!ReadFully(stream, header)) { reason = T("The Mac closed the display stream.", pl: "Mac zamknął strumień ekranu."); break; }
                var length = (int)BinaryPrimitives.ReadUInt32LittleEndian(header);
                if (length < VideoStream.CounterBytes + VideoStream.TagBytes || length > VideoStream.MaxRecordBytes)
                {
                    reason = T("Invalid display stream record.", pl: "Nieprawidłowy rekord strumienia ekranu.");
                    break;
                }
                if (body.Length < length) body = new byte[Math.Max(length, body.Length * 2)];
                if (!ReadFully(stream, body.AsSpan(0, length))) { reason = T("The Mac closed the display stream.", pl: "Mac zamknął strumień ekranu."); break; }
                var clear = opener.Open(body.AsSpan(0, length));
                if (clear is null || !VideoStream.TryParseFrame(clear, out var frame))
                {
                    reason = T("Display stream integrity check failed.", pl: "Błąd integralności strumienia ekranu.");
                    break;
                }
                Interlocked.Increment(ref _framesReceived);
                Interlocked.Add(ref _bytesReceived, VideoStream.LengthBytes + length);
                FrameReceived?.Invoke(frame);
            }
        }
        catch (Exception ex) when (ex is IOException or SocketException or ObjectDisposedException or AggregateException)
        {
            if (_running) reason = T("Video connection error: ", pl: "Błąd połączenia wideo: ") + (ex.InnerException ?? ex).Message;
        }
        finally
        {
            CryptographicOperations.ZeroMemory(key);
            CryptographicOperations.ZeroMemory(token);
            _tcp = null;
        }
        if (_running)
        {
            _running = false;
            Closed?.Invoke(reason);
        }
    }

    private static bool ReadFully(NetworkStream stream, Span<byte> buffer)
    {
        var offset = 0;
        while (offset < buffer.Length)
        {
            var read = stream.Read(buffer[offset..]);
            if (read <= 0) return false;
            offset += read;
        }
        return true;
    }

    public void Dispose() => Stop();
}
