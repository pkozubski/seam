import SwiftUI

struct WindowGuideNote: View {
    let title: String
    let detail: String
    let symbol: String
    let edge: ScreenEdge
    let progress: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: symbol).font(.headline).accessibilityAddTraits(.isHeader)
            Text(detail).font(.callout).foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true).frame(minHeight: 42, alignment: .topLeading)
            WindowTransferDiagram(edge: edge, progress: progress, compact: true).frame(height: 110)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .modifier(WindowGuideSurface())
    }
}
