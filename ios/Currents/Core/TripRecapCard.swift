import SwiftUI
import MapKit
import CoreLocation

/// Strava-style shareable recap of a fishing session: the route drawn over a
/// real map, headline stats, and the day's catches — rendered to an image.
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
        let card = TripRecapCardView(trip: trip, catches: catches, routeImage: routeImage)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        return renderer.uiImage
    }

    static func caption(for trip: Trip, catches: [CatchDetail]) -> String {
        let fish = catches.count
        return "\(trip.name) — \(fish) fish, \(SessionFormat.distance(trip.totalTrackDistanceMeters)) covered. Logged with Currents 🎣"
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

struct TripRecapCardView: View {
    let trip: Trip
    let catches: [CatchDetail]
    let routeImage: UIImage?

    private let cardWidth: CGFloat = 380

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
        VStack(alignment: .leading, spacing: 16) {
            header
            mapPanel
            statsRow
            if !speciesCounts.isEmpty { speciesList }
            footer
        }
        .padding(22)
        .frame(width: cardWidth)
        .background(
            LinearGradient(colors: [Color(red: 0.05, green: 0.11, blue: 0.19),
                                    Color(red: 0.02, green: 0.05, blue: 0.10)],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(trip.name)
                    .font(.title2.bold()).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(dateLabel)
                    .font(.subheadline).foregroundStyle(.white.opacity(0.65))
            }
            Spacer(minLength: 8)
            Image("Logo")
                .resizable().scaledToFit()
                .frame(width: 42, height: 42)
        }
    }

    @ViewBuilder private var mapPanel: some View {
        ZStack(alignment: .bottomLeading) {
            if let routeImage {
                Image(uiImage: routeImage)
                    .resizable().scaledToFill()
            } else {
                Rectangle().fill(Color.white.opacity(0.06))
                    .overlay(
                        Text("No track recorded")
                            .font(.caption).foregroundStyle(.white.opacity(0.4))
                    )
            }

            // Distance pill anchored to the map corner.
            Label(SessionFormat.distance(trip.totalTrackDistanceMeters),
                  systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(10)
        }
        .frame(height: 192)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            stat("\(catches.count)", "Catches")
            stat(SessionFormat.distance(trip.totalTrackDistanceMeters), "Distance")
            stat(SessionFormat.duration(trip.totalDurationSeconds), "Time")
            if trip.isMultiDay { stat("\(trip.dayCount)", "Days") }
        }
    }

    private var speciesList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(speciesCounts.prefix(3)), id: \.0) { row in
                HStack(spacing: 10) {
                    if let sp = row.2 {
                        SpeciesArtworkView(species: sp, caught: true, size: 28)
                    }
                    Text(row.0).font(.subheadline.weight(.medium)).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer()
                    Text("×\(row.1)").font(.subheadline.bold()).foregroundStyle(CurrentsTheme.accent)
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Rectangle().fill(.white.opacity(0.10)).frame(height: 1)
            HStack(spacing: 8) {
                Image("Logo").resizable().scaledToFit().frame(width: 24, height: 24)
                Text("Currents").font(.headline.bold()).foregroundStyle(.white)
                Spacer()
                Text("Tight lines 🎣")
                    .font(.caption).foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.headline.bold()).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private var dateLabel: String {
        let start = trip.startDate.formatted(date: .abbreviated, time: .omitted)
        if trip.isMultiDay, let end = trip.endDate {
            let endStr = end.formatted(date: .abbreviated, time: .omitted)
            if endStr != start { return "\(start) – \(endStr)" }
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
