import SwiftUI

/// Dźwięk: słuchawki na fali u góry, miernik poziomu i dwie karty ustawień na fioletowym tle (`AudioBackdrop`).
struct AudioPage: View {
    @Environment(AppState.self) private var state
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
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 18) {
                    hero(height: geometry.size.height < 760 ? 190 : 240)
                    VStack(spacing: 8) {
                        Text(L10n.text("Dźwięk Maca na Windowsie", "Mac audio on Windows"))
                            .font(.system(size: 36, weight: .semibold)).tracking(-0.8)
                            .accessibilityAddTraits(.isHeader)
                        Text(L10n.text("Dźwięk systemowy Maca grany na głośnikach Windowsa.",
                                       "The Mac's system audio played on the Windows speakers."))
                            .font(.system(size: 16)).foregroundStyle(AudioTokens.mutedText)
                    }
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)
                    controls(narrow: geometry.size.width < 720)
                }
                .padding(.horizontal, 28).padding(.top, 16).padding(.bottom, 96)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
        .tint(AudioTokens.accent)
    }

    private func hero(height: CGFloat) -> some View {
        ZStack {
            AudioWaveBackdrop()
                .frame(height: height * 0.62)
            SeamArtwork(name: "hero-audio-headphones")
                .frame(height: height)
                .shadow(color: AudioTokens.accent.opacity(0.45), radius: 30)
        }
        .frame(maxWidth: .infinity)
        .background {
            Ellipse()
                .fill(AudioTokens.glow.opacity(0.45))
                .frame(width: height * 1.6, height: height * 0.9)
                .blur(radius: 60)
                .allowsHitTesting(false)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private func controls(narrow: Bool) -> some View {
        @Bindable var state = state
        if state.audioPermissionGranted == false {
            PermissionBanner(title: "Brak zgody na nagrywanie dźwięku systemowego",
                             message: "Bez niej Mac nie może przechwycić dźwięku do streamowania.",
                             grant: state.repairAudioPermission,
                             openSettings: state.openAudioCaptureSettings)
        }
        TintedGlassCard(border: AudioTokens.cardBorder) {
            HStack(spacing: 14) {
                SeamArtwork(name: "tile-audio-violet").frame(width: 46, height: 46)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("Udostępniaj dźwięk systemowy", "Share system audio")).font(.title3.weight(.semibold))
                    HStack(spacing: 7) {
                        StatusDot(ok: state.audioStreaming ? true : (state.audioError == nil ? nil : false))
                        Text(status).font(.callout).foregroundStyle(AudioTokens.mutedText)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                Toggle(L10n.text("Udostępniaj dźwięk systemowy", "Share system audio"), isOn: $state.settings.audioEnabled)
                    .labelsHidden().toggleStyle(.switch)
            }
        }
        .frame(maxWidth: 600)
        TintedGlassCard(border: AudioTokens.cardBorder) {
            HStack {
                Text(L10n.text("Poziom dźwięku", "Audio level")).font(.callout.weight(.medium))
                    .foregroundStyle(AudioTokens.mutedText)
                Spacer()
                if state.audioStreaming {
                    Button { state.stopAudio() } label: {
                        Label(L10n.text("Zatrzymaj", "Stop"), systemImage: "stop.fill")
                    }
                    .buttonStyle(GlassPillButtonStyle(border: AudioTokens.cardBorder))
                }
            }
            .frame(minHeight: 28)
            AudioBarMeter(level: { state.audioLevel }, active: state.audioStreaming)
        }
        let layout = narrow ? AnyLayout(VStackLayout(spacing: 16)) : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
        layout {
            TintedGlassCard(border: AudioTokens.cardBorder) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text("Wycisz głośniki Maca", "Mute the Mac's speakers")).font(.title3.weight(.semibold))
                        Text(L10n.text("Podczas streamowania dźwięk słychać tylko na Windowsie.",
                                       "While streaming, audio plays only on Windows."))
                            .font(.callout).foregroundStyle(AudioTokens.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Toggle(L10n.text("Wycisz głośniki Maca", "Mute the Mac's speakers"), isOn: $state.settings.muteLocalAudio)
                        .labelsHidden().toggleStyle(.switch)
                }
            }
            TintedGlassCard(border: AudioTokens.cardBorder) {
                Text(L10n.text("Opóźnienie", "Latency")).font(.title3.weight(.semibold))
                Picker(L10n.text("Bufor przechwytywania", "Capture buffer"), selection: $state.settings.audioBufferFrames) {
                    Text(L10n.text("Najszybszy", "Fastest")).tag(128)
                    Text(L10n.text("Zrównoważony", "Balanced")).tag(256)
                    Text(L10n.text("Stabilny", "Stable")).tag(512)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(bufferSubtitle)
                    .font(.callout).foregroundStyle(AudioTokens.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if state.audioStreaming {
            DisclosureGroup(L10n.text("Statystyki strumienia", "Stream statistics"), isExpanded: $showStats) {
                Text(L10n.text("Pakiety: \(state.audioPackets) · błędy wysyłki: \(state.audioSendErrors)",
                               "Packets: \(state.audioPackets) · send errors: \(state.audioSendErrors)"))
                    .monospacedDigit()
                    .font(.callout).foregroundStyle(AudioTokens.mutedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 4)
        }
    }
}
