import SwiftUI

struct ClipboardPage: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        SettingsPageLayout(title: "Schowek", subtitle: "Kopiuj na jednym komputerze, wklejaj na drugim.") {
            FeatureHero(icon: "icon-clipboard", title: "Synchronizuj schowek",
                        status: state.settings.clipboardSyncEnabled ? state.clipboardStatus : L10n.text("Wyłączone", "Off"),
                        ok: state.settings.clipboardSyncEnabled ? (state.peer != nil ? true : nil) : nil,
                        isOn: $state.settings.clipboardSyncEnabled)
            SettingsGroup("Co jest przesyłane") {
                HStack(spacing: 8) {
                    ForEach([L10n.text("Tekst", "Text"),
                             L10n.text("Zdjęcia i zrzuty ekranu", "Photos and screenshots"),
                             L10n.text("Obrazy do 32 MiB", "Images up to 32 MiB")], id: \.self) { item in
                        Text(item).font(.callout)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .overlay(Capsule().strokeBorder(.primary.opacity(0.15)))
                    }
                }
                Text("W obie strony, tylko w sieci lokalnej, szyfrowane jak całe połączenie.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}
