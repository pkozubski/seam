using System.Buffers.Binary;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text;
using Seam.Protocol;

namespace Seam.Net;

public sealed record DiscoveredPeer(string Name, string Address, int Port)
{
    public string Display => $"{Name}  ·  {Address}";
}

/// <summary>
/// Wysyła broadcast "BLM2?" i zbiera odpowiedzi Maców. Bez połączenia: co 2 s przez pierwsze
/// próby po starcie, wznowieniu i zmianie sieci, potem co 15 s. Podczas połączenia wstrzymany (<see cref="Pause"/>).
/// </summary>
public sealed class DiscoveryClient : IDisposable
{
    private const int FastAttempts = 10;
    private static readonly TimeSpan FastInterval = TimeSpan.FromSeconds(2);
    private static readonly TimeSpan SlowInterval = TimeSpan.FromSeconds(15);
    /// <summary>Lista adresów broadcast odświeżana przy zmianie sieci; to tylko zabezpieczenie na przeoczone zdarzenie.</summary>
    private const long AddressRefreshMs = 5 * 60 * 1000;

    public event Action<DiscoveredPeer>? PeerFound;
    /// <summary>Zmienił się adres sieciowy (NetworkChange). Wywoływane z wątku puli.</summary>
    public event Action? NetworkChanged;

    private UdpClient? _udp;
    private CancellationTokenSource? _cts;
    // Budzi pętlę wysyłki przed końcem przerwy (wznowienie, zmiana sieci).
    private readonly SemaphoreSlim _wake = new(0, 1);
    private volatile bool _paused;
    private int _fastLeft = FastAttempts;
    private int _networkVersion;
    private bool _watchingNetwork;

    public void Start()
    {
        Stop();
        var udp = new UdpClient(AddressFamily.InterNetwork) { EnableBroadcast = true };
        udp.Client.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
        udp.Client.Bind(new IPEndPoint(IPAddress.Any, 0));
        SocketHelpers.DisableUdpConnReset(udp.Client);
        _udp = udp;
        _paused = false;
        Volatile.Write(ref _fastLeft, FastAttempts);
        try
        {
            NetworkChange.NetworkAddressChanged += OnNetworkAddressChanged;
            _watchingNetwork = true;
        }
        catch (Exception)
        {
            // bez powiadomień lista adresów odświeża się co kilka minut
        }
        var cts = new CancellationTokenSource();
        _cts = cts;
        _ = Task.Run(() => ReceiveLoop(udp, cts.Token));
        _ = Task.Run(() => BroadcastLoop(udp, cts.Token));
    }

    public void Stop()
    {
        if (_watchingNetwork)
        {
            NetworkChange.NetworkAddressChanged -= OnNetworkAddressChanged;
            _watchingNetwork = false;
        }
        _cts?.Cancel();
        _cts = null;
        try { _udp?.Close(); } catch { /* ignore */ }
        _udp = null;
    }

    public void Dispose() => Stop();

    /// <summary>Wstrzymuje broadcast (np. podczas połączenia z Makiem); odbiór działa dalej.</summary>
    public void Pause() => _paused = true;

    /// <summary>Wznawia broadcast od razu, z szybkimi próbami. Bez skutku, gdy nie był wstrzymany.</summary>
    public void Resume()
    {
        if (!_paused) return;
        _paused = false;
        Volatile.Write(ref _fastLeft, FastAttempts);
        Wake();
    }

    private void Wake()
    {
        try { _wake.Release(); }
        catch (SemaphoreFullException) { /* pętla i tak się obudzi */ }
    }

    private void OnNetworkAddressChanged(object? sender, EventArgs e)
    {
        Interlocked.Increment(ref _networkVersion);
        Volatile.Write(ref _fastLeft, FastAttempts);
        if (!_paused) Wake();
        NetworkChanged?.Invoke();
    }

