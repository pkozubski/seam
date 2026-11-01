using System.Diagnostics;
using CommunityToolkit.Mvvm.ComponentModel;
using Seam.Models;

namespace Seam.Licensing;

/// <summary>Stan licencji dla widoków i silnika: trial, aktywacja, walidacja w tle (wątek UI).</summary>
public sealed partial class LicenseManager : ObservableObject
{
    /// <summary>Kod rabatowy dla osób, które używały Seam przed wersją płatną.</summary>
    public const string TesterCoupon = "BETA50";

    [ObservableProperty] [NotifyPropertyChangedFor(nameof(IsEntitled), nameof(CanStartTrial))] private Entitlement _entitlement;
    [ObservableProperty] private StoredLicense? _license;
    [ObservableProperty] private bool _isBusy;
    [ObservableProperty] private string? _errorMessage;

    private DateTimeOffset? _trialStartedAt;
    /// <summary>Dopóki sklep nie istnieje (<see cref="LicenseConfig"/>), nikt nie traci funkcji, także testerzy z kanału dev.
    /// Podgląd UI pokazuje blokady zawsze.</summary>
    private readonly bool _enforced;
    private readonly Settings? _settings;
    private System.Threading.Timer? _timer;

    /// <summary>Zmiana <see cref="IsEntitled"/> (MainViewModel przekazuje ją Macowi i włącza/wyłącza funkcje).</summary>
    public event Action<bool>? EntitlementChanged;

    public LicenseManager(Settings settings)
    {
        _settings = settings;
        _license = LicenseStore.LoadLicense();
        _trialStartedAt = LicenseStore.TrialStartedAt();
        _entitlement = Entitlement.Evaluate(DateTimeOffset.UtcNow, _trialStartedAt, _license?.Snapshot);
        _enforced = LicenseConfig.IsConfigured;
    }

    /// <summary>Podgląd UI (<c>--screenshot-license free|trial|expired|pro</c>), bez pliku licencji i sieci.</summary>
    public LicenseManager(string preview)
    {
        var now = DateTimeOffset.UtcNow;
        _trialStartedAt = preview switch
        {
            "trial" => now.AddDays(-2.5),
            "expired" => now.AddDays(-9),
            _ => null,
        };
        _license = preview == "pro"
            ? new StoredLicense("38B1460A-5104-4067-A91D-77B872934D51", "preview", LicenseStatus.Active, now, "you@example.com")
            : null;
        _entitlement = Entitlement.Evaluate(now, _trialStartedAt, _license?.Snapshot);
        _enforced = true;
    }

    public bool IsEntitled => !_enforced || Entitlement.IsEntitled;
    public bool CanStartTrial => _trialStartedAt is null && !Entitlement.IsEntitled;
    public bool ShowsTesterOffer => _settings?.TesterTrialGranted == true && Entitlement.State != EntitlementState.Pro;

    /// <summary>Pierwsze uruchomienie z płatnym Pro u kogoś, kto już używał Seam: trial startuje sam.</summary>
    public void GrantTesterTrialIfNeeded(bool existingUser)
    {
        if (!_enforced || !existingUser || License is not null || _settings is null || _settings.TesterTrialGranted) return;
        _settings.TesterTrialGranted = true;
        _settings.Save();
        if (_trialStartedAt is null) StartTrial();
    }

    /// <summary>Przelicza stan co godzinę (koniec trialu, okres łaski) i waliduje licencję, gdy pora.</summary>
    public void Start(Action<Action> post)
    {
        _timer = new System.Threading.Timer(_ => post(Refresh), null, TimeSpan.FromHours(1), TimeSpan.FromHours(1));
        Refresh();
    }

    public void Refresh()
    {
        var wasEntitled = IsEntitled;
        var next = Entitlement.Evaluate(DateTimeOffset.UtcNow, _trialStartedAt, License?.Snapshot);
        if (next != Entitlement) Entitlement = next;
        if (IsEntitled != wasEntitled) EntitlementChanged?.Invoke(IsEntitled);
        if (next.ShouldRevalidate && !IsBusy) _ = RevalidateAsync();
    }

    public void StartTrial()
    {
        _trialStartedAt = LicenseStore.StartTrial(DateTimeOffset.UtcNow);
        OnPropertyChanged(nameof(CanStartTrial));
        Refresh();
    }

    public async Task ActivateAsync(string? raw)
    {
        var key = raw?.Trim() ?? "";
        if (key.Length == 0 || IsBusy) return;
        IsBusy = true;
        ErrorMessage = null;
        try
        {
            var result = await LemonSqueezyClient.ActivateAsync(key, Environment.MachineName);
            var stored = new StoredLicense(key, result.InstanceId ?? "", LicenseStatus.Active, DateTimeOffset.UtcNow, result.CustomerEmail);
            LicenseStore.Save(stored);
            License = stored;
            Refresh();
        }
        catch (LicenseException ex)
        {
            ErrorMessage = ex.Message;
        }
        finally
        {
            IsBusy = false;
        }
    }

    /// <summary>Zwalnia miejsce w limicie urządzeń. Bez sieci licencja i tak znika z tego komputera.</summary>
    public async Task DeactivateAsync()
    {
        if (License is not { } current || IsBusy) return;
        IsBusy = true;
        ErrorMessage = null;
        try
        {
            await LemonSqueezyClient.DeactivateAsync(current.Key, current.InstanceId);
        }
        catch (LicenseException ex)
        {
            ErrorMessage = ex.Message;
        }
        finally
        {
            IsBusy = false;
        }
        LicenseStore.DeleteLicense();
        License = null;
        Refresh();
    }

    public async Task RevalidateAsync()
    {
        if (License is not { } current || IsBusy) return;
        IsBusy = true;
        try
        {
            var result = await LemonSqueezyClient.ValidateAsync(current.Key, current.InstanceId);
            var updated = current with
            {
                Status = result.Status,
                ValidatedAt = DateTimeOffset.UtcNow,
                CustomerEmail = result.CustomerEmail ?? current.CustomerEmail,
            };
            LicenseStore.Save(updated);
            License = updated;
            ErrorMessage = null;
        }
        catch (LicenseException ex) when (ex.IsNetwork)
        {
            // Bez sieci zostaje ostatni wynik; okres łaski liczy Entitlement.
        }
        catch (LicenseException ex)
        {
            ErrorMessage = ex.Message;
        }
        finally
        {
            IsBusy = false;
        }
        Refresh();
    }

    public static void OpenCheckout() =>
        Process.Start(new ProcessStartInfo(LicenseConfig.CheckoutUrl) { UseShellExecute = true });
}
