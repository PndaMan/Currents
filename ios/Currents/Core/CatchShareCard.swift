import SwiftUI
import MapKit

/// Generates a Strava-style shareable image card from a catch.
@MainActor
enum CatchShareCard {

    /// Render a shareable catch card image (1080×1350 — Instagram 4:5).
    static func render(detail: CatchDetail, photo: UIImage) async -> UIImage? {
        let cardWidth: CGFloat = 1080
        let cardHeight: CGFloat = 1350

        // Get a map snapshot for the location strip
        let mapSnapshot = await captureMapSnapshot(
            latitude: detail.catchRecord.latitude,
            longitude: detail.catchRecord.longitude,
            size: CGSize(width: cardWidth, height: 200)
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
                end: CGPoint(x: 0, y: 120),
                options: []
            )

            // 3. App logo watermark (top-left)
            drawWatermark(in: cgCtx, rect: rect)

            // 4. Map strip (bottom area, above info)
            let mapY = cardHeight - 460
            if let mapSnapshot {
                let mapRect = CGRect(x: 40, y: mapY, width: cardWidth - 80, height: 160)
                // Rounded rect clip
                let mapPath = UIBezierPath(roundedRect: mapRect, cornerRadius: 16)
                cgCtx.saveGState()
                mapPath.addClip()
                mapSnapshot.draw(in: mapRect)
                cgCtx.restoreGState()

                // Map border
                UIColor.white.withAlphaComponent(0.3).setStroke()
                mapPath.lineWidth = 2
                mapPath.stroke()

                // Pin icon in center of map
                let pinRect = CGRect(x: mapRect.midX - 12, y: mapRect.midY - 24, width: 24, height: 24)
                let pinConfig = UIImage.SymbolConfiguration(pointSize: 24, weight: .bold)
                if let pinImage = UIImage(systemName: "mappin.circle.fill", withConfiguration: pinConfig) {
                    UIColor.red.setFill()
                    pinImage.withTintColor(.red, renderingMode: .alwaysOriginal).draw(in: pinRect)
                }
            }

            // 5. Info overlay at bottom
            let infoY = cardHeight - 280
            drawInfoSection(
                in: cgCtx,
                detail: detail,
                at: CGPoint(x: 40, y: infoY),
                width: cardWidth - 80
            )
        }
    }

    // MARK: - Drawing Helpers

    private static func drawWatermark(in ctx: CGContext, rect: CGRect) {
        // Draw logo image
        if let logoImage = UIImage(named: "Logo") {
            let logoSize: CGFloat = 40
            let logoRect = CGRect(x: 32, y: 32, width: logoSize, height: logoSize)
            logoImage.draw(in: logoRect)

            // Draw "Currents" text next to logo
            let wordmark = "Currents"
            let wordmarkAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 26, weight: .semibold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.9),
            ]
            let wordmarkPoint = CGPoint(x: 82, y: 37)
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
                in: CGRect(x: origin.x, y: y, width: width, height: 30),
                withAttributes: statsAttrs
            )
            y += 36
        }

        // Forecast score badge
        if let score = detail.catchRecord.forecastScoreAtCapture {
            let badgeRect = CGRect(x: origin.x, y: y, width: 180, height: 44)
            let badgePath = UIBezierPath(roundedRect: badgeRect, cornerRadius: 22)
            scoreUIColor(score).withAlphaComponent(0.9).setFill()
            badgePath.fill()

            let scoreText = "Bite Score: \(score)"
            let scoreAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 20, weight: .bold),
                .foregroundColor: UIColor.white,
            ]
            let scoreSize = (scoreText as NSString).size(withAttributes: scoreAttrs)
            let scorePoint = CGPoint(
                x: badgeRect.midX - scoreSize.width / 2,
                y: badgeRect.midY - scoreSize.height / 2
            )
            (scoreText as NSString).draw(at: scorePoint, withAttributes: scoreAttrs)

            y += 52
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
        switch score {
        case 0..<25: return .systemRed
        case 25..<50: return .systemOrange
        case 50..<75: return .systemYellow
        case 75..<90: return .systemGreen
        default: return .systemBlue
        }
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
            latitudinalMeters: 2000,
            longitudinalMeters: 2000
        )
        options.size = size
        options.mapType = .hybrid
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)

        let snapshotter = MKMapSnapshotter(options: options)
        return try? await snapshotter.start().image
    }
}
