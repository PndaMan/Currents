import SwiftUI

// MARK: - Theme Options

/// Available color themes for the app.
enum ThemeOption: String, CaseIterable, Codable, Identifiable {
    case ocean = "ocean"
    case forest = "forest"
    case ember = "ember"
    case sunset = "sunset"
    case amethyst = "amethyst"
    case teal = "teal"
    case rose = "rose"
    case gold = "gold"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ocean: "Ocean"
        case .forest: "Forest"
        case .ember: "Ember"
        case .sunset: "Sunset"
        case .amethyst: "Amethyst"
        case .teal: "Teal"
        case .rose: "Rose"
        case .gold: "Gold"
        }
    }

    var primary: Color {
        switch self {
        case .ocean: .blue
        case .forest: .green
        case .ember: Color(red: 0.86, green: 0.15, blue: 0.15)
        case .sunset: .orange
        case .amethyst: .purple
        case .teal: .teal
        case .rose: .pink
        case .gold: Color(red: 0.85, green: 0.65, blue: 0.13)
        }
    }

    /// The currently selected theme, read from UserDefaults.
    static var current: ThemeOption {
        guard let raw = UserDefaults.standard.string(forKey: "selectedTheme"),
              let theme = ThemeOption(rawValue: raw) else {
            return .ocean
        }
        return theme
    }
}

// MARK: - Liquid Glass Theme for iOS 26

/// Currents design system built on iOS 26 Liquid Glass.
/// Dark-mode first — anglers fish dawn/dusk.
enum CurrentsTheme {
    // MARK: Colors

    /// Dynamic accent color that follows the user's selected theme.
    static var accent: Color { ThemeOption.current.primary }
    static let danger = Color.red

    /// Score color ramp on the grade breakpoints: red (0) → orange (25) →
    /// yellow (50) → green (65) → accent (80).
    /// Delegates to the design system so old and new screens agree.
    static func scoreColor(_ score: Int) -> Color { DS.scoreColor(score) }

    // MARK: Spacing

    static let paddingS: CGFloat = 8
    static let paddingM: CGFloat = 16
    static let paddingL: CGFloat = 24
    static let cornerRadius: CGFloat = 16
}

// MARK: - Weather Condition Icon

struct WeatherIcon: View {
    let condition: String // "clear", "cloudy", "rain", "storm", "wind"

    var systemName: String {
        switch condition.lowercased() {
        case "clear": "sun.max.fill"
        case "cloudy", "overcast": "cloud.fill"
        case "rain": "cloud.rain.fill"
        case "storm", "thunder": "cloud.bolt.rain.fill"
        case "wind": "wind"
        case "snow": "cloud.snow.fill"
        case "fog": "cloud.fog.fill"
        default: "cloud.fill"
        }
    }

    var body: some View {
        Image(systemName: systemName)
            .symbolRenderingMode(.multicolor)
    }
}
