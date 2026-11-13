import SwiftUI

/// Ustawienia → Licencja: stan Seam Pro, okres próbny, klucz, zakup i dezaktywacja.
struct LicenseSettingsPane: View {
    @Environment(AppState.self) private var state
    @State private var key = ""

    private var license: LicenseManager { state.license }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsChrome.sectionSpacing) {
            SettingsCard {
                HStack(spacing: 14) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable().interpolation(.high).scaledToFit()
                        .frame(width: 56, height: 56)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(verbatim: headline).font(.title3.weight(.semibold))
                            if license.entitlement.state == .pro { ProBadge() }
                        }
                        Text(verbatim: detail).font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    if license.entitlement.state != .pro {
                        Button(L10n.text("Buy Pro – \(LicenseConfig.price)", pl: "Kup Pro – \(LicenseConfig.price)"), action: license.openCheckout)
                            .modifier(NativeActionStyle(prominent: true))
                            .controlSize(.small)
                    }
                }
                .padding(16)
                if license.canStartTrial {
                    SettingsRowDivider()
                    SettingsCardRow(title: L10n.text("Free trial", pl: "Okres próbny"),
                                    detail: L10n.text("\(Entitlement.trialDays) days of every Pro feature. No account, no card.",
                                                      pl: "\(Entitlement.trialDays) dni wszystkich funkcji Pro. Bez konta i karty.")) {
                        Button(L10n.text("Start trial", pl: "Rozpocznij"), action: license.startTrial)
                            .modifier(NativeActionStyle())
                            .controlSize(.small)
                    }
                }
                if license.showsTesterOffer {
                    SettingsRowDivider()
                    SettingsCardRow(title: L10n.text("Thanks for testing Seam", pl: "Dziękujemy za testowanie Seam"),
                                    detail: L10n.text("Use code \(LicenseManager.testerCoupon) at checkout for 50% off.",
                                                      pl: "Kod \(LicenseManager.testerCoupon) daje 50% zniżki przy zakupie.")) {
                        Button(L10n.text("Copy code", pl: "Kopiuj kod")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(LicenseManager.testerCoupon, forType: .string)
                        }
                        .modifier(NativeActionStyle())
                        .controlSize(.small)
                    }
                }
            }

            if let stored = license.license {
                SettingsSection(title: L10n.text("This Mac", pl: "Ten Mac")) {
                    SettingsCardRow(title: L10n.text("License key", pl: "Klucz licencji"),
                                    detail: [stored.maskedKey, stored.customerEmail].compactMap { $0 }.joined(separator: " · ")) {
                        Button(L10n.text("Deactivate", pl: "Dezaktywuj")) { Task { await license.deactivate() } }
                            .modifier(NativeActionStyle())
                            .controlSize(.small)
                            .disabled(license.isBusy)
                    }
                    SettingsRowDivider()
                    SettingsCardRow(title: L10n.text("Last checked", pl: "Ostatnio sprawdzona"),
                                    detail: L10n.text("Works offline for up to \(Entitlement.offlineGraceDays) days.",
                                                      pl: "Działa bez internetu do \(Entitlement.offlineGraceDays) dni.")) {
                        Text(stored.validatedAt, format: .dateTime.day().month().hour().minute())
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            } else {
                SettingsSection(title: L10n.text("Activate", pl: "Aktywacja")) {
                    SettingsCardRow(title: L10n.text("License key", pl: "Klucz licencji"),
                                    detail: L10n.text("From the purchase email. One license covers up to 3 computers.",
                                                      pl: "Z e-maila po zakupie. Jedna licencja obejmuje do 3 komputerów.")) {
                        HStack(spacing: 8) {
                            TextField("", text: $key, prompt: Text(verbatim: "SEAM-XXXXX-XXXXX-XXXXX-XXXXX"))
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 230)
                                .onSubmit(activate)
                            Button(L10n.text("Activate", pl: "Aktywuj"), action: activate)
                                .modifier(NativeActionStyle())
                                .controlSize(.small)
                                .disabled(license.isBusy || key.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
            }

            if let error = license.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline).foregroundStyle(.orange)
                    .padding(.leading, 4)
            }

            SettingsSection(title: L10n.text("What's in Pro", pl: "Co daje Pro")) {
                ForEach(Array(Self.features.enumerated()), id: \.offset) { index, feature in
                    if index > 0 { SettingsRowDivider() }
                    HStack(spacing: 12) {
                        Image(systemName: feature.symbol).frame(width: 20).foregroundStyle(.secondary)
                        Text(verbatim: feature.title)
                        Spacer()
                        Text(verbatim: feature.pro ? "Pro" : L10n.text("Free", pl: "Za darmo"))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(feature.pro ? Color.orange : Color.secondary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                }
            }
            Text(verbatim: L10n.text("Pro works on both computers when either of them has a license or a trial.",
                                     pl: "Pro działa na obu komputerach, gdy licencję albo okres próbny ma którykolwiek z nich."))
                .font(.subheadline).foregroundStyle(.secondary)
                .padding(.leading, 4)
        }
    }

    private func activate() {
        let value = key
        Task {
            await license.activate(key: value)
            if license.license != nil { key = "" }
        }
    }

    private var headline: String {
        switch license.entitlement.state {
        case .pro: return "Seam Pro"
        case .trial: return L10n.text("Seam Pro trial", pl: "Seam Pro – okres próbny")
        default: return "Seam Free"
        }
    }

    private var detail: String {
        let entitlement = license.entitlement
        switch entitlement.state {
        case .pro:
            return L10n.text("Thank you! Every feature is unlocked on this Mac and the PCs it connects to.",
                             pl: "Dziękujemy! Wszystkie funkcje działają na tym Macu i połączonych z nim PC.")
        case .trial:
            let days = entitlement.trialDaysLeft ?? 0
            return L10n.text(days == 1 ? "Last day of the trial." : "\(days) days left in the trial.",
                             pl: days == 1 ? "Ostatni dzień okresu próbnego." : "Do końca okresu próbnego: \(days) dni.")
        case .trialExpired:
            return L10n.text("The trial has ended. Keyboard, mouse and text in the clipboard stay free.",
                             pl: "Okres próbny się skończył. Klawiatura, mysz i tekst w schowku zostają darmowe.")
        case .validationRequired:
            return L10n.text("Connect to the internet so Seam can check the license.",
                             pl: "Połącz się z internetem, żeby Seam sprawdził licencję.")
        case .revoked:
            return L10n.text("The license was refunded or disabled.", pl: "Licencja została zwrócona albo wyłączona.")
        case .free:
            return L10n.text("Keyboard, mouse and text in the clipboard, free forever.",
                             pl: "Klawiatura, mysz i tekst w schowku, za darmo na zawsze.")
        }
    }

    private static let features: [(symbol: String, title: String, pro: Bool)] = [
        ("keyboard", L10n.text("One keyboard and mouse", pl: "Jedna klawiatura i mysz"), false),
        ("doc.on.clipboard", L10n.text("Text in the clipboard", pl: "Tekst w schowku"), false),
        ("photo", L10n.text("Images and screenshots in the clipboard", pl: "Obrazy i zrzuty w schowku"), true),
        ("speaker.wave.2", L10n.text("Mac audio on the PC", pl: "Dźwięk Maca na PC"), true),
        ("macwindow.on.rectangle", L10n.text("Mac windows on the PC", pl: "Okna Maca na PC"), true),
        ("rectangle.on.rectangle", L10n.text("Windows apps on the Mac", pl: "Aplikacje Windows na Macu"), true),
    ]
}
