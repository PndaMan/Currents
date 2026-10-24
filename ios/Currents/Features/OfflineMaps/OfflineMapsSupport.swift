import SwiftUI
import CoreLocation
import MapKit
import GRDB

// MARK: - What to download

/// What the download sheet saves.
enum OfflineDownloadTarget: Hashable {
    /// A square on the map. nil starts around the angler.
    case area(GeoRect?, name: String)
    case region(OfflineAdminRegion)
    case country(OfflineCountry)

    var isArea: Bool {
        if case .area = self { return true }
        return false
    }
}

/// A sheet request, so the same target can be opened twice in a row.
struct OfflineDownloadRequest: Identifiable {
    let id = UUID()
    let target: OfflineDownloadTarget
}

/// Pages pushed inside Offline maps.
enum OfflineMapsRoute: Hashable {
    case regions
    case country(OfflineCountry)
    case pack(String)
}

// MARK: - Formatting

enum OfflineFormat {
    /// A size in figures, never "Zero KB", so a download that has only just
    /// started still reads as a number. Callers say "None" when there is
    /// nothing at all.
    static func bytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: max(bytes, 0))
    }

    /// "About 85 MB", rounded so an estimate does not look exact.
    static func estimate(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_000_000
        let rounded: Double
        switch mb {
        case ..<10: rounded = max(1, mb.rounded())
        case ..<100: rounded = (mb / 5).rounded() * 5
        default: rounded = (mb / 10).rounded() * 10
        }
        return "About " + ByteCountFormatter.string(fromByteCount: Int64(rounded * 1_000_000), countStyle: .file)
    }

    static func area(_ km2: Double) -> String {
        Units.area(km2: km2)
    }

    static func side(_ rect: GeoRect) -> String {
        let w = Units.distance(km: rect.widthKm), h = Units.distance(km: rect.heightKm)
        return w == h ? "\(w) square" : "\(w) by \(h)"
    }

    /// "24 October 2026", day first as everywhere else in the app.
    static func date(_ date: Date) -> String {
        LogbookFormat.fullDate(date)
    }

    /// "Province", "State" or "Region" for a region's kind.
    static func kind(_ region: OfflineAdminRegion) -> String {
        region.kind.isEmpty ? "Region" : region.kind.prefix(1).uppercased() + region.kind.dropFirst()
    }

    static func waters(_ n: Int) -> String {
        n == 1 ? "1 water" : "\(n.formatted()) waters"
    }

    static func places(_ n: Int) -> String {
        n == 1 ? "1 of your places" : "\(n.formatted()) of your places"
    }

    /// What a plan's close-ups cover, in words.
    static func closeUps(_ plan: OfflinePlan, isArea: Bool) -> String {
        if isArea { return "Close-ups of the whole square" }
        guard plan.closeUpZoom > plan.overviewZoom else { return "The whole area at a glance, no close-ups" }
        var parts: [String] = []
        if plan.watersIncluded > 0 {
            parts.append(plan.trimmed
                ? "the \(plan.watersIncluded.formatted()) biggest of \(plan.watersAvailable.formatted()) waters"
                : waters(plan.watersIncluded))
        }
        if plan.placesIncluded > 0 { parts.append(places(plan.placesIncluded)) }
        guard !parts.isEmpty else { return "No known waters here yet, so overview only" }
        return "Close-ups of " + parts.joined(separator: " and ")
    }

    static func status(_ pack: OfflinePack, live: OfflineProgress?) -> String {
        let percent = Int((Double(live?.done ?? pack.doneUnits) / Double(max(live?.total ?? pack.totalUnits, 1)) * 100).rounded(.down))
        switch pack.status {
        case .downloading:
            return pack.isUpdating ? "Updating, \(percent) percent" : "Downloading, \(percent) percent"
        case .paused:
            return "Paused at \(percent) percent"
        case .complete:
            if pack.isFromEarlierSource {
                return "Saved from an earlier map source. Update it to show it on the map."
            }
            return "\(bytes(pack.bytes)), saved \(date(pack.completedAt ?? pack.createdAt))"
        }
    }
}

// MARK: - The angler's own places

/// Spots, catch locations and planned sessions, read once for suggestions
/// and for the close-ups inside a region.
struct OfflineUserPlaces {
    struct CatchPoint {
        let coordinate: CLLocationCoordinate2D
        let spotId: String?
    }

