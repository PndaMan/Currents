import SwiftUI

/// A playful loading indicator: a big fish on the right and a little school
/// swimming toward it, each minnow fading out at the mouth ("eaten") before the
/// loop restarts. Uses the app accent so it feels on-brand.
struct FishLoader: View {
    var message: String? = nil
    var width: CGFloat = 200

    var body: some View {
        VStack(spacing: 12) {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                ZStack {
                    // Predator, anchored on the right, gently bobbing.
                    Image(systemName: "fish.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(CurrentsTheme.accent)
                        .offset(x: width / 2 - 22, y: CGFloat(sin(t * 3) * 3))

                    // A school swimming in from the left toward the predator.
                    ForEach(0..<3, id: \.self) { i in
                        let phase = (t * 0.55 + Double(i) * 0.34).truncatingRemainder(dividingBy: 1)
                        let x = -width / 2 + CGFloat(phase) * (width - 46)
                        Image(systemName: "fish.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(CurrentsTheme.accent.opacity(0.55))
                            .scaleEffect(x: -1) // face the way they're swimming
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
