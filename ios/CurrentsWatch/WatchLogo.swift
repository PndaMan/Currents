import SwiftUI

/// The Currents mark, drawn on the watch as a single-colour vector so it tints
/// to whichever app icon / theme the angler picked on the phone. watchOS can't
/// swap the home-screen app icon per-user (there's no `setAlternateIconName`),
/// so this in-app logo is how the watch "follows" the chosen icon.
struct CurrentsMark: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        let amp = h * 0.11
        let xL = w * 0.10, xR = w * 0.90
        let xM = (xL + xR) / 2
        for y in [h * 0.32, h * 0.52, h * 0.72] {
            p.move(to: CGPoint(x: xL, y: y))
            p.addCurve(to: CGPoint(x: xM, y: y),
                       control1: CGPoint(x: xL + (xM - xL) * 0.35, y: y - amp * 1.7),
                       control2: CGPoint(x: xM - (xM - xL) * 0.35, y: y + amp * 1.7))
            p.addCurve(to: CGPoint(x: xR, y: y),
                       control1: CGPoint(x: xM + (xR - xM) * 0.35, y: y - amp * 1.7),
                       control2: CGPoint(x: xR - (xR - xM) * 0.35, y: y + amp * 1.7))
        }
        return p
    }
}

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

/// Small logo header: the current mark + wordmark, tinted to the chosen theme.
struct WatchLogoHeader: View {
    var theme: String
    var size: CGFloat = 22

    var body: some View {
        HStack(spacing: size * 0.3) {
            CurrentsMark()
                .stroke(currentsThemeColor(theme),
                        style: StrokeStyle(lineWidth: size * 0.12, lineCap: .round, lineJoin: .round))
                .frame(width: size, height: size)
            Text("Currents")
                .font(.system(size: size * 0.7, weight: .semibold, design: .rounded))
                .foregroundStyle(currentsThemeColor(theme))
        }
    }
}
