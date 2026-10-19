import SwiftUI

struct WindowGuideStep: View {
    let number: Int
    let title: String
    let detail: String
    let progress: CGFloat
    let edge: ScreenEdge

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(format: "%02d", number))
                .font(.callout.monospacedDigit().weight(.medium))
                .foregroundStyle(.white.opacity(0.6))
            Text(title).font(.headline).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(detail).font(.callout).foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
            WindowTransferDiagram(edge: edge, progress: progress, compact: true)
                .frame(height: 90)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}
