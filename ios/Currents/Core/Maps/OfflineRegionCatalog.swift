import Foundation
import CoreLocation
import MapKit

// MARK: - Geometry

/// A latitude and longitude box. `minLon` and `maxLon` may pass -180 or 180
/// for areas that cross the antimeridian (Fiji, Chukotka); the tile maths
/// wraps them.
struct GeoRect: Codable, Hashable, Sendable {
    var minLat: Double
    var minLon: Double
    var maxLat: Double
    var maxLon: Double

    init(minLat: Double, minLon: Double, maxLat: Double, maxLon: Double) {
        self.minLat = minLat
        self.minLon = minLon
        self.maxLat = maxLat
        self.maxLon = maxLon
    }

    /// A square `sideKm` across, centred on `center`.
    init(center: CLLocationCoordinate2D, sideKm: Double) {
        let half = sideKm / 2
        let dLat = half / 110.574
        let dLon = half / (111.320 * max(cos(center.latitude * .pi / 180), 0.05))
        self.init(minLat: max(center.latitude - dLat, -TileMath.maxLatitude),
                  minLon: center.longitude - dLon,
                  maxLat: min(center.latitude + dLat, TileMath.maxLatitude),
                  maxLon: center.longitude + dLon)
    }

    init(region: MKCoordinateRegion) {
        let halfLat = region.span.latitudeDelta / 2
        let halfLon = region.span.longitudeDelta / 2
        self.init(minLat: max(region.center.latitude - halfLat, -TileMath.maxLatitude),
                  minLon: region.center.longitude - halfLon,
                  maxLat: min(region.center.latitude + halfLat, TileMath.maxLatitude),
                  maxLon: region.center.longitude + halfLon)
    }

    /// From a bundled `[minLon, minLat, maxLon, maxLat]` box.
    init?(box: [Double]) {
        guard box.count == 4 else { return nil }
        self.init(minLat: box[1], minLon: box[0], maxLat: box[3], maxLon: box[2])
    }

    var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                               longitude: GeoRect.normalised((minLon + maxLon) / 2))
    }

    /// The box as a map region, with a little room around it.
    func region(padding: Double = 1.1) -> MKCoordinateRegion {
        MKCoordinateRegion(center: center,
                           span: MKCoordinateSpan(latitudeDelta: min((maxLat - minLat) * padding, 170),
                                                  longitudeDelta: min((maxLon - minLon) * padding, 359)))
    }

    var heightKm: Double { (maxLat - minLat) * 110.574 }
    var widthKm: Double { (maxLon - minLon) * 111.320 * cos((minLat + maxLat) / 2 * .pi / 180) }
    var areaKm2: Double { widthKm * heightKm }

    func contains(_ c: CLLocationCoordinate2D) -> Bool {
        guard c.latitude >= minLat, c.latitude <= maxLat else { return false }
        return [c.longitude, c.longitude + 360, c.longitude - 360].contains { $0 >= minLon && $0 <= maxLon }
    }

    func intersects(_ other: GeoRect) -> Bool {
        guard other.maxLat >= minLat, other.minLat <= maxLat else { return false }
        return [0.0, 360, -360].contains { shift in
            other.maxLon + shift >= minLon && other.minLon + shift <= maxLon
        }
    }

    /// The box grown by `km` on every side.
    func expanded(byKm km: Double) -> GeoRect {
        let dLat = km / 110.574
        let dLon = km / (111.320 * max(cos((minLat + maxLat) / 2 * .pi / 180), 0.05))
        return GeoRect(minLat: max(minLat - dLat, -TileMath.maxLatitude), minLon: minLon - dLon,
                       maxLat: min(maxLat + dLat, TileMath.maxLatitude), maxLon: maxLon + dLon)
    }

    static func normalised(_ lon: Double) -> Double {
        var l = lon
        while l > 180 { l -= 360 }
        while l < -180 { l += 360 }
        return l
    }
}

/// Web Mercator tile maths, the scheme every XYZ tile server uses.
enum TileMath {
    static let maxLatitude = 85.05112878

    /// Column for a longitude. Not wrapped, so a box past 180 keeps going.
    static func x(_ lon: Double, _ z: Int) -> Int {
        Int(floor((lon + 180) / 360 * Double(1 << z)))
    }

    static func y(_ lat: Double, _ z: Int) -> Int {
        let l = min(max(lat, -maxLatitude), maxLatitude) * .pi / 180
        let v = Int(floor((1 - log(tan(l) + 1 / cos(l)) / .pi) / 2 * Double(1 << z)))
        return min(max(v, 0), (1 << z) - 1)
    }

    static func lat(ofY y: Double, _ z: Int) -> Double {
        let n = Double.pi - 2 * Double.pi * y / Double(1 << z)
        return atan(sinh(n)) * 180 / .pi
    }

