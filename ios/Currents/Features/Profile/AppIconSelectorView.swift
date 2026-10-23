import SwiftUI

// MARK: - App icon preview

/// The home screen icon drawn in SwiftUI: the fish on the dark ground with a
/// glow in the theme's hue, as scripts/generate_app_icons.py draws the PNGs.
struct AppIconPreview: View {
    let tint: Color
    var size: CGFloat = 64

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.09, green: 0.10, blue: 0.12), // ui-lint: allow (copies the icon art, see generate_app_icons.py)
                                          Color(red: 0.05, green: 0.06, blue: 0.07)], // ui-lint: allow (copies the icon art, see generate_app_icons.py)
                                 startPoint: .top, endPoint: .bottom))
            .overlay(
                RadialGradient(colors: [tint.opacity(0.22), tint.opacity(0)], // ui-lint: allow (the glow in the icon art)
                               center: .center, startRadius: 0, endRadius: size * 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
            .overlay(
                CurrentsMark()
                    .filled(tint)
                    .frame(width: size * 0.56, height: size * 0.56)
            )
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - App Icon Option

struct AppIconOption: Identifiable {
    let id: String              // matches ThemeOption raw value
    let name: String
    let logoAsset: String       // image asset name for preview
    let alternateIconName: String? // nil = primary icon, string = CFBundleAlternateIcons key

    /// One icon per theme. Previews are drawn live (AppIconPreview) tinted by
    /// the theme, so `logoAsset` is unused for previews now.
    static let all: [AppIconOption] = [
        AppIconOption(id: "ocean", name: "Ocean",
                      logoAsset: "Logo",
                      alternateIconName: nil), // Primary (default)
        AppIconOption(id: "forest", name: "Forest",
                      logoAsset: "LogoGreen",
                      alternateIconName: "AppIcon-Green"),
        AppIconOption(id: "teal", name: "Teal",
                      logoAsset: "Logo",
                      alternateIconName: "AppIcon-Teal"),
        AppIconOption(id: "amethyst", name: "Amethyst",
                      logoAsset: "LogoPurple",
                      alternateIconName: "AppIcon-Purple"),
        AppIconOption(id: "rose", name: "Rose",
                      logoAsset: "Logo",
                      alternateIconName: "AppIcon-Rose"),
        AppIconOption(id: "ember", name: "Ember",
                      logoAsset: "Logo",
                      alternateIconName: "AppIcon-Ember"),
        AppIconOption(id: "sunset", name: "Sunset",
                      logoAsset: "Logo",
                      alternateIconName: "AppIcon-Sunset"),
        AppIconOption(id: "gold", name: "Gold",
                      logoAsset: "LogoGold",
                      alternateIconName: "AppIcon-Gold"),
    ]

    static func option(for id: String) -> AppIconOption {
        all.first { $0.id == id } ?? all[0]
    }
}

// The picker UI now lives in `AppearanceSettingsView`, where the app icon and
// colour theme are chosen together and kept in sync.
