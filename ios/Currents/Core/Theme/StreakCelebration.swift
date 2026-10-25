import SwiftUI

/// What the streak moment shows: the run after the save, and the recent
/// weeks drawn in the row under the number.
struct StreakMoment {
    /// The streak after this catch, in weeks; 2 or more.
    var weeks: Int
    /// Starts of the weeks in the row, oldest first, ending with this week.
    var rowWeeks: [Date]
    /// Weeks in the row already fished before this catch. This week isn't
    /// in it: it fills in as the number rolls on.
    var fishedBefore: Set<Date>
}

// MARK: - Embers

/// Sparks that leave the flame as it lights and again as the number rolls
/// on: they shoot out, drift up on the heat, sway, shrink and fade. Two
/// expanding rings mark the same beats. All of it in one Canvas.
private struct EmberBurst: View {
    struct Spark {
        var angle: Double    // launch direction in radians; -pi/2 is straight up
        var speed: Double    // points/sec at launch
        var life: Double     // seconds
        var size: Double     // diameter at launch
        var sway: Double     // phase of the sideways drift
        var colorIndex: Int
    }

    let ignite: Date
    let roll: Date?
    let igniteSparks: [Spark]
    let rollSparks: [Spark]
    /// Radius of the flame's tile, where the sparks and rings start.
    let radius: Double

    static let ringLife: Double = 0.7
    private static let drag: Double = 2.6
    private static let lift: Double = 110

    static func makeSparks(count: Int, speed: ClosedRange<Double>) -> [Spark] {
        (0..<count).map { _ in
            // Mostly upward: a fan from lower left round to lower right.
            Spark(angle: -Double.pi / 2 + Double.random(in: -1.25...1.25),
                  speed: Double.random(in: speed),
                  life: Double.random(in: 0.9...1.7),
                  size: Double.random(in: 3...7),
                  sway: Double.random(in: 0...6.3),
                  colorIndex: [0, 0, 0, 1, 1, 2].randomElement() ?? 0)
        }
    }

    private static var palette: [Color] { [.dsScoreLow, .dsScoreFair, .dsScoreSlow] }

