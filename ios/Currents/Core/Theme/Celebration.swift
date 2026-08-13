import SwiftUI

/// Full-screen confetti moments for catches that deserve more than a toast:
/// the first time a species is landed, and personal bests. Detection always
/// runs against the CURRENT catch log — delete a fish and re-log it and it's
/// a "first" again, because it genuinely is the only one in the log.
struct Celebration: Equatable, Identifiable {
    let id = UUID()
    var headline: String
    var detail: String
    var icon: String

    static func == (lhs: Celebration, rhs: Celebration) -> Bool { lhs.id == rhs.id }
}

/// Decides whether a just-about-to-be-saved catch is a first-of-species or a
/// personal best, judged against the rest of the log (excluding the catch
/// itself, so edits don't celebrate against their own numbers).
enum CelebrationJudge {
    static func judge(speciesName: String?, speciesId: Int64?,
                      weightKg: Double?, lengthCm: Double?,
                      excludingCatchId: String?,
                      existing: [Catch]) -> Celebration? {
        guard let speciesId, let name = speciesName else { return nil }
        let priors = existing.filter { $0.speciesId == speciesId && $0.id != excludingCatchId }

        if priors.isEmpty {
            return Celebration(headline: "New species!",
                               detail: "Your first \(name) — added to your collection.",
                               icon: "sparkles")
        }
        if let w = weightKg, w > 0, w > (priors.compactMap(\.weightKg).max() ?? 0) {
            return Celebration(headline: "Personal best!",
                               detail: "Your heaviest \(name) yet — \(Units.weight(kg: w)).",
                               icon: "trophy.fill")
        }
        if let l = lengthCm, l > 0, l > (priors.compactMap(\.lengthCm).max() ?? 0) {
            return Celebration(headline: "Personal best!",
                               detail: "Your longest \(name) yet — \(Units.length(cm: l)).",
                               icon: "trophy.fill")
        }
        return nil
    }
}

/// App-wide celebration queue, mirroring ToastCenter. Fire it right before a
/// sheet dismisses — the overlay lives at the root, so it plays over whatever
/// screen is underneath.
@MainActor
final class CelebrationCenter: ObservableObject {
    static let shared = CelebrationCenter()
    @Published var current: Celebration?
    private var dismissTask: Task<Void, Never>?

    func show(_ celebration: Celebration) {
        Haptics.success()
        withAnimation(.spring(duration: 0.4)) { current = celebration }
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3.4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.4)) { self?.current = nil }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.25)) { current = nil }
    }
}

// MARK: - Confetti

/// A deterministic-per-launch confetti burst drawn in one Canvas — no emitters,
/// no UIKit particle layers, cheap enough to overlay anywhere.
private struct ConfettiBurst: View {
    struct Piece {
        var x: Double          // 0…1 across the width
        var delay: Double
        var speed: Double      // points/sec fall
        var drift: Double      // horizontal sway amplitude
        var spin: Double
        var size: Double
        var colorIndex: Int
        var isRect: Bool
    }

    let pieces: [Piece]
    let start: Date

    static func makePieces(count: Int = 90) -> [Piece] {
        (0..<count).map { i in
            var rng = SystemRandomNumberGenerator()
            _ = i
            return Piece(x: Double.random(in: 0...1, using: &rng),
                         delay: Double.random(in: 0...0.7, using: &rng),
                         speed: Double.random(in: 180...420, using: &rng),
                         drift: Double.random(in: 12...46, using: &rng),
                         spin: Double.random(in: 2...7, using: &rng),
                         size: Double.random(in: 6...11, using: &rng),
                         colorIndex: Int.random(in: 0...5, using: &rng),
                         isRect: Bool.random(using: &rng))
        }
    }

    private static let palette: [Color] = [
        CurrentsTheme.accent, .orange, .pink, .yellow, .teal, .purple
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(start)
                for p in pieces {
                    let local = t - p.delay
                    guard local > 0 else { continue }
                    let y = local * p.speed - 20
                    guard y < size.height + 20 else { continue }
                    let x = p.x * size.width + sin(local * 3 + p.drift) * p.drift
                    let alpha = min(1, max(0, 1.6 - local * 0.55))
                    guard alpha > 0 else { continue }
                    var piece = context
                    piece.translateBy(x: x, y: y)
                    piece.rotate(by: .radians(local * p.spin))
                    piece.opacity = alpha
                    let rect = CGRect(x: -p.size / 2, y: -p.size / 2,
                                      width: p.size, height: p.isRect ? p.size * 0.55 : p.size)
                    let path = p.isRect ? Path(rect) : Path(ellipseIn: rect)
                    piece.fill(path, with: .color(Self.palette[p.colorIndex]))
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

private struct CelebrationView: View {
    let celebration: Celebration

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: celebration.icon)
                .font(.system(size: 44))
                .foregroundStyle(.yellow.gradient)
                .shadow(color: .yellow.opacity(0.4), radius: 12)
            Text(celebration.headline)
                .font(.title2.bold())
            Text(celebration.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28).padding(.vertical, 24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.yellow.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 24, y: 8)
        .padding(.horizontal, 36)
    }
}

private struct CelebrationHost: ViewModifier {
    @ObservedObject private var center = CelebrationCenter.shared
    @State private var pieces = ConfettiBurst.makePieces()
    @State private var burstStart = Date.distantPast

    func body(content: Content) -> some View {
        content.overlay {
            if let celebration = center.current {
                ZStack {
                    ConfettiBurst(pieces: pieces, start: burstStart)
                    CelebrationView(celebration: celebration)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                        .onTapGesture { center.dismiss() }
                }
                .onAppear {
                    burstStart = Date()
                    pieces = ConfettiBurst.makePieces()
                }
            }
        }
    }
}

extension View {
    /// Attach once near the app root so `CelebrationCenter.shared.show(...)`
    /// plays confetti over the whole screen.
    func celebrationHost() -> some View { modifier(CelebrationHost()) }
}
