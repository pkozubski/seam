import SwiftUI

struct AudioPage: View {
    @EnvironmentObject private var state: AppState
    @State private var showStats = false

    private var status: String {
        if state.audioStreaming { return L10n.text("Streamowanie · \(state.audioDescription)", "Streaming · \(state.audioDescription)") }
        if let error = state.audioError { return error }
        if !state.settings.audioEnabled { return L10n.text("Wyłączone", "Off") }
        return L10n.text("Gotowe · Windows włącza odbiór po swojej stronie", "Ready · Windows starts playback on its side")
    }

    private var bufferSubtitle: String {
        let ms = (Double(state.settings.audioBufferFrames) / 48.0).formatted(.number.precision(.fractionLength(1)))
        return L10n.text("\(state.settings.audioBufferFrames) ramek · ok. \(ms) ms. Gdy dźwięk trzeszczy, wybierz Stabilny.",
                         "\(state.settings.audioBufferFrames) frames · about \(ms) ms. Choose Stable if audio crackles.")
    }

    var body: some View {
        SettingsPageLayout(title: "Dźwięk", subtitle: "Dźwięk systemowy Maca grany na głośnikach Windowsa.") {
            if state.audioPermissionGranted == false {
                PermissionBanner(title: "Brak zgody na nagrywanie dźwięku systemowego",
                                 message: "Bez niej Mac nie może przechwycić dźwięku do streamowania.",
                                 grant: state.repairAudioPermission,
                                 openSettings: state.openAudioCaptureSettings)
            }
            FeatureHero(icon: "icon-audio", title: "Udostępniaj dźwięk systemowy",
                        status: status,
                        ok: state.audioStreaming ? true : (state.audioError == nil ? nil : false),
                        isOn: $state.settings.audioEnabled) {
                if state.audioStreaming {
                    Button("Zatrzymaj") { state.stopAudio() }
                }
            } accessory: {
                if state.audioStreaming {
                    LevelMeter(level: state.audioLevel)
                }
            }
            SettingsGroup("Odtwarzanie") {
                SettingRow(title: "Wycisz głośniki Maca podczas streamowania",
                           subtitle: "Dźwięk słychać tylko na Windowsie.") {
                    Toggle("", isOn: $state.settings.muteLocalAudio).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsGroup("Opóźnienie") {
                SettingRow(title: "Bufor przechwytywania", subtitle: bufferSubtitle) {
                    Picker("", selection: $state.settings.audioBufferFrames) {
                        Text("Najszybszy").tag(128)
                        Text("Zrównoważony").tag(256)
                        Text("Stabilny").tag(512)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
            if state.audioStreaming {
                DisclosureGroup("Statystyki strumienia", isExpanded: $showStats) {
                    Text(L10n.text("Pakiety: \(state.audioPackets) · błędy wysyłki: \(state.audioSendErrors)",
                                   "Packets: \(state.audioPackets) · send errors: \(state.audioSendErrors)"))
                        .monospacedDigit()
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 4)
            }
        }
    }
}
