import SwiftUI

/// Theme raw value → primary tint, mirroring `ThemeOption.primary` on the phone.
func currentsThemeColor(_ raw: String) -> Color {
    switch raw {
    case "forest":   return .green
    case "ember":    return Color(red: 0.86, green: 0.15, blue: 0.15)
    case "sunset":   return .orange
    case "amethyst": return .purple
    case "teal":     return .teal
    case "rose":     return .pink
    case "gold":     return Color(red: 0.85, green: 0.65, blue: 0.13)
    default:         return .blue   // ocean
    }
}

/// Small logo header: just the mark, tinted to the chosen theme. The app name
/// already sits in the watch's navigation title, so the wordmark would only
/// repeat it and eat vertical space on a small screen.
///
/// The mark itself (`CurrentsMark`) lives in ios/Shared so the watch draws the
/// exact fish that is the phone's app icon. watchOS can't swap the home-screen
/// icon per-user (no `setAlternateIconName`), so tinting this in-app logo is
/// how the watch "follows" the icon the angler picked on the phone.
struct WatchLogoHeader: View {
    var theme: String
    var size: CGFloat = 22

    var body: some View {
        CurrentsMark(tint: currentsThemeColor(theme))
            .frame(width: size, height: size)
    }
}
