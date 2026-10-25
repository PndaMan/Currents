import SwiftUI

/// The opening moment, after the old Twitter bird reveal. The fish waits on
/// the plain launch background as a faint outline, water rises inside it
/// under a gently moving surface, it dips once when full, and then its body
/// turns into a window that rushes out past the edges of the screen and
/// leaves the app behind it. About 1.3 seconds and no text. A tap skips
/// straight to the opening; Reduce Motion gets the filled mark and a short
/// crossfade instead.
///
/// The launch screen is the plain system background in the style Info.plist
/// sets (dark, whatever the angler picked in Settings), so the overlay draws
/// in that style and its first frame matches the launch screen exactly.
struct LaunchAnimation: View {
    /// Called once as the fish starts to open (or, with Reduce Motion, to
    /// fade), so the app behind it can settle. True when it animates.
    let onReveal: (Bool) -> Void
    let onFinish: () -> Void

    @AppStorage("selectedTheme") private var selectedTheme = ThemeOption.ocean.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    /// When the first frame went up.
    @State private var start: Date? = nil
    /// When the fish starts to open. A tap brings it forward to the tap.
    @State private var exitAt: Date? = nil
    /// True from the moment it opens, so taps and VoiceOver reach the app.
    @State private var opening = false
    /// 1, or slower for a CI recording (ScreenshotSupport.launchPace).
    private let pace = ScreenshotSupport.launchPace
    /// Absorbs stalls, so launch work that holds up the main thread delays
    /// the animation instead of skipping it.
    @State private var clock = LaunchClock()

    init(onReveal: @escaping (Bool) -> Void, onFinish: @escaping () -> Void) {
        self.onReveal = onReveal
        self.onFinish = onFinish
    }

    private var tint: Color { (ThemeOption(rawValue: selectedTheme) ?? .ocean).primary }

    /// The mark in a unit box, and its outer edge alone: the solid silhouette
    /// the water fills and the window opens through.
    private static let unitMark = CurrentsMark().path(in: CGRect(x: 0, y: 0, width: 1, height: 1))
    private static let unitSilhouette = LaunchArt.outerContour(of: LaunchAnimation.unitMark)

    var body: some View {
        TimelineView(.animation) { timeline in
            let current = pose(at: clock.frame(at: timeline.date))
            let color = tint
            Canvas { context, size in
                LaunchArt.draw(current, in: &context, size: size, tint: color,
                               mark: Self.unitMark, silhouette: Self.unitSilhouette)
            }
            // Keeps the cut-out inside the overlay, so it clears the
            // overlay's own background and never the app below it.
            .compositingGroup()
            .opacity(current.alpha)
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, LaunchArt.launchScheme ?? colorScheme)
        .contentShape(Rectangle())
        .onTapGesture { skip() }
        .allowsHitTesting(!opening)
        .accessibilityElement()
        .accessibilityLabel("Currents")
        .accessibilityAddTraits(.isImage)
        .accessibilityHidden(opening)
        .onAppear { begin() }
        .task(id: exitAt) { await run() }
    }

    private func begin() {
        guard start == nil else { return }
        let now = clock.now
        start = now
        exitAt = now.addingTimeInterval((reduceMotion ? LaunchArt.stillHold : LaunchArt.openAt) * pace)
    }

    /// A tap goes straight to the opening.
    private func skip() {
        let now = clock.now
        guard !opening, let at = exitAt, at > now else { return }
        exitAt = now
    }

    /// Waits for the opening, plays it, then hands over. A tap moves
    /// `exitAt`, which cancels this run and starts a new one from the tap.
    private func run() async {
        guard let at = exitAt else { return }
        let length = (reduceMotion ? LaunchArt.fade : LaunchArt.zoom) * pace
        do {
            try await sleep(until: at)
            opening = true
            if !reduceMotion { Haptics.softPress() }
            onReveal(!reduceMotion)
            try await sleep(until: at.addingTimeInterval(length))
        } catch {
            return
        }
        onFinish()
    }

