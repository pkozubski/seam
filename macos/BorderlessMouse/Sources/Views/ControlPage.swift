import SwiftUI

struct ControlPage: View {
    @EnvironmentObject private var state: AppState
    @State private var category = ControlCategory.input

    init(initialCategory: ControlCategory = .input) {
        _category = State(initialValue: initialCategory)
    }

    var body: some View {
        SettingsPageLayout(title: "Sterowanie", subtitle: "Dostosuj sposób, w jaki Twoje komputery współpracują.") {
            Picker("Sterowanie", selection: $category) {
                ForEach(ControlCategory.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if category == .input {
                SettingsGroup("Klawiatura i mysz") {
                    SettingRow(title: "Przyjmuj klawiaturę i mysz z Windowsa",
                               subtitle: "Windows steruje Makiem po przekroczeniu krawędzi ekranu.") {
                        Toggle("", isOn: $state.settings.inputEnabled).labelsHidden().toggleStyle(.switch)
                    }
                    SettingRow(title: "Zamień Ctrl ↔ Cmd",
                               subtitle: "Ctrl+C na klawiaturze PC działa jak ⌘C na Macu.") {
                        Toggle("", isOn: $state.settings.swapCtrlCmd).labelsHidden().toggleStyle(.switch)
                    }
                    SettingRow(title: "Kierunek przewijania",
                               subtitle: "Automatycznie uwzględnia ustawienie „naturalne przewijanie”.") {
                        Picker("", selection: $state.settings.scrollDirection) {
                            ForEach(ScrollDirectionMode.allCases) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 170)
                    }
                    SettingRow(title: "Szybkość przewijania",
                               subtitle: String(format: "%.1f×", state.settings.scrollSpeed)) {
                        Slider(value: $state.settings.scrollSpeed, in: 0.25...4, step: 0.25).frame(width: 170)
                    }
                }
            }
            if category == .audio {
                SettingsGroup("Dźwięk do Windowsa") {
                    SettingRow(title: "Udostępniaj dźwięk systemowy",
                               subtitle: "Słuchaj dźwięku z Maca na komputerze z Windows.") {
                        Toggle("", isOn: $state.settings.audioEnabled).labelsHidden().toggleStyle(.switch)
                    }
                    SettingRow(title: "Wycisz głośniki Maca podczas streamowania",
                               subtitle: "Dźwięk słychać tylko na Windowsie.") {
                        Toggle("", isOn: $state.settings.muteLocalAudio).labelsHidden().toggleStyle(.switch)
                    }
                    SettingRow(title: "Bufor przechwytywania",
                               subtitle: "Mniejszy = niższe opóźnienie, większy = odporniejszy.") {
                        Picker("", selection: $state.settings.audioBufferFrames) {
                            Text("128 ramek (~2,7 ms)").tag(128)
                            Text("256 ramek (~5,3 ms)").tag(256)
                            Text("512 ramek (~10,7 ms)").tag(512)
                        }
                        .labelsHidden()
                        .frame(width: 190)
                    }
                }
                SettingsGroup("Stan strumienia") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            StatusDot(ok: state.audioStreaming ? true : (state.audioError == nil ? nil : false))
                            if state.audioStreaming {
                                Text(L10n.text("Streamowanie: \(state.audioDescription)", "Streaming: \(state.audioDescription)"))
                                    .font(.callout)
                                Spacer()
                                Button("Zatrzymaj") { state.stopAudio() }
                            } else if let error = state.audioError {
                                Text(error).font(.callout).foregroundStyle(.red)
                            } else {
                                Text(L10n.text("Nieaktywne – Windows włącza stream po stronie odbiornika.", "Inactive — start the receiver on Windows."))
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                        }
                        LevelMeter(level: state.audioLevel)
                        if state.audioStreaming {
                            Text(L10n.text("Pakiety: \(state.audioPackets) · błędy wysyłki: \(state.audioSendErrors)",
                                           "Packets: \(state.audioPackets) · send errors: \(state.audioSendErrors)"))
                                .monospacedDigit()
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            if category == .display {
                SettingsGroup("Ekran wirtualny dla Windowsa") {
                    SettingRow(title: "Udostępniaj ekran wirtualny",
                               subtitle: "Monitor Windowsa staje się drugim ekranem Maca. Przeciągnij okno w stronę Windowsa, a pojawi się na jego ekranie.") {
                        Toggle("", isOn: $state.settings.displayEnabled).labelsHidden().toggleStyle(.switch)
                    }
                    SettingRow(title: "Stan", subtitle: state.displayStatusText) {
                        HStack(spacing: 8) {
                            StatusDot(ok: state.displayStreaming ? true : (state.displayError == nil ? nil : false))
                            if state.displayStreaming {
                                Button("Zatrzymaj") { state.stopDisplay() }
                            }
                        }
                    }
                }
            }
            if category == .clipboard {
                SettingsGroup("Schowek") {
                    SettingRow(title: "Synchronizuj schowek (tekst i zdjęcia)",
                               subtitle: "Kopiuj i wklejaj tekst, zdjęcia oraz zrzuty ekranu w obie strony. Obrazy do 32 MiB.") {
                        Toggle("", isOn: $state.settings.clipboardSyncEnabled).labelsHidden().toggleStyle(.switch)
                    }
                    SettingRow(title: "Ostatnia synchronizacja", subtitle: state.clipboardStatus) {
                        StatusDot(ok: state.settings.clipboardSyncEnabled ? (state.peer != nil ? true : nil) : false)
                    }
                }
            }
        }
    }
}
