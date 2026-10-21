import SwiftUI

struct SettingsPageLayout<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.sectionSpacing) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(LocalizedStringKey(title))
                        .font(.largeTitle.bold())
                        .tracking(-0.7)
                        .accessibilityAddTraits(.isHeader)
                    Text(LocalizedStringKey(subtitle))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 4)
                content
            }
            .frame(maxWidth: DesignTokens.contentWidth, alignment: .leading)
            .padding(DesignTokens.pageInset)
            .frame(maxWidth: .infinity)
        }
    }
}
