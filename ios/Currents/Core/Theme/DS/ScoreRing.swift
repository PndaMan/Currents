import SwiftUI

/// A 0 to 100 bite score as a ring in the score colour, with the number (and
/// an optional caption) inside. The arc sweeps in on first appear and
/// animates between values; the number rolls with `.numericText`.
struct ScoreRing: View {
    let score: Int
    var size: CGFloat = 62
    var caption: String? = nil
    /// What VoiceOver reads before the score, when the caption is shorter
    /// than the thing it names. Defaults to the caption.
    var spokenLabel: String? = nil
    /// Defaults to 10 percent of `size`.
    var lineWidth: CGFloat? = nil

    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private var clamped: Int { min(100, max(0, score)) }
    private var stroke: CGFloat { lineWidth ?? size * 0.1 }
    private var color: Color { DS.scoreColor(clamped) }
    private var captionSize: CGFloat { max(10, size * 0.12) }

    /// The widest the caption can be: the chord of the circle inside the
    /// stroke (the stroke spans `size / 2 - stroke` to `size / 2`), at
    /// the foot of the caption. The text is laid out in the square
    /// inside the stroke, but the circle is narrower at that height, so a
    /// wider caption runs into the stroke. Line heights are about 1.2 times
    /// the font size.
    private var captionWidth: CGFloat {
        let reach = (size * 0.34 * 1.2 + captionSize * 1.2 + 1) / 2
        let inner = size / 2 - stroke - 1
        guard inner > reach else { return 0 }
        return 2 * (inner * inner - reach * reach).squareRoot()
    }

    var body: some View {
        ZStack {
            // Inset by half the stroke, so the whole stroke sits inside the
            // frame rather than half of it hanging outside.
            Circle()
                .inset(by: stroke / 2)
                .stroke(color.opacity(0.22), lineWidth: stroke)
            Circle()
                .inset(by: stroke / 2)
                .trim(from: 0, to: shown / 100)
                .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(clamped)")
                    .font(.system(size: size * 0.34, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.dsText)
                    .contentTransition(.numericText(value: Double(clamped)))
                // The ring does not grow with text size, so the caption is
                // dropped at accessibility sizes, and wherever it is wider
                // than the stroke leaves room for; the label still reads it.
                if let caption, !typeSize.isAccessibilitySize {
                    ViewThatFits(in: .horizontal) {
                        Text(caption)
                            .font(.system(size: captionSize))
                            .foregroundStyle(.dsText2)
                            .lineLimit(1)
                            .padding(.top, 1)
                        Color.clear.frame(width: 0, height: 0)
                    }
                    .frame(maxWidth: captionWidth)
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
        .accessibilityLabel((spokenLabel ?? caption).map { "\($0), \(clamped) out of 100" } ?? "Score \(clamped) out of 100")
    }
}