    var spots: [Spot] = []
    var catches: [CatchPoint] = []
    var planned: [Trip] = []
    var location: CLLocationCoordinate2D?
    var homeWater = ""

    @MainActor
    static func load(_ appState: AppState) -> OfflineUserPlaces {
        var places = OfflineUserPlaces()
        places.spots = (try? appState.spotRepository.fetchAll()) ?? []
        places.planned = (try? appState.tripRepository.fetchPlanned()) ?? []
        places.location = appState.locationManager.currentLocation?.coordinate
        places.homeWater = (UserDefaults.standard.string(forKey: "communityHomeWater") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rows = (try? appState.db.db.read { db in
            try Row.fetchAll(db, sql: "SELECT latitude, longitude, spotId FROM catch")
        }) ?? []
        places.catches = rows.compactMap { row in
            let lat: Double = row["latitude"], lon: Double = row["longitude"]
            guard abs(lat) > 0.0001 || abs(lon) > 0.0001 else { return nil }
            return CatchPoint(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                              spotId: row["spotId"])
        }
        return places
    }

    /// Where a planned session is: its own pin, or its spot.
    func coordinate(of trip: Trip) -> CLLocationCoordinate2D? {
        if let lat = trip.plannedLatitude, let lon = trip.plannedLongitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        guard let id = trip.spotId, let spot = spots.first(where: { $0.id == id }) else { return nil }
        return CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude)
    }

    /// Every place that should get close-ups in a region download.
    var closeUpPoints: [CLLocationCoordinate2D] {
        var points = spots.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        points += catches.map(\.coordinate)
        points += planned.compactMap(coordinate(of:))
        // Catches cluster at the same water; one close-up each 1 km is plenty.
        var seen = Set<String>()
        return points.filter { p in
            seen.insert("\(Int((p.latitude * 100).rounded()))_\(Int((p.longitude * 100).rounded()))").inserted
        }
    }

    /// Water bodies in a box, from the bundled and fetched water data.
    @MainActor
    static func waters(in bounds: GeoRect, appState: AppState) -> [Waterbody] {
        var ranges: [(Double, Double)] = [(max(bounds.minLon, -180), min(bounds.maxLon, 180))]
        if bounds.maxLon > 180 { ranges.append((-180, bounds.maxLon - 360)) }
        if bounds.minLon < -180 { ranges.append((bounds.minLon + 360, 180)) }
        return ranges.flatMap { lo, hi in
            (try? appState.db.db.read { db in
                try Waterbody
                    .filter(Column("latitude") >= bounds.minLat && Column("latitude") <= bounds.maxLat)
                    .filter(Column("longitude") >= lo && Column("longitude") <= hi)
                    .fetchAll(db)
            }) ?? []
        }
    }
}

// MARK: - Suggestions

/// A ready-made area to download, worked out from the angler's own data.
struct OfflineSuggestion: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let center: CLLocationCoordinate2D
    let target: OfflineDownloadTarget
    /// Size at standard detail, for squares.
    var estimate: Int64?
}

enum OfflineSuggestions {
    /// Squares around each place, sized to what is there.
    static let nearbySideKm = 24.0
    static let spotSideKm = 10.0

