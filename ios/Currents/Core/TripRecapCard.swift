import SwiftUI
import MapKit
import CoreLocation

/// A shareable recap of a fishing session: the route drawn over a real map,
/// headline stats and the day's catches, rendered to an image.
@MainActor
enum TripRecapCard {
    /// Async because it snapshots real map tiles for the route before laying
    /// out the card (ImageRenderer can't snapshot a live Map, so we bake the
    /// route into a UIImage first and hand it to the SwiftUI card).
    static func render(trip: Trip, catches: [CatchDetail]) async -> UIImage? {
        let coords = trip.allTrackPoints.map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
        }
        let routeImage = await RouteMapRenderer.image(
            for: coords,
            size: CGSize(width: 1040, height: 588)
        )
        return ShareCardRenderer.image(
            TripRecapCardView(trip: trip, catches: catches, routeImage: routeImage))
    }

    static func caption(for trip: Trip, catches: [CatchDetail]) -> String {
        let fish = catches.count
        return "\(trip.name): \(fish) fish, \(SessionFormat.distance(trip.totalTrackDistanceMeters)) covered. Logged with Currents"
    }
}

// MARK: - Route map renderer

/// Renders a session's GPS track as a polyline drawn over a real MapKit
/// snapshot (muted-standard tiles so the route colour pops).
@MainActor
enum RouteMapRenderer {
    static func image(for coords: [CLLocationCoordinate2D], size: CGSize) async -> UIImage? {
        guard !coords.isEmpty else { return nil }

        let options = MKMapSnapshotter.Options()
        options.region = region(for: coords)
        options.size = size
        options.mapType = .mutedStandard
        options.showsBuildings = false
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)

        let snapshotter = MKMapSnapshotter(options: options)
        guard let snapshot = try? await snapshotter.start() else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1 // snapshot is already at the requested pixel size
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            snapshot.image.draw(at: .zero)
            let cg = ctx.cgContext

            guard coords.count > 1 else {
                drawDot(cg, at: snapshot.point(for: coords[0]), color: .systemGreen)
                return
            }

            let path = UIBezierPath()
            for (i, c) in coords.enumerated() {
                let p = snapshot.point(for: c)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.lineJoinStyle = .round
            path.lineCapStyle = .round

            // Dark casing beneath the accent line for contrast over any terrain.
            path.lineWidth = 13
            UIColor.black.withAlphaComponent(0.45).setStroke()
            path.stroke()

            path.lineWidth = 7
            UIColor(CurrentsTheme.accent).setStroke()
            path.stroke()

            drawDot(cg, at: snapshot.point(for: coords.first!), color: .systemGreen)
            drawDot(cg, at: snapshot.point(for: coords.last!), color: .systemRed)
        }
    }

    private static func drawDot(_ cg: CGContext, at point: CGPoint, color: UIColor) {
        let outer: CGFloat = 26, inner: CGFloat = 16
        cg.setFillColor(UIColor.white.cgColor)
        cg.fillEllipse(in: CGRect(x: point.x - outer / 2, y: point.y - outer / 2, width: outer, height: outer))
        cg.setFillColor(color.cgColor)
        cg.fillEllipse(in: CGRect(x: point.x - inner / 2, y: point.y - inner / 2, width: inner, height: inner))
    }

    private static func region(for coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let lats = coords.map(\.latitude), lons = coords.map(\.longitude)
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLon = lons.min()!, maxLon = lons.max()!
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        // Pad the bounding box so the track isn't jammed against the edges,
        // with a sensible floor for near-stationary sessions.
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.5, 0.004),
            longitudeDelta: max((maxLon - minLon) * 1.5, 0.004)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

// MARK: - Card

/// The session recap in the share-card family: the route over a real map,
/// the date and name, headline stats and the day's top species.
struct TripRecapCardView: View {
    let trip: Trip
    let catches: [CatchDetail]
    let routeImage: UIImage?

    private var speciesCounts: [(String, Int, Species?)] {
        var acc: [String: (Int, Species?)] = [:]
        for c in catches {
            let n = displayName(c.species?.commonName ?? "Unknown")
            let e = acc[n] ?? (0, c.species)
            acc[n] = (e.0 + 1, e.1)
        }
        return acc.map { ($0.key, $0.value.0, $0.value.1) }.sorted { $0.1 > $1.1 }
    }

    var body: some View {
        ShareCardCanvas(height: nil) {
            mapPanel
            Text(dateLabel)
                .font(.subheadline)
                .foregroundStyle(Color.dsText2)
                .padding(.top, DS.Space.s4)
            Text(trip.name)
                .font(.title.bold())
                .foregroundStyle(Color.dsText)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            HStack(spacing: DS.Space.s2) {
                ShareCardStat(value: "\(catches.count)", label: catches.count == 1 ? "Catch" : "Catches")
                ShareCardStat(value: SessionFormat.distance(trip.totalTrackDistanceMeters), label: "Distance")
                ShareCardStat(value: SessionFormat.duration(trip.totalDurationSeconds), label: "Time")
                if trip.isMultiDay { ShareCardStat(value: "\(trip.dayCount)", label: "Days") }
            }
            .padding(.top, DS.Space.s4)
            if !speciesCounts.isEmpty {
                VStack(spacing: DS.Space.s2) {
                    ForEach(Array(speciesCounts.prefix(3).enumerated()), id: \.offset) { _, row in
                        speciesRow(name: row.0, count: row.1, species: row.2)
                    }
                }
                .padding(.top, DS.Space.s4)
            }
            ShareCardFooter(detail: "Tight lines")
                .padding(.top, DS.Space.s5)
        }
    }

    private var mapPanel: some View {
        Color.clear
            .frame(height: 180)
            .frame(maxWidth: .infinity)
            .overlay {
                if let routeImage {
                    Image(uiImage: routeImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Color.dsFill
                        DS.accent.opacity(0.22)
                        VStack(spacing: DS.Space.s2) {
                            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                                .font(.largeTitle)
                                .foregroundStyle(DS.accent)
                            Text("No track recorded")
                                .font(.footnote)
                                .foregroundStyle(Color.dsText2)
                        }
                    }
                }
            }
            .overlay(alignment: .bottomLeading) {
                if routeImage != nil {
                    // The distance on the map's corner, like a map label.
                    Label(SessionFormat.distance(trip.totalTrackDistanceMeters),
                          systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.dsText)
                        .padding(.horizontal, DS.Space.s3)
                        .padding(.vertical, 6)
                        .background(Color.dsBackground.opacity(0.7), in: Capsule())
                        .padding(DS.Space.s3)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }

    private func speciesRow(name: String, count: Int, species: Species?) -> some View {
        HStack(spacing: DS.Space.s3) {
            if let species {
                ThumbView(species: species, size: 36)
            } else {
                ThumbView(systemImage: "fish.fill", tint: .gray, size: 36)
            }
            Text(name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.dsText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: DS.Space.s2)
            Text(count == 1 ? "1 fish" : "\(count) fish")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.dsText2)
        }
    }

    private var dateLabel: String {
        let start = trip.startDate.formatted(date: .abbreviated, time: .omitted)
        if trip.isMultiDay, let end = trip.endDate {
            let endStr = end.formatted(date: .abbreviated, time: .omitted)
            if endStr != start { return "\(start) to \(endStr)" }
        }
        return start
    }

    /// Guards against the "'S" artefact that `.capitalized` leaves on names
    /// like "Abbott's Moray" when they arrive title-cased.
    private func displayName(_ name: String) -> String {
        name.replacingOccurrences(of: "'S ", with: "'s ")
            .replacingOccurrences(of: "’S ", with: "’s ")
    }
}
