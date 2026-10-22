import SwiftUI
import UIKit
import MapKit

// MARK: - Frame

/// The UIKit twin of `CatchPhotoCard` for the offline map's MKMapView: the
/// catch's photo (or species art) inside a white rounded frame. Uses the same
/// metrics and photo cache as the SwiftUI pin.
final class CatchPinCardView: UIView {
    private let face = UIView()
    private let tintView = UIView()
    private let artView = UIImageView()
    private let photoView = UIImageView()
    private var path: String?
    private var loadTask: Task<Void, Never>?

    override init(frame: CGRect) {
        let edge = CatchPinMetrics.card
        super.init(frame: CGRect(x: 0, y: 0, width: edge, height: edge))
        backgroundColor = .white
        layer.cornerRadius = CatchPinMetrics.radius
        layer.cornerCurve = .continuous

        let inset = CatchPinMetrics.border
        face.frame = bounds.insetBy(dx: inset, dy: inset)
        face.layer.cornerRadius = CatchPinMetrics.photoRadius
        face.layer.cornerCurve = .continuous
        face.clipsToBounds = true
        face.backgroundColor = UIColor(Color.dsBackground)
        addSubview(face)

        tintView.frame = face.bounds
        artView.contentMode = .scaleAspectFit
        photoView.frame = face.bounds
        photoView.contentMode = .scaleAspectFill
        photoView.clipsToBounds = true
        face.addSubview(tintView)
        face.addSubview(artView)
        face.addSubview(photoView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Species art drawn at 92 percent of the frame, centred then nudged
    /// right 4 percent, as `SpeciesThumbArt` draws it.
    private var artFrame: CGRect {
        let s = face.bounds.width
        return CGRect(x: s * 0.08, y: s * 0.04, width: s * 0.92, height: s * 0.92)
    }

    private var symbolFrame: CGRect {
        let s = face.bounds.width
        return CGRect(x: s * 0.3, y: s * 0.3, width: s * 0.4, height: s * 0.4)
    }

    func configure(_ detail: CatchDetail) {
        let tint = UIColor(detail.species?.artTint ?? DS.accent)
        tintView.backgroundColor = UIColor { traits in
            tint.resolvedColor(with: traits)
                .withAlphaComponent(DS.thumbTintOpacity(traits.userInterfaceStyle == .dark ? .dark : .light))
        }
        if let species = detail.species, let art = UIImage(named: species.artworkAssetName) {
            artView.image = art
            artView.frame = artFrame
        } else {
            artView.image = UIImage(systemName: "fish.fill")
            artView.tintColor = tint
            artView.frame = symbolFrame
        }

        let newPath = CatchPinPhotos.path(for: detail.catchRecord)
        guard newPath != path || photoView.image == nil else { return }
        path = newPath
        loadTask?.cancel()
        photoView.image = newPath.flatMap { CatchPinPhotos.cached($0) }
        guard let newPath, photoView.image == nil else { return }
        loadTask = Task { [weak self] in
            let image = await CatchPinPhotos.load(newPath)
            guard let self, !Task.isCancelled, self.path == newPath, let image else { return }
            UIView.transition(with: self.photoView, duration: DS.Motion.fast,
                              options: [.transitionCrossDissolve, .allowUserInteraction],
                              animations: { self.photoView.image = image },
                              completion: nil)
        }
    }

    func reset() {
        loadTask?.cancel()
        loadTask = nil
        path = nil
        photoView.image = nil
    }
}

// MARK: - Shared chrome

enum CatchPinChrome {
    /// The pointer under a frame whose top left corner is at the origin.
    static func pointerPath() -> UIBezierPath {
        let m = CatchPinMetrics.self
        let top = m.card - m.pointerOverlap
        let mid = m.card / 2
        let half = m.pointerWidth / 2
        let tip = m.pointerWidth * 0.12
        let bottom = top + m.pointerHeight
        let p = UIBezierPath()
        p.move(to: CGPoint(x: mid - half, y: top))
        p.addLine(to: CGPoint(x: mid + half, y: top))
        p.addLine(to: CGPoint(x: mid + tip, y: bottom - tip))
        p.addQuadCurve(to: CGPoint(x: mid - tip, y: bottom - tip), controlPoint: CGPoint(x: mid, y: bottom))
        p.close()
        return p
    }

    /// The same lift as `mapPinShadow()`, drawn from a fixed path so MapKit
    /// does not render it offscreen for every pin.
    static func applyShadow(to layer: CALayer, path: CGPath) {
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowPath = path
        layer.masksToBounds = false
    }

    static func framePath() -> UIBezierPath {
        let edge = CatchPinMetrics.card
        return UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: edge, height: edge),
                            cornerRadius: CatchPinMetrics.radius)
    }

