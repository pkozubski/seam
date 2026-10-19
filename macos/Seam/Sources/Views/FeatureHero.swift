import SwiftUI

/// Karta na górze strony funkcji: ikona, główny włącznik i bieżący stan.
/// `accessory` trafia pod wiersz (np. miernik poziomu), `actions` obok włącznika.
struct FeatureHero<Actions: View, Accessory: View>: View {
    let icon: String
    let title: String
    let status: String
    let ok: Bool?
    @Binding var isOn: Bool
    @ViewBuilder var actions: Actions
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                SeamIconTile(name: icon, size: 44, active: isOn)
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey(title)).font(.title3.weight(.semibold))
                    HStack(spacing: 7) {
                        StatusDot(ok: ok)
                        Text(status).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                actions
                Toggle(LocalizedStringKey(title), isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            accessory
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SurfaceStyle())
    }
}

extension FeatureHero where Actions == EmptyView, Accessory == EmptyView {
    init(icon: String, title: String, status: String, ok: Bool?, isOn: Binding<Bool>) {
        self.init(icon: icon, title: title, status: status, ok: ok, isOn: isOn,
                  actions: { EmptyView() }, accessory: { EmptyView() })
    }
}

extension FeatureHero where Accessory == EmptyView {
    init(icon: String, title: String, status: String, ok: Bool?, isOn: Binding<Bool>,
         @ViewBuilder actions: () -> Actions) {
        self.init(icon: icon, title: title, status: status, ok: ok, isOn: isOn,
                  actions: actions, accessory: { EmptyView() })
    }
}

/// Baner brakującego uprawnienia, pokazywany na stronie funkcji, która go potrzebuje.
struct PermissionBanner: View {
    let title: String
    let message: String
    let grant: () -> Void
    var openSettings: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title)).font(.body.weight(.medium))
                Text(LocalizedStringKey(message)).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let openSettings {
                Button("Ustawienia systemowe", action: openSettings)
            }
            Button("Nadaj", action: grant).buttonStyle(.borderedProminent)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SurfaceStyle())
    }
}
