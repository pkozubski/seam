import Foundation

/// Sklep i produkt Seam Pro w Lemon Squeezy. Zera = sklep jeszcze nie założony: aktywacja jest wtedy
/// wyłączona, bo bez sprawdzenia sklepu i produktu przeszedłby klucz z dowolnego sklepu Lemon Squeezy.
enum LicenseConfig {
    static let storeID = 0
    static let productID = 0
    static let checkoutURL = URL(string: "https://seam.lemonsqueezy.com/buy/seam-pro")!
    static let price = "$10"

    static var isConfigured: Bool { storeID != 0 && productID != 0 }
}

/// License API Lemon Squeezy (bez klucza API; klucz licencyjny wystarcza).
/// https://docs.lemonsqueezy.com/api/license-api
struct LemonSqueezyClient {
    struct Result {
        var status: Entitlement.LicenseStatus
        var instanceID: String?
        var customerEmail: String?
    }

    enum Failure: LocalizedError {
        /// Brak sieci albo błąd serwera: nic nie zmieniamy, licencja działa w okresie łaski.
        case network(String)
        /// Sklep odpowiedział odmową (zły klucz, limit urządzeń, zwrot).
        case rejected(String)
        /// Klucz z innego sklepu albo produktu.
        case wrongProduct
        case notConfigured

        var errorDescription: String? {
            switch self {
            case .network(let message):
                return L10n.text("Couldn't reach the license server: \(message)", pl: "Brak połączenia z serwerem licencji: \(message)")
            case .rejected(let message):
                return message
            case .wrongProduct:
                return L10n.text("This key isn't a Seam Pro license.", pl: "Ten klucz nie jest licencją Seam Pro.")
            case .notConfigured:
                return L10n.text("This build can't activate licenses.", pl: "Ta wersja nie może aktywować licencji.")
            }
        }
    }

    var session: URLSession = .shared
    private let base = URL(string: "https://api.lemonsqueezy.com/v1/licenses/")!

    func activate(key: String, instanceName: String) async throws -> Result {
        let json = try await post("activate", ["license_key": key, "instance_name": instanceName])
        try checkProduct(json)
        guard json["activated"] as? Bool == true, let instance = (json["instance"] as? [String: Any])?["id"] as? String else {
            throw Failure.rejected(Self.message(json))
        }
        return Result(status: .active, instanceID: instance, customerEmail: Self.email(json))
    }

    /// Zwraca stan licencji także przy odmowie: zwrot albo dezaktywacja to wynik, nie błąd.
    func validate(key: String, instanceID: String) async throws -> Result {
        let json = try await post("validate", ["license_key": key, "instance_id": instanceID])
        if json["meta"] != nil { try checkProduct(json) }
        if json["valid"] as? Bool == true {
            return Result(status: .active, instanceID: instanceID, customerEmail: Self.email(json))
        }
        // Niepoprawna odpowiedź przy statusie „active” oznacza brak tej instancji (dezaktywowana gdzie indziej).
        let licenseKey = json["license_key"] as? [String: Any]
        var status = Entitlement.LicenseStatus.inactive
        if let raw = licenseKey?["status"] as? String, let parsed = Entitlement.LicenseStatus(rawValue: raw), parsed != .active {
            status = parsed
        }
        return Result(status: status, instanceID: instanceID, customerEmail: Self.email(json))
    }

    func deactivate(key: String, instanceID: String) async throws {
        let json = try await post("deactivate", ["license_key": key, "instance_id": instanceID])
        guard json["deactivated"] as? Bool == true else { throw Failure.rejected(Self.message(json)) }
    }

    private func post(_ path: String, _ fields: [String: String]) async throws -> [String: Any] {
        guard LicenseConfig.isConfigured else { throw Failure.notConfigured }
        var request = URLRequest(url: base.appendingPathComponent(path), timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        // Formularz ręcznie: URLComponents nie koduje „+” ani „&” w wartościach.
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        request.httpBody = Data(fields.map { name, value in
            "\(name)=\(value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? "")"
        }.joined(separator: "&").utf8)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Failure.network(error.localizedDescription)
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        // 4xx niesie odpowiedź sklepu (np. zły klucz); 5xx i śmieci to awaria, nie decyzja.
        guard code < 500, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.network("HTTP \(code)")
        }
        return json
    }

    private func checkProduct(_ json: [String: Any]) throws {
        guard let meta = json["meta"] as? [String: Any] else { throw Failure.rejected(Self.message(json)) }
        guard meta["store_id"] as? Int == LicenseConfig.storeID,
              meta["product_id"] as? Int == LicenseConfig.productID else { throw Failure.wrongProduct }
    }

    private static func email(_ json: [String: Any]) -> String? {
        (json["meta"] as? [String: Any])?["customer_email"] as? String
    }

    private static func message(_ json: [String: Any]) -> String {
        (json["error"] as? String) ?? L10n.text("The license server rejected the key.", pl: "Serwer licencji odrzucił klucz.")
    }
}
