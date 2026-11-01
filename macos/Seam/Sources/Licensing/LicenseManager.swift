import AppKit
import Foundation

/// Stan licencji dla widoków i silnika: trial, aktywacja, walidacja w tle.
@MainActor
@Observable
final class LicenseManager {
    private(set) var license: StoredLicense?
    private(set) var trialStartedAt: Date?
    private(set) var entitlement: Entitlement
    private(set) var isBusy = false
    private(set) var errorMessage: String?

    /// Wołane przy każdej zmianie `entitlement.isEntitled` (AppState przekazuje to silnikowi).
    @ObservationIgnored var onEntitlementChanged: ((Bool) -> Void)?

    @ObservationIgnored private let client = LemonSqueezyClient()
    @ObservationIgnored private var timer: Timer?
    /// Dopóki sklep nie istnieje (`LicenseConfig`), nikt nie traci funkcji, także testerzy na kanale dev.
    /// Podgląd UI pokazuje blokady zawsze.
    @ObservationIgnored private let enforced: Bool

    init() {
        let storedLicense = LicenseStore.loadLicense()
        let trial = LicenseStore.trialStartedAt()
        license = storedLicense
        trialStartedAt = trial
        entitlement = Entitlement(now: Date(), trialStartedAt: trial, license: storedLicense?.entitlementLicense)
        enforced = LicenseConfig.isConfigured
    }

    /// Podgląd UI (`--ui-license <free|trial|expired|pro>`), bez Pęku kluczy i sieci.
    init(preview: String) {
        let now = Date()
        let trial: Date? = switch preview {
        case "trial": now.addingTimeInterval(-2.5 * 86_400)
        case "expired": now.addingTimeInterval(-9 * 86_400)
        default: nil
        }
        let stored: StoredLicense? = preview == "pro"
            ? StoredLicense(key: "38B1460A-5104-4067-A91D-77B872934D51", instanceID: "preview", status: .active,
                            validatedAt: now, customerEmail: "you@example.com")
            : nil
        trialStartedAt = trial
        license = stored
        entitlement = Entitlement(now: now, trialStartedAt: trial, license: stored?.entitlementLicense)
        enforced = true
    }

    var isEntitled: Bool { !enforced || entitlement.isEntitled }
    var canStartTrial: Bool { trialStartedAt == nil && !entitlement.isEntitled }

    /// Kod rabatowy dla osób, które używały Seam przed wersją płatną.
    static let testerCoupon = "BETA50"
    private static let testerMarkerKey = "license.testerTrialGranted"
    var showsTesterOffer: Bool { UserDefaults.standard.bool(forKey: Self.testerMarkerKey) && entitlement.state != .pro }

    /// Pierwsze uruchomienie z płatnym Pro u kogoś, kto już używał Seam: trial startuje sam.
    func grantTesterTrialIfNeeded(existingUser: Bool) {
        guard enforced, existingUser, license == nil,
              !UserDefaults.standard.bool(forKey: Self.testerMarkerKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.testerMarkerKey)
        if trialStartedAt == nil { startTrial() }
    }

    /// Start w tle: przelicza stan co godzinę (koniec trialu, okres łaski) i waliduje licencję, gdy pora.
    func start() {
        let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 300
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    func refresh() {
        let next = Entitlement(now: Date(), trialStartedAt: trialStartedAt, license: license?.entitlementLicense)
        let wasEntitled = isEntitled
        if next != entitlement { entitlement = next }
        if isEntitled != wasEntitled { onEntitlementChanged?(isEntitled) }
        if next.shouldRevalidate, !isBusy { Task { await revalidate() } }
    }

    func startTrial() {
        trialStartedAt = LicenseStore.startTrial(at: Date())
        refresh()
    }

    func activate(key raw: String) async {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !isBusy else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let result = try await client.activate(key: key, instanceName: Host.current().localizedName ?? "Mac")
            let stored = StoredLicense(key: key, instanceID: result.instanceID ?? "", status: .active,
                                       validatedAt: Date(), customerEmail: result.customerEmail)
            if let error = LicenseStore.save(stored) { errorMessage = error }
            license = stored
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Zwalnia miejsce w limicie urządzeń. Bez sieci licencja i tak znika z tego Maca.
    func deactivate() async {
        guard let license, !isBusy else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await client.deactivate(key: license.key, instanceID: license.instanceID)
        } catch {
            errorMessage = error.localizedDescription
        }
        LicenseStore.deleteLicense()
        self.license = nil
        refresh()
    }

    func revalidate() async {
        guard let current = license, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await client.validate(key: current.key, instanceID: current.instanceID)
            var updated = current
            updated.status = result.status
            updated.validatedAt = Date()
            updated.customerEmail = result.customerEmail ?? current.customerEmail
            LicenseStore.save(updated)
            license = updated
            errorMessage = nil
        } catch LemonSqueezyClient.Failure.network {
            // Bez sieci zostaje ostatni wynik; okres łaski liczy `Entitlement`.
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    func openCheckout() {
        NSWorkspace.shared.open(LicenseConfig.checkoutURL)
    }
}
