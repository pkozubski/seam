using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Seam.Licensing;

/// <summary>Licencja zapisana po aktywacji. Klucz i instancja są potrzebne do walidacji i dezaktywacji.</summary>
public sealed record StoredLicense(string Key, string InstanceId, LicenseStatus Status, DateTimeOffset ValidatedAt, string? CustomerEmail)
{
    public LicenseSnapshot Snapshot => new(Status, ValidatedAt);

    /// <summary>Klucz do wyświetlenia: tylko ostatnie znaki.</summary>
    public string MaskedKey => "••••-" + (Key.Length > 4 ? Key[^4..] : Key);
}

/// <summary>
/// Licencja i początek trialu w <c>%APPDATA%\BorderlessMouse\license.dat</c>, szyfrowane DPAPI dla
/// bieżącego użytkownika (jak <c>pairing.key</c>), żeby nie dało się ich po prostu edytować.
/// </summary>
public static class LicenseStore
{
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("BorderlessMouse/v2/license");
    private static readonly JsonSerializerOptions Options = new() { Converters = { new JsonStringEnumConverter() } };

    public static string FilePath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "BorderlessMouse", "license.dat");

    private sealed record Contents(StoredLicense? License, DateTimeOffset? TrialStartedAt);

    public static StoredLicense? LoadLicense() => Read().License;
    public static DateTimeOffset? TrialStartedAt() => Read().TrialStartedAt;

    public static bool Save(StoredLicense license) => Write(Read() with { License = license });
    public static void DeleteLicense() => Write(Read() with { License = null });

    /// <summary>Trial startuje raz; kolejne wywołania zwracają pierwszą datę.</summary>
    public static DateTimeOffset StartTrial(DateTimeOffset now)
    {
        var contents = Read();
        if (contents.TrialStartedAt is { } existing) return existing;
        Write(contents with { TrialStartedAt = now });
        return now;
    }

    private static Contents Read()
    {
        if (!OperatingSystem.IsWindows() || !File.Exists(FilePath)) return new(null, null);
        try
        {
            var json = ProtectedData.Unprotect(File.ReadAllBytes(FilePath), Entropy, DataProtectionScope.CurrentUser);
            return JsonSerializer.Deserialize<Contents>(json, Options) ?? new(null, null);
        }
        catch (Exception ex) when (ex is CryptographicException or JsonException or IOException)
        {
            return new(null, null);
        }
    }

    private static bool Write(Contents contents)
    {
        if (!OperatingSystem.IsWindows()) return false;
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
            var protectedBytes = ProtectedData.Protect(JsonSerializer.SerializeToUtf8Bytes(contents, Options), Entropy, DataProtectionScope.CurrentUser);
            var temporary = FilePath + "." + Guid.NewGuid().ToString("N") + ".tmp";
            File.WriteAllBytes(temporary, protectedBytes);
            File.Move(temporary, FilePath, true);
            return true;
        }
        catch (Exception ex) when (ex is CryptographicException or IOException or UnauthorizedAccessException)
        {
            return false;
        }
    }
}
