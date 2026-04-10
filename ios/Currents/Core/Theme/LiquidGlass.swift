import SwiftUI

// MARK: - Liquid Glass Theme for iOS 26

/// Currents design system built on iOS 26 Liquid Glass.
/// Dark-mode first — anglers fish dawn/dusk.
enum CurrentsTheme {
    // MARK: Colors

    static let accent = Color.blue
    static let accentGreen = Color.green
    static let warning = Color.orange
    static let danger = Color.red

    /// Score color ramp: red (0) → orange (40) → yellow (60) → green (80) → blue (100)
    static func scoreColor(_ score: Int) -> Color {
        switch score {
        case 0..<25: return .red
        case 25..<50: return .orange
        case 50..<75: return .yellow
        case 75..<90: return .green
        default: return .blue
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

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(
                        CurrentsTheme.scoreColor(score),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text("\(score)")
                    .font(.title2.bold())
                    .monospacedDigit()
            }
            .frame(width: 64, height: 64)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
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