    /// Sleeps until `date` on the animation's clock, which stands still
    /// through a stall, so the hand-over keeps pace with what is on screen.
    /// It gives up six seconds late in real time, longer than any launch
    /// stall seen, so a clock with no frames can never hold the overlay over
    /// the app.
    private func sleep(until date: Date) async throws {
        let deadline = Date().addingTimeInterval(date.timeIntervalSince(clock.now) + 6)
        while true {
            let left = min(date.timeIntervalSince(clock.now), deadline.timeIntervalSinceNow)
            guard left > 0 else { return }
            try await Task.sleep(for: .seconds(left))
        }
    }

    private func pose(at date: Date) -> LaunchPose {
        var exitTime = reduceMotion ? LaunchArt.stillHold : LaunchArt.openAt
        if let start, let exitAt { exitTime = exitAt.timeIntervalSince(start) / pace }
        let time = start.map { date.timeIntervalSince($0) / pace } ?? 0
        let sinceExit = exitAt.map { date.timeIntervalSince($0) / pace } ?? -1
        return LaunchPose(time: time, sinceExit: sinceExit, exitTime: exitTime, still: reduceMotion)
    }
}

/// The animation's time: real time less the stalls. Each frame drawn moves
/// it on by the time since the last frame, but never by more than
/// `maxStep`, so when launch work holds up the main thread for a second the
/// animation picks up where it stopped instead of jumping to the end.
private final class LaunchClock {
    static let maxStep = 1.0 / 15
    private var lastFrame: Date?
    /// Real time lost to stalls so far, in seconds.
    private var lost: TimeInterval = 0

    /// Now, on the animation's clock. A stall still going on, or one the
    /// next frame has yet to record, counts as lost already.
    var now: Date {
        let date = Date()
        return date.addingTimeInterval(-lost - stalled(at: date))
    }

    /// Records a frame drawn at `date` and returns that moment on the
    /// animation's clock.
    func frame(at date: Date) -> Date {
        lost += stalled(at: date)
        lastFrame = date
        return date.addingTimeInterval(-lost)
    }

    /// How far `date` is past a frame's worth after the last frame.
    private func stalled(at date: Date) -> TimeInterval {
        guard let lastFrame else { return 0 }
        return max(0, date.timeIntervalSince(lastFrame) - Self.maxStep)
    }
}

/// Where the animation is at one moment, worked out from the animation's
/// clock alone, so a dropped frame never leaves it behind.
private struct LaunchPose {
    /// Seconds since the first frame.
    var time: Double
    /// Seconds since the fish started to open; negative before.
    var sinceExit: Double
    /// Seconds from the first frame to the opening.
    var exitTime: Double
    /// Reduce Motion: the filled mark, no waves, a fade instead of the zoom.
    var still: Bool

    /// How far the faint outline has come in over the first moment.
    var outline: Double { still ? 0 : LaunchArt.unit(time / LaunchArt.outlineIn) }
    /// The mark and its water as a whole; only Reduce Motion fades it in.
    var presence: Double { still ? LaunchArt.unit(time / LaunchArt.stillIn) : 1 }
    /// The water, from empty (0) to full (1).
    var level: Double {
        still ? 1 : LaunchArt.ease(LaunchArt.unit((time - LaunchArt.fillStart) / LaunchArt.fill))
    }
    /// The size it opens from: wherever the dip had got to.
    var baseScale: Double { still ? 1 : LaunchArt.dip(min(time, exitTime)) }
    /// How far through the zoom, on an ease-in.
    var zoom: Double {
        let p = still ? 0 : LaunchArt.unit(sinceExit / LaunchArt.zoom)
        return p * p * p
    }
    /// 0 while the inside is solid, 1 once the body is a clear window.
    var open: Double { still ? 0 : LaunchArt.unit(sinceExit / LaunchArt.open) }
    /// The whole overlay. Only Reduce Motion fades it out.
    var alpha: Double { still ? 1 - LaunchArt.unit(sinceExit / LaunchArt.fade) : 1 }
}

/// The drawing, timings and geometry. The launch art is the app's one custom
/// drawn element, so its sizes and opacities live here rather than in DS.
private enum LaunchArt {
    // Timings, in seconds from the first frame.
    static let outlineIn = 0.10
    static let fillStart = 0.10
    static let fill = 0.50
    static let dipStart = 0.60
    static let dipLength = 0.15
    static let openAt = 0.75
    static let open = 0.10
    static let zoom = 0.55
    // Reduce Motion.
    static let stillIn = 0.20
    static let stillHold = 0.50
    static let fade = 0.30

