import SwiftUI

// MARK: - App Icon Option

struct AppIconOption: Identifiable {
    let id: String              // matches ThemeOption raw value
    let name: String
    let logoAsset: String       // image asset name for preview
    let alternateIconName: String? // nil = primary icon, string = CFBundleAlternateIcons key

    /// One icon per theme. The mark is drawn live (CurrentsMark) tinted by the
    /// theme, so `logoAsset` is unused for previews now.
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
