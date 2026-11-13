import Foundation

/// Sklep Seam Pro: Stripe Payment Link (przez seamdesk.app/buy/) i własny serwer licencji
/// (`license-server/`, api.seamdesk.app). Te same wartości co `LicenseConfig` w LicenseClient.cs na Windows.
enum LicenseConfig {
    static let apiBase = URL(string: "https://api.seamdesk.app/v1/licenses/")!
    static let price = "$10"
    /// Sprzedaż w Stripe działa w trybie live. Dopiero wtedy wydania blokują funkcje Pro.
    static let liveSales = true
    /// Payment Link w trybie testowym Stripe (karta 4242 4242 4242 4242): kanał dev blokuje Pro i przyjmuje
    /// klucze testowe, wydania nigdy.
    static let testSales = true

    static var acceptsTestLicenses: Bool { Updater.isDevChannel }
    /// Bez sprzedaży nikt nie traci funkcji, bo nie miałby gdzie kupić licencji.
    static var isConfigured: Bool { liveSales || (testSales && Updater.isDevChannel) }
    static var checkoutURL: URL {
        URL(string: Updater.isDevChannel && testSales ? "https://seamdesk.app/buy/?test" : "https://seamdesk.app/buy/")!
    }
}