    /// The mark's size on screen before it opens.
    static let side: CGFloat = 104
    static let dipScale = 0.92
    /// The centre and radius of the largest circle that fits inside the
    /// silhouette, as fractions of the mark's box. The zoom grows around
    /// it, so the window always opens from inside the body.
    static let anchor = CGPoint(x: 0.679, y: 0.319)
    static let inscribed: CGFloat = 0.27

    /// Water level as a fraction of the box from the top, empty to full,
    /// with room for the waves to clear the tail and the head.
    static let emptyLevel = 1.08
    static let fullLevel = -0.10

    /// The style the launch screen is drawn in: Info.plist's
    /// UIUserInterfaceStyle, or nil when it follows the phone.
    static var launchScheme: ColorScheme? {
        switch Bundle.main.object(forInfoDictionaryKey: "UIUserInterfaceStyle") as? String {
        case "Dark": return ColorScheme.dark
        case "Light": return ColorScheme.light
        default: return nil
        }
    }

    /// The first contour of a path. For the mark that is the fish's outer
    /// edge, without the open body or the eye.
    static func outerContour(of path: Path) -> Path {
        var outer = Path()
        var contours = 0
        path.forEach { element in
            switch element {
            case .move(to: let p):
                contours += 1
                if contours == 1 { outer.move(to: p) }
            case .line(to: let p):
                if contours == 1 { outer.addLine(to: p) }
            case .quadCurve(to: let p, control: let c):
                if contours == 1 { outer.addQuadCurve(to: p, control: c) }
            case .curve(to: let p, control1: let c1, control2: let c2):
                if contours == 1 { outer.addCurve(to: p, control1: c1, control2: c2) }
            case .closeSubpath:
                if contours == 1 { outer.closeSubpath() }
            }
        }
        return outer
    }

    /// A few tiny bubbles that rise through the water once it reaches them:
    /// where they start (fractions of the box), when (seconds), how fast
    /// they rise (box heights a second) and their radius.
    struct Bubble {
        let x: Double
        let y: Double
        let at: Double
        let rise: Double
        let radius: Double
    }

    static let bubbles: [Bubble] = [
        Bubble(x: 0.50, y: 0.70, at: 0.32, rise: 0.80, radius: 0.014),
        Bubble(x: 0.63, y: 0.64, at: 0.37, rise: 0.95, radius: 0.010),
        Bubble(x: 0.75, y: 0.57, at: 0.42, rise: 0.85, radius: 0.016),
        Bubble(x: 0.56, y: 0.66, at: 0.49, rise: 1.05, radius: 0.009),
        Bubble(x: 0.84, y: 0.50, at: 0.46, rise: 0.90, radius: 0.012),
    ]

    static func unit(_ x: Double) -> Double { min(1, max(0, x)) }

    /// Ease in and out.
    static func ease(_ x: Double) -> Double { 0.5 - 0.5 * cos(Double.pi * x) }

    /// The anticipatory dip once the fish is full.
    static func dip(_ time: Double) -> Double {
        1 - (1 - dipScale) * ease(unit((time - dipStart) / dipLength))
    }

    /// How large the fish has to grow around its anchor before its body
    /// covers the screen: the farthest corner over the circle inside the
    /// silhouette, with some to spare. Never less than 40.
    static func coverScale(anchor point: CGPoint, size: CGSize) -> Double {
        let dx = max(point.x, size.width - point.x)
        let dy = max(point.y, size.height - point.y)
        let reach = (dx * dx + dy * dy).squareRoot()
        return max(40, Double(reach / (inscribed * side)) * 1.2)
    }

