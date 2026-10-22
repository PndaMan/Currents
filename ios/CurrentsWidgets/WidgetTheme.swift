import SwiftUI
import UIKit

/// The few design tokens the widgets and Live Activities need, copied from the
/// app's design system (Core/Theme/DS/DSTokens.swift), which this target does
/// not compile. Keep the values in step with DSTokens.
enum WidgetTheme {
    static let scoreSlow = Color(red: 1.0, green: 0.271, blue: 0.227)    // #ff453a
    static let scoreLow = Color(red: 1.0, green: 0.624, blue: 0.039)     // #ff9f0a
    static let scoreFair = Color(red: 1.0, green: 0.839, blue: 0.039)    // #ffd60a
    static let scoreGood = Color(red: 0.188, green: 0.820, blue: 0.345)  // #30d158
    /// The app uses the angler's theme colour for the top band. The widget
    /// cannot read that setting, so it uses the default ocean blue.
    static let scoreBest = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.298, green: 0.784, blue: 1.0, alpha: 1)     // #4cc8ff
            : UIColor(red: 0.102, green: 0.608, blue: 0.949, alpha: 1)   // #1a9bf2
    })

    /// Widget background: white in light, near black in dark (dsElevated).
    static let background = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.110, green: 0.110, blue: 0.118, alpha: 1)   // #1c1c1e
            : .white
    })

    /// The Live Activity card on the lock screen: the system material colour.
    static let activityBackground = Color(red: 0.110, green: 0.110, blue: 0.118).opacity(0.78)

    /// Same breakpoints as `DS.scoreColor`.
    static func scoreColor(_ score: Int) -> Color {
        switch score {
        case ..<25: return scoreSlow
        case 25..<50: return scoreLow
        case 50..<75: return scoreFair
        case 75..<90: return scoreGood
        default: return scoreBest
        }
    }

    /// "1st", "2nd", "3rd", "4th", "11th".
    static func ordinal(_ n: Int) -> String {
        let tens = n % 100
        if (11...13).contains(tens) { return "\(n)th" }
        switch n % 10 {
        case 1: return "\(n)st"
        case 2: return "\(n)nd"
        case 3: return "\(n)rd"
        default: return "\(n)th"
        }
    }
}

/// The Today hero ring, drawn statically (widgets do not animate): the score
/// colour at 22 percent for the track, the arc in full colour, the number in
/// the primary text colour.
struct WidgetScoreRing: View {
    let score: Int
    var size: CGFloat = 62
    var caption: String? = nil

    private var clamped: Int { min(100, max(0, score)) }
    private var stroke: CGFloat { size * 0.1 }
    private var color: Color { WidgetTheme.scoreColor(clamped) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.22), lineWidth: stroke)
            Circle()
                .trim(from: 0, to: CGFloat(clamped) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
            VStack(spacing: 0) {
                Text("\(clamped)")
                    .font(.system(size: size * 0.34, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                if let caption {
                    Text(caption)
                        .font(.system(size: max(10, size * 0.12)))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .padding(stroke)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bite score \(clamped) out of 100")
    }
}
