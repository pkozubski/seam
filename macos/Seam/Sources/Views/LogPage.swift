import SwiftUI

struct LogPage: View {
    @Environment(AppState.self) private var state

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        SettingsPageLayout(title: "Diagnostics", subtitle: "Connections and app events. Useful when reporting a bug.") {
            if state.log.isEmpty {
                ContentUnavailableView {
                    Label("No events", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("Connection and app activity will appear here.")
                }
                .frame(maxWidth: .infinity, minHeight: 300)
            } else {
                HStack {
                    Text(L10n.text("Recent activity", pl: "Ostatnie zdarzenia"))
                        .font(.headline).foregroundStyle(.secondary)
                    Spacer()
                    Button("Copy", action: copyLog)
                    Button("Clear activity", action: state.clearLog)
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
