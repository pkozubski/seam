using System.Net.Http;
using System.Text;
using System.Text.Json;
using static Seam.Localization.L10n;

namespace Seam.Licensing;

/// <summary>
/// Sklep Seam Pro: Stripe Payment Link (przez seamdesk.app/buy/) i własny serwer licencji (<c>license-server/</c>,
/// api.seamdesk.app). Te same wartości co <c>LicenseConfig.swift</c> na Macu.
/// </summary>
public static class LicenseConfig
{
    public const string ApiBase = "https://api.seamdesk.app/v1/licenses/";
    public const string Price = "$10";
    /// <summary>Sprzedaż w Stripe działa w trybie live. Dopiero wtedy wydania blokują funkcje Pro.</summary>
    public const bool LiveSales = false;
    /// <summary>Payment Link w trybie testowym Stripe (karta 4242 4242 4242 4242): kanał dev blokuje Pro
    /// i przyjmuje klucze testowe, wydania nigdy.</summary>
    public const bool TestSales = false;

    public static bool AcceptsTestLicenses => Net.Updater.IsDevChannel;
    /// <summary>Bez sprzedaży nikt nie traci funkcji, bo nie miałby gdzie kupić licencji.</summary>
    public static bool IsConfigured => Enabled(LiveSales, TestSales, Net.Updater.IsDevChannel);
    public static string CheckoutUrl => Net.Updater.IsDevChannel && TestSales ? "https://seamdesk.app/buy/?test" : "https://seamdesk.app/buy/";

    // przez metodę, bo stałe w warunku dają ostrzeżenie o martwym kodzie (-warnaserror)
    private static bool Enabled(bool live, bool test, bool dev) => live || (test && dev);
}

public enum LicenseFailure { Network, Rejected, WrongProduct, NotConfigured }

public sealed class LicenseException(LicenseFailure kind, string message, string? code = null) : Exception(message)
{
    public LicenseFailure Kind { get; } = kind;
    /// <summary>Stała błędu z serwera (<c>invalid_key</c>, <c>device_limit</c>, <c>license_disabled</c>…).</summary>
    public string? Code { get; } = code;
    /// <summary>Brak sieci albo błąd serwera: nic nie zmieniamy, licencja działa w okresie łaski.</summary>
    public bool IsNetwork => Kind == LicenseFailure.Network;
}

public sealed record LicenseResult(LicenseStatus Status, string? InstanceId, string? CustomerEmail);

public enum LicenseCall { Activate, Validate, Deactivate }

/// <summary>
/// API serwera licencji Seam. Znaczenie odpowiedzi opisują wspólne wektory <c>tests/fixtures/license-api.json</c>
/// (ten sam kontrakt co LicenseClient.swift na Macu).
/// </summary>
public static class LicenseClient
{
    private static readonly HttpClient Http = new() { BaseAddress = new Uri(LicenseConfig.ApiBase), Timeout = TimeSpan.FromSeconds(20) };

    public static async Task<LicenseResult> ActivateAsync(string key, string instanceName, CancellationToken ct = default)
    {
        var (http, body) = await PostAsync(LicenseCall.Activate, new() { ["license_key"] = key, ["instance_name"] = instanceName }, ct);
        return Interpret(LicenseCall.Activate, http, body, LicenseConfig.AcceptsTestLicenses);
    }

    /// <summary>Zwraca stan licencji także przy odmowie: zwrot albo dezaktywacja to wynik, nie błąd.</summary>
    public static async Task<LicenseResult> ValidateAsync(string key, string instanceId, CancellationToken ct = default)
    {
        var (http, body) = await PostAsync(LicenseCall.Validate, new() { ["license_key"] = key, ["instance_id"] = instanceId }, ct);
        return Interpret(LicenseCall.Validate, http, body, LicenseConfig.AcceptsTestLicenses, instanceId);
    }

    public static async Task DeactivateAsync(string key, string instanceId, CancellationToken ct = default)
    {
        var (http, body) = await PostAsync(LicenseCall.Deactivate, new() { ["license_key"] = key, ["instance_id"] = instanceId }, ct);
        Interpret(LicenseCall.Deactivate, http, body, LicenseConfig.AcceptsTestLicenses, instanceId);
    }

