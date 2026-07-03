import Foundation
import MapKit

/// A disk-caching XYZ tile overlay.
///
/// Apple's own base-map tiles can't legally be cached for offline use, so for
/// the offline fishing view we render a cacheable satellite layer (Esri World
/// Imagery, which permits offline caching). Every tile fetched while online is
/// written to disk keyed by `z/x/y`; when the same tile is requested again —
/// including with no connectivity — it is served straight from disk.
///
/// Combined with `OfflineTilePrefetcher`, the area around the user is filled
/// into the cache in the background so it's visible even without signal.
final class OfflineTileOverlay: MKTileOverlay {
    static let template =
        "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"

    private let cacheDir: URL
    private let session: URLSession

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheDir = caches.appendingPathComponent("MapTiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 20
        self.session = URLSession(configuration: config)

        super.init(urlTemplate: OfflineTileOverlay.template)
        self.canReplaceMapContent = true
        self.maximumZ = 19
        self.minimumZ = 3
    }

    private func fileURL(for path: MKTileOverlayPath) -> URL {
        cacheDir
            .appendingPathComponent("\(path.z)", isDirectory: true)
            .appendingPathComponent("\(path.x)_\(path.y).jpg")
    }

    override func url(forTilePath path: MKTileOverlayPath) -> URL {
        URL(string: Self.template
            .replacingOccurrences(of: "{z}", with: "\(path.z)")
            .replacingOccurrences(of: "{x}", with: "\(path.x)")
            .replacingOccurrences(of: "{y}", with: "\(path.y)"))!
    }

    override func loadTile(
        at path: MKTileOverlayPath,
        result: @escaping (Data?, Error?) -> Void
    ) {
        let cached = fileURL(for: path)

        // 1. Serve from disk if we already have it (works fully offline).
        if let data = try? Data(contentsOf: cached) {
            result(data, nil)
            return
        }

        // 2. Fetch, cache to disk, return.
        let task = session.dataTask(with: url(forTilePath: path)) { data, _, error in
            if let data {
                try? FileManager.default.createDirectory(
                    at: cached.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try? data.write(to: cached, options: .atomic)
            }
            result(data, error)
        }
        task.resume()
    }

    /// Async wrapper used by the prefetcher.
    func fetchAndCache(_ path: MKTileOverlayPath) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            loadTile(at: path) { _, _ in cont.resume() }
        }
    }

    /// Total bytes currently cached on disk.
    var cacheSizeBytes: Int64 {
        guard let en = FileManager.default.enumerator(
            at: cacheDir, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in en {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }

    func clearCache() {
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }
}

/// Prefetches the tiles around a coordinate into the overlay's disk cache so
/// the surrounding area is browsable offline. Runs in the background and is
/// bounded so it never floods the tile server.
actor OfflineTilePrefetcher {
    private let overlay: OfflineTileOverlay
    private var lastCenter: CLLocationCoordinate2D?

    init(overlay: OfflineTileOverlay) {
        self.overlay = overlay
    }

    /// Cache a small ring of tiles around `center` at a couple of zoom levels.
    /// No-ops if we already prefetched a nearby center recently.
    func prefetch(around center: CLLocationCoordinate2D, zoomLevels: [Int] = [12, 14, 16]) async {
        if let last = lastCenter {
            let dLat = abs(last.latitude - center.latitude)
            let dLon = abs(last.longitude - center.longitude)
            if dLat < 0.02 && dLon < 0.02 { return } // moved < ~2km, skip
        }
        lastCenter = center

        for z in zoomLevels {
            let (cx, cy) = Self.tile(for: center, z: z)
            // 5×5 ring around the center tile
            for dx in -2...2 {
                for dy in -2...2 {
                    let path = MKTileOverlayPath(x: cx + dx, y: cy + dy, z: z, contentScaleFactor: 2)
                    await overlay.fetchAndCache(path)
                }
            }
        }
    }

    private static func tile(for coord: CLLocationCoordinate2D, z: Int) -> (Int, Int) {
        let n = pow(2.0, Double(z))
        let x = Int((coord.longitude + 180.0) / 360.0 * n)
        let latRad = coord.latitude * .pi / 180.0
        let y = Int((1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / .pi) / 2.0 * n)
        return (x, y)
    }
}
