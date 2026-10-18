import SwiftUI

struct QuickToggleRow: View {
    let title: String
    let symbol: String
    @Binding var isOn: Bool

    private var assetName: String {
        switch symbol {
        case "computermouse": return "control"
        case "speaker.wave.2": return "audio"
        case "clipboard": return "clipboard"
        default: return "windows"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            SeamArtwork(name: "icon-\(assetName)")
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
            Text(LocalizedStringKey(title))
            Spacer(minLength: 8)
            Toggle(LocalizedStringKey(title), isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}
