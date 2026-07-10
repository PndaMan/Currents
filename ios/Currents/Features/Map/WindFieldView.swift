import UIKit
import CoreLocation

/// Windy-style animated flow field drawn over the map. Thousands of particles
/// stream along a vector (wind, or a wind-driven surface-drift approximation
/// for "current"), leaving fading trails. Uses the classic accumulation-buffer
/// technique — advect particles, draw short segments into an offscreen bitmap,
/// and fade the whole buffer a little each frame — so it's smooth at 30fps
/// without Metal. The view is non-interactive; map gestures pass straight
/// through.
final class WindFieldView: UIView {

    // MARK: Public inputs (set by the map coordinator)

    /// Wind the field represents: speed (km/h) and the bearing it blows FROM
    /// (meteorological). Nil speed pauses the animation.
    var windSpeedKmh: Double? { didSet { restartIfNeeded() } }
    var windFromDeg: Double = 0
    /// Map heading (deg clockwise from north that screen-up points to), so the
    /// flow rotates with the map.
    var mapHeading: Double = 0

    /// "current" mode uses a slower, deflected surface-drift vector and a
    /// distinct tint.
    enum Mode { case wind, current }
    var mode: Mode = .wind

    var tint: UIColor = .white

    // MARK: Private

    private struct Particle { var x: CGFloat; var y: CGFloat; var px: CGFloat; var py: CGFloat; var age: CGFloat; var life: CGFloat }
    private var particles: [Particle] = []
    private var link: CADisplayLink?
    private var buffer: CGContext?
    private var lastSize: CGSize = .zero
    private let particleCount = 480

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        layer.drawsAsynchronously = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: Lifecycle

    func startIfActive() {
        guard windSpeedKmh != nil, window != nil else { stop(); return }
        guard link == nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(tick))
        l.preferredFramesPerSecond = 30
        l.add(to: .main, forMode: .common)
        link = l
    }

    func stop() {
        link?.invalidate()
        link = nil
        particles.removeAll()
        buffer = nil
        layer.contents = nil
    }

    private func restartIfNeeded() {
        if windSpeedKmh == nil { stop() } else { startIfActive() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stop() } else { startIfActive() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastSize { buffer = nil }
    }

    // MARK: Velocity

    /// Screen-space velocity in points/second, rotation-adjusted.
    private var screenVelocity: CGVector {
        guard let kmh = windSpeedKmh else { return .zero }
        // Surface drift ≈ a few % of wind speed, deflected ~45°; slower + turned.
        let deflect: Double = mode == .current ? 45 : 0
        let scale: Double = mode == .current ? 0.5 : 1.0
        // Bearing the flow moves TOWARD (deg clockwise from north).
        let toBearing = windFromDeg + 180 + deflect
        // On-screen angle clockwise from up.
        let theta = (toBearing - mapHeading) * .pi / 180
        // Map km/h to a pleasant on-screen speed; clamp so gales don't blur.
        let ptsPerSec = min(max(kmh, 2) * 2.4, 190) * scale
        return CGVector(dx: sin(theta) * ptsPerSec, dy: -cos(theta) * ptsPerSec)
    }

    // MARK: Frame

    private func ensureBuffer() {
        guard bounds.width > 1, bounds.height > 1 else { return }
        if buffer == nil || bounds.size != lastSize {
            lastSize = bounds.size
            let s = UIScreen.main.scale
            let w = Int(bounds.width * s), h = Int(bounds.height * s)
            guard w > 0, h > 0 else { return }
            let ctx = CGContext(
                data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            // Flip to UIKit's top-left origin so the flow direction is correct.
            ctx?.translateBy(x: 0, y: CGFloat(h))
            ctx?.scaleBy(x: s, y: -s)
            ctx?.setLineCap(.round)
            buffer = ctx
            seed()
        }
        if particles.isEmpty { seed() }
    }

    private func seed() {
        particles = (0..<particleCount).map { _ in spawn() }
    }
    private func spawn() -> Particle {
        let x = CGFloat.random(in: 0...max(1, bounds.width))
        let y = CGFloat.random(in: 0...max(1, bounds.height))
        return Particle(x: x, y: y, px: x, py: y, age: 0, life: CGFloat.random(in: 45...120))
    }

    @objc private func tick() {
        ensureBuffer()
        guard let ctx = buffer else { return }

        // Fade the accumulation buffer toward transparent (trail decay).
        ctx.setBlendMode(.destinationIn)
        ctx.setFillColor(UIColor(white: 1, alpha: 0.90).cgColor)
        ctx.fill(bounds)
        ctx.setBlendMode(.normal)

        let v = screenVelocity
        let dt: CGFloat = 1.0 / 30.0
        ctx.setLineWidth(mode == .current ? 1.4 : 1.1)

        for i in particles.indices {
            var p = particles[i]
            p.px = p.x
            p.py = p.y
            let jx = CGFloat.random(in: -6...6)
            let jy = CGFloat.random(in: -6...6)
            p.x += (v.dx + jx) * dt
            p.y += (v.dy + jy) * dt
            p.age += 1

            let a = max(0, 1 - p.age / p.life) * 0.85
            ctx.setStrokeColor(tint.withAlphaComponent(a).cgColor)
            ctx.move(to: CGPoint(x: p.px, y: p.py))
            ctx.addLine(to: CGPoint(x: p.x, y: p.y))
            ctx.strokePath()

            if p.age >= p.life || p.x < -2 || p.x > bounds.width + 2 || p.y < -2 || p.y > bounds.height + 2 {
                p = spawn()
            }
            particles[i] = p
        }

        if let img = ctx.makeImage() {
            layer.contents = img
        }
    }
}
