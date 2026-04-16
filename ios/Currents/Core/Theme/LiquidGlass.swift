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

    /// Two-color gradient for the wordmark.
    var gradient: (Color, Color) {
        switch self {
        case .ocean:
            (Color(red: 0.10, green: 0.55, blue: 0.95),
             Color(red: 0.15, green: 0.82, blue: 0.98))
        case .forest:
            (Color(red: 0.18, green: 0.62, blue: 0.34),
             Color(red: 0.30, green: 0.85, blue: 0.50))
        case .ember:
            (Color(red: 0.86, green: 0.15, blue: 0.15),
             Color(red: 0.95, green: 0.40, blue: 0.25))
        case .sunset:
            (Color(red: 0.95, green: 0.55, blue: 0.15),
             Color(red: 0.98, green: 0.75, blue: 0.25))
        case .amethyst:
            (Color(red: 0.55, green: 0.25, blue: 0.85),
             Color(red: 0.72, green: 0.45, blue: 0.95))
        case .teal:
            (Color(red: 0.15, green: 0.65, blue: 0.70),
             Color(red: 0.25, green: 0.85, blue: 0.85))
        case .rose:
            (Color(red: 0.88, green: 0.30, blue: 0.55),
             Color(red: 0.95, green: 0.50, blue: 0.70))
        case .gold:
            (Color(red: 0.85, green: 0.65, blue: 0.13),
             Color(red: 0.95, green: 0.80, blue: 0.30))
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

    /// Score color ramp: red (0) → orange (40) → yellow (60) → green (80) → accent (100)
    static func scoreColor(_ score: Int) -> Color {
        switch score {
        case 0..<25: return .red
        case 25..<50: return .orange
        case 50..<75: return .yellow
        case 75..<90: return .green
        default: return accent
        }
    }

    // MARK: Spacing

    static let paddingS: CGFloat = 8
    static let paddingM: CGFloat = 16
    static let paddingL: CGFloat = 24
    static let cornerRadius: CGFloat = 16
}

// MARK: - Reusable Liquid Glass Modifiers

extension View {
    /// Apply a glass card background — uses iOS 26 .glassEffect when available.
    func glassCard() -> some View {
        self
            .padding(CurrentsTheme.paddingM)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: CurrentsTheme.cornerRadius))
    }

    /// Subtle glass pill for tags/badges.
    func glassPill() -> some View {
        self
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
    }
}

// MARK: - Score Gauge View

struct ScoreGauge: View {
    let score: Int
    let label: String
    var size: CGFloat = 64

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: size > 80 ? 8 : 6)
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(
                        CurrentsTheme.scoreColor(score),
                        style: StrokeStyle(lineWidth: size > 80 ? 8 : 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text("\(score)")
                    .font(size > 80 ? .largeTitle.bold() : .title2.bold())
                    .monospacedDigit()
            }
            .frame(width: size, height: size)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? CurrentsTheme.accent : Color.clear)
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(.secondary.opacity(0.3)))
        }
    }
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