    /// Lifts catch pins above water and spot markers when they collide, since
    /// the angler switched the catches layer on to see them.
    static let displayPriority = MKFeatureDisplayPriority(rawValue: MKFeatureDisplayPriority.defaultHigh.rawValue + 10)
    static let clusteringIdentifier = "catches"
}

/// A frame with its pointer, casting one shadow: the single pin, and the top
/// of a stack.
final class CatchPinFrameView: UIView {
    let card = CatchPinCardView()
    private let pointer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: CatchPinMetrics.card, height: CatchPinMetrics.height))
        backgroundColor = .clear
        pointer.path = CatchPinChrome.pointerPath().cgPath
        pointer.fillColor = UIColor.white.cgColor
        layer.addSublayer(pointer)
        addSubview(card)
        let outline = CatchPinChrome.framePath()
        outline.append(CatchPinChrome.pointerPath())
        CatchPinChrome.applyShadow(to: layer, path: outline.cgPath)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Badge

/// The stack's count: primary button colours, ringed in the background
/// colour so it separates from the white frame in both themes.
final class CatchPinBadgeView: UIView {
    private let fill = UIView()
    private let label = UILabel()
    private let ring: CGFloat = 1.5

    override init(frame: CGRect) {
        super.init(frame: .zero)
        backgroundColor = UIColor(Color.dsBackground)
        fill.backgroundColor = UIColor(Color.dsPrimaryButton)
        label.textColor = UIColor(Color.dsOnPrimary)
        let base = UIFont.preferredFont(forTextStyle: .caption2,
                                        compatibleWith: UITraitCollection(preferredContentSizeCategory: .large))
        label.font = UIFontMetrics(forTextStyle: .caption2)
            .scaledFont(for: .monospacedDigitSystemFont(ofSize: base.pointSize, weight: .bold))
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        addSubview(fill)
        fill.addSubview(label)
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func set(count: Int) {
        label.text = CatchPinText.badge(count)
        setNeedsLayout()
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let text = label.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        let height = max(CatchPinMetrics.badgeHeight, text.height + 4)
        return CGSize(width: max(height, text.width + 12 + ring * 2), height: height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        fill.frame = bounds.insetBy(dx: ring, dy: ring)
        fill.layer.cornerRadius = fill.bounds.height / 2
        label.frame = fill.bounds
    }
}

// MARK: - Annotation views

/// A single catch on the offline map: photo in a white frame with a pointer
/// whose tip sits on the catch.
final class CatchPhotoAnnotationView: MKAnnotationView {
    static let reuseID = "catchPhoto"
    private let pin = CatchPinFrameView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = pin.frame
        centerOffset = CGPoint(x: 0, y: -pin.frame.height / 2)
        backgroundColor = .clear
        addSubview(pin)
        clusteringIdentifier = CatchPinChrome.clusteringIdentifier
        collisionMode = .rectangle
        displayPriority = CatchPinChrome.displayPriority
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        pin.card.reset()
    }

    override func prepareForDisplay() {
        super.prepareForDisplay()
        clusteringIdentifier = CatchPinChrome.clusteringIdentifier
        guard let detail = (annotation as? OfflineMapView.CatchAnnotation)?.detail else { return }
        pin.card.configure(detail)
        accessibilityLabel = CatchPinText.label(detail)
    }
}

/// Catches merged on zoom out: the top photo with one or two more fanned
/// behind it and a count badge. MapKit animates pins gliding into and out of
/// the stack; the fan opens with a spring when a stack forms. Reduce Motion
/// shows it open and still.
final class CatchStackAnnotationView: MKAnnotationView {
    static let reuseID = "catchStack"
    private let top = CatchPinFrameView()
    /// Behind the top photo, nearest first.
    private let behind = [CatchPinCardView(), CatchPinCardView()]
    private let badge = CatchPinBadgeView()
    private var shownKey = ""

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = top.frame
        centerOffset = CGPoint(x: 0, y: -top.frame.height / 2)
        backgroundColor = .clear
        // Farthest back first.
        for card in behind.reversed() {
            CatchPinChrome.applyShadow(to: card.layer, path: CatchPinChrome.framePath().cgPath)
            addSubview(card)
        }
        addSubview(top)
        addSubview(badge)
        collisionMode = .rectangle
        displayPriority = CatchPinChrome.displayPriority
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityHint = "Zooms in"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        top.card.reset()
        behind.forEach { $0.reset() }
        shownKey = ""
    }

