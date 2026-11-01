using System.Diagnostics;
using System.Runtime.Versioning;
using Microsoft.Win32;
using static Seam.Localization.L10n;

namespace Seam.Models;

/// <summary>
/// Autostart na Windows przez klucz rejestru
/// HKCU\Software\Microsoft\Windows\CurrentVersion\Run. Nie wymaga uprawnień
/// administratora ani zadania w Harmonogramie.
/// </summary>
public static class Autostart
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "BorderlessMouse";
    /// <summary>Argument dodawany przy autostarcie – aplikacja startuje do zasobnika.</summary>
    public const string BackgroundArgument = "--background";

    public static bool IsSupported => OperatingSystem.IsWindows();

    /// <summary>Ścieżka do bieżącego pliku wykonywalnego (obsługuje publikację single-file).</summary>
    public static string? ExecutablePath
    {
        get
        {
            var path = Environment.ProcessPath;
            if (!string.IsNullOrEmpty(path) && path.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)) return path;
            return Process.GetCurrentProcess().MainModule?.FileName;
        }
    }

    private static string CommandLine => $"\"{ExecutablePath}\" {BackgroundArgument}";

    [SupportedOSPlatform("windows")]
    private static string? ReadValue()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKey);
        return key?.GetValue(ValueName) as string;
    }

    public static bool IsEnabled
    {
        get
        {
            if (!IsSupported) return false;
            try { return !string.IsNullOrEmpty(ReadValue()); }
            catch { return false; }
        }
    }

    /// <summary>Opis stanu dla interfejsu.</summary>
    public static string StatusDescription
    {
        get
        {
            if (!IsSupported) return T("Available only on Windows.", pl: "Dostępne tylko na Windows.");
            try
            {
                var value = ReadValue();
                if (string.IsNullOrEmpty(value)) return T("Disabled.", pl: "Wyłączony.");
                var exe = ExecutablePath;
                if (string.IsNullOrEmpty(exe)) return T("Enabled (the current executable path is unavailable).", pl: "Włączony (nie można ustalić ścieżki bieżącego pliku exe).");
                return value.Contains(exe, StringComparison.OrdinalIgnoreCase)
                    ? T("Enabled for the current Windows account.", pl: "Włączony (wpis w rejestrze, klucz Run użytkownika).")
                    : T("Enabled, but points to another file; it will be repaired on the next change.", pl: "Włączony, ale wpis wskazuje inny plik – zostanie poprawiony przy następnej zmianie.");
            }
            catch (Exception ex)
            {
                return T("Cannot read the registry: ", pl: "Nie można odczytać rejestru: ") + ex.Message;
            }
        }
    }

    /// <summary>Włącza lub wyłącza autostart. Zwraca opis do dziennika.</summary>
    [SupportedOSPlatform("windows")]
    public static string SetEnabled(bool enabled)
    {
        using var key = Registry.CurrentUser.CreateSubKey(RunKey, writable: true)
                        ?? throw new InvalidOperationException(T("Cannot open the Run registry key.", pl: "Nie można otworzyć klucza Run."));
        if (enabled)
        {
            var path = ExecutablePath ?? throw new InvalidOperationException(T("Cannot determine the executable path.", pl: "Nie można ustalić ścieżki pliku exe."));
            key.SetValue(ValueName, CommandLine, RegistryValueKind.String);
            return T("Launch at sign-in enabled: ", pl: "Autostart włączony: ") + path;
        }
        key.DeleteValue(ValueName, throwOnMissingValue: false);
        return T("Launch at sign-in disabled", pl: "Autostart wyłączony");
    }

    /// <summary>Po aktualizacji lub przeniesieniu pliku uaktualnia wpis, jeśli wskazuje inną ścieżkę.</summary>
    public static void RefreshIfNeeded()
    {
        if (!IsSupported) return;
        try
        {
            if (!OperatingSystem.IsWindows()) return;
            var value = ReadValue();
            if (string.IsNullOrEmpty(value)) return;
            if (value == CommandLine) return;
            SetEnabled(true);
        }
        catch
        {
            // brak dostępu do rejestru nie może wywrócić startu aplikacji
        }
    }
}
