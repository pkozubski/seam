using System.Buffers.Binary;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using Seam.Audio;
using Seam.Protocol;
using static Seam.Localization.L10n;

namespace Seam.Net;

/// <summary>Odbiera wyłącznie uwierzytelnione pakiety audio z aktywnej sesji Maca.</summary>
public sealed class AudioReceiver : IDisposable
{
    // Wybudzenie odbioru bez pakietów: gdy gramy, wykrywa ciszę (Mac przestaje nadawać);
    // w uśpieniu tylko sprawdza świeży bufor po AUDIO_FORMAT (musi być < IdleTimeoutMs).
    private const int ActiveWakeMs = 500;
    private const int IdleWakeMs = JitterBufferProvider.IdleTimeoutMs * 2 / 3; // 2 s
    private const int ErrorBackoffMs = 50;
    // Jak UdpClient.Receive: każdy datagram mieści się w całości, więc długość pakietu się nie zmienia.
    private const int MaxDatagramBytes = 65536;
    // frames ≤ 1024 × channels ≤ 8 × float32 (walidacja w Authenticate).
    private const int MaxClearBytes = 1024 * 8 * 4;
    private const int NonceBytes = 12;
    private static readonly IPEndPoint AnyEndPoint = new(IPAddress.Any, 0);

    private UdpClient? _udp;
    private Thread? _thread;
    private volatile bool _running;
    private ushort _lastSeq;
    private bool _haveSeq;
    private float _level;
    private IPAddress? _expectedAddress;
    private ulong _sessionId;
    private ulong _highestCounter;
    private ulong _counterWindow;
    private bool _haveCounter;
    private volatile JitterBufferProvider? _provider;

    public JitterBufferProvider? Provider { get => _provider; set => _provider = value; }
    public int Port { get; private set; }
    public long PacketsReceived;
    public long PacketsLost;
    public long PacketsRejected;
    public long BytesReceived;
    public float Level => _level;

