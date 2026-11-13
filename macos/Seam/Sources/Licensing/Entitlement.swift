import Foundation

/// Uprawnienie do funkcji Pro: czysta logika, ta sama co `Entitlement.cs` na Windows
/// (wspólne wektory w `tests/fixtures/entitlement.json`).
struct Entitlement: Equatable {
    static let trialDays = 7
    static let revalidateDays = 7
    static let offlineGraceDays = 30
    /// Zmiana strefy czasowej może cofnąć zegar o kilka godzin; dalsze cofnięcie kończy trial.
    static let clockSkewTolerance: TimeInterval = 86_400

    enum State: String {
        /// Trial jeszcze nie ruszył.
        case free
        case trial
        case trialExpired
        case pro
        /// Licencja nie była sprawdzona dłużej niż `offlineGraceDays`.
        case validationRequired
        /// Zwrot, blokada albo wygaśnięcie po stronie sklepu.
        case revoked
    }

    enum LicenseStatus: String, Codable {
        case active, inactive, disabled, expired
    }

    struct License: Equatable, Codable {
        var status: LicenseStatus
        var validatedAt: Date
    }

    let state: State
    let trialDaysLeft: Int?
    /// Pora zapytać sklep o stan licencji (przy dostępie do sieci).
    let shouldRevalidate: Bool

    var isEntitled: Bool { state == .trial || state == .pro }

    init(now: Date, trialStartedAt: Date?, license: License?) {
        let day: TimeInterval = 86_400
        var trialLeft: Int?
        if let start = trialStartedAt {
            let elapsed = now.timeIntervalSince(start)
            let length = Double(Self.trialDays) * day
            if elapsed >= -Self.clockSkewTolerance, elapsed < length {
                trialLeft = Int(((length - max(elapsed, 0)) / day).rounded(.up))
            }
        }

        var licenseAge: TimeInterval?
        if let license, license.status == .active {
            licenseAge = max(now.timeIntervalSince(license.validatedAt), 0)
        }
        shouldRevalidate = licenseAge.map { $0 >= Double(Self.revalidateDays) * day } ?? false

        if let age = licenseAge, age <= Double(Self.offlineGraceDays) * day {
            state = .pro
            trialDaysLeft = nil
        } else if let trialLeft {
            state = .trial
            trialDaysLeft = trialLeft
        } else {
            trialDaysLeft = nil
            if licenseAge != nil {
                state = .validationRequired
            } else if let license, license.status == .disabled || license.status == .expired {
                state = .revoked
            } else {
                state = trialStartedAt == nil ? .free : .trialExpired
            }
        }
    }
}
