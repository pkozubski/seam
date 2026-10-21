using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using Microsoft.Win32.SafeHandles;

namespace Seam.Display;

/// <summary>
/// Krótkie, dokładne oczekiwanie bez <c>timeBeginPeriod(1)</c>, które przyspiesza zegar całego
/// systemu i kosztuje baterię (a Windows 11 i tak je ignoruje dla aplikacji schowanych w zasobniku).
/// Timer wysokiej rozdzielczości (Windows 10 1803+) budzi wątek po zadanym czasie z dokładnością
/// poniżej milisekundy. Jeden obiekt na wątek: klasa nie jest bezpieczna wątkowo.
/// </summary>
[SupportedOSPlatform("windows")]
internal sealed class PreciseTimer : IDisposable
{
    private const uint CREATE_WAITABLE_TIMER_HIGH_RESOLUTION = 0x00000002;
    private const uint TIMER_ALL_ACCESS = 0x1F0003;

    private readonly TimerHandle _timer;
    private WaitHandle[]? _pair;

    public PreciseTimer()
    {
        var handle = CreateWaitableTimerExW(IntPtr.Zero, null, CREATE_WAITABLE_TIMER_HIGH_RESOLUTION, TIMER_ALL_ACCESS);
        // Starszy system: zwykły timer (rozdzielczość zegara systemowego).
        if (handle == IntPtr.Zero) handle = CreateWaitableTimerExW(IntPtr.Zero, null, 0, TIMER_ALL_ACCESS);
        if (handle == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
        _timer = new TimerHandle(handle);
    }

    /// <summary>
    /// Czeka <paramref name="microseconds"/> albo do sygnału <paramref name="wake"/> (zdarzenie
    /// auto-reset zostaje wtedy zużyte, jak przy <c>WaitOne</c>). Zwraca true, gdy obudził sygnał.
    /// </summary>
    public bool Wait(int microseconds, WaitHandle? wake = null)
    {
        if (!TryArm(microseconds, out _))
        {
            var milliseconds = Math.Max(1, microseconds / 1000);
            if (wake is not null) return wake.WaitOne(milliseconds);
            Thread.Sleep(milliseconds);
            return false;
        }
        if (wake is null)
        {
            _timer.WaitOne();
            return false;
        }
        if (_pair is null || !ReferenceEquals(_pair[1], wake)) _pair = new WaitHandle[] { _timer, wake };
        return WaitHandle.WaitAny(_pair) == 1;
    }

    /// <summary>
    /// Uzbraja timer bez czekania i podaje jego uchwyt do własnego oczekiwania, np. w
    /// <c>MsgWaitForMultipleObjectsEx</c>, które przy okazji pompuje komunikaty (haki WinEvent).
    /// false = nie udało się uzbroić; wtedy uchwyt nie zostanie zasygnalizowany i trzeba czekać z limitem czasu.
    /// </summary>
    public bool TryArm(int microseconds, out IntPtr handle)
    {
        // Sygnał z poprzedniego oczekiwania, przerwanego czymś innym, nie może skrócić tego.
        _timer.WaitOne(0);
        var due = -(long)Math.Max(microseconds, 1) * 10; // jednostki 100 ns, ujemna = względem teraz
        var armed = SetWaitableTimer(_timer.SafeWaitHandle, ref due, 0, IntPtr.Zero, IntPtr.Zero, false);
        handle = armed ? _timer.SafeWaitHandle.DangerousGetHandle() : IntPtr.Zero;
        return armed;
    }

    public void Dispose() => _timer.Dispose();

    private sealed class TimerHandle : WaitHandle
    {
        public TimerHandle(IntPtr handle) => SafeWaitHandle = new SafeWaitHandle(handle, ownsHandle: true);
    }

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern IntPtr CreateWaitableTimerExW(IntPtr attributes, string? name, uint flags, uint access);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWaitableTimer(SafeWaitHandle timer, ref long dueTime, int period,
        IntPtr completionRoutine, IntPtr completionArgument, [MarshalAs(UnmanagedType.Bool)] bool resume);
}