    /// <summary>Otwiera port UDP i wiąże odbiór z adresem oraz kluczem aktywnej sesji.</summary>
    public int Start(int port, string expectedAddress, ReadOnlySpan<byte> key, ulong sessionId)
    {
        Stop();
        if (!IPAddress.TryParse(expectedAddress, out var address))
            throw new ArgumentException(T("Nie można ustalić adresu IPv4 Maca.", "Cannot determine the Mac IPv4 address."), nameof(expectedAddress));
        // Gniazdo sterowania jest dual-stack, więc Mac w IPv4 potrafi przyjść
        // jako adres zmapowany (::ffff:192.168.x.y) – to nadal ten sam host.
        if (address.IsIPv4MappedToIPv6) address = address.MapToIPv4();
        if (address.AddressFamily != AddressFamily.InterNetwork)
            throw new ArgumentException(
                T($"Sesja zestawiona po IPv6 ({expectedAddress}); dźwięk wymaga adresu IPv4 Maca.",
                  $"The session uses IPv6 ({expectedAddress}); audio requires the Mac IPv4 address."),
                nameof(expectedAddress));
        if (key.Length != 32) throw new ArgumentException(T("Nieprawidłowy klucz sesji audio.", "Invalid audio-session key."), nameof(key));

        var udp = new UdpClient(AddressFamily.InterNetwork);
        AesGcm aes;
        try
        {
            udp.Client.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, false);
            udp.Client.ReceiveBufferSize = 1 << 20;
            udp.Client.Bind(new IPEndPoint(IPAddress.Any, port));
            SocketHelpers.DisableUdpConnReset(udp.Client);
            Port = ((IPEndPoint)udp.Client.LocalEndPoint!).Port;
            // Jeden AesGcm na sesję; klucz trzyma tylko on (bez kopii w zarządzanej tablicy).
            // Zwalnia go wątek odbioru po ostatnim użyciu, na co czeka Join w Stop().
            aes = new AesGcm(key, ProtocolConstants.AudioTagBytes);
        }
        catch
        {
            udp.Dispose();
            throw;
        }
        _expectedAddress = address;
        _sessionId = sessionId;
        _udp = udp;
        _running = true;
        _haveSeq = false;
        _haveCounter = false;
        _counterWindow = 0;
        PacketsReceived = PacketsLost = PacketsRejected = BytesReceived = 0;
        _thread = new Thread(() => Loop(udp, aes))
        {
            IsBackground = true,
            Name = "blm-audio-rx",
            Priority = ThreadPriority.Highest,
        };
        _thread.Start();
        return Port;
    }

    public void Stop()
    {
        _running = false;
        var udp = _udp;
        var thread = _thread;
        try { udp?.Close(); } catch { /* ignore */ }
        // Po wyjściu z pętli wątek sam zwalnia AesGcm (z kluczem) i zeruje bufory jawnego tekstu.
        if (thread is not null && thread != Thread.CurrentThread) thread.Join(TimeSpan.FromSeconds(1));
        _udp = null;
        _thread = null;
        _level = 0;
        _expectedAddress = null;
        _haveCounter = false;
    }

    private void Loop(UdpClient udp, AesGcm aes)
    {
        var socket = udp.Client;
        // Bufory wielokrotnego użytku: bez alokacji na pakiet. Provider.Write kopiuje dane od razu.
        var packet = new byte[MaxDatagramBytes];
        var clear = new byte[MaxClearBytes];
        var pcm = new byte[MaxClearBytes / 2];
        var addressSize = SocketAddress.GetMaximumAddressSize(AddressFamily.InterNetwork);
        var remote = new SocketAddress(AddressFamily.InterNetwork, addressSize);
        SocketAddress? trusted = null; // ostatni nadawca, który przeszedł pełne sprawdzenie adresu
        var wakeMs = -1;
        try
        {
            while (_running)
            {
                int length;
                try
                {
                    var wanted = Provider is { IsIdle: false } ? ActiveWakeMs : IdleWakeMs;
                    if (wanted != wakeMs)
                    {
                        socket.ReceiveTimeout = wanted;
                        wakeMs = wanted;
                    }
                    remote.Size = addressSize;
                    length = socket.ReceiveFrom(packet.AsSpan(), SocketFlags.None, remote);
                }
                catch (SocketException ex) when (ex.SocketErrorCode is SocketError.TimedOut or SocketError.WouldBlock)
                {
                    // Brak pakietów to nie błąd: Mac nie nadaje w ciszy. Poziom gaśnie, bufor może zasnąć.
                    _level = 0;
                    Provider?.CheckIdle();
                    continue;
                }
                catch (SocketException)
                {
                    if (!_running) break;
                    Thread.Sleep(ErrorBackoffMs); // trwały błąd gniazda nie może kręcić rdzeniem
                    continue;
                }
                catch (ObjectDisposedException) { break; }

                if (trusted is null || !remote.Equals(trusted))
                {
                    if (!IsExpectedSource(remote))
                    {
                        Interlocked.Increment(ref PacketsRejected);
                        continue;
                    }
                    trusted = Copy(remote);
                }
                var clearLength = Authenticate(aes, packet.AsSpan(0, length), clear, out var sequence, out var frames, out var channels, out var format);
                if (clearLength < 0)
                {
                    Interlocked.Increment(ref PacketsRejected);
                    continue;
                }
                var audio = clear.AsSpan(0, clearLength);
                var provider = Provider;
                if (provider is null) continue;

                if (_haveSeq)
                {
                    // Bufor odtwarzania jest FIFO, więc stare/przestawione pakiety
                    // muszą zostać odrzucone zamiast zanieczyszczać kolejność próbek.
                    var distance = (ushort)(sequence - _lastSeq);
                    if (distance == 0 || distance >= 0x8000)
                    {
                        Interlocked.Increment(ref PacketsRejected);
                        CryptographicOperations.ZeroMemory(audio);
                        continue;
                    }
                    var gap = distance - 1;
                    if (gap is > 0 and < 100)
                    {
                        Interlocked.Add(ref PacketsLost, gap);
                        var silenceBytes = checked(gap * frames * channels * 2);
                        if (silenceBytes <= 2 * 1024 * 1024) provider.WriteSilence(silenceBytes);
                    }
                }
                _lastSeq = sequence;
                _haveSeq = true;

                Interlocked.Increment(ref PacketsReceived);
                Interlocked.Add(ref BytesReceived, clearLength);
                if (format == 0)
                {
                    var peak = 0;
                    for (var index = 0; index + 1 < audio.Length; index += 2)
                    {
                        var value = Math.Abs((int)BinaryPrimitives.ReadInt16LittleEndian(audio[index..]));
                        if (value > peak) peak = value;
                    }
                    var level = peak / 32768f;
                    _level = level > _level ? level : _level * 0.85f;
                    provider.WritePacket(audio, silent: peak == 0);
                }
                else
                {
                    var count = clearLength / 4;
                    var converted = pcm.AsSpan(0, count * 2);
                    var peak = 0f;
                    var silent = true;
                    for (var index = 0; index < count; index++)
                    {
                        var sample = Math.Clamp(BinaryPrimitives.ReadSingleLittleEndian(audio[(index * 4)..]), -1f, 1f);
                        if (Math.Abs(sample) > peak) peak = Math.Abs(sample);
                        var value = (short)(sample * 32767);
                        if (value != 0) silent = false;
                        BinaryPrimitives.WriteInt16LittleEndian(converted[(index * 2)..], value);
                    }
                    _level = peak > _level ? peak : _level * 0.85f;
                    provider.WritePacket(converted, silent);
                }
                // Starsze Maki nadają ciszę bez przerwy: tu bufor zaśnie mimo płynących pakietów.
                provider.CheckIdle();
                if (provider.IsIdle) _level = 0;
            }
        }
        finally
        {
            aes.Dispose();
            CryptographicOperations.ZeroMemory(clear);
            CryptographicOperations.ZeroMemory(pcm);
        }
    }

    /// <summary>Pełne sprawdzenie nadawcy, jak przy UdpClient.Receive; Loop zapamiętuje adres, który je przeszedł.</summary>
    private bool IsExpectedSource(SocketAddress address)
    {
        IPEndPoint endpoint;
        try
        {
            if (AnyEndPoint.Create(address) is not IPEndPoint created) return false;
            endpoint = created;
        }
        catch (ArgumentException)
        {
            return false; // nie-IP albo ucięty adres
        }
        var source = endpoint.Address.IsIPv4MappedToIPv6 ? endpoint.Address.MapToIPv4() : endpoint.Address;
        return _expectedAddress is { } expected && source.Equals(expected);
    }

    private static SocketAddress Copy(SocketAddress address)
    {
        var copy = new SocketAddress(address.Family, address.Size);
        address.Buffer.Span[..address.Size].CopyTo(copy.Buffer.Span);
        return copy;
    }

    /// <summary>Sprawdza nagłówek i odszyfrowuje PCM do <paramref name="clear"/>. Zwraca długość PCM albo -1.</summary>
    private int Authenticate(AesGcm aes, ReadOnlySpan<byte> packet, Span<byte> clear, out ushort sequence, out int frames, out int channels, out byte format)
    {
        sequence = 0;
        frames = channels = 0;
        format = 0;
        if (packet.Length < ProtocolConstants.AudioHeaderBytes + ProtocolConstants.AudioTagBytes) return -1;
        if (BinaryPrimitives.ReadUInt16LittleEndian(packet) != ProtocolConstants.AudioMagic ||
            packet[2] != ProtocolConstants.AudioVersion || packet[3] != 0 ||
            BinaryPrimitives.ReadUInt64LittleEndian(packet[4..]) != _sessionId ||
            BinaryPrimitives.ReadUInt16LittleEndian(packet[26..]) != 0) return -1;

        var counter = BinaryPrimitives.ReadUInt64LittleEndian(packet[12..]);
        sequence = BinaryPrimitives.ReadUInt16LittleEndian(packet[20..]);
        frames = BinaryPrimitives.ReadUInt16LittleEndian(packet[22..]);
        channels = packet[24];
        format = packet[25];
        if (frames is <= 0 or > 1024 || channels is <= 0 or > 8 || format > 1) return -1;
        var bytesPerSample = format == 0 ? 2 : 4;
        var expectedBytes = checked(frames * channels * bytesPerSample);
        var cipherBytes = packet.Length - ProtocolConstants.AudioHeaderBytes - ProtocolConstants.AudioTagBytes;
        if (cipherBytes != expectedBytes) return -1;

        var output = clear[..cipherBytes];
        Span<byte> nonce = stackalloc byte[NonceBytes];
        WriteNonce(nonce, counter);
        try
        {
            aes.Decrypt(nonce,
                packet.Slice(ProtocolConstants.AudioHeaderBytes, cipherBytes),
                packet.Slice(ProtocolConstants.AudioHeaderBytes + cipherBytes, ProtocolConstants.AudioTagBytes),
                output, packet[..ProtocolConstants.AudioHeaderBytes]);
        }
        catch (CryptographicException)
        {
            CryptographicOperations.ZeroMemory(output);
            return -1;
        }
        if (!AcceptCounter(counter))
        {
            CryptographicOperations.ZeroMemory(output);
            return -1;
        }
        return cipherBytes;
    }

    /// <summary>64-pakietowe okno anty-replay tolerujące niewielką zmianę kolejności UDP.</summary>
    private bool AcceptCounter(ulong counter)
    {
        if (!_haveCounter)
        {
            _haveCounter = true;
            _highestCounter = counter;
            _counterWindow = 1;
            return true;
        }
        if (counter > _highestCounter)
        {
            var shift = counter - _highestCounter;
            _counterWindow = shift >= 64 ? 1 : (_counterWindow << (int)shift) | 1;
            _highestCounter = counter;
            return true;
        }
        var distance = _highestCounter - counter;
        if (distance >= 64) return false;
        var bit = 1UL << (int)distance;
        if ((_counterWindow & bit) != 0) return false;
        _counterWindow |= bit;
        return true;
    }

    // Układ bez zmian: sessionId (LE), od bajtu 4 nadpisany licznikiem (LE).
    private void WriteNonce(Span<byte> nonce, ulong counter)
    {
        BinaryPrimitives.WriteUInt64LittleEndian(nonce, _sessionId);
        BinaryPrimitives.WriteUInt64LittleEndian(nonce[4..], counter);
    }

    public void Dispose() => Stop();
}
