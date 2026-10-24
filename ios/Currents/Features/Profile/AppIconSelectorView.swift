import SwiftUI

// MARK: - App icon preview

/// The home screen icon drawn in SwiftUI, as scripts/generate_app_icons.py
/// draws the PNGs: the theme-coloured fish on white in light mode, and on the
/// dark backdrop iOS draws behind the transparent dark icon in dark mode.
struct AppIconPreview: View {
    let tint: Color
    var size: CGFloat = 64
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(scheme == .dark ? Color(white: 0.12) : .white) // ui-lint: allow (the icon's own ground, not a theme colour)
            .overlay(
                CurrentsMark()
                    .filled(tint)
                    .frame(width: size * 0.6, height: size * 0.6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                    .strokeBorder(Color.dsSeparator, lineWidth: scheme == .dark ? 0 : 0.5)
            )
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - App Icon Option

struct AppIconOption: Identifiable {
    let id: String              // matches ThemeOption raw value
    let name: String
    let alternateIconName: String? // nil = primary icon, string = CFBundleAlternateIcons key

    /// One icon per theme, in `ThemeOption.allCases` order so the icon grid
    /// and the colour theme grid read the same way. Previews are drawn live
    /// (AppIconPreview) tinted by the theme. The primary icon stays first.
    static let all: [AppIconOption] = [
        AppIconOption(id: "ocean", name: "Ocean",
                      alternateIconName: nil), // Primary (default)
        AppIconOption(id: "forest", name: "Forest",
                      alternateIconName: "AppIcon-Green"),
        AppIconOption(id: "ember", name: "Ember",
                      alternateIconName: "AppIcon-Ember"),
        AppIconOption(id: "sunset", name: "Sunset",
                      alternateIconName: "AppIcon-Sunset"),
        AppIconOption(id: "amethyst", name: "Amethyst",
                      alternateIconName: "AppIcon-Purple"),
        AppIconOption(id: "teal", name: "Teal",
                      alternateIconName: "AppIcon-Teal"),
        AppIconOption(id: "rose", name: "Rose",
                      alternateIconName: "AppIcon-Rose"),
        AppIconOption(id: "gold", name: "Gold",
                      alternateIconName: "AppIcon-Gold"),
    ]

    static func option(for id: String) -> AppIconOption {
        all.first { $0.id == id } ?? all[0]
    }
}

// The picker UI now lives in `AppearanceSettingsView`, where the app icon and
// colour theme are chosen together and kept in sync.
