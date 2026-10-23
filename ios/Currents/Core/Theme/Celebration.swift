import SwiftUI

/// Confetti moments for catches that deserve more than a toast: the first
/// time a species is landed, and personal bests. Detection always runs
/// against the CURRENT catch log — delete a fish and re-log it and it's a
/// "first" again, because it genuinely is the only one in the log.
struct Celebration: Equatable, Identifiable {
    let id = UUID()
    /// The over line ("New species", "Personal best"). Shown as the title
    /// itself when `title` is nil.
    var headline: String
    var detail: String
    /// Symbol shown in the art panel when there is no species art.
    var icon: String
    /// The big title, usually the species name.
    var title: String? = nil
    /// Species whose art fills the panel, tinted with its art colour.
    var speciesId: Int64? = nil
    /// Optional primary button ("View in Fishdex") that opens a deep link.
    var primaryTitle: String? = nil
    var primaryLink: URL? = nil
    /// Which haptic pattern plays with the card.
    var moment: Haptics.Moment = .newSpecies

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
            return Celebration(headline: "New species",
                               detail: "Your first one. It's in your Fishdex now.",
                               icon: "fish.fill",
                               title: name,
                               speciesId: speciesId,
                               primaryTitle: "View in Fishdex",
                               primaryLink: URL(string: "currents://fishdex"))
        }
        if let w = weightKg, w > 0, w > (priors.compactMap(\.weightKg).max() ?? 0) {
            return Celebration(headline: "Personal best",
                               detail: "Your heaviest yet at \(Units.weight(kg: w)).",
                               icon: "trophy.fill",
                               title: name,
                               speciesId: speciesId,
                               moment: .personalBest)
        }
        if let l = lengthCm, l > 0, l > (priors.compactMap(\.lengthCm).max() ?? 0) {
            return Celebration(headline: "Personal best",
                               detail: "Your longest yet at \(Units.length(cm: l)).",
                               icon: "trophy.fill",
                               title: name,
                               speciesId: speciesId,
                               moment: .personalBest)
        }
        return nil
    }
}

/// App-wide celebration queue, mirroring ToastCenter. Fire it right before a
/// sheet dismisses — the overlay lives at the root, so it plays over whatever
/// screen is underneath. The card stays until the angler dismisses it;
/// observe `current` becoming nil to follow up (the rate prompt does).
@MainActor
final class CelebrationCenter: ObservableObject {
    static let shared = CelebrationCenter()
    @Published var current: Celebration?

    func show(_ celebration: Celebration) {
        // Callers show the card after saving, so a log holding one catch
        // means this new species is the angler's first fish ever.
        var moment = celebration.moment
        if moment == .newSpecies, (try? AppState.shared?.catchRepository.totalCount()) == 1 {
            moment = .firstCatch
        }
        Haptics.celebrate(moment)
        withAnimation(DS.Motion.spring) { current = celebration }
    }

    func dismiss() {
        withAnimation(.easeOut(duration: DS.Motion.med)) { current = nil }
    }
}

// MARK: - Confetti

/// One burst from just above the card: pieces fly up and out, then fall under
/// gravity and fade, drawn in a single Canvas.
private struct ConfettiBurst: View {
    struct Piece {
        var dx: Double         // launch offset from centre
        var vx: Double         // points/sec
        var vy: Double         // points/sec, negative is up
        var spin: Double       // radians/sec
        var angle: Double
        var size: Double
        var colorIndex: Int
    }

    let pieces: [Piece]
    let start: Date

    static let duration: Double = 2.6
    private static let gravity: Double = 1350

    static func makePieces(count: Int = 110) -> [Piece] {
        (0..<count).map { _ in
            Piece(dx: Double.random(in: -40...40),
                  vx: Double.random(in: -330...330),
                  vy: -Double.random(in: 240...1020),
                  spin: Double.random(in: -18...18),
                  angle: Double.random(in: 0...6),
                  size: Double.random(in: 5...10),
                  colorIndex: Int.random(in: 0..<6))
        }
    }

