import Foundation
import MapKit

/// Optional map overlay layers, all off by default and toggled from the map's
/// layers button. Each is a free, no-API-key tile source rendered above the
/// cached satellite base.
enum MapOverlayLayer: String, CaseIterable, Identifiable {
    case nautical   // OpenSeaMap seamarks: depth soundings, buoys, beacons, chart lines
    case radar      // RainViewer precipitation radar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nautical: "Nautical / Depth"
        case .radar: "Weather Radar"
        }
    }

    var systemImage: String {
        switch self {
        case .nautical: "water.waves"
        case .radar: "cloud.rain"
        }
    }

    var storageKey: String { "mapLayer_\(rawValue)" }
}

/// OpenSeaMap seamark overlay — transparent nautical chart features (depth
/// contours/soundings, buoys, beacons) drawn over the base map.
final class SeamarkTileOverlay: MKTileOverlay {
    init() {
        super.init(urlTemplate: "https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png")
        canReplaceMapContent = false
        maximumZ = 18
        minimumZ = 8
    }
}

/// RainViewer radar overlay. The tile URL embeds a timestamped frame path that
/// must be fetched from RainViewer's index first; call `latest()` to build one
/// pointing at the most recent radar frame.
enum RadarTiles {
    static func latest() async -> MKTileOverlay? {
        guard let url = URL(string: "https://api.rainviewer.com/public/weather-maps.json"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let host = json["host"] as? String,
              let radar = json["radar"] as? [String: Any],
              let past = radar["past"] as? [[String: Any]],
              let path = past.last?["path"] as? String else {
            return nil
        }
        // colour scheme 2 (Universal Blue), smooth=1, snow=1
        let overlay = MKTileOverlay(urlTemplate: "\(host)\(path)/256/{z}/{x}/{y}/2/1_1.png")
        overlay.canReplaceMapContent = false
        return overlay
    }
}