    override func prepareForDisplay() {
        super.prepareForDisplay()
        guard let cluster = annotation as? MKClusterAnnotation else { return }
        let all = cluster.memberAnnotations
            .compactMap { ($0 as? OfflineMapView.CatchAnnotation)?.detail }
            .sorted { $0.catchRecord.caughtAt > $1.catchRecord.caughtAt }
        let shown = CatchPinPhotos.stackTop(all)
        guard let first = shown.first else { return }

        top.card.configure(first)
        for (i, card) in behind.enumerated() {
            if i + 1 < shown.count {
                card.isHidden = false
                card.configure(shown[i + 1])
            } else {
                card.isHidden = true
                card.reset()
            }
        }
        badge.set(count: all.count)
        accessibilityLabel = CatchPinText.stack(all.count)
        accessibilityHint = PinClustering.spread(all) < PinClustering.stackMetres ? "Lists these catches" : "Zooms in"
        setNeedsLayout()

        // Open the fan when this view shows a new stack, not on every redraw.
        let key = shown.map(\.id).joined(separator: ",") + "#\(all.count)"
        let isNew = key != shownKey
        shownKey = key
        fan(animated: isNew && !UIAccessibility.isReduceMotionEnabled)
    }

    private func fanTransform(_ index: Int) -> CGAffineTransform {
        let f = CatchPinMetrics.fan[index]
        return CGAffineTransform(translationX: f.x, y: f.y).rotated(by: CGFloat(f.angle) * .pi / 180)
    }

    private func fan(animated: Bool) {
        let open: () -> Void = { [weak self] in
            guard let self else { return }
            for (i, card) in self.behind.enumerated() { card.transform = self.fanTransform(i + 1) }
            self.badge.alpha = 1
        }
        guard animated else { open(); return }
        behind.forEach { $0.transform = .identity }
        badge.alpha = 0
        UIView.animate(withDuration: DS.Motion.slow, delay: 0,
                       usingSpringWithDamping: 0.7, initialSpringVelocity: 0,
                       options: [.allowUserInteraction, .beginFromCurrentState],
                       animations: open, completion: nil)
    }

    /// The badge hangs past the frame's corner; taps on it still count.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        super.point(inside: point, with: event) || badge.frame.contains(point)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let edge = CatchPinMetrics.card
        for card in behind {
            // Position through bounds and center so the fan transform turns
            // each card about its middle.
            card.bounds = CGRect(x: 0, y: 0, width: edge, height: edge)
            card.center = CGPoint(x: edge / 2, y: edge / 2)
        }
        top.frame.origin = .zero
        let size = badge.sizeThatFits(.zero)
        badge.frame = CGRect(x: edge + CatchPinMetrics.badgeOffset - size.width,
                             y: -CatchPinMetrics.badgeOffset,
                             width: size.width, height: size.height)
    }
}
