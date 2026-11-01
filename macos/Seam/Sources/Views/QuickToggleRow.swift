import SwiftUI

struct QuickToggleRow: View {
    let title: String
    let symbol: String
    @Binding var isOn: Bool
    /// Kolorowy kafelek z `assets/seam` zamiast grafitowej płytki (strona Połączenie).
    var tile: String? = nil

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
            if let tile {
                ConnectionTile(name: tile)
            } else {
                SeamIconTile(name: "icon-\(assetName)", size: 32)
            }
            Text(LocalizedStringKey(title))
            Spacer(minLength: 8)
            Toggle(LocalizedStringKey(title), isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}