    /// One frame. `mark` and `silhouette` are in a unit box.
    static func draw(_ pose: LaunchPose, in context: inout GraphicsContext, size: CGSize, tint: Color,
                     mark: Path, silhouette: Path) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.dsBackground))

        // The mark's box, centred, then grown around the anchor.
        let base = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
        let pivot = CGPoint(x: base.minX + anchor.x * side, y: base.minY + anchor.y * side)
        let target = coverScale(anchor: pivot, size: size)
        let scale = CGFloat(pose.baseScale + (target - pose.baseScale) * pose.zoom)
        let length = side * scale
        let box = CGRect(x: pivot.x - anchor.x * length, y: pivot.y - anchor.y * length,
                         width: length, height: length)
        let place = CGAffineTransform(a: length, b: 0, c: 0, d: length, tx: box.minX, ty: box.minY)
        let markPath = mark.applying(place)
        let body = silhouette.applying(place)

        if pose.open < 1 {
            drawFish(pose, in: &context, box: box, mark: markPath, body: body, tint: tint)
        }
        if pose.open > 0 {
            // Clears the body, water and all, so the app shows through.
            var cut = context
            cut.blendMode = .destinationOut
            cut.fill(body, with: .color(Color.black.opacity(pose.open)))
        }
    }

    private static func drawFish(_ pose: LaunchPose, in context: inout GraphicsContext, box: CGRect,
                                 mark: Path, body: Path, tint: Color) {
        let presence = pose.presence
        let eoFill = FillStyle(eoFill: true)

        // The faint outline it starts as.
        if pose.outline > 0 {
            context.fill(mark, with: .color(tint.opacity(0.24 * pose.outline)), style: eoFill)
        }

        // Two layered waves rising through the silhouette, the back one paler
        // and a little higher so it shows above the front. They drift the
        // same way at slightly different speeds.
        let t = pose.time
        let swell = pose.still ? 0.0 : 1.0
        let waterline = emptyLevel + (fullLevel - emptyLevel) * pose.level
        let backSurface = surface(in: box, level: waterline - 0.03, amplitude: 0.040 * swell,
                                  length: 0.78, phase: 1.9 - 2 * Double.pi * t * 0.55 / 0.78)
        let frontSurface = surface(in: box, level: waterline, amplitude: 0.032 * swell,
                                   length: 0.62, phase: -2 * Double.pi * t * 0.75 / 0.62)
        let front = water(below: frontSurface, in: box)
        var inside = context
        inside.clip(to: body)
        inside.fill(water(below: backSurface, in: box), with: .color(tint.opacity(0.22 * presence)))
        inside.fill(front, with: .color(tint.opacity(0.36 * presence)))

        // Under the water the mark itself fills in at full strength.
        var under = inside
        under.clip(to: front)
        under.fill(mark, with: .color(tint.opacity(presence)), style: eoFill)

        guard !pose.still else { return }
        // A fine bright line along the front surface, so it reads as water.
        inside.stroke(frontSurface, with: .color(tint.opacity(0.85)), lineWidth: 1.25)
        for bubble in bubbles where t > bubble.at {
            let age = t - bubble.at
            let x = bubble.x + 0.012 * sin(age * 11 + bubble.x * 20)
            let y = bubble.y - bubble.rise * age
            let r = CGFloat(bubble.radius) * box.width
            let centre = CGPoint(x: box.minX + CGFloat(x) * box.width, y: box.minY + CGFloat(y) * box.height)
            let dot = Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2))
            // White reads as a highlight on every theme colour.
            under.fill(dot, with: .color(Color.white.opacity(0.4 * unit(age / 0.08))))
        }
    }

    /// A sine surface across the box and a little past it. Level, amplitude
    /// and wavelength are fractions of the box; the phase moves it along.
    private static func surface(in box: CGRect, level: Double, amplitude: Double,
                                length: Double, phase: Double) -> Path {
        var path = Path()
        let steps = 40
        for i in 0...steps {
            let u = -0.1 + 1.2 * Double(i) / Double(steps)
            let v = level + amplitude * sin(2 * Double.pi * u / length + phase)
            let point = CGPoint(x: box.minX + CGFloat(u) * box.width, y: box.minY + CGFloat(v) * box.height)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }

    /// Everything below a surface, down past the bottom of the box.
    private static func water(below surface: Path, in box: CGRect) -> Path {
        var path = surface
        path.addLine(to: CGPoint(x: box.minX + 1.1 * box.width, y: box.maxY + 0.2 * box.height))
        path.addLine(to: CGPoint(x: box.minX - 0.1 * box.width, y: box.maxY + 0.2 * box.height))
        path.closeSubpath()
        return path
    }
}

#Preview {
    LaunchAnimation(onReveal: { _ in }, onFinish: {})
}