    /// Around you, your province, home water, planned sessions, waters you
    /// have caught fish at, and saved spots, minus anything already
    /// downloaded and repeats of the same place.
    /// `homeRegion` is the region the angler is in, looked up off the main
    /// thread (it reads the bundled outlines).
    @MainActor
    static func build(appState: AppState, places: OfflineUserPlaces, homeRegion: OfflineAdminRegion?,
                      packs: [OfflinePack], scale: Double) -> [OfflineSuggestion] {
        var out: [OfflineSuggestion] = []
        let waterRepo = appState.waterbodyRepository

        func square(_ id: String, _ title: String, _ subtitle: String, _ icon: String, _ tint: Color,
                    _ center: CLLocationCoordinate2D, sideKm: Double, name: String) {
            let rect = GeoRect(center: center, sideKm: sideKm)
            let estimate = OfflinePlanner.areaPlan(rect, detail: .standard, scale: scale).estimatedBytes
            out.append(OfflineSuggestion(id: id, title: title, subtitle: subtitle, systemImage: icon, tint: tint,
                                         center: center, target: .area(rect, name: name), estimate: estimate))
        }

        /// A square that takes in the whole water, with room for the shore.
        func side(for water: Waterbody?, minimum: Double) -> Double {
            guard let area = water?.surfaceAreaKm2, area > 0 else { return minimum }
            return min(max(minimum, 2 * sqrt(area / .pi) * 1.4 + 4), 40)
        }

        if let here = places.location {
            square("nearby", "Around you", "\(Units.distance(km: nearbySideKm)) square", "location.fill", DS.accent,
                   here, sideKm: nearbySideKm, name: "")
            if let region = homeRegion {
                let country = OfflineRegionCatalog.country(region.countryId).map(OfflineRegionCatalog.displayName)
                out.append(OfflineSuggestion(
                    id: "region-\(region.id)", title: region.name,
                    subtitle: "Your \(OfflineFormat.kind(region).lowercased())" + (country.map { " in \($0)" } ?? ""),
                    systemImage: "map.fill", tint: .green, center: region.bounds.center,
                    target: .region(region), estimate: nil))
            }
        }

        if !places.homeWater.isEmpty {
            let key = places.homeWater.lowercased()
            if let spot = places.spots.first(where: { $0.name.lowercased() == key }) {
                let water = spot.waterbodyId.flatMap { try? waterRepo.fetch(id: $0) }
                square("home", spot.name, "Your home water", "house.fill", .orange,
                       CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude),
                       sideKm: side(for: water, minimum: spotSideKm), name: spot.name)
            } else if let water = homeWater(named: places.homeWater, near: places.location, appState: appState) {
                square("home", water.name, "Your home water", "house.fill", .orange,
                       CLLocationCoordinate2D(latitude: water.latitude, longitude: water.longitude),
                       sideKm: side(for: water, minimum: spotSideKm), name: water.name)
            }
        }

        for trip in places.planned {
            guard let c = places.coordinate(of: trip) else { continue }
            let when = trip.plannedDate.map(ForecastFormat.longDate)
            square("trip-\(trip.id)", trip.name, when.map { "Planned for \($0)" } ?? "Planned session",
                   "calendar", .indigo, c, sideKm: spotSideKm, name: trip.name)
        }

