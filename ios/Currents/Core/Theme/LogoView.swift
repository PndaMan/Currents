import SwiftUI

/// The Currents wordmark + symbol.
///
/// The symbol is `CurrentsMark` (ios/Shared/CurrentsMark.swift): the same fish
/// that is the app icon, drawn as a vector with no baked-in background, so it
/// tints to the active theme and sits cleanly on any light/dark surface.
struct LogoView: View {
    enum Style {
        case symbol            // just the current mark
        case horizontal        // mark + wordmark on one line
        case stacked           // mark above wordmark
    }

    var style: Style = .horizontal
    var size: CGFloat = 32
    var showsTagline: Bool = false

    /// Override which theme tints the logo. `nil` reads from UserDefaults.
    var themeOverride: String? = nil

    // MARK: - Resolved theme / tint

    private var resolvedTheme: ThemeOption {
        if let override = themeOverride, let opt = ThemeOption(rawValue: override) {
            return opt
        }
        return ThemeOption.current
    }

    private var tint: Color { resolvedTheme.primary }

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
                    Text("Fish smarter. Log everything.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Symbol (the fish mark, tinted to the theme)

    private var symbolView: some View {
        CurrentsMark(tint: tint)
            .frame(width: size, height: size)
    }

    // MARK: - Wordmark (single colour)

    private var wordmark: some View {
        Text("Currents")
            .font(.system(size: size * 0.62, weight: .semibold, design: .rounded))
            .tracking(-0.5)
            .foregroundStyle(tint)
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
