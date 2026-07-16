import SwiftUI

/// A playful loading indicator: a big fish leading on the left with its mouth
/// open, and a little school swimming in from the right toward it — each minnow
/// fading out at the mouth ("eaten") before the loop restarts. Uses the app
/// accent so it feels on-brand.
struct FishLoader: View {
    var message: String? = nil
    var width: CGFloat = 200

    /// Where the predator's mouth sits (a little right of its body centre) — the
    /// point the minnows vanish at.
    private var mouthX: CGFloat { -width / 2 + 40 }
    private var startX: CGFloat { width / 2 - 6 }

    var body: some View {
        VStack(spacing: 12) {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                // A gentle "gulp" — the predator pulses slightly as it feeds.
                let gulp = 1 + CGFloat(max(0, sin(t * 3.3)) * 0.06)
                ZStack {
                    // Predator, leading on the LEFT, gently bobbing as it feeds
                    // on the school that swims in and vanishes at its mouth.
                    Image(systemName: "fish.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(CurrentsTheme.accent)
                        .scaleEffect(gulp)
                        .offset(x: -width / 2 + 22, y: CGFloat(sin(t * 3) * 3))

                    // A school swimming in from the RIGHT toward the mouth.
                    ForEach(0..<3, id: \.self) { i in
                        let phase = (t * 0.55 + Double(i) * 0.34).truncatingRemainder(dividingBy: 1)
                        let x = startX + CGFloat(phase) * (mouthX - startX)
                        Image(systemName: "fish.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(CurrentsTheme.accent.opacity(0.55))
                            // Default orientation already faces left, the way
                            // they're swimming — no flip needed.
                            .offset(x: x, y: CGFloat(sin(t * 4 + Double(i)) * 4))
                            .opacity(phase > 0.82 ? max(0, 1 - (phase - 0.82) / 0.18) : 1)
                    }
                }
                .frame(width: width, height: 56)
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel(message ?? "Loading")
    }
}
