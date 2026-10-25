import SwiftUI

/// The few design tokens the watch needs, copied from the app's design system
/// (Core/Theme/DS/DSTokens.swift), which this target does not compile. Keep
/// the values in step with DSTokens.
enum WatchTheme {
    static let scoreSlow = Color(red: 1.0, green: 0.271, blue: 0.227)    // #ff453a
    static let scoreLow = Color(red: 1.0, green: 0.624, blue: 0.039)     // #ff9f0a
    static let scoreFair = Color(red: 1.0, green: 0.839, blue: 0.039)    // #ffd60a
    static let scoreGood = Color(red: 0.188, green: 0.820, blue: 0.345)  // #30d158

    /// Tonal fill for secondary buttons: white at 14 percent on black.
    static let tonal = Color.white.opacity(0.14)

    /// Same breakpoints as `DS.scoreColor`; the top band is the angler's theme
    /// colour, as on the phone.
    static func scoreColor(_ score: Int, theme: String) -> Color {
        switch score {
        case ..<25: return scoreSlow
        case 25..<50: return scoreLow
        case 50..<75: return scoreFair
        case 75..<90: return scoreGood
        default: return currentsThemeColor(theme)
        }
    }
}

/// The Today hero ring on the watch.
struct WatchScoreRing: View {
    let score: Int
    let theme: String
    var size: CGFloat = 84
    var caption: String? = nil

    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clamped: Int { min(100, max(0, score)) }
    private var stroke: CGFloat { size * 0.1 }
    private var color: Color { WatchTheme.scoreColor(clamped, theme: theme) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.22), lineWidth: stroke)
            Circle()
                .trim(from: 0, to: shown / 100)
                .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(clamped)")
                    .font(.system(size: size * 0.34, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(clamped)))
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
        .onAppear {
            if reduceMotion {
                shown = Double(clamped)
            } else {
                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 1.1)) { shown = Double(clamped) }
            }
        }
        .onChange(of: clamped) { _, new in
            withAnimation(reduceMotion ? nil : .spring(duration: 0.56, bounce: 0.12)) { shown = Double(new) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bite score \(clamped) out of 100")
    }
}

/// Luma's primary button: filled white, black label, dims when pressed.
struct WatchPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

/// Luma's secondary button: a tonal fill, optionally tinted (red for End).
struct WatchTonalButtonStyle: ButtonStyle {
    var tint: Color? = nil
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(tint ?? .white)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(tint.map { $0.opacity(0.2) } ?? WatchTheme.tonal,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}