    /// The square of half-width `r` centred on (x, y).
    private static func square(_ x: Double, _ y: Double, _ r: Double) -> CGRect {
        CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                draw(&context, centre: centre, sparks: igniteSparks,
                     t: timeline.date.timeIntervalSince(ignite), ringGrowth: 1)
                if let roll {
                    draw(&context, centre: centre, sparks: rollSparks,
                         t: timeline.date.timeIntervalSince(roll), ringGrowth: 0.6)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(_ context: inout GraphicsContext, centre: CGPoint,
                      sparks: [Spark], t: Double, ringGrowth: Double) {
        guard t >= 0 else { return }

        // The ring: grows out from the tile's edge and thins as it fades.
        if t < Self.ringLife {
            let p: Double = t / Self.ringLife
            let eased: Double = 1 - pow(1 - p, 3)
            let r: Double = radius + 110 * ringGrowth * eased
            var ring = context
            ring.opacity = (1 - p) * 0.55
            ring.stroke(Path(ellipseIn: Self.square(Double(centre.x), Double(centre.y), r)),
                        with: .color(.dsScoreLow), lineWidth: CGFloat(1 + 3 * (1 - p)))
        }

        let cx = Double(centre.x)
        let cy = Double(centre.y)
        for s in sparks where t < s.life {
            let age: Double = t / s.life
            // Launch with air drag, then the heat lifts it and it sways.
            let travel: Double = s.speed * (1 - exp(-Self.drag * t)) / Self.drag
            let reach: Double = radius * 0.7 + travel
            let sway: Double = sin(t * 7 + s.sway) * 5 * age
            let rise: Double = 0.5 * Self.lift * t * t
            let x: Double = cx + cos(s.angle) * reach + sway
            let y: Double = cy + sin(s.angle) * reach - rise
            let d: Double = s.size * (1 - 0.65 * age)
            let alpha: Double = min(1, t / 0.06) * pow(1 - age, 1.4)
            let color = Self.palette[s.colorIndex]

            // A faint wide disc behind each spark reads as its glow.
            var glow = context
            glow.opacity = alpha * 0.22
            glow.fill(Path(ellipseIn: Self.square(x, y, d * 1.4)), with: .color(color))

            var core = context
            core.opacity = alpha
            core.fill(Path(ellipseIn: Self.square(x, y, d / 2)), with: .color(color))
        }
    }
}

// MARK: - Moment

/// The full-screen streak moment, after a catch that makes this week count
/// and extends a run: the flame lights, the number rolls on from last
/// week's, and this week fills in at the end of the row. About two seconds
/// to settle. A tap anywhere or Done dismisses it; Reduce Motion fades in
/// the final state.
struct StreakMomentView: View {
    let celebration: Celebration
    let moment: StreakMoment
    /// Seconds to wait before starting, while a card before it fades out.
    let startDelay: Double
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .largeTitle) private var tileSize: CGFloat = 148
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 96
    @ScaledMetric(relativeTo: .body) private var markerSize: CGFloat = 34

    @State private var shown = false
    @State private var ignited = false
    @State private var numberIn = false
    @State private var rowIn = false
    @State private var rolled = false
    @State private var flare = false
    @State private var settled = false
    @State private var igniteStart: Date?
    @State private var rollStart: Date?
    @State private var igniteSparks = EmberBurst.makeSparks(count: 64, speed: 120...340)
    @State private var rollSparks = EmberBurst.makeSparks(count: 30, speed: 80...220)

    /// Capped so the art still fits on screen at the largest text sizes.
    private var tile: CGFloat { min(tileSize, 200) }
    /// Seven markers share the row, so they stop growing before they crowd it.
    private var markerSide: CGFloat { min(markerSize, 40) }
    private var count: Int { rolled ? moment.weeks : moment.weeks - 1 }
    private var thisWeek: Date? { moment.rowWeeks.last }

    var body: some View {
        ZStack {
            backdrop
            VStack(spacing: 0) {
                // Centred on screen. Only when large text outgrows the screen
                // does it scroll, as the celebration card does; unscrolled,
                // nothing clips the sparks.
                ViewThatFits(in: .vertical) {
                    content
                    ScrollView {
                        content
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Button("Done", action: onDone)
                    .buttonStyle(.dsPrimary)
                    .padding(.horizontal, DS.gutter)
                    .padding(.bottom, DS.Space.s4)
                    .opacity(settled ? 1 : 0)
            }
            .opacity(shown ? 1 : 0)
        }
        // Tap anywhere to dismiss, once it is on screen. Before that the
        // backdrop still takes the tap, so it can't reach the app beneath.
        .contentShape(Rectangle())
        .onTapGesture { if shown { onDone() } }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { onDone() }
        .task { await play() }
    }

    private var backdrop: some View {
        ZStack {
            Color.dsBackground
            Color.dsScoreLow.opacity(DS.heroTintOpacity(scheme) * 1.6)
        }
        .ignoresSafeArea()
        .opacity(shown ? 1 : 0)
    }

    private var content: some View {
        VStack(spacing: 0) {
            flame
                .padding(.bottom, DS.Space.s5)
            number
            weekRow
                .padding(.top, DS.Space.s8)
            Text(celebration.detail)
                .font(.body)
                .foregroundStyle(.dsText2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.s5)
                .opacity(settled ? 1 : 0)
                .offset(y: settled ? 0 : DS.Space.s2)
        }
        .padding(.horizontal, DS.gutter)
        .padding(.vertical, DS.Space.s6)
    }

    // MARK: Flame

    private var flame: some View {
        ZStack {
            // A wider faint halo that opens as the flame lights.
            Circle()
                .fill(Color.dsScoreLow.opacity(0.1))
                .frame(width: tile * 1.4, height: tile * 1.4)
                .scaleEffect(ignited ? 1 : 0.5)
                .opacity(ignited ? 1 : 0)
            Circle()
                .fill(Color.dsScoreLow.opacity(ignited ? 0.22 : 0.08))
                .frame(width: tile, height: tile)
            Image(systemName: ignited ? "flame.fill" : "flame")
                .font(.system(size: tile * 0.46, weight: .semibold)) // ui-lint: allow, glyph sized from its tile, which scales with text
                .foregroundStyle(ignited ? DS.ink(.dsScoreLow) : Color.dsText3)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.breathe, options: .repeating, isActive: settled && !reduceMotion)
        }
        .scaleEffect(ignited ? (flare ? 1.12 : 1) : 0.6)
        .frame(width: tile * 1.4, height: tile * 1.4)
        .overlay {
            if let igniteStart, !reduceMotion {
                EmberBurst(ignite: igniteStart, roll: rollStart,
                           igniteSparks: igniteSparks, rollSparks: rollSparks,
                           radius: Double(tile / 2))
                    .frame(width: tile * 2.6, height: tile * 3.6)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Number

    private var number: some View {
        VStack(spacing: 0) {
            Text("\(count)")
                .font(.system(size: min(numberSize, 140), weight: .bold)) // ui-lint: allow, the hero number scales with text up to a cap
                .monospacedDigit()
                .foregroundStyle(.dsText)
                .contentTransition(.numericText(value: Double(count)))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text("week streak")
                .font(.title3.weight(.semibold))
                .foregroundStyle(DS.ink(.dsScoreLow))
        }
        .scaleEffect(numberIn ? (flare ? 1.06 : 1) : 0.7)
        .opacity(numberIn ? 1 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(celebration.headline)
    }

    // MARK: Week row

    private var weekRow: some View {
        VStack(spacing: DS.Space.s2) {
            HStack(spacing: 0) {
                ForEach(Array(moment.rowWeeks.enumerated()), id: \.offset) { i, week in
                    marker(week, index: i)
                        .frame(maxWidth: .infinity)
                }
            }
            HStack {
                Text(moment.rowWeeks.first.map { LogbookFormat.shortDay($0) } ?? "")
                Spacer()
                Text("This week")
            }
            .font(.caption)
            .foregroundStyle(.dsText2)
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: 420)
        .background(Color.dsElevated, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowLabel)
    }

    private func marker(_ week: Date, index: Int) -> some View {
        let isThisWeek = week == thisWeek
        let fished = moment.fishedBefore.contains(week) || (isThisWeek && rolled)
        return ZStack {
            Circle()
                .fill(fished ? Color.dsScoreLow : Color.dsFill2)
            if isThisWeek && !fished {
                Circle()
                    .strokeBorder(Color.dsScoreLow, lineWidth: 2)
            }
            if fished {
                // A mark as well as the colour, so the row reads without it.
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.dsOnPrimary)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: markerSide, height: markerSide)
        .scaleEffect(isThisWeek && flare ? 1.3 : 1)
        .scaleEffect(rowIn ? 1 : 0.3)
        .opacity(rowIn ? 1 : 0)
        .animation(reduceMotion ? nil : DS.Motion.spring.delay(Double(index) * 0.06), value: rowIn)
    }

    private var rowLabel: String {
        let fished = moment.rowWeeks.filter { moment.fishedBefore.contains($0) || $0 == thisWeek }.count
        return "Fished in \(fished) of the last \(moment.rowWeeks.count) weeks, this week included"
    }

    // MARK: Timeline

    /// False once the view has gone, so a dismissed moment stops where it is.
    private func hold(_ seconds: Double) async -> Bool {
        (try? await Task.sleep(for: .seconds(seconds))) != nil
    }

    private func play() async {
        if startDelay > 0 {
            guard await hold(startDelay) else { return }
        }
        AccessibilityNotification.Announcement("\(celebration.headline). \(celebration.detail)").post()

        if reduceMotion {
            // The final state, faded in.
            ignited = true
            numberIn = true
            rowIn = true
            rolled = true
            settled = true
            Haptics.success()
            withAnimation(.easeOut(duration: DS.Motion.med)) { shown = true }
            return
        }

        // Haptics.Moment.streak is timed to the beats below.
        Haptics.celebrate(.streak)
        withAnimation(.easeOut(duration: DS.Motion.med)) { shown = true }

        // 0.3 s: the flame lights and throws its sparks.
        guard await hold(0.3) else { return }
        igniteStart = Date()
        withAnimation(.spring(duration: 0.5, bounce: 0.45)) { ignited = true }

        // 0.55 s: last week's number.
        guard await hold(0.25) else { return }
        withAnimation(DS.Motion.spring) { numberIn = true }

        // 0.75 s: the row lands, one week after another.
        guard await hold(0.2) else { return }
        rowIn = true

        // 1.35 s: the number rolls on and this week fills in.
        guard await hold(0.6) else { return }
        rollStart = Date()
        withAnimation(.spring(duration: 0.45, bounce: 0.3)) {
            rolled = true
            flare = true
        }
        guard await hold(0.18) else { return }
        withAnimation(DS.Motion.softSpring) { flare = false }

        // 1.85 s: the copy and the button.
        guard await hold(0.32) else { return }
        withAnimation(DS.Motion.easeOut) { settled = true }
    }
}