    static func lon(ofX x: Double, _ z: Int) -> Double {
        x / Double(1 << z) * 360 - 180
    }

    static func wrap(_ x: Int, _ z: Int) -> Int {
        let n = 1 << z
        return ((x % n) + n) % n
    }

    /// One integer per tile: zoom, column and row packed together.
    static func key(_ z: Int, _ x: Int, _ y: Int) -> Int64 {
        Int64(z) << 40 | Int64(x) << 20 | Int64(y)
    }

    static func unpack(_ key: Int64) -> (z: Int, x: Int, y: Int) {
        (Int(key >> 40), Int((key >> 20) & 0xFFFFF), Int(key & 0xFFFFF))
    }

    /// Tiles covering a box at one zoom.
    static func count(_ rect: GeoRect, _ z: Int) -> Int {
        let cols = min(x(rect.maxLon, z) - x(rect.minLon, z) + 1, 1 << z)
        let rows = y(rect.minLat, z) - y(rect.maxLat, z) + 1
        return max(cols, 0) * max(rows, 0)
    }

    static func forEachTile(in rect: GeoRect, _ z: Int, _ body: (Int64) -> Void) {
        let x0 = x(rect.minLon, z)
        let x1 = min(x(rect.maxLon, z), x0 + (1 << z) - 1)
        let y0 = y(rect.maxLat, z), y1 = y(rect.minLat, z)
        guard x1 >= x0, y1 >= y0 else { return }
        for tx in x0...x1 {
            let wx = wrap(tx, z)
            for ty in y0...y1 { body(key(z, wx, ty)) }
        }
    }
}

// MARK: - Countries and regions

/// A country in the bundled list (Natural Earth admin 0).
struct OfflineCountry: Identifiable, Hashable, Sendable {
    let id: String
    let iso: String
    let name: String
    let bounds: GeoRect
    let areaKm2: Double
    let regionCount: Int
}

/// A province, state or other first-level region (Natural Earth admin 1).
struct OfflineAdminRegion: Identifiable, Hashable, Sendable {
    let id: String
    let countryId: String
    let name: String
    let localName: String?
    let kind: String
    let bounds: GeoRect
    let areaKm2: Double
}

/// Every country and its provinces or states, bundled from Natural Earth by
/// scripts/regions/build.py, with outlines for drawing and for skipping
/// tiles outside an area. Decoded once, on first use; touch it off the main
/// thread the first time (the outlines file is about 2 MB).
enum OfflineRegionCatalog {
    private struct File: Decodable {
        let countries: [CountryEntry]
        let regions: [RegionEntry]
    }

    private struct CountryEntry: Decodable {
        let id: String
        let iso: String
        let n: String
        let b: [Double]
        let a: Double
        let r: Int
    }

    private struct RegionEntry: Decodable {
        let id: String
        let c: String
        let n: String
        let m: String?
        let t: String
        let b: [Double]
        let a: Double
    }

    private struct ShapesFile: Decodable {
        let shapes: [String: [String]]
    }

    struct Index: Sendable {
        var countries: [OfflineCountry] = []
        var countryById: [String: OfflineCountry] = [:]
        var regionsByCountry: [String: [OfflineAdminRegion]] = [:]
        var regionById: [String: OfflineAdminRegion] = [:]
        /// Folded names, worked out once so search stays quick while typing.
        var countryKeys: [(OfflineCountry, [String])] = []
        var regionKeys: [(OfflineAdminRegion, [String])] = []
    }

    static let index: Index = load()
    private static let shapes: [String: [String]] = loadShapes()

    static var countries: [OfflineCountry] { index.countries }

    static func country(_ id: String) -> OfflineCountry? { index.countryById[id] }
    static func region(_ id: String) -> OfflineAdminRegion? { index.regionById[id] }
    static func regions(in countryId: String) -> [OfflineAdminRegion] { index.regionsByCountry[countryId] ?? [] }

