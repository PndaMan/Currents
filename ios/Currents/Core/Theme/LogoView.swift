import SwiftUI

/// The Currents wordmark + symbol. The symbol PNG is a blue gradient
/// that reads well on both light and dark backgrounds, so a single
/// asset drives every appearance.
struct LogoView: View {
    enum Style {
        case symbol            // just the symbol glyph
        case horizontal        // symbol + wordmark on one line
        case stacked           // symbol above wordmark
    }

    var style: Style = .horizontal
    var size: CGFloat = 32
    var showsTagline: Bool = false

    var body: some View {
        switch style {
        case .symbol:
            symbol
        case .horizontal:
            HStack(spacing: size * 0.28) {
                symbol
                wordmark
            }
        case .stacked:
            VStack(spacing: size * 0.18) {
                symbol
                wordmark
                if showsTagline {
                    Text("Fish smarter. Log everything. Offline-first.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var symbol: some View {
        Image("Logo")
            .resizable()
            .renderingMode(.original)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }

    private var wordmark: some View {
        Text("Currents")
            .font(.system(size: size * 0.62, weight: .semibold, design: .rounded))
            .tracking(-0.5)
            .foregroundStyle(
                LinearGradient(
                    colors: [Color(red: 0.10, green: 0.55, blue: 0.95),
                             Color(red: 0.15, green: 0.82, blue: 0.98)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
    }
}

#Preview {
    VStack(spacing: 24) {
        LogoView(style: .symbol, size: 64)
        LogoView(style: .horizontal, size: 32)
        LogoView(style: .stacked, size: 80, showsTagline: true)
    }
    .padding()
}
