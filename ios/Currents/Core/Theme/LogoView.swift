import SwiftUI

/// The Currents wordmark + symbol. Each theme has its own logo asset.
struct LogoView: View {
    enum Style {
        case symbol            // just the symbol glyph
        case horizontal        // symbol + wordmark on one line
        case stacked           // symbol above wordmark
    }

    var style: Style = .horizontal
    var size: CGFloat = 32
    var showsTagline: Bool = false

    /// Override which theme's logo to display. `nil` reads from UserDefaults.
    var themeOverride: String? = nil

    // MARK: - Resolved theme

    private var resolvedTheme: ThemeOption {
        if let override = themeOverride, let opt = ThemeOption(rawValue: override) {
            return opt
        }
        return ThemeOption.current
    }

    /// Map each theme to its logo image asset name.
    private var logoAssetName: String {
        switch resolvedTheme {
        case .ocean:                    return "Logo"
        case .forest, .teal:            return "LogoGreen"
        case .amethyst, .rose:          return "LogoPurple"
        case .gold, .sunset, .ember:    return "LogoGold"
        }
    }

    // MARK: - Body

    var body: some View {
        switch style {
        case .symbol:
            symbolView
        case .horizontal:
            HStack(spacing: size * 0.28) {
                symbolView
                wordmark
            }
        case .stacked:
            VStack(spacing: size * 0.18) {
                symbolView
                wordmark
                if showsTagline {
                    Text("Fish smarter. Log everything. Offline-first.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Symbol

    private var symbolView: some View {
        Image(logoAssetName)
            .resizable()
            .renderingMode(.original)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }

    // MARK: - Wordmark

    private var wordmark: some View {
        let grad = resolvedTheme.gradient
        return Text("Currents")
            .font(.system(size: size * 0.62, weight: .semibold, design: .rounded))
            .tracking(-0.5)
            .foregroundStyle(
                LinearGradient(
                    colors: [grad.0, grad.1],
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
        LogoView(style: .horizontal, size: 44, themeOverride: "forest")
        LogoView(style: .horizontal, size: 44, themeOverride: "amethyst")
        LogoView(style: .horizontal, size: 44, themeOverride: "gold")
    }
    .padding()
}
