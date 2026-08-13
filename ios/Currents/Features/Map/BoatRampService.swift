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

    private func merge(_ new: [BoatRamp], tile: String) {
        loadedTiles.insert(tile)
        let known = Set(ramps.map(\.id))
        ramps.append(contentsOf: new.filter { !known.contains($0.id) })
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