        // Waters with catches: every catch at a saved spot goes where the
        // spot is, its own water or else the water at the spot, so a water
        // never counts fewer catches than one spot on it. Other catches go
        // to the water at the catch.
        var catchesByWater: [Int64: Int] = [:]
        var watersById: [Int64: Waterbody] = [:]
        var waterAtSpot: [String: Waterbody?] = [:]
        for point in places.catches {
            let water: Waterbody?
            if let spotId = point.spotId, let spot = places.spots.first(where: { $0.id == spotId }) {
                if let known = waterAtSpot[spotId] {
                    water = known
                } else {
                    let found = spot.waterbodyId.flatMap { wid in watersById[wid] ?? (try? waterRepo.fetch(id: wid)) }
                        ?? nearestWater(to: CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude),
                                        in: waterRepo)
                    waterAtSpot.updateValue(found, forKey: spotId)
                    water = found
                }
            } else {
                water = nearestWater(to: point.coordinate, in: waterRepo)
            }
            guard let water, let id = water.id else { continue }
            watersById[id] = water
            catchesByWater[id, default: 0] += 1
        }
        for (id, count) in catchesByWater.sorted(by: { $0.value > $1.value }) {
            guard let water = watersById[id] else { continue }
            square("water-\(id)", water.name, count == 1 ? "1 catch logged here" : "\(count) catches logged here",
                   "fish.fill", .teal, CLLocationCoordinate2D(latitude: water.latitude, longitude: water.longitude),
                   sideKm: side(for: water, minimum: spotSideKm), name: water.name)
        }

        for spot in places.spots {
            let water = spot.waterbodyId.flatMap { try? waterRepo.fetch(id: $0) }
            square("spot-\(spot.id)", spot.name, "Saved spot", spot.type.icon, DS.accent,
                   CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude),
                   sideKm: side(for: water, minimum: spotSideKm), name: spot.name)
        }

        // Drop repeats of the same place and anything already downloaded.
        var kept: [OfflineSuggestion] = []
        for s in out {
            let here = CLLocation(latitude: s.center.latitude, longitude: s.center.longitude)
            let repeated = kept.contains {
                $0.target.isArea && s.target.isArea
                    && here.distance(from: CLLocation(latitude: $0.center.latitude, longitude: $0.center.longitude)) < 2_000
            }
            if repeated || isDownloaded(s, packs: packs) { continue }
            kept.append(s)
        }
        return kept
    }

    private static func isDownloaded(_ s: OfflineSuggestion, packs: [OfflinePack]) -> Bool {
        switch s.target {
        case .region(let region):
            return packs.contains { $0.regionId == region.id }
        case .country(let country):
            return packs.contains { $0.regionId == country.id }
        case .area:
            return packs.contains { pack in
                pack.kind == .area ? pack.bounds.contains(s.center)
                    : pack.closeUps.contains { $0.contains(s.center) }
            }
        }
    }

    /// The water a point is on or beside. Each water counts as a circle of
    /// its size; the one whose edge is nearest wins, ties to the nearest
    /// middle. A water is in reach within 1.5 km of its edge or 3 km of its
    /// middle, whichever is further, so the shore of a big dam counts as
    /// well as a small dam's banks.
    @MainActor
    private static func nearestWater(to point: CLLocationCoordinate2D, in repo: WaterbodyRepository) -> Waterbody? {
        let here = CLLocation(latitude: point.latitude, longitude: point.longitude)
        // Each query keeps the largest 60, so small waters close by come
        // from a tight search and big ones from a wide one.
        let close = (try? repo.fetchNearby(latitude: point.latitude, longitude: point.longitude, radiusKm: 3)) ?? []
        let wide = (try? repo.fetchNearby(latitude: point.latitude, longitude: point.longitude, radiusKm: 15)) ?? []
        var seen = Set<Int64>()
        var best: (edge: Double, middle: Double, water: Waterbody)?
        for water in close + wide {
            guard let id = water.id, seen.insert(id).inserted else { continue }
            let middle = here.distance(from: CLLocation(latitude: water.latitude, longitude: water.longitude))
            let radius = water.approximateRadiusM
            guard middle <= max(3_000, radius + 1_500) else { continue }
            let edge = max(0, middle - radius)
            if let b = best, (edge, middle) >= (b.edge, b.middle) { continue }
            best = (edge, middle, water)
        }
        return best?.water
    }

    @MainActor
    private static func homeWater(named name: String, near: CLLocationCoordinate2D?, appState: AppState) -> Waterbody? {
        let matches = (try? appState.db.db.read { db in
            try Waterbody.filter(Column("name").collating(.nocase) == name).fetchAll(db)
        }) ?? []
        guard let near else { return matches.max { ($0.surfaceAreaKm2 ?? 0) < ($1.surfaceAreaKm2 ?? 0) } }
        let here = CLLocation(latitude: near.latitude, longitude: near.longitude)
        return matches.min {
            here.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
                < here.distance(from: CLLocation(latitude: $1.latitude, longitude: $1.longitude))
        }
    }
}

// MARK: - Thumbnails

/// A small picture of a downloaded map, drawn by its download engine from
/// the map's own saved data, so it works with no signal.
enum OfflinePackThumbnail {
    private static let cache = NSCache<NSString, UIImage>()

    static func cached(_ pack: OfflinePack) -> UIImage? {
        cache.object(forKey: key(pack, stage: stage(pack, live: nil)))
    }

    /// `points` is the output size in pixels (44 pt at 3x by default).
    static func image(for pack: OfflinePack, points: CGFloat = 132) async -> UIImage? {
        if let hit = cached(pack) { return hit }
        let image = await Task.detached(priority: .utility) {
            TileSources.current.offlineEngine.preview(pack, pixels: points)
        }.value
        if let image { cache.setObject(image, forKey: key(pack, stage: stage(pack, live: nil))) }
        return image
    }

    /// How far along the map is, in fifths, so the picture is redrawn as
    /// more of it comes down.
    static func stage(_ pack: OfflinePack, live: OfflineProgress?) -> Int {
        let done = Double(live?.done ?? pack.doneUnits), total = Double(max(live?.total ?? pack.totalUnits, 1))
        return pack.status == .complete ? 5 : Int(done / total * 5)
    }

    private static func key(_ pack: OfflinePack, stage: Int) -> NSString {
        "\(pack.id)-\(stage)" as NSString
    }
}

/// Places a reverse geocode can name, for the default name of a square.
enum OfflinePlaceName {
    static func name(for coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        if let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first {
            if let name = placemark.locality ?? placemark.subAdministrativeArea ?? placemark.administrativeArea {
                return name
            }
        }
        return await Task.detached(priority: .utility) {
            OfflineRegionCatalog.region(containing: coordinate)?.name
        }.value
    }
}
