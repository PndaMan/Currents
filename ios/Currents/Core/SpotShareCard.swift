import SwiftUI
import MapKit

/// Generates a shareable image card for a saved spot — a map-hero version of
/// the catch share card (a spot has no photo, so the map IS the hero).
@MainActor
enum SpotShareCard {

    /// A universal Apple Maps link that drops a pin at exactly this spot.
    /// Opens in Apple Maps on iOS and the web elsewhere — ideal as the caption
    /// when the image is shared to WhatsApp, Messages, etc.
    static func mapsLink(for spot: Spot) -> String {
        let name = spot.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Spot"
        return "https://maps.apple.com/?ll=\(spot.latitude),\(spot.longitude)&q=\(name)"
    }

    /// The caption text attached alongside the image when sharing.
    static func caption(for spot: Spot) -> String {
        "\(spot.name) — my fishing spot on Currents 🎣\n\(mapsLink(for: spot))"
    }

    /// Render a shareable spot card (1080×1350 — Instagram 4:5).
    static func render(spot: Spot, catchCount: Int, biteScore: Int?) async -> UIImage? {
        let cardWidth: CGFloat = 1080
        let cardHeight: CGFloat = 1350

        let coordinate = CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude)
        let snapshot = await captureMapSnapshot(
            coordinate: coordinate,
            size: CGSize(width: cardWidth, height: cardHeight)
        )

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: cardWidth, height: cardHeight))
        return renderer.image { ctx in
            let rect = CGRect(x: 0, y: 0, width: cardWidth, height: cardHeight)
            let cg = ctx.cgContext

            // 1. Full-bleed map background (or a solid fallback offline).
            if let snapshot {
                snapshot.image.draw(in: rect)
            } else {
                UIColor(red: 0.05, green: 0.12, blue: 0.20, alpha: 1).setFill()
                cg.fill(rect)
            }

            // 2. Bottom + top gradients for legibility.
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor.clear.cgColor,
                    UIColor.black.withAlphaComponent(0.35).cgColor,
                    UIColor.black.withAlphaComponent(0.88).cgColor,
                ] as CFArray,
                locations: [0.0, 0.5, 1.0]
            ) {
                cg.drawLinearGradient(gradient,
                    start: CGPoint(x: 0, y: cardHeight * 0.35),
                    end: CGPoint(x: 0, y: cardHeight), options: [])
            }
            if let topGradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [UIColor.black.withAlphaComponent(0.5).cgColor, UIColor.clear.cgColor] as CFArray,
                locations: [0.0, 1.0]
            ) {
                cg.drawLinearGradient(topGradient,
                    start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: 160), options: [])
            }

            // 3. Watermark (top-left).
            drawWatermark(in: cg)

            // 4. Pin at the exact spot coordinate.
            if let snapshot {
                let p = snapshot.point(for: coordinate)
                let pinSize: CGFloat = 88
                let pinRect = CGRect(x: p.x - pinSize / 2, y: p.y - pinSize, width: pinSize, height: pinSize)
                let cfg = UIImage.SymbolConfiguration(pointSize: pinSize, weight: .bold)
                if let pin = UIImage(systemName: "mappin.circle.fill", withConfiguration: cfg) {
                    pin.withTintColor(UIColor(CurrentsTheme.accent), renderingMode: .alwaysOriginal).draw(in: pinRect)
                }
            }

            // 5. Info block bottom-left.
            drawInfo(in: cg, spot: spot, catchCount: catchCount, biteScore: biteScore,
                     origin: CGPoint(x: 60, y: cardHeight - 300), width: cardWidth - 120)
        }
    }

    // MARK: - Drawing helpers

    private static func drawWatermark(in ctx: CGContext) {
        if let logo = UIImage(named: "Logo") {
            logo.draw(in: CGRect(x: 40, y: 40, width: 60, height: 60))
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 40, weight: .semibold),
            .foregroundColor: UIColor.white.withAlphaComponent(0.92),
        ]
        ("Currents" as NSString).draw(at: CGPoint(x: 112, y: 48), withAttributes: attrs)
    }

    private static func drawInfo(
        in ctx: CGContext, spot: Spot, catchCount: Int, biteScore: Int?,
        origin: CGPoint, width: CGFloat
    ) {
        var y = origin.y

        ("\(spot.name)" as NSString).draw(
            in: CGRect(x: origin.x, y: y, width: width, height: 120),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 56, weight: .bold),
                .foregroundColor: UIColor.white,
            ]
        )
        y += 74

        // Coordinates
        let coords = String(format: "%.4f, %.4f", spot.latitude, spot.longitude)
        (coords as NSString).draw(at: CGPoint(x: origin.x, y: y), withAttributes: [
            .font: UIFont.monospacedSystemFont(ofSize: 24, weight: .regular),
            .foregroundColor: UIColor.white.withAlphaComponent(0.7),
        ])
        y += 44

        // Stat chips row
        var items: [String] = []
        if spot.type != .general { items.append(spot.type.rawValue) }
        items.append(catchCount == 1 ? "1 catch" : "\(catchCount) catches")
        if let biteScore { items.append("Bite \(biteScore)") }
        (items.joined(separator: "  •  ") as NSString).draw(
            at: CGPoint(x: origin.x, y: y),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 26, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.9),
            ]
        )
    }

    // MARK: - Map snapshot

    private static func captureMapSnapshot(
        coordinate: CLLocationCoordinate2D, size: CGSize
    ) async -> MKMapSnapshotter.Snapshot? {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: coordinate, latitudinalMeters: 1400, longitudinalMeters: 1400
        )
        options.size = size
        options.mapType = .hybrid
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        return try? await MKMapSnapshotter(options: options).start()
    }
}
