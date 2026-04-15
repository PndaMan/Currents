import SwiftUI

/// The Currents wordmark + symbol. For the default "ocean" theme the
/// bundled Logo asset is used; for other themes a programmatic SF Symbol
/// placeholder is rendered in the theme's gradient colours.
struct LogoView: View {
    enum Style {
        case symbol            // just the symbol glyph
        case horizontal        // symbol + wordmark on one line
        case stacked           // symbol above wordmark
    }

    var style: Style = .horizontal
    var size: CGFloat = 32
    var showsTagline: Bool = false

    /// Override which icon theme to display. `nil` reads from UserDefaults.
    var iconOverride: String? = nil

    // MARK: - Resolved icon

    private var resolvedIcon: String {
        iconOverride ?? UserDefaults.standard.string(forKey: "selectedAppIcon") ?? "ocean"
    }

    private var iconOption: ThemeIconOption {
        ThemeIconOption.option(for: resolvedIcon)
    }

    /// Use the bundled PNG only for the default ocean theme.
    private var useCustomAsset: Bool {
        resolvedIcon == "ocean"
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

    @ViewBuilder
    private var symbolView: some View {
        if useCustomAsset {
            Image("Logo")
                .resizable()
                .renderingMode(.original)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            themedPlaceholderSymbol
        }
    }

    /// Programmatic placeholder: SF Symbol centred in a gradient circle.
    private var themedPlaceholderSymbol: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: iconOption.gradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: iconOption.sfSymbol)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }

    // MARK: - Wordmark

    private var wordmark: some View {
        let grad = ThemeOption.current.gradient
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
        // Preview non-ocean themes
        LogoView(style: .horizontal, size: 44, iconOverride: "ember")
        LogoView(style: .horizontal, size: 44, iconOverride: "forest")
    }
    .padding()
}
