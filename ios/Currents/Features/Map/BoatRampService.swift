import Foundation
import CoreLocation

/// A public boat ramp / slipway or a designated fishing access point, pulled
/// from OpenStreetMap.
struct BoatRamp: Identifiable, Equatable, Codable {
    enum Kind: String, Codable {
        case ramp        // leisure=slipway
        case access      // leisure=fishing (designated fishing access)

        var label: String {
            switch self {
            case .ramp:   "Boat ramp"
            case .access: "Fishing access"
            }
        }
        var icon: String {
            switch self {
            case .ramp:   "sailboat.fill"
            case .access: "figure.fishing"
            }
        }
        /// How an unnamed place named after its water starts, as in
        /// "Ramp at Theewaterskloof Dam".
        var waterNamePrefix: String {
            switch self {
            case .ramp:   "Ramp at "
            case .access: "Fishing access at "
            }
        }
    }

    let id: String           // OSM type/id, e.g. "node/123"
    let name: String
    let kind: Kind
    let lat: Double
    let lon: Double

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
}

/// Fetches public boat ramps + fishing access points from the Overpass API,
/// cached to disk per half-degree tile for a month — the data barely changes
/// and Overpass asks to be queried gently.
@MainActor
final class BoatRampService: ObservableObject {
    static let shared = BoatRampService()
    @Published private(set) var ramps: [BoatRamp] = []

    private var loadedTiles = Set<String>()
    private var inFlight = Set<String>()

