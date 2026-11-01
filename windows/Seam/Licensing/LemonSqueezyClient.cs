using System.Net.Http;
using System.Text.Json;
using static Seam.Localization.L10n;

namespace Seam.Licensing;

/// <summary>
/// Sklep i produkt Seam Pro w Lemon Squeezy (te same wartości co <c>LicenseConfig</c> na Macu). Zera = sklep
/// jeszcze nie założony: aktywacja jest wyłączona, bo bez sprawdzenia sklepu i produktu przeszedłby klucz
/// z dowolnego sklepu Lemon Squeezy.
/// </summary>
public static class LicenseConfig
{
    public const long StoreId = 0;
    public const long ProductId = 0;
    public const string CheckoutUrl = "https://seam.lemonsqueezy.com/buy/seam-pro";
    public const string Price = "$10";

    public static bool IsConfigured => StoreId != 0 && ProductId != 0;
}

public sealed class LicenseException(string message, bool isNetwork = false) : Exception(message)
{
    /// <summary>Brak sieci albo błąd serwera: nic nie zmieniamy, licencja działa w okresie łaski.</summary>
    public bool IsNetwork { get; } = isNetwork;
}

public sealed record LicenseResult(LicenseStatus Status, string? InstanceId, string? CustomerEmail);

/// <summary>License API Lemon Squeezy (bez klucza API; klucz licencyjny wystarcza).</summary>
public static class LemonSqueezyClient
{
    private static readonly HttpClient Http = new() { BaseAddress = new Uri("https://api.lemonsqueezy.com/v1/licenses/"), Timeout = TimeSpan.FromSeconds(20) };

    public static async Task<LicenseResult> ActivateAsync(string key, string instanceName, CancellationToken ct = default)
    {
        using var json = await PostAsync("activate", new() { ["license_key"] = key, ["instance_name"] = instanceName }, ct);
        var root = json.RootElement;
        CheckProduct(root);
        if (!Bool(root, "activated") || !root.TryGetProperty("instance", out var instance) || instance.ValueKind != JsonValueKind.Object)
            throw new LicenseException(Message(root));
        return new(LicenseStatus.Active, instance.GetProperty("id").GetString(), Email(root));
    }

    /// <summary>Zwraca stan licencji także przy odmowie: zwrot albo dezaktywacja to wynik, nie błąd.</summary>
    public static async Task<LicenseResult> ValidateAsync(string key, string instanceId, CancellationToken ct = default)
    {
        using var json = await PostAsync("validate", new() { ["license_key"] = key, ["instance_id"] = instanceId }, ct);
        var root = json.RootElement;
        if (root.TryGetProperty("meta", out _)) CheckProduct(root);
        if (Bool(root, "valid")) return new(LicenseStatus.Active, instanceId, Email(root));
        // Odmowa przy statusie „active” oznacza brak tej instancji (dezaktywowana gdzie indziej).
        var status = LicenseStatus.Inactive;
        if (root.TryGetProperty("license_key", out var licenseKey) && licenseKey.ValueKind == JsonValueKind.Object
            && licenseKey.TryGetProperty("status", out var raw) && Enum.TryParse<LicenseStatus>(raw.GetString(), true, out var parsed)
            && parsed != LicenseStatus.Active)
            status = parsed;
        return new(status, instanceId, Email(root));
    }

    public static async Task DeactivateAsync(string key, string instanceId, CancellationToken ct = default)
    {
        using var json = await PostAsync("deactivate", new() { ["license_key"] = key, ["instance_id"] = instanceId }, ct);
        if (!Bool(json.RootElement, "deactivated")) throw new LicenseException(Message(json.RootElement));
    }

    private static async Task<JsonDocument> PostAsync(string path, Dictionary<string, string> fields, CancellationToken ct)
    {
        if (!LicenseConfig.IsConfigured)
            throw new LicenseException(T("This build can't activate licenses.", pl: "Ta wersja nie może aktywować licencji."));
        HttpResponseMessage response;
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Post, path) { Content = new FormUrlEncodedContent(fields) };
            request.Headers.Accept.ParseAdd("application/json");
            response = await Http.SendAsync(request, ct);
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
        {
            throw Network(ex.Message);
        }
        using (response)
        {
            // 4xx niesie odpowiedź sklepu (np. zły klucz); 5xx i śmieci to awaria, nie decyzja.
            if ((int)response.StatusCode >= 500) throw Network($"HTTP {(int)response.StatusCode}");
            try
            {
                var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync(ct));
                if (document.RootElement.ValueKind == JsonValueKind.Object) return document;
                document.Dispose();
            }
            catch (JsonException) { }
            throw Network($"HTTP {(int)response.StatusCode}");
        }
    }

    private static LicenseException Network(string message) =>
        new(T($"Couldn't reach the license server: {message}", pl: $"Brak połączenia z serwerem licencji: {message}"), isNetwork: true);

    private static void CheckProduct(JsonElement root)
    {
        if (!root.TryGetProperty("meta", out var meta) || meta.ValueKind != JsonValueKind.Object) throw new LicenseException(Message(root));
        if (!meta.TryGetProperty("store_id", out var store) || store.ValueKind != JsonValueKind.Number || store.GetInt64() != LicenseConfig.StoreId
            || !meta.TryGetProperty("product_id", out var product) || product.ValueKind != JsonValueKind.Number || product.GetInt64() != LicenseConfig.ProductId)
            throw new LicenseException(T("This key isn't a Seam Pro license.", pl: "Ten klucz nie jest licencją Seam Pro."));
    }

    private static bool Bool(JsonElement root, string name) =>
        root.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.True;

    private static string? Email(JsonElement root) =>
        root.TryGetProperty("meta", out var meta) && meta.ValueKind == JsonValueKind.Object
        && meta.TryGetProperty("customer_email", out var email) ? email.GetString() : null;

    private static string Message(JsonElement root) =>
        root.TryGetProperty("error", out var error) && error.ValueKind == JsonValueKind.String
            ? error.GetString()!
            : T("The license server rejected the key.", pl: "Serwer licencji odrzucił klucz.");
}
