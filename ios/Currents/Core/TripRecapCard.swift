import SwiftUI
import CoreLocation

/// Strava-style shareable recap of a fishing session: route, headline stats,
/// and the day's catches, rendered to an image for sharing.
@MainActor
enum TripRecapCard {
    static func render(trip: Trip, catches: [CatchDetail]) -> UIImage? {
        let renderer = ImageRenderer(content: TripRecapCardView(trip: trip, catches: catches))
        renderer.scale = 3
        return renderer.uiImage
    }

    static func caption(for trip: Trip, catches: [CatchDetail]) -> String {
        let fish = catches.count
        return "\(trip.name) — \(fish) fish, \(SessionFormat.distance(trip.totalTrackDistanceMeters)) covered. Logged with Currents 🎣"
    }
}

struct TripRecapCardView: View {
    let trip: Trip
    let catches: [CatchDetail]

    private let cardWidth: CGFloat = 380
    private var coords: [CLLocationCoordinate2D] {
        trip.allTrackPoints.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }

    private var speciesCounts: [(String, Int, Species?)] {
        var acc: [String: (Int, Species?)] = [:]
        for c in catches {
            let n = c.species?.commonName ?? "Unknown"
            let e = acc[n] ?? (0, c.species)
            acc[n] = (e.0 + 1, e.1)
        }
        return acc.map { ($0.key, $0.value.0, $0.value.1) }.sorted { $0.1 > $1.1 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(trip.name).font(.title2.bold()).foregroundStyle(.white)
                    Text(trip.startDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.subheadline).foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Image(systemName: "figure.fishing").font(.title).foregroundStyle(CurrentsTheme.accent)
            }

            routeCanvas
                .frame(height: 180)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))

            HStack(spacing: 10) {
                stat("\(catches.count)", "Catches")
                stat(SessionFormat.distance(trip.totalTrackDistanceMeters), "Distance")
                stat(SessionFormat.duration(trip.totalDurationSeconds), "Time")
                if trip.isMultiDay { stat("\(trip.dayCount)", "Days") }
            }

            if !speciesCounts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(speciesCounts.prefix(3)), id: \.0) { row in
                        HStack(spacing: 8) {
                            if let sp = row.2 { SpeciesArtworkView(species: sp, caught: true, size: 26) }
                            Text(row.0).font(.subheadline).foregroundStyle(.white)
                            Spacer()
                            Text("×\(row.1)").font(.subheadline.bold()).foregroundStyle(CurrentsTheme.accent)
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "location.north.circle.fill").foregroundStyle(CurrentsTheme.accent)
                Text("Currents").font(.headline.bold()).foregroundStyle(.white)
                Spacer()
                Text("currents.fishing").font(.caption).foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(22)
        .frame(width: cardWidth)
        .background(
            LinearGradient(colors: [Color(red: 0.04, green: 0.09, blue: 0.16),
                                    Color(red: 0.02, green: 0.05, blue: 0.10)],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    /// Stylised normalised route (ImageRenderer can't snapshot a live Map).
    private var routeCanvas: some View {
        Canvas { ctx, size in
            let pts = coords
            guard pts.count > 1 else {
                let txt = Text("No track recorded").font(.caption).foregroundStyle(.white.opacity(0.4))
                ctx.draw(txt, at: CGPoint(x: size.width / 2, y: size.height / 2))
                return
            }
            let lats = pts.map(\.latitude), lons = pts.map(\.longitude)
            let minLat = lats.min()!, maxLat = lats.max()!, minLon = lons.min()!, maxLon = lons.max()!
            let spanLat = max(maxLat - minLat, 0.0001), spanLon = max(maxLon - minLon, 0.0001)
            let pad: CGFloat = 20
            func project(_ c: CLLocationCoordinate2D) -> CGPoint {
                let x = pad + CGFloat((c.longitude - minLon) / spanLon) * (size.width - 2 * pad)
                let y = pad + CGFloat((maxLat - c.latitude) / spanLat) * (size.height - 2 * pad)
                return CGPoint(x: x, y: y)
            }
            var path = Path()
            path.move(to: project(pts[0]))
            for p in pts.dropFirst() { path.addLine(to: project(p)) }
            ctx.stroke(path, with: .color(CurrentsTheme.accent), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            // Start/end dots
            ctx.fill(Path(ellipseIn: CGRect(x: project(pts[0]).x - 5, y: project(pts[0]).y - 5, width: 10, height: 10)), with: .color(.green))
            ctx.fill(Path(ellipseIn: CGRect(x: project(pts.last!).x - 5, y: project(pts.last!).y - 5, width: 10, height: 10)), with: .color(.red))
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.bold()).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}
