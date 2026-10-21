using System.Runtime.Versioning;
using Avalonia.Threading;
using NAudio.CoreAudioApi;
using NAudio.Wave;
using static Seam.Localization.L10n;

namespace Seam.Audio;

public sealed record AudioDeviceInfo(string? Id, string Name)
{
    public override string ToString() => Name;
}

/// <summary>
/// Odtwarzanie WASAPI (NAudio) z bufora jitter. Gdy bufor zasypia (cisza z Maca),
/// strumień jest zatrzymywany, żeby nie budzić CPU, nie zasilać urządzenia i nie
/// blokować uśpienia systemu; dźwięk wznawia go od razu. Wywołania tylko z wątku UI.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class AudioPlayer : IDisposable
{
    private WasapiOut? _output;
    private MMDevice? _device;
    private JitterBufferProvider? _jitter;

    public bool IsPlaying => _output?.PlaybackState == PlaybackState.Playing;
    /// <summary>Strumień zatrzymany z powodu ciszy; wznowi się sam przy dźwięku.</summary>
    public bool IsSuspended => _output is not null && _jitter is { IsIdle: true };
    public string ActiveDescription { get; private set; } = string.Empty;

    public static IReadOnlyList<AudioDeviceInfo> EnumerateOutputDevices()
    {
        var list = new List<AudioDeviceInfo> { new(null, T("Domyślne urządzenie systemowe", "Default system device")) };
        try
        {
            using var enumerator = new MMDeviceEnumerator();
            foreach (var d in enumerator.EnumerateAudioEndPoints(DataFlow.Render, DeviceState.Active))
            {
                list.Add(new AudioDeviceInfo(d.ID, d.FriendlyName));
            }
        }
        catch
        {
            // brak urządzeń / brak COM – zostaje tylko domyślne
        }
        return list;
    }

    /// <summary>Uruchamia odtwarzanie. Zwraca opis użytego trybu.</summary>
    public string Start(string? deviceId, IWaveProvider provider, bool exclusive, int wasapiLatencyMs)
    {
        Stop();
        var enumerator = new MMDeviceEnumerator();
        MMDevice device;
        try
        {
            device = deviceId is null
                ? enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia)
                : enumerator.GetDevice(deviceId);
        }
        catch
        {
            device = enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia);
        }
        finally
        {
            enumerator.Dispose();
        }
        _device = device;

        var mode = exclusive ? AudioClientShareMode.Exclusive : AudioClientShareMode.Shared;
        try
        {
            _output = new WasapiOut(device, mode, true, wasapiLatencyMs);
            _output.Init(provider);
        }
        catch when (exclusive)
        {
            // urządzenie nie wspiera tego formatu w trybie exclusive – wracamy do shared
            _output?.Dispose();
            _output = new WasapiOut(device, AudioClientShareMode.Shared, true, Math.Max(wasapiLatencyMs, 10));
            _output.Init(provider);
            mode = AudioClientShareMode.Shared;
        }
        // Najpierw subskrypcja, potem odczyt stanu: żadna zmiana uśpienia nie umknie.
        _jitter = provider as JitterBufferProvider;
        if (_jitter is not null) _jitter.ActivityChanged += OnActivityChanged;
        SyncWithActivity();
        ActiveDescription = $"{device.FriendlyName} · WASAPI {(mode == AudioClientShareMode.Exclusive ? "exclusive" : "shared")} · {wasapiLatencyMs} ms";
        return ActiveDescription;
    }

    // Przychodzi z wątku odbioru; WASAPI sterujemy z wątku UI, tak jak Start/Stop.
    private void OnActivityChanged(bool active) => Dispatcher.UIThread.Post(SyncWithActivity, DispatcherPriority.Normal);

    /// <summary>
    /// Gra, gdy bufor jest aktywny, i zatrzymuje strumień, gdy zasnął. WasapiOut.Pause()
    /// w NAudio 2.2.1 tylko zmienia flagę (IAudioClient dalej chodzi), dlatego Stop():
    /// IAudioClient::Stop + Reset bez ponownej inicjalizacji; Play() startuje go od nowa.
    /// </summary>
    private void SyncWithActivity()
    {
        if (_output is not { } output) return;
        var idle = _jitter is { IsIdle: true };
        try
        {
            if (idle)
            {
                if (output.PlaybackState != PlaybackState.Stopped) output.Stop();
            }
            else if (output.PlaybackState != PlaybackState.Playing)
            {
                output.Play();
            }
        }
        catch
        {
            // urządzenie zniknęło – zmiana urządzenia lub ponowne połączenie uruchomi je od nowa
        }
    }

    public void Stop()
    {
        if (_jitter is not null) _jitter.ActivityChanged -= OnActivityChanged;
        _jitter = null;
        try { _output?.Stop(); } catch { /* ignore */ }
        _output?.Dispose();
        _output = null;
        _device?.Dispose();
        _device = null;
        ActiveDescription = string.Empty;
    }

    public void Dispose() => Stop();
}