    private static IEnumerable<IPAddress> BroadcastAddresses()
    {
        yield return IPAddress.Broadcast;
        foreach (var nic in NetworkInterface.GetAllNetworkInterfaces())
        {
            if (nic.OperationalStatus != OperationalStatus.Up) continue;
            if (nic.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
            foreach (var ua in nic.GetIPProperties().UnicastAddresses)
            {
                if (ua.Address.AddressFamily != AddressFamily.InterNetwork || ua.IPv4Mask is null) continue;
                var ip = ua.Address.GetAddressBytes();
                var mask = ua.IPv4Mask.GetAddressBytes();
                var bc = new byte[4];
                for (var i = 0; i < 4; i++) bc[i] = (byte)(ip[i] | (byte)~mask[i]);
                yield return new IPAddress(bc);
            }
        }
    }

    private async Task BroadcastLoop(UdpClient udp, CancellationToken ct)
    {
        var payload = Encoding.ASCII.GetBytes(ProtocolConstants.DiscoveryRequest);
        var targets = Array.Empty<IPAddress>();
        var targetsVersion = -1;
        var targetsTime = 0L;
        try
        {
            while (!ct.IsCancellationRequested)
            {
                if (!_paused)
                {
                    // Wyliczanie interfejsów jest kosztowne: robimy to po zmianie sieci, nie przy każdym broadcaście.
                    var version = Volatile.Read(ref _networkVersion);
                    if (version != targetsVersion || Environment.TickCount64 - targetsTime > AddressRefreshMs)
                    {
                        targetsVersion = version;
                        targetsTime = Environment.TickCount64;
                        try { targets = BroadcastAddresses().Distinct().ToArray(); }
                        catch (Exception) { targets = new[] { IPAddress.Broadcast }; }
                    }
                    foreach (var addr in targets)
                    {
                        try { await udp.SendAsync(payload, payload.Length, new IPEndPoint(addr, ProtocolConstants.DiscoveryPort)).ConfigureAwait(false); }
                        catch { /* interfejs bez broadcastu */ }
                    }
                }
                TimeSpan delay;
                if (_paused) delay = Timeout.InfiniteTimeSpan;
                else if (Volatile.Read(ref _fastLeft) > 0)
                {
                    Interlocked.Decrement(ref _fastLeft);
                    delay = FastInterval;
                }
                else delay = SlowInterval;
                await _wake.WaitAsync(delay, ct).ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException) { }
        catch (ObjectDisposedException) { }
    }

    private async Task ReceiveLoop(UdpClient udp, CancellationToken ct)
    {
        var reply = Encoding.ASCII.GetBytes(ProtocolConstants.DiscoveryReply);
        var errors = 0;
        try
        {
            while (!ct.IsCancellationRequested)
            {
                UdpReceiveResult result;
                try
                {
                    result = await udp.ReceiveAsync(ct).ConfigureAwait(false);
                    errors = 0;
                }
                catch (SocketException)
                {
                    // Seria błędów (np. znikający interfejs) nie może kręcić pętli bez przerwy.
                    if (++errors >= 3) await Task.Delay(errors >= 20 ? 1000 : 100, ct).ConfigureAwait(false);
                    continue;
                }
                var data = result.Buffer;
                if (data.Length < reply.Length + 2 || !data.AsSpan(0, reply.Length).SequenceEqual(reply)) continue;
                var port = BinaryPrimitives.ReadUInt16LittleEndian(data.AsSpan(reply.Length));
                var name = Encoding.UTF8.GetString(data, reply.Length + 2, data.Length - reply.Length - 2);
                var address = result.RemoteEndPoint.Address.ToString();
                PeerFound?.Invoke(new DiscoveredPeer(string.IsNullOrWhiteSpace(name) ? address : name, address, port));
            }
        }
        catch (OperationCanceledException) { }
        catch (ObjectDisposedException) { }
    }
}

internal static class SocketHelpers
{
    /// <summary>Windows: ICMP "port unreachable" zamyka odbiór UDP wyjątkiem – wyłączamy to.</summary>
    public static void DisableUdpConnReset(Socket socket)
    {
        if (!OperatingSystem.IsWindows()) return;
        try
        {
            const int SIO_UDP_CONNRESET = -1744830452;
            socket.IOControl(SIO_UDP_CONNRESET, new byte[] { 0, 0, 0, 0 }, null);
        }
        catch
        {
            // nie każdy stos to wspiera
        }
    }
}