    private static var palette: [Color] {
        [DS.accent, .dsScoreGood, .dsScoreFair, .dsScoreLow, .dsScoreSlow, .purple]
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(start)
                guard t < Self.duration else { return }
                let origin = CGPoint(x: size.width / 2, y: size.height * 0.42)
                let alpha = min(1, max(0, (Self.duration - t) / 0.6))
                for p in pieces {
                    // Light air drag on the horizontal drift.
                    let x = origin.x + p.dx + p.vx * (1 - exp(-1.2 * t)) / 1.2
                    let y = origin.y + p.vy * t + 0.5 * Self.gravity * t * t
                    guard y < size.height + 20 else { continue }
                    var piece = context
                    piece.opacity = alpha
                    piece.translateBy(x: x, y: y)
                    piece.rotate(by: .radians(p.angle + p.spin * t))
                    let rect = CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.size / 2)
                    piece.fill(Path(rect), with: .color(Self.palette[p.colorIndex]))
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

// MARK: - Card

private struct CelebrationCard: View {
    let celebration: Celebration
    let species: Species?
    let onPrimary: () -> Void
    let onDone: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var swim = false

    private var tint: Color { species?.artTint ?? DS.accent }

    var body: some View {
        VStack(spacing: DS.Space.s1) {
            art
                .padding(.bottom, DS.Space.s3)
            if celebration.title != nil {
                Text(celebration.headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            Text(celebration.title ?? celebration.headline)
                .font(.title2.bold())
                .foregroundStyle(.dsText)
                .multilineTextAlignment(.center)
            Text(celebration.detail)
                .font(.footnote)
                .foregroundStyle(.dsText2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, DS.Space.s4)
            if let primaryTitle = celebration.primaryTitle {
                Button(primaryTitle, action: onPrimary)
                    .buttonStyle(PrimaryButtonStyle())
            }
            Button(action: onDone) {
                Text("Done")
                    .font(.headline)
                    .foregroundStyle(.dsText2)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.dim)
        }
        .padding(DS.Space.s5)
        .frame(maxWidth: 320)
        .background(Color.dsElevated, in: RoundedRectangle(cornerRadius: DS.Radius.sheet, style: .continuous))
        .padding(.horizontal, DS.Space.s8)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .onAppear { if !reduceMotion { swim = true } }
    }

    private var art: some View {
        ZStack {
            Color.dsElevated
            tint.opacity(0.3)
            if let species {
                SpeciesArtworkView(species: species, caught: true, size: 120, fillWidth: true)
                    .padding(.horizontal, DS.Space.s4)
                    .offset(y: swim ? -6 : 0)
                    .rotationEffect(.degrees(swim ? -2 : 0))
                    .animation(swim ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true) : nil,
                               value: swim)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: celebration.icon)
                    .font(.largeTitle.weight(.semibold))
                    .imageScale(.large)
                    .foregroundStyle(tint)
                    .symbolEffect(.bounce, value: swim)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }
}

private struct CelebrationHost: ViewModifier {
    @ObservedObject private var center = CelebrationCenter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pieces = ConfettiBurst.makePieces()
    @State private var burstStart = Date.distantPast
    @State private var species: Species?

    func body(content: Content) -> some View {
        content.overlay {
            if let celebration = center.current {
                ZStack {
                    Color.dsScrim
                        .ignoresSafeArea()
                        .onTapGesture { center.dismiss() }
                        .accessibilityHidden(true)
                    // At the largest text sizes the card can outgrow the
                    // screen; it scrolls then instead of clipping its buttons.
                    ViewThatFits(in: .vertical) {
                        card(celebration)
                        ScrollView {
                            card(celebration)
                                .padding(.vertical, DS.Space.s6)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                    }
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                    if !reduceMotion {
                        ConfettiBurst(pieces: pieces, start: burstStart)
                    }
                }
                .transition(.opacity)
                .onAppear { prepare(celebration) }
                .onChange(of: celebration.id) { _, _ in prepare(celebration) }
            }
        }
    }

    private func card(_ celebration: Celebration) -> some View {
        CelebrationCard(celebration: celebration, species: species,
                        onPrimary: { openPrimary(celebration) },
                        onDone: { center.dismiss() })
    }

    private func prepare(_ celebration: Celebration) {
        species = celebration.speciesId.flatMap { try? AppState.shared?.speciesRepository.fetch(id: $0) }
        burstStart = Date()
        pieces = ConfettiBurst.makePieces()
        let spoken = [celebration.headline, celebration.title, celebration.detail]
            .compactMap { $0 }
            .joined(separator: ". ")
        AccessibilityNotification.Announcement(spoken).post()
    }

    private func openPrimary(_ celebration: Celebration) {
        center.dismiss()
        if let link = celebration.primaryLink {
            AppState.shared?.pendingDeepLink = link
        }
    }
}

extension View {
    /// Attach once near the app root so `CelebrationCenter.shared.show(...)`
    /// plays its card and confetti over the whole screen.
    func celebrationHost() -> some View { modifier(CelebrationHost()) }
}
