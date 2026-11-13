import Foundation

/// API serwera licencji Seam (`license-server/`). Znaczenie odpowiedzi opisują wspólne wektory
/// `tests/fixtures/license-api.json` (ten sam kontrakt co LicenseClient.cs na Windows).
struct LicenseClient {
    struct Result: Equatable {
        var status: Entitlement.LicenseStatus
        var instanceID: String?
        var customerEmail: String?
    }

    enum Call: String {
        case activate, validate, deactivate
    }

    enum Failure: LocalizedError, Equatable {
        /// Brak sieci albo błąd serwera: nic nie zmieniamy, licencja działa w okresie łaski.
        case network(String)
        /// Serwer odmówił (zły klucz, limit urządzeń, zwrot). `code` to stała z serwera.
        case rejected(code: String?, message: String)
        /// Klucz testowy w wydaniu (testowe zakupy Stripe działają tylko na kanale dev).
        case wrongProduct
        case notConfigured

        var errorDescription: String? {
            switch self {
            case .network(let message):
                return L10n.text("Couldn't reach the license server: \(message)", pl: "Brak połączenia z serwerem licencji: \(message)")
            case .rejected(let code, let message):
                return Self.message(for: code) ?? message
            case .wrongProduct:
                return L10n.text("This is a test key. It works only in test builds of Seam.",
                                 pl: "To klucz testowy. Działa tylko w testowych wersjach Seam.")
            case .notConfigured:
                return L10n.text("This build can't activate licenses yet.", pl: "Ta wersja nie może jeszcze aktywować licencji.")
            }
        }

        static func message(for code: String?) -> String? {
            switch code {
            case "invalid_key":
                L10n.text("This license key doesn't exist. Check it in your purchase email.",
                          pl: "Taki klucz licencji nie istnieje. Sprawdź go w mailu z zakupu.")
            case "device_limit":
                L10n.text("This key is already active on 3 computers. Deactivate it on one of them (Settings → License) and try again.",
                          pl: "Ten klucz działa już na 3 komputerach. Dezaktywuj go na jednym z nich (Ustawienia → Licencja) i spróbuj ponownie.")
            case "license_disabled":
                L10n.text("This license was disabled after a refund or a payment dispute.",
                          pl: "Ta licencja została wyłączona po zwrocie pieniędzy albo sporze o płatność.")
            default:
                nil
            }
        }
    }

    var base: URL
    var acceptsTestLicenses: Bool
    var isEnabled: Bool
    var session: URLSession = .shared

    func activate(key: String, instanceName: String) async throws -> Result {
        let (http, data) = try await post(.activate, ["license_key": key, "instance_name": instanceName])
        return try Self.interpret(.activate, http: http, data: data, acceptsTestLicenses: acceptsTestLicenses)
    }

    /// Zwraca stan licencji także przy odmowie: zwrot albo dezaktywacja to wynik, nie błąd.
    func validate(key: String, instanceID: String) async throws -> Result {
        let (http, data) = try await post(.validate, ["license_key": key, "instance_id": instanceID])
        return try Self.interpret(.validate, http: http, data: data, acceptsTestLicenses: acceptsTestLicenses, instanceID: instanceID)
    }

    func deactivate(key: String, instanceID: String) async throws {
        let (http, data) = try await post(.deactivate, ["license_key": key, "instance_id": instanceID])
        _ = try Self.interpret(.deactivate, http: http, data: data, acceptsTestLicenses: acceptsTestLicenses, instanceID: instanceID)
    }

    /// Odpowiedź serwera → wynik albo błąd (bez sieci, testowane na wektorach z license-api.json).
    static func interpret(_ call: Call, http: Int, data: Data, acceptsTestLicenses: Bool, instanceID: String? = nil) throws -> Result {
        // 4xx niesie decyzję serwera (np. zły klucz); 5xx i śmieci to awaria, nie decyzja.
        guard http < 500, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.network("HTTP \(http)")
        }
        let code = json["code"] as? String
        let rejected = Failure.rejected(code: code, message: (json["error"] as? String)
            ?? L10n.text("The license server rejected the key.", pl: "Serwer licencji odrzucił klucz."))
        let license = json["license"] as? [String: Any]
        let isTest = license?["test"] as? Bool == true
        let email = json["customer_email"] as? String

        switch call {
        case .activate:
            guard json["activated"] as? Bool == true,
                  let instance = (json["instance"] as? [String: Any])?["id"] as? String else { throw rejected }
            if isTest && !acceptsTestLicenses { throw Failure.wrongProduct }
            return Result(status: .active, instanceID: instance, customerEmail: email)
        case .validate:
            guard let valid = json["valid"] as? Bool else { throw rejected }
            if valid && !(isTest && !acceptsTestLicenses) {
                return Result(status: .active, instanceID: instanceID, customerEmail: email)
            }
            // Odmowa przy statusie „active” oznacza brak tej instancji (dezaktywowana gdzie indziej)
            // albo klucz testowy w wydaniu; nieznany klucz też kończy licencję na tym komputerze.
            var status = Entitlement.LicenseStatus.inactive
            if let raw = license?["status"] as? String, let parsed = Entitlement.LicenseStatus(rawValue: raw), parsed != .active {
                status = parsed
            }
            return Result(status: status, instanceID: instanceID, customerEmail: email)
        case .deactivate:
            guard json["deactivated"] as? Bool == true else { throw rejected }
            return Result(status: .inactive, instanceID: instanceID, customerEmail: nil)
        }
    }

    private func post(_ call: Call, _ fields: [String: String]) async throws -> (Int, Data) {
        guard isEnabled else { throw Failure.notConfigured }
        var request = URLRequest(url: base.appendingPathComponent(call.rawValue), timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: fields)
        do {
            let (data, response) = try await session.data(for: request)
            return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
        } catch {
            throw Failure.network(error.localizedDescription)
        }
    }
}
