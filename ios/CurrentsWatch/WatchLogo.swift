import SwiftUI

// The Currents mark (Shared/CurrentsMark.swift) is drawn on the watch as a
// single-colour vector so it tints to whichever app icon / theme the angler
// picked on the phone. watchOS can't swap the home-screen app icon per-user
// (there's no `setAlternateIconName`), so this in-app logo is how the watch
// "follows" the chosen icon.

/// Theme raw value → primary tint, mirroring `ThemeOption.primary` on the phone.
func currentsThemeColor(_ raw: String) -> Color {
    switch raw {
    case "forest":   return .green
    case "ember":    return Color(red: 0.86, green: 0.15, blue: 0.15) // ui-lint: allow (mirrors ThemeOption.primary, the watch has no theme file)
    case "sunset":   return .orange
    case "amethyst": return .purple
    case "teal":     return .teal
    case "rose":     return .pink
    case "gold":     return Color(red: 0.85, green: 0.65, blue: 0.13) // ui-lint: allow (mirrors ThemeOption.primary)
    default:         return .blue   // ocean
    }
}

/// Small logo header: just the mark, tinted to the chosen theme. The app name
/// already sits in the watch's navigation title, so the wordmark would only
/// repeat it and eat vertical space on a small screen.
struct WatchLogoHeader: View {
    var theme: String
    var size: CGFloat = 20

    var body: some View {
        CurrentsMark()
            .filled(currentsThemeColor(theme))
            .frame(width: size, height: size)
    }
}
