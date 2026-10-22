import SwiftUI

/// A 0 to 100 bite score as a ring in the score colour, with the number (and
/// an optional caption) inside. The arc sweeps in on first appear and
/// animates between values; the number rolls with `.numericText`.
struct ScoreRing: View {
    let score: Int
    var size: CGFloat = 62
    var caption: String? = nil
    /// Defaults to 10 percent of `size`.
    var lineWidth: CGFloat? = nil

    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clamped: Int { min(100, max(0, score)) }
    private var stroke: CGFloat { lineWidth ?? size * 0.1 }
    private var color: Color { DS.scoreColor(clamped) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.22), lineWidth: stroke)
            Circle()
                .trim(from: 0, to: shown / 100)
                .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text("\(clamped)")
                    .font(.system(size: size * 0.34, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.dsText)
                    .contentTransition(.numericText(value: Double(clamped)))
                if let caption {
                    Text(caption)
                        .font(.system(size: max(10, size * 0.12)))
                        .foregroundStyle(.dsText2)
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
            withAnimation(reduceMotion ? nil : DS.Motion.softSpring) { shown = Double(new) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption.map { "\($0), \(clamped) out of 100" } ?? "Score \(clamped) out of 100")
    }
}
