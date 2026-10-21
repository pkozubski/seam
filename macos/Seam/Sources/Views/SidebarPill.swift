import SwiftUI

/// Szklana pigułka zaznaczenia w pasku bocznym: jaśniejsza góra i krawędź, która łapie światło
/// z lewego górnego rogu, jak w CleanMyMac. Wspólna dla paska głównego, ustawień i wąskiej szyny.
struct SidebarPill: View {
    var cornerRadius: CGFloat = 14

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(LinearGradient(colors: [.white.opacity(0.14), .white.opacity(0.07)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.30), .white.opacity(0.10), .white.opacity(0.05)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing),
                                   lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
            .accessibilityHidden(true)
    }
}

/// Tło wiersza paska bocznego: pigułka dla zaznaczenia (przesuwa się między wierszami
/// dzięki `namespace`) i delikatne podświetlenie pod kursorem.
struct SidebarRowBackground: View {
    let selected: Bool
    let hovering: Bool
    var namespace: Namespace.ID?
    var cornerRadius: CGFloat = 14

    var body: some View {
        if selected {
            if let namespace {
                SidebarPill(cornerRadius: cornerRadius).matchedGeometryEffect(id: "sidebar-selection", in: namespace)
            } else {
                SidebarPill(cornerRadius: cornerRadius)
            }
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.05 : 0))
        }
    }
}

/// Pionowa krawędź paska bocznego, która zanika u góry i u dołu, zamiast odcinać kolumnę od treści.
struct SidebarSeparator: View {
    var body: some View {
        LinearGradient(stops: [.init(color: .white.opacity(0), location: 0.06),
                               .init(color: .white.opacity(0.09), location: 0.32),
                               .init(color: .white.opacity(0.09), location: 0.68),
                               .init(color: .white.opacity(0), location: 0.94)],
                       startPoint: .top, endPoint: .bottom)
            .frame(width: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