    /// <summary>Odpowiedź serwera → wynik albo <see cref="LicenseException"/> (bez sieci, testowane na wektorach).</summary>
    public static LicenseResult Interpret(LicenseCall call, int http, string body, bool acceptsTestLicenses, string? instanceId = null)
    {
        // 4xx niesie decyzję serwera (np. zły klucz); 5xx i śmieci to awaria, nie decyzja.
        if (http >= 500) throw Network($"HTTP {http}");
        JsonDocument document;
        try
        {
            document = JsonDocument.Parse(body);
        }
        catch (JsonException)
        {
            throw Network($"HTTP {http}");
        }
        using (document)
        {
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object) throw Network($"HTTP {http}");
            var code = String(root, "code");
            var license = root.TryGetProperty("license", out var l) && l.ValueKind == JsonValueKind.Object ? l : (JsonElement?)null;
            var isTest = license is { } lic && lic.TryGetProperty("test", out var t) && t.ValueKind == JsonValueKind.True;
            var email = String(root, "customer_email");
            LicenseException Rejected() => new(LicenseFailure.Rejected,
                MessageFor(code) ?? String(root, "error") ?? T("The license server rejected the key.", pl: "Serwer licencji odrzucił klucz."), code);

            switch (call)
            {
                case LicenseCall.Activate:
                    if (!Bool(root, "activated") || !root.TryGetProperty("instance", out var instance) || instance.ValueKind != JsonValueKind.Object
                        || String(instance, "id") is not { } id)
                        throw Rejected();
                    if (isTest && !acceptsTestLicenses)
                        throw new LicenseException(LicenseFailure.WrongProduct,
                            T("This is a test key. It works only in test builds of Seam.", pl: "To klucz testowy. Działa tylko w testowych wersjach Seam."));
                    return new(LicenseStatus.Active, id, email);

                case LicenseCall.Validate:
                    if (!root.TryGetProperty("valid", out var valid) || valid.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
                        throw Rejected();
                    if (valid.ValueKind == JsonValueKind.True && !(isTest && !acceptsTestLicenses))
                        return new(LicenseStatus.Active, instanceId, email);
                    // Odmowa przy statusie „active” oznacza brak tej instancji (dezaktywowana gdzie indziej)
                    // albo klucz testowy w wydaniu; nieznany klucz też kończy licencję na tym komputerze.
                    var status = LicenseStatus.Inactive;
                    if (license is { } info && String(info, "status") is { } raw
                        && Enum.TryParse<LicenseStatus>(raw, true, out var parsed) && parsed != LicenseStatus.Active)
                        status = parsed;
                    return new(status, instanceId, email);

                default:
                    if (!Bool(root, "deactivated")) throw Rejected();
                    return new(LicenseStatus.Inactive, instanceId, null);
            }
        }
    }

    /// <summary>Przetłumaczony opis znanych odmów serwera; null = pokaż tekst z serwera.</summary>
    public static string? MessageFor(string? code) => code switch
    {
        "invalid_key" => T("This license key doesn't exist. Check it in your purchase email.",
                           pl: "Taki klucz licencji nie istnieje. Sprawdź go w mailu z zakupu."),
        "device_limit" => T("This key is already active on 3 computers. Deactivate it on one of them (Settings → License) and try again.",
                            pl: "Ten klucz działa już na 3 komputerach. Dezaktywuj go na jednym z nich (Ustawienia → Licencja) i spróbuj ponownie."),
        "license_disabled" => T("This license was disabled after a refund or a payment dispute.",
                                pl: "Ta licencja została wyłączona po zwrocie pieniędzy albo sporze o płatność."),
        _ => null,
    };

    private static async Task<(int Http, string Body)> PostAsync(LicenseCall call, Dictionary<string, string> fields, CancellationToken ct)
    {
        if (!LicenseConfig.IsConfigured)
            throw new LicenseException(LicenseFailure.NotConfigured, T("This build can't activate licenses yet.", pl: "Ta wersja nie może jeszcze aktywować licencji."));
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Post, call.ToString().ToLowerInvariant())
            {
                Content = new StringContent(JsonSerializer.Serialize(fields), Encoding.UTF8, "application/json"),
            };
            request.Headers.Accept.ParseAdd("application/json");
            using var response = await Http.SendAsync(request, ct);
            return ((int)response.StatusCode, await response.Content.ReadAsStringAsync(ct));
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
        {
            throw Network(ex.Message);
        }
    }

    private static LicenseException Network(string message) =>
        new(LicenseFailure.Network, T($"Couldn't reach the license server: {message}", pl: $"Brak połączenia z serwerem licencji: {message}"));

    private static bool Bool(JsonElement root, string name) =>
        root.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.True;

    private static string? String(JsonElement root, string name) =>
        root.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;
}
