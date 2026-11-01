import Foundation

/// Język interfejsu wybrany w ustawieniach. `system` idzie za kolejnością języków macOS.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, english, polish

    var id: String { rawValue }

    /// Nazwy języków zawsze we własnym języku, żeby dało się je znaleźć po złym wyborze.
    var label: String {
        switch self {
        case .system: return L10n.text("System", pl: "Systemowy")
        case .english: return "English"
        case .polish: return "Polski"
        }
    }
}

/// Angielski jest językiem źródłowym, polski tłumaczeniem.
enum L10n {
    /// Raz na uruchomienie: odczyt preferencji przy każdym napisie kosztował zauważalnie dużo
    /// (widoki wołają `text` przy każdym odświeżeniu), a język i tak zmienia się dopiero po restarcie.
    /// W Seam ten sam wybór co `Bundle`, żeby napisy z `text` i z `Localizable.strings` się zgadzały.
    /// Pakiety `SeamHost` i testy nie mają `pl.lproj`: biorą wybór z ustawień Seam albo z systemu.
    static let isPolish: Bool = {
        if Bundle.main.localizations.contains("pl") {
            return Bundle.main.preferredLocalizations.first?.lowercased().hasPrefix("pl") == true
        }
        let override = UserDefaults.standard.persistentDomain(forName: seamBundleID)?[languagesKey] as? [String]
        return (override?.first ?? Locale.preferredLanguages.first)?.lowercased().hasPrefix("pl") == true
    }()

    static func text(_ english: String, pl polish: String) -> String {
        isPolish ? polish : english
    }

    static func localized(_ source: String) -> String {
        NSLocalizedString(source, comment: "")
    }

    /// `AppleLanguages` w domenie aplikacji nadpisuje kolejność języków systemu tylko dla Seam.
    private static let languagesKey = "AppleLanguages"
    private static let seamBundleID = "com.borderlessmouse.mac"

    static var language: AppLanguage {
        get {
            guard let first = (UserDefaults.standard.persistentDomain(forName: seamBundleID)?[languagesKey]
                               as? [String])?.first else { return .system }
            return first.lowercased().hasPrefix("pl") ? .polish : .english
        }
        set {
            switch newValue {
            case .system: UserDefaults.standard.removeObject(forKey: languagesKey)
            case .english: UserDefaults.standard.set(["en"], forKey: languagesKey)
            case .polish: UserDefaults.standard.set(["pl"], forKey: languagesKey)
            }
        }
    }

    /// Wybór różni się od języka, w którym działa ten proces: zmiana zadziała po restarcie.
    static var needsRestart: Bool {
        switch language {
        case .system:
            return isPolish != (Locale.preferredLanguages.first?.lowercased().hasPrefix("pl") == true)
        case .english: return isPolish
        case .polish: return !isPolish
        }
    }
}
