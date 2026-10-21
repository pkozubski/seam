import Foundation

enum L10n {
    /// Raz na uruchomienie: odczyt preferencji przy każdym napisie kosztował zauważalnie dużo
    /// (widoki wołają `text` przy każdym odświeżeniu), a język i tak zmienia się dopiero po restarcie.
    static let isPolish: Bool = Locale.preferredLanguages.first?.lowercased().hasPrefix("pl") == true

    static func text(_ polish: String, _ english: String) -> String {
        isPolish ? polish : english
    }

    static func localized(_ source: String) -> String {
        NSLocalizedString(source, comment: "")
    }
}
