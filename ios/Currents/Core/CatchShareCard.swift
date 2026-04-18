import SwiftUI
import MapKit

/// Generates a Strava-style shareable image card from a catch.
@MainActor
enum CatchShareCard {

    /// Render a shareable catch card image (1080×1350 — Instagram 4:5).
    static func render(detail: CatchDetail, photo: UIImage) async -> UIImage? {
        let cardWidth: CGFloat = 1080
        let cardHeight: CGFloat = 1350
        let mapSize: CGFloat = 240

        // Get a map snapshot — square, zoomed in tight
        let mapSnapshot = await captureMapSnapshot(
            latitude: detail.catchRecord.latitude,
            longitude: detail.catchRecord.longitude,
            size: CGSize(width: mapSize * 2, height: mapSize * 2)
        )

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: cardWidth, height: cardHeight))
        return renderer.image { ctx in
            let rect = CGRect(x: 0, y: 0, width: cardWidth, height: cardHeight)
            let cgCtx = ctx.cgContext

            // 1. Draw catch photo as full-bleed background
            photo.draw(in: rect)

            // 2. Dark gradient overlay from bottom for text legibility
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor.clear.cgColor,
                    UIColor.black.withAlphaComponent(0.3).cgColor,
                    UIColor.black.withAlphaComponent(0.85).cgColor,
                ] as CFArray,
                locations: [0.0, 0.45, 1.0]
            )!
            cgCtx.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: cardHeight * 0.3),
                end: CGPoint(x: 0, y: cardHeight),
                options: []
            )

            // Also a subtle top gradient for watermark
            let topGradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor.black.withAlphaComponent(0.5).cgColor,
                    UIColor.clear.cgColor,
                ] as CFArray,
                locations: [0.0, 1.0]
            )!
            cgCtx.drawLinearGradient(
                topGradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: 0, y: 140),
                options: []
            )

            // 3. App logo watermark (top-left) — 1.5x bigger
            drawWatermark(in: cgCtx, rect: rect)

            // 4. Map square (bottom-right corner)
            let mapMargin: CGFloat = 40
            let mapRect = CGRect(
                x: cardWidth - mapSize - mapMargin,
                y: cardHeight - mapSize - mapMargin,
                width: mapSize,
                height: mapSize
            )
            if let mapSnapshot {
                let mapPath = UIBezierPath(roundedRect: mapRect, cornerRadius: 20)
                cgCtx.saveGState()
                mapPath.addClip()
                mapSnapshot.draw(in: mapRect)
                cgCtx.restoreGState()

                // Map border
                UIColor.white.withAlphaComponent(0.4).setStroke()
                mapPath.lineWidth = 3
                mapPath.stroke()

                // Pin icon in center of map
                let pinSize: CGFloat = 32
                let pinRect = CGRect(
                    x: mapRect.midX - pinSize / 2,
                    y: mapRect.midY - pinSize,
                    width: pinSize,
                    height: pinSize
                )
                let pinConfig = UIImage.SymbolConfiguration(pointSize: pinSize, weight: .bold)
                if let pinImage = UIImage(systemName: "mappin.circle.fill", withConfiguration: pinConfig) {
                    pinImage.withTintColor(UIColor(CurrentsTheme.accent), renderingMode: .alwaysOriginal).draw(in: pinRect)
                }
            }

            // 5. Info overlay at bottom-left (alongside map)
            let infoWidth = cardWidth - mapSize - mapMargin * 2 - 20
            let infoY = cardHeight - 340
            drawInfoSection(
                in: cgCtx,
                detail: detail,
                at: CGPoint(x: 40, y: infoY),
                width: infoWidth
            )
        }
    }

    // MARK: - Drawing Helpers

    private static func drawWatermark(in ctx: CGContext, rect: CGRect) {
        if let logoImage = UIImage(named: "Logo") {
            let logoSize: CGFloat = 60
            let logoRect = CGRect(x: 36, y: 36, width: logoSize, height: logoSize)
            logoImage.draw(in: logoRect)

            let wordmark = "Currents"
            let wordmarkAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 40, weight: .semibold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.9),
            ]
            let wordmarkPoint = CGPoint(x: 108, y: 44)
            (wordmark as NSString).draw(at: wordmarkPoint, withAttributes: wordmarkAttrs)
        }
    }

    private static func drawInfoSection(
        in ctx: CGContext,
        detail: CatchDetail,
        at origin: CGPoint,
        width: CGFloat
    ) {
        var y = origin.y

        // Species name (large)
        let speciesName = detail.species?.commonName ?? "Unknown Species"
        let speciesAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 48, weight: .bold),
            .foregroundColor: UIColor.white,
        ]
        (speciesName as NSString).draw(
            in: CGRect(x: origin.x, y: y, width: width, height: 60),
            withAttributes: speciesAttrs
        )
        y += 62

        // Scientific name
        if let sciName = detail.species?.scientificName {
            let sciAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.italicSystemFont(ofSize: 22),
                .foregroundColor: UIColor.white.withAlphaComponent(0.7),
            ]
            (sciName as NSString).draw(at: CGPoint(x: origin.x, y: y), withAttributes: sciAttrs)
            y += 30
        }

        y += 16

        // Stats row: weight, length, released
        var statsItems: [String] = []
        if let weight = detail.catchRecord.weightKg {
            statsItems.append(String(format: "%.2f kg", weight))
        }
        if let length = detail.catchRecord.lengthCm {
            statsItems.append(String(format: "%.0f cm", length))
        }
        if detail.catchRecord.released {
            statsItems.append("Released")
        }

        // Location
        if let spot = detail.spot {
            statsItems.append(spot.name)
        }

        if !statsItems.isEmpty {
            let statsText = statsItems.joined(separator: "  •  ")
            let statsAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.85),
            ]
            (statsText as NSString).draw(
                in: CGRect(x: origin.x, y: y, width: width, height: 60),
                withAttributes: statsAttrs
            )
            y += 36
        }

        // Forecast score badge
        if let score = detail.catchRecord.forecastScoreAtCapture {
            let badgeRect = CGRect(x: origin.x, y: y, width: 200, height: 48)
            let badgePath = UIBezierPath(roundedRect: badgeRect, cornerRadius: 24)
            scoreUIColor(score).withAlphaComponent(0.9).setFill()
            badgePath.fill()

            let scoreText = "Bite Score: \(score)"
            let scoreAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .bold),
                .foregroundColor: UIColor.white,
            ]
            let scoreSize = (scoreText as NSString).size(withAttributes: scoreAttrs)
            let scorePoint = CGPoint(
                x: badgeRect.midX - scoreSize.width / 2,
                y: badgeRect.midY - scoreSize.height / 2
            )
            (scoreText as NSString).draw(at: scorePoint, withAttributes: scoreAttrs)

            y += 56
        }

        // Date
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        let dateText = formatter.string(from: detail.catchRecord.caughtAt)
        let dateAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 18, weight: .regular),
            .foregroundColor: UIColor.white.withAlphaComponent(0.6),
        ]
        (dateText as NSString).draw(at: CGPoint(x: origin.x, y: y), withAttributes: dateAttrs)
    }

    private static func scoreUIColor(_ score: Int) -> UIColor {
        UIColor(CurrentsTheme.scoreColor(score))
    }

    // MARK: - Map Snapshot

    private static func captureMapSnapshot(
        latitude: Double,
        longitude: Double,
        size: CGSize
    ) async -> UIImage? {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            latitudinalMeters: 500,
            longitudinalMeters: 500
        )
        options.size = size
        options.mapType = .hybrid
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)

        let snapshotter = MKMapSnapshotter(options: options)
        return try? await snapshotter.start().image
    }
}