    private var cacheDir: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("boatramps", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Make sure every half-degree tile covering the region is loaded (from
    /// disk when fresh, Overpass otherwise). Publishes into `ramps`.
    func load(around center: CLLocationCoordinate2D, latSpan: Double) async {
        // A whole country's ramps is thousands of pins — only bother once the
        // map is zoomed to a fishable area.
        guard latSpan < 2.5 else { return }
        let half = 0.5
        let latIndex = (center.latitude / half).rounded(.down)
        let lonIndex = (center.longitude / half).rounded(.down)
        // The tile under the camera plus its neighbours, so panning doesn't
        // show an empty edge.
        for dLat in -1...1 {
            for dLon in -1...1 {
                let tile = "\(Int(latIndex) + dLat)_\(Int(lonIndex) + dLon)"
                guard !loadedTiles.contains(tile), !inFlight.contains(tile) else { continue }
                let south = (latIndex + Double(dLat)) * half
                let west = (lonIndex + Double(dLon)) * half
                await loadTile(tile, south: south, west: west, size: half)
            }
        }
    }

    private func loadTile(_ tile: String, south: Double, west: Double, size: Double) async {
        // Bundled with the app for the covered region: no network needed.
        if let bundled = BundledMapData.places(inTile: tile) {
            merge(bundled, tile: tile)
            return
        }
        let file = cacheDir.appendingPathComponent("tile-\(tile).json")
        if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
           let modified = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) < 30 * 86_400,
           let data = try? Data(contentsOf: file),
           let cached = try? JSONDecoder().decode([BoatRamp].self, from: data) {
            merge(cached, tile: tile)
            return
        }
        inFlight.insert(tile)
        defer { inFlight.remove(tile) }
        let bbox = "\(south),\(west),\(south + size),\(west + size)"
        let query = """
        [out:json][timeout:20];
        (
          node["leisure"="slipway"](\(bbox));
          way["leisure"="slipway"](\(bbox));
          node["leisure"="fishing"](\(bbox));
        );
        out center 400;
        """
        var request = URLRequest(url: URL(string: "https://overpass-api.de/api/interpreter")!)
        request.httpMethod = "POST"
        request.httpBody = "data=\(query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? query)".data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(OverpassResponse.self, from: data) else { return }
        let found = decoded.elements.compactMap { el -> BoatRamp? in
            let lat = el.lat ?? el.center?.lat
            let lon = el.lon ?? el.center?.lon
            guard let lat, let lon else { return nil }
            let isAccess = el.tags?["leisure"] == "fishing"
            let kind: BoatRamp.Kind = isAccess ? .access : .ramp
            let name = el.tags?["name"] ?? kind.label
            return BoatRamp(id: "\(el.type)/\(el.id)", name: name, kind: kind, lat: lat, lon: lon)
        }
        if let encoded = try? JSONEncoder().encode(found) {
            try? encoded.write(to: file)
        }
        merge(found, tile: tile)
    }

    /// Two places of one kind closer than this are one place mapped twice,
    /// often as a point and as an outline.
    static let samePlaceMetres = 50.0

    /// Places whose name was made from the water they are on, so a merge
    /// still prefers a place OpenStreetMap names.
    private var madeNames = Set<String>()

    /// Adds a tile's places. A place within 50 m of one of the same kind is
    /// the same place: the one with a name in OpenStreetMap is kept, else the
    /// outline (a way) over the point (a node), else the one already here.
    /// An unnamed place is then named after the water it is on, when it is
    /// on bundled water: "Ramp at Theewaterskloof Dam".
    private func merge(_ new: [BoatRamp], tile: String) {
        loadedTiles.insert(tile)
        var list = ramps
        var known = Set(list.map(\.id))
        // Places by cell of about 200 m, so each one is only measured
        // against its neighbours.
        var cells: [String: [Int]] = [:]
        for (index, place) in list.enumerated() {
            cells[Self.cell(place, dLat: 0, dLon: 0), default: []].append(index)
        }
        var touched: [Int] = []
        let incoming = new.filter { !known.contains($0.id) }.sorted { rank($0) > rank($1) }
        for place in incoming where !known.contains(place.id) {
            known.insert(place.id)
            var match: Int?
            search: for dLat in -1...1 {
                for dLon in -1...1 {
                    for index in cells[Self.cell(place, dLat: dLat, dLon: dLon)] ?? []
                    where list[index].kind == place.kind && Self.metres(list[index], place) < Self.samePlaceMetres {
                        match = index
                        break search
                    }
                }
            }
            if let index = match {
                guard rank(place) > rank(list[index]) else { continue }
                list[index] = place
                cells[Self.cell(place, dLat: 0, dLon: 0), default: []].append(index)
                touched.append(index)
            } else {
                list.append(place)
                cells[Self.cell(place, dLat: 0, dLon: 0), default: []].append(list.count - 1)
                touched.append(list.count - 1)
            }
        }
        for index in touched where list[index].name == list[index].kind.label {
            let place = list[index]
            guard let water = BundledMapData.waterName(near: place.coordinate) else { continue }
            list[index] = BoatRamp(id: place.id, name: place.kind.waterNamePrefix + water,
                                   kind: place.kind, lat: place.lat, lon: place.lon)
            madeNames.insert(place.id)
        }
        ramps = list
    }

    /// A place by its OpenStreetMap id or, for one merged into a neighbour,
    /// the place that stands for it now.
    func place(id: String, near: CLLocationCoordinate2D?) -> BoatRamp? {
        if let hit = ramps.first(where: { $0.id == id }) { return hit }
        guard let near else { return nil }
        let probe = BoatRamp(id: id, name: "", kind: .ramp, lat: near.latitude, lon: near.longitude)
        return ramps
            .map { ($0, Self.metres($0, probe)) }
            .filter { $0.1 < Self.samePlaceMetres }
            .min { $0.1 < $1.1 }?.0
    }

    /// Named in OpenStreetMap first, then outlines before points.
    private func rank(_ place: BoatRamp) -> Int {
        let named = place.name != place.kind.label && !madeNames.contains(place.id)
        return (named ? 2 : 0) + (place.id.hasPrefix("way/") ? 1 : 0)
    }

    /// The key of the 0.002 degree cell a place is in, or of a neighbour.
    private static func cell(_ place: BoatRamp, dLat: Int, dLon: Int) -> String {
        let lat = Int((place.lat / 0.002).rounded(.down)) + dLat
        let lon = Int((place.lon / 0.002).rounded(.down)) + dLon
        return "\(lat)_\(lon)"
    }

    private static func metres(_ a: BoatRamp, _ b: BoatRamp) -> Double {
        BundledMapData.metres(a.lat, a.lon, b.lat, b.lon)
    }

    private struct OverpassResponse: Decodable {
        struct Element: Decodable {
            struct Center: Decodable { let lat: Double; let lon: Double }
            let type: String
            let id: Int64
            let lat: Double?
            let lon: Double?
            let center: Center?
            let tags: [String: String]?
        }
        let elements: [Element]
    }
}
