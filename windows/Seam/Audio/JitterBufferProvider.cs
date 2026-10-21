using NAudio.Wave;

namespace Seam.Audio;

/// <summary>
/// Bufor pierścieniowy między odbiorem UDP a WASAPI. Utrzymuje docelowe
/// opóźnienie: przy niedoborze gra ciszę i czeka aż uzbiera się TargetMs,
/// przy nadmiarze (narastające opóźnienie) tnie do wartości docelowej.
/// Po <see cref="IdleTimeoutMs"/> bez dźwięku zasypia (<see cref="IsIdle"/>), żeby
/// AudioPlayer mógł zatrzymać strumień WASAPI; pierwszy niecichy pakiet go budzi.
/// </summary>
public sealed class JitterBufferProvider : IWaveProvider
{
    /// <summary>Czas bez dźwięku (same zera albo brak pakietów), po którym bufor zasypia.</summary>
    public const int IdleTimeoutMs = 3000;

    private readonly byte[] _ring;
    private readonly object _gate = new();
    private int _readPos;
    private int _count;
    private bool _prebuffering = true;
    private int _targetBytes;
    private int _maxBytes;
    // Stan uśpienia zmienia tylko wątek odbioru (WritePacket/CheckIdle).
    private long _lastSoundTicks = Environment.TickCount64;
    private volatile bool _idle;
    private volatile bool _silentTail;

    public WaveFormat WaveFormat { get; }
    public long Underruns { get; private set; }
    public long Overruns { get; private set; }

    /// <summary>Uśpiony: brak dźwięku od IdleTimeoutMs, bufor pusty i niekarmiony.</summary>
    public bool IsIdle => _idle;

    /// <summary>Zmiana uśpienia (true = dźwięk wrócił). Wywoływane z wątku odbioru.</summary>
    public event Action<bool>? ActivityChanged;

    public JitterBufferProvider(WaveFormat format, int targetMs)
    {
        WaveFormat = format;
        _ring = new byte[format.AverageBytesPerSecond * 2]; // 2 s
        SetTarget(targetMs);
    }

    public int TargetMs { get; private set; }

    public void SetTarget(int targetMs)
    {
        TargetMs = Math.Clamp(targetMs, 2, 500);
        _targetBytes = Align(WaveFormat.AverageBytesPerSecond * TargetMs / 1000);
        _maxBytes = Math.Min(_ring.Length - WaveFormat.BlockAlign, _targetBytes * 3 + WaveFormat.AverageBytesPerSecond / 20);
    }

    /// <summary>Aktualne wypełnienie w milisekundach.</summary>
    public int BufferedMs
    {
        get { lock (_gate) return (int)(_count * 1000L / WaveFormat.AverageBytesPerSecond); }
    }

    private int Align(int bytes) => bytes - bytes % WaveFormat.BlockAlign;

    /// <summary>
    /// Pakiet z odbiornika (dane są kopiowane od razu). Dźwięk budzi uśpiony bufor;
    /// cisza w uśpieniu jest pomijana. <paramref name="silent"/> = same zerowe próbki.
    /// </summary>
    public void WritePacket(ReadOnlySpan<byte> data, bool silent)
    {
        if (!silent)
        {
            _lastSoundTicks = Environment.TickCount64;
            if (_idle)
            {
                // wznowienie od pustego bufora: prebuffering zaczyna się czysto
                Clear();
                _idle = false;
                ActivityChanged?.Invoke(true);
            }
        }
        else if (_idle)
        {
            return;
        }
        _silentTail = silent;
        Write(data);
    }

    /// <summary>Usypia bufor po IdleTimeoutMs bez dźwięku. Woła go odbiornik po pakiecie i po przekroczeniu czasu odbioru.</summary>
    public void CheckIdle()
    {
        if (_idle || Environment.TickCount64 - _lastSoundTicks < IdleTimeoutMs) return;
        _idle = true;
        Clear();
        ActivityChanged?.Invoke(false);
    }

    public void Write(ReadOnlySpan<byte> data)
    {
        lock (_gate)
        {
            if (data.Length >= _ring.Length) data = data[^(_ring.Length - WaveFormat.BlockAlign)..];
            var free = _ring.Length - _count;
            if (data.Length > free)
            {
                // wyrzuć najstarsze
                var drop = data.Length - free;
                _readPos = (_readPos + drop) % _ring.Length;
                _count -= drop;
            }
            var writePos = (_readPos + _count) % _ring.Length;
            var first = Math.Min(data.Length, _ring.Length - writePos);
            data[..first].CopyTo(_ring.AsSpan(writePos));
            if (first < data.Length) data[first..].CopyTo(_ring.AsSpan(0));
            _count += data.Length;

            if (_count > _maxBytes)
            {
                // opóźnienie narosło – przytnij do docelowego
                var drop = Align(_count - _targetBytes);
                _readPos = (_readPos + drop) % _ring.Length;
                _count -= drop;
                Overruns++;
            }
        }
    }

    /// <summary>Wypełnia lukę po zgubionych pakietach; w uśpieniu nic nie robi.</summary>
    public void WriteSilence(int bytes)
    {
        if (bytes <= 0 || _idle) return;
        Span<byte> zeros = stackalloc byte[Math.Min(bytes, 4096)];
        zeros.Clear();
        while (bytes > 0)
        {
            var n = Math.Min(bytes, zeros.Length);
            Write(zeros[..n]);
            bytes -= n;
        }
    }

    public void Clear()
    {
        lock (_gate)
        {
            _count = 0;
            _readPos = 0;
            _prebuffering = true;
        }
    }

    public int Read(byte[] buffer, int offset, int count)
    {
        lock (_gate)
        {
            if (_prebuffering)
            {
                if (_count >= _targetBytes)
                {
                    _prebuffering = false;
                }
                else
                {
                    Array.Clear(buffer, offset, count);
                    return count;
                }
            }

            var take = Math.Min(count, _count);
            take = Align(take);
            var first = Math.Min(take, _ring.Length - _readPos);
            Array.Copy(_ring, _readPos, buffer, offset, first);
            if (first < take) Array.Copy(_ring, 0, buffer, offset + first, take - first);
            _readPos = (_readPos + take) % _ring.Length;
            _count -= take;

            if (take < count)
            {
                Array.Clear(buffer, offset + take, count - take);
                // koniec strumienia po ciszy (Mac przestał nadawać) nie jest słyszalnym niedopełnieniem
                if (!_silentTail) Underruns++;
                _prebuffering = true;
            }
            return count;
        }
    }
}
