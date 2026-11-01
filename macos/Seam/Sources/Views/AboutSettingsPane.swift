import AppKit
import SwiftUI

/// Adresy w jednym miejscu. Lista zmian zostaje na GitHubie, dopóki strona nie ma własnej.
enum AppLinks {
    static let website = URL(string: "https://seamdesk.app/")!
    static let changelog = URL(string: "https://github.com/pkozubski/seam/blob/main/CHANGELOG.md")!
    static let privacy = URL(string: "https://seamdesk.app/legal/privacy/")!
    static let reportProblem = URL(string: "mailto:support@seamdesk.app")!
}

/// Ustawienia → O programie: wersja, aktualizacja, lista zmian, wprowadzenie i dokumenty.
struct AboutSettingsPane: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsChrome.sectionSpacing) {
            SettingsCard {
                VStack(spacing: 8) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable().interpolation(.high).scaledToFit()
                        .frame(width: 72, height: 72)
                        .accessibilityHidden(true)
                    Text(verbatim: "seam").font(.title2.weight(.semibold))
                    Text(verbatim: L10n.text("Version \(Updater.versionDescription)", pl: "Wersja \(Updater.versionDescription)"))
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(verbatim: L10n.text("One keyboard, mouse, clipboard and sound for your Mac and PC.",
                                             pl: "Jedna klawiatura, mysz, schowek i dźwięk dla Maca i PC."))
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }

            SettingsSection(title: L10n.text("Software update", pl: "Aktualizacje")) {
                SettingsCardRow(title: L10n.text("Updates", pl: "Aktualizacje"),
                                detail: L10n.text("Check for new versions and choose automatic checks.",
                                                  pl: "Sprawdzaj nowe wersje i ustaw automatyczne sprawdzanie.")) {
                    Button(L10n.text("Open", pl: "Otwórz")) { SettingsNavigation.shared.select(.updates) }
                        .modifier(NativeActionStyle()).controlSize(.small)
                }
                SettingsRowDivider()
                SettingsCardRow(title: L10n.text("Changelog", pl: "Lista zmian")) {
                    Link(L10n.text("Open", pl: "Otwórz"), destination: AppLinks.changelog)
                        .modifier(NativeActionStyle()).controlSize(.small)
                }
                SettingsRowDivider()
                SettingsCardRow(title: L10n.text("Introduction", pl: "Wprowadzenie"),
                                detail: L10n.text("Show the welcome steps again.", pl: "Pokaż ponownie kroki powitalne.")) {
                    Button(L10n.text("Replay", pl: "Odtwórz")) {
                        state.settings.hasCompletedOnboarding = false
                        MainWindowRouter.shared.requested = .connection
                    }
                    .modifier(NativeActionStyle()).controlSize(.small)
                }
            }

            SettingsSection(title: L10n.text("Help", pl: "Pomoc")) {
                LinkRow(title: L10n.text("Website", pl: "Strona internetowa"), symbol: "globe", url: AppLinks.website)
                SettingsRowDivider()
                LinkRow(title: L10n.text("Report a problem", pl: "Zgłoś problem"), symbol: "exclamationmark.bubble", url: AppLinks.reportProblem)
            }

            SettingsSection(title: L10n.text("Privacy", pl: "Prywatność")) {
                SettingsCardRow(title: L10n.text("No accounts, ads or tracking", pl: "Bez kont, reklam i śledzenia"),
                                detail: L10n.text("Everything stays on your local network. Seam only checks for updates and, with Pro, your license.",
                                                  pl: "Wszystko zostaje w sieci lokalnej. Seam sprawdza tylko aktualizacje i, z Pro, licencję.")) {
                    EmptyView()
                }
                SettingsRowDivider()
                LinkRow(title: L10n.text("Privacy policy", pl: "Polityka prywatności"), symbol: "hand.raised", url: AppLinks.privacy)
                SettingsRowDivider()
                SettingsCardRow(title: L10n.text("Third-party notices", pl: "Licencje komponentów")) {
                    Button(L10n.text("Show", pl: "Pokaż")) {
                        if let url = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "txt") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .modifier(NativeActionStyle()).controlSize(.small)
                }
            }
        }
    }
}

/// Wiersz z odnośnikiem na zewnątrz (strzałka ↗ jak w Droppy).
private struct LinkRow: View {
    let title: String
    let symbol: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: symbol).frame(width: 20).foregroundStyle(.secondary)
                Text(verbatim: title).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
