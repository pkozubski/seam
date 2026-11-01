import SwiftUI

/// Dźwięk: słuchawki na fali u góry, miernik poziomu i dwie karty ustawień na fioletowym tle (`AudioBackdrop`).
struct AudioPage: View {
    @Environment(AppState.self) private var state
    @State private var showStats = false

    private var status: String {
        if !state.proUnlocked { return L10n.text("Paused — needs Seam Pro", pl: "Wstrzymane – wymaga Seam Pro") }
        if state.audioStreaming { return L10n.text("Streaming · \(state.audioDescription)", pl: "Streamowanie · \(state.audioDescription)") }
        if let error = state.audioError { return error }
        if !state.settings.audioEnabled { return L10n.text("Off", pl: "Wyłączone") }
        return L10n.text("Ready · Windows starts playback on its side", pl: "Gotowe · Windows włącza odbiór po swojej stronie")
    }

    private var bufferSubtitle: String {
        let ms = (Double(state.settings.audioBufferFrames) / 48.0).formatted(.number.precision(.fractionLength(1)))
        return L10n.text("\(state.settings.audioBufferFrames) frames · about \(ms) ms. Choose Stable if audio crackles.",
                         pl: "\(state.settings.audioBufferFrames) ramek · ok. \(ms) ms. Gdy dźwięk trzeszczy, wybierz Stabilny.")
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 18) {
                    hero(height: geometry.size.height < 760 ? 190 : 240)
                    VStack(spacing: 8) {
                        Text(L10n.text("Mac audio on Windows", pl: "Dźwięk Maca na Windowsie"))
                            .font(.system(size: 36, weight: .semibold)).tracking(-0.8)
                            .accessibilityAddTraits(.isHeader)
                        Text(L10n.text("The Mac's system audio played on the Windows speakers.",
                                       pl: "Dźwięk systemowy Maca grany na głośnikach Windowsa."))
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
            PermissionBanner(title: "System audio recording not allowed",
                             message: "Without it the Mac cannot capture audio for streaming.",
                             grant: state.repairAudioPermission,
                             openSettings: state.openAudioCaptureSettings)
        }
        TintedGlassCard(border: AudioTokens.cardBorder) {
            HStack(spacing: 14) {
                SeamArtwork(name: "tile-audio-violet").frame(width: 46, height: 46)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(L10n.text("Share system audio", pl: "Udostępniaj dźwięk systemowy")).font(.title3.weight(.semibold))
                        if !state.proUnlocked { ProBadge() }
                        if let days = state.license.entitlement.trialDaysLeft { TrialPill(daysLeft: days, border: AudioTokens.cardBorder) }
                    }
                    HStack(spacing: 7) {
                        StatusDot(ok: state.audioStreaming ? true : (state.audioError == nil ? nil : false))
                        Text(status).font(.callout).foregroundStyle(AudioTokens.mutedText)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                // Bez Pro przełącznik pokazuje „wyłączone”, ale zapisana wartość zostaje na po zakupie.
                Toggle(L10n.text("Share system audio", pl: "Udostępniaj dźwięk systemowy"),
                       isOn: state.proUnlocked ? $state.settings.audioEnabled : .constant(false))
                    .labelsHidden().toggleStyle(.switch)
                    .disabled(!state.proUnlocked)
            }
        }
        .frame(maxWidth: 600)
        if !state.proUnlocked {
            ProGateCard(border: AudioTokens.cardBorder, mutedText: AudioTokens.mutedText)
        }
        TintedGlassCard(border: AudioTokens.cardBorder) {
            HStack {
                Text(L10n.text("Audio level", pl: "Poziom dźwięku")).font(.callout.weight(.medium))
                    .foregroundStyle(AudioTokens.mutedText)
                Spacer()
                if state.audioStreaming {
                    Button { state.stopAudio() } label: {
                        Label(L10n.text("Stop", pl: "Zatrzymaj"), systemImage: "stop.fill")
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
                        Text(L10n.text("Mute the Mac's speakers", pl: "Wycisz głośniki Maca")).font(.title3.weight(.semibold))
                        Text(L10n.text("While streaming, audio plays only on Windows.",
                                       pl: "Podczas streamowania dźwięk słychać tylko na Windowsie."))
                            .font(.callout).foregroundStyle(AudioTokens.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Toggle(L10n.text("Mute the Mac's speakers", pl: "Wycisz głośniki Maca"), isOn: $state.settings.muteLocalAudio)
                        .labelsHidden().toggleStyle(.switch)
                }
            }
            TintedGlassCard(border: AudioTokens.cardBorder) {
                Text(L10n.text("Latency", pl: "Opóźnienie")).font(.title3.weight(.semibold))
                Picker(L10n.text("Capture buffer", pl: "Bufor przechwytywania"), selection: $state.settings.audioBufferFrames) {
                    Text(L10n.text("Fastest", pl: "Najszybszy")).tag(128)
                    Text(L10n.text("Balanced", pl: "Zrównoważony")).tag(256)
                    Text(L10n.text("Stable", pl: "Stabilny")).tag(512)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(bufferSubtitle)
                    .font(.callout).foregroundStyle(AudioTokens.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if state.audioStreaming {
            DisclosureGroup(L10n.text("Stream statistics", pl: "Statystyki strumienia"), isExpanded: $showStats) {
                Text(L10n.text("Packets: \(state.audioPackets) · send errors: \(state.audioSendErrors)",
                               pl: "Pakiety: \(state.audioPackets) · błędy wysyłki: \(state.audioSendErrors)"))
                    .monospacedDigit()
                    .font(.callout).foregroundStyle(AudioTokens.mutedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 4)
        }
    }
}
