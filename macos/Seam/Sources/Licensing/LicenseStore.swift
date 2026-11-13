import Foundation

/// Licencja zapisana po aktywacji. Klucz i identyfikator instancji są potrzebne do walidacji i dezaktywacji.
struct StoredLicense: Codable, Equatable {
    var key: String
    var instanceID: String
    var status: Entitlement.LicenseStatus
    var validatedAt: Date
    var customerEmail: String?

    var entitlementLicense: Entitlement.License { .init(status: status, validatedAt: validatedAt) }

    /// Klucz do wyświetlenia: tylko ostatnie znaki.
    var maskedKey: String { "••••-" + key.suffix(4) }
}

/// Licencja i początek trialu w Pęku kluczy (ten Mac, po odblokowaniu). Pęk kluczy przetrwa
/// usunięcie aplikacji, więc ponowna instalacja nie daje nowego trialu.
enum LicenseStore {
    private static let service = "com.borderlessmouse.license"
    private static let licenseAccount = "license"
    private static let trialAccount = "trial"

    static func loadLicense() -> StoredLicense? {
        guard let data = Keychain.read(service: service, account: licenseAccount) else { return nil }
        return try? decoder.decode(StoredLicense.self, from: data)
    }

    @discardableResult
    static func save(_ license: StoredLicense) -> String? {
        guard let data = try? encoder.encode(license) else { return nil }
        return Keychain.write(data, service: service, account: licenseAccount)
    }

    static func deleteLicense() {
        Keychain.delete(service: service, account: licenseAccount)
    }

    static func trialStartedAt() -> Date? {
        guard let data = Keychain.read(service: service, account: trialAccount) else { return nil }
        return try? decoder.decode(Date.self, from: data)
    }

    /// Trial startuje raz; kolejne wywołania zwracają pierwszą datę.
    static func startTrial(at date: Date) -> Date {
        if let existing = trialStartedAt() { return existing }
        if let data = try? encoder.encode(date) { Keychain.write(data, service: service, account: trialAccount) }
        return date
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
