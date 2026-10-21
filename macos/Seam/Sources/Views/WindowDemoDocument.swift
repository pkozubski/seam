import SwiftUI

/// A native miniature, so text and title-bar controls stay sharp at every size.
struct WindowDemoDocument: View {
    var compact = false

    var body: some View {
        GeometryReader { geometry in
            document
                .frame(width: 200, height: 130)
                .scaleEffect(min(geometry.size.width / 200, geometry.size.height / 130))
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .accessibilityHidden(true)
    }

    private var document: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                ForEach([Color(red: 0.95, green: 0.36, blue: 0.33), .yellow, .green], id: \.self) { color in
                    Circle().fill(color).frame(width: 7, height: 7)
                }
                Spacer(minLength: 2)
                if !compact {
                    Text(L10n.text("Plan projektu", "Project plan"))
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                }
                Spacer(minLength: 2)
            }
            .padding(10)
            .background(Color(red: 0.16, green: 0.20, blue: 0.21))
            VStack(alignment: .leading, spacing: 12) {
                ForEach(0..<3) { index in
                    HStack(spacing: 9) {
                        Image(systemName: index == 0 ? "checkmark.square.fill" : "square")
                            .foregroundStyle(index == 0 ? Color(red: 0.16, green: 0.52, blue: 0.49) : Color.gray)
                            .font(.system(size: 11))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.black.opacity(index == 0 ? 0.26 : 0.13))
                            .frame(height: 5)
                            .padding(.trailing, index == 1 ? 20 : 0)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(red: 0.95, green: 0.96, blue: 0.94))
        }
        .clipShape(RoundedRectangle(cornerRadius: compact ? 5 : 9))
        .overlay { RoundedRectangle(cornerRadius: compact ? 5 : 9).strokeBorder(.white.opacity(0.35), lineWidth: 0.5) }
        .shadow(color: .black.opacity(0.28), radius: compact ? 4 : 12, y: 5)
        .accessibilityHidden(true)
    }
}
