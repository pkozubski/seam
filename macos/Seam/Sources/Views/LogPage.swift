import SwiftUI

struct LogPage: View {
    @EnvironmentObject private var state: AppState

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        SettingsPageLayout(title: "Dziennik", subtitle: "Połączenia i zdarzenia aplikacji. Przydatne przy zgłaszaniu błędu.") {
            if state.log.isEmpty {
                ContentUnavailableView {
                    Label("Brak zdarzeń", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("Tutaj pojawią się informacje o połączeniu i działaniu aplikacji.")
                }
                .frame(maxWidth: .infinity, minHeight: 300)
            } else {
                HStack {
                    Text(L10n.text("Ostatnie zdarzenia", "Recent activity"))
                        .font(.headline).foregroundStyle(.secondary)
                    Spacer()
                    Button("Kopiuj", action: copyLog)
                    Button("Wyczyść dziennik", action: state.clearLog)
                }
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(state.log.suffix(200)) { entry in
                        HStack(alignment: .top, spacing: 16) {
                            Text(Self.formatter.string(from: entry.time))
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(entry.text)
                                .font(.callout)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(14)
                        .textSelection(.enabled)
                        Divider().padding(.horizontal, 14)
                    }
                }
                .modifier(SurfaceStyle())
            }
        }
    }

    private func copyLog() {
        let text = state.log.map { "\(Self.formatter.string(from: $0.time))  \($0.text)" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