    /// Countries and regions whose name matches, best first: names that
    /// start with the text, then a word that does, then anywhere.
    static func search(_ text: String, limit: Int = 60) -> (countries: [OfflineCountry], regions: [OfflineAdminRegion]) {
        let q = fold(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !q.isEmpty else { return ([], []) }
        func rank(_ names: [String]) -> Int? {
            var best: Int?
            for n in names {
                let r: Int?
                if n.hasPrefix(q) { r = 0 }
                else if n.split(whereSeparator: { $0 == " " || $0 == "-" }).contains(where: { $0.hasPrefix(q) }) { r = 1 }
                else if n.contains(q) { r = 2 }
                else { r = nil }
                if let r { best = min(best ?? r, r) }
            }
            return best
        }
        let countries = index.countryKeys
            .compactMap { c, keys in rank(keys).map { (c, $0) } }
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : displayName($0.0) < displayName($1.0) }
            .prefix(limit)
            .map { $0.0 }
        let regions = index.regionKeys
            .compactMap { r, keys in rank(keys).map { (r, $0) } }
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.name < $1.0.name }
            .prefix(limit)
            .map { $0.0 }
        return (Array(countries), Array(regions))
    }

    /// The region outline as rings of coordinates. Longitudes may pass 180
    /// next to the antimeridian.
    static func outline(_ id: String) -> [[CLLocationCoordinate2D]] {
        (shapes[id] ?? []).map(decodePolyline)
    }

    /// The first-level region a point falls in, if any.
    static func region(containing c: CLLocationCoordinate2D) -> OfflineAdminRegion? {
        index.regionById.values
            .filter { $0.bounds.contains(c) }
            .sorted { $0.areaKm2 < $1.areaKm2 }
            .first { contains(outline($0.id), c) }
    }

    /// Point in any of the rings (even-odd rule), trying the point either
    /// side of the antimeridian.
    static func contains(_ rings: [[CLLocationCoordinate2D]], _ c: CLLocationCoordinate2D) -> Bool {
        for lon in [c.longitude, c.longitude + 360, c.longitude - 360] {
            for ring in rings where ring.count > 2 {
                var inside = false
                var j = ring.count - 1
                for i in 0..<ring.count {
                    let a = ring[i], b = ring[j]
                    if (a.latitude > c.latitude) != (b.latitude > c.latitude) {
                        let crossLon = a.longitude + (c.latitude - a.latitude) * (b.longitude - a.longitude) / (b.latitude - a.latitude)
                        if lon < crossLon { inside.toggle() }
                    }
                    j = i
                }
                if inside { return true }
            }
        }
        return false
    }

    /// The name to show for a country: the phone's own name for its ISO
    /// code, or the bundled English name.
    static func displayName(_ country: OfflineCountry) -> String {
        guard !country.iso.isEmpty, let local = Locale.current.localizedString(forRegionCode: country.iso) else {
            return country.name
        }
        return local
    }

    // MARK: Loading

    private static func resource(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "Data")
            ?? Bundle.main.url(forResource: name, withExtension: "json")
    }

    private static func load() -> Index {
        guard let url = resource("offline_regions"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return Index() }
        var index = Index()
        for r in file.regions {
            guard let bounds = GeoRect(box: r.b) else { continue }
            let region = OfflineAdminRegion(id: r.id, countryId: r.c, name: r.n, localName: r.m,
                                            kind: r.t, bounds: bounds, areaKm2: r.a)
            index.regionById[r.id] = region
            index.regionsByCountry[r.c, default: []].append(region)
        }
        for c in file.countries {
            guard let bounds = GeoRect(box: c.b) else { continue }
            let country = OfflineCountry(id: c.id, iso: c.iso, name: c.n, bounds: bounds, areaKm2: c.a,
                                         regionCount: c.r)
            index.countryById[c.id] = country
            index.countries.append(country)
        }
        index.countries.sort { displayName($0).localizedStandardCompare(displayName($1)) == .orderedAscending }
        for key in index.regionsByCountry.keys {
            index.regionsByCountry[key]?.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        index.countryKeys = index.countries.map { c in
            (c, [fold(displayName(c)), fold(c.name), fold(c.iso)])
        }
        index.regionKeys = index.regionById.values.map { r in
            (r, [r.name, r.localName].compactMap { $0 }.map(fold))
        }
        return index
    }

    private static func loadShapes() -> [String: [String]] {
        guard let url = resource("offline_regions_shapes"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(ShapesFile.self, from: data) else { return [:] }
        return file.shapes
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Google's encoded polyline format at 1e4 precision, latitude first.
    private static func decodePolyline(_ text: String) -> [CLLocationCoordinate2D] {
        var coords: [CLLocationCoordinate2D] = []
        let bytes = Array(text.utf8)
        var i = 0, lat = 0, lon = 0
        func next() -> Int? {
            var result = 0, shift = 0
            while i < bytes.count {
                let b = Int(bytes[i]) - 63
                i += 1
                result |= (b & 0x1F) << shift
                shift += 5
                if b < 0x20 { return (result & 1) != 0 ? ~(result >> 1) : (result >> 1) }
            }
            return nil
        }
        while i < bytes.count {
            guard let dLat = next(), let dLon = next() else { break }
            lat += dLat
            lon += dLon
            coords.append(CLLocationCoordinate2D(latitude: Double(lat) / 1e4, longitude: Double(lon) / 1e4))
        }
        return coords
    }
}
