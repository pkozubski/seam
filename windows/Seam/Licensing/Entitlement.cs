namespace Seam.Licensing;

public enum EntitlementState
{
    /// <summary>Trial jeszcze nie ruszył.</summary>
    Free,
    Trial,
    TrialExpired,
    Pro,
    /// <summary>Licencja nie była sprawdzona dłużej niż <see cref="Entitlement.OfflineGraceDays"/>.</summary>
    ValidationRequired,
    /// <summary>Zwrot, blokada albo wygaśnięcie po stronie sklepu.</summary>
    Revoked,
}

public enum LicenseStatus
{
    Active,
    Inactive,
    Disabled,
    Expired,
}

public sealed record LicenseSnapshot(LicenseStatus Status, DateTimeOffset ValidatedAt);

/// <summary>
/// Uprawnienie do funkcji Pro: czysta logika, ta sama co Entitlement.swift na Macu
/// (wspólne wektory w <c>tests/fixtures/entitlement.json</c>).
/// </summary>
public sealed record Entitlement(EntitlementState State, int? TrialDaysLeft, bool ShouldRevalidate)
{
    public const int TrialDays = 7;
    public const int RevalidateDays = 7;
    public const int OfflineGraceDays = 30;
    /// <summary>Zmiana strefy czasowej może cofnąć zegar o kilka godzin; dalsze cofnięcie kończy trial.</summary>
    private static readonly TimeSpan ClockSkewTolerance = TimeSpan.FromDays(1);

    public bool IsEntitled => State is EntitlementState.Trial or EntitlementState.Pro;

    public static Entitlement Evaluate(DateTimeOffset now, DateTimeOffset? trialStartedAt, LicenseSnapshot? license)
    {
        int? trialLeft = null;
        if (trialStartedAt is { } start)
        {
            var elapsed = now - start;
            var length = TimeSpan.FromDays(TrialDays);
            if (elapsed >= -ClockSkewTolerance && elapsed < length)
                trialLeft = (int)Math.Ceiling((length - (elapsed < TimeSpan.Zero ? TimeSpan.Zero : elapsed)).TotalDays);
        }

        TimeSpan? licenseAge = null;
        if (license is { Status: LicenseStatus.Active })
        {
            var age = now - license.ValidatedAt;
            licenseAge = age < TimeSpan.Zero ? TimeSpan.Zero : age;
        }
        var shouldRevalidate = licenseAge >= TimeSpan.FromDays(RevalidateDays);

        if (licenseAge <= TimeSpan.FromDays(OfflineGraceDays)) return new(EntitlementState.Pro, null, shouldRevalidate);
        if (trialLeft is not null) return new(EntitlementState.Trial, trialLeft, shouldRevalidate);
        if (licenseAge is not null) return new(EntitlementState.ValidationRequired, null, shouldRevalidate);
        if (license is { Status: LicenseStatus.Disabled or LicenseStatus.Expired }) return new(EntitlementState.Revoked, null, false);
        return new(trialStartedAt is null ? EntitlementState.Free : EntitlementState.TrialExpired, null, false);
    }
}
