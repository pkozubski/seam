import SwiftUI

struct WindowsGuideHeader: View {
    @EnvironmentObject private var state: AppState
    var compact = false

    private var status: String {
        if !state.settings.displayEnabled { return L10n.text("Wyłączone", "Off") }
        if !VirtualDisplay.isSupported { return state.displayStatusText }
        if state.peer == nil { return L10n.text("Połącz oba urządzenia, aby rozpocząć.", "Connect both devices to get started.") }
        if !state.screenCaptureGranted || !state.accessibilityGranted {
            return L10n.text("Nadaj wymagane uprawnienia poniżej.", "Grant the required permissions below.")
        }
        if let error = state.displayError { return error }
        if state.displayStreaming { return L10n.text("Drugi ekran jest aktywny", "Second display is active") }
        return L10n.text("Włącz ekran Maca w zakładce Okna na Windowsie.", "Enable the Mac display under Windows on your PC.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(state.peer.map { "\(state.settings.deviceName)  ·  \($0.name)" }
                  ?? L10n.text("Czeka na drugie urządzenie", "Waiting for the other device"),
                  systemImage: state.peer == nil ? "link.badge.plus" : "link")
                .font(.callout).foregroundStyle(.white.opacity(0.65))
            let layout = compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 20))
                                 : AnyLayout(HStackLayout(alignment: .top, spacing: 28))
            layout {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.text("Drugi komputer.\nDodatkowy ekran.", "Another computer.\nAn extra display."))
                        .font(.largeTitle.weight(.semibold)).tracking(-0.7)
                        .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                    Text(L10n.text("Przeciągnij dowolne okno za krawędź ekranu. Pojawi się na drugim urządzeniu — tak jak na dodatkowym monitorze.",
                                   "Drag any window past the edge of your screen. It appears on the other device — just like on an extra monitor."))
                        .font(.body).foregroundStyle(.white.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(L10n.text("Przenoszenie okien", "Move windows"), isOn: $state.settings.displayEnabled)
                        .toggleStyle(.switch).font(.headline)
                    Text(status).font(.callout).foregroundStyle(.white.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
                }
                .padding(18).frame(width: compact ? nil : 250, alignment: .leading)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.12), lineWidth: 1) }
            }
        }
    }
}
