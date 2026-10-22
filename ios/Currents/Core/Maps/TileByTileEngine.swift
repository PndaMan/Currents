import Foundation
import CoreLocation
import GRDB
import UIKit

/// Saves an offline map tile by tile from an XYZ source into one SQLite file
/// per map (`<id>.sqlite`, table `tiles(k, data)` keyed by `TileMath.key`),
/// and serves those tiles to the map overlay.
struct TileByTileEngine: OfflineEngine {
    let source: any TileSource
    /// Requests at once.
    let parallel: Int

    private static let batch = 48

    func download(_ job: OfflineJob, report: @escaping @Sendable (OfflineProgress) async -> Void) async -> OfflineOutcome {
        let files = OfflineTileFiles.shared
        let packId = job.pack.id
        let tiles = OfflinePlanner.tiles(for: job.pack, rings: job.outline)
        let parallel = max(1, self.parallel)
        let source = self.source

        let config = URLSessionConfiguration.default
        config.allowsCellularAccess = job.allowCellular
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 20
        config.httpMaximumConnectionsPerHost = parallel
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        let refresh = job.refresh
        let existing = refresh ? Set<Int64>() : files.existingKeys(packId)
        let begin = refresh ? min(max(job.pack.updateCursor ?? 0, 0), tiles.count) : 0
        let todo = tiles[begin...].filter { !existing.contains($0) }
        var done = tiles.count - todo.count
        var failed: [Int64] = []
        var stalls = 0
        var lastError: URLError?

        func fetchAll(_ keys: [Int64]) async -> [(Int64, Data?, URLError?)] {
            await withTaskGroup(of: (Int64, Data?, URLError?).self) { group in
                var results: [(Int64, Data?, URLError?)] = []
                var iterator = keys.makeIterator()
                for _ in 0..<parallel {
                    guard let key = iterator.next() else { break }
                    group.addTask { await TileByTileEngine.fetch(key, session: session, source: source) }
                }
                while let result = await group.next() {
                    results.append(result)
                    if let key = iterator.next() {
                        group.addTask { await TileByTileEngine.fetch(key, session: session, source: source) }
                    }
                }
                return results
            }
        }

        var position = begin
        var index = todo.startIndex
        while index < todo.endIndex {
            if Task.isCancelled { return .stopped }
            let end = min(index + Self.batch, todo.endIndex)
            let chunk = Array(todo[index..<end])
            let results = await fetchAll(chunk)
            if Task.isCancelled { return .stopped }

            let saved = results.compactMap { key, data, _ in data.map { (key, $0) } }
            do {
                try files.write(packId, tiles: saved)
            } catch {
                return .stalled("Could not save the map. Free some space and resume.")
            }
            let errors = results.filter { $0.2 != nil }
            failed.append(contentsOf: errors.map { $0.0 })
            lastError = errors.last?.2 ?? lastError
            done += chunk.count - errors.count
            position = refresh ? begin + end : position
            index = end

            if saved.isEmpty && errors.count == chunk.count {
                stalls += 1
                if stalls >= 2 { return .stalled(Self.reason(for: lastError)) }
            } else {
                stalls = 0
            }
            await report(OfflineProgress(done: done, total: tiles.count,
                                         bytes: OfflinePackStore.shared.size(packId), cursor: position))
        }

        // One more go at anything a blip dropped.
        if !failed.isEmpty, !Task.isCancelled {
            let retry = await fetchAll(failed)
            let saved = retry.compactMap { key, data, _ in data.map { (key, $0) } }
            try? files.write(packId, tiles: saved)
            let stillFailed = retry.filter { $0.2 != nil }
            done += retry.count - stillFailed.count
            await report(OfflineProgress(done: done, total: tiles.count,
                                         bytes: OfflinePackStore.shared.size(packId), cursor: tiles.count))
            if !stillFailed.isEmpty && !refresh {
                return .stalled(Self.reason(for: stillFailed.last?.2))
            }
        }
        if Task.isCancelled { return .stopped }
        files.compact(packId)
        await report(OfflineProgress(done: tiles.count, total: tiles.count,
                                     bytes: OfflinePackStore.shared.size(packId), cursor: tiles.count))
        return .finished
    }

    func register(_ pack: OfflinePack) {
        OfflineTileFiles.shared.setCoverage(pack, visible: pack.source == source.id)
    }

    func close(_ packId: String) {
        OfflineTileFiles.shared.close(packId)
    }

    func preview(_ pack: OfflinePack, pixels: CGFloat) -> UIImage? {
        Self.stitch(pack, pixels: pixels)
    }

    // MARK: Fetching

    /// One tile. Data on success; no data and no error when the source has
    /// nothing there (nothing to retry); an error when it should be retried.
    private static func fetch(_ key: Int64, session: URLSession, source: any TileSource) async -> (Int64, Data?, URLError?) {
        let t = TileMath.unpack(key)
        switch await source.fetch(z: t.z, x: t.x, y: t.y, session: session) {
        case .tile(let data): return (key, data, nil)
        case .empty: return (key, nil, nil)
        case .failed(let error): return (key, nil, error)
        }
    }

    private static func reason(for error: URLError?) -> String {
        guard let error else { return "Some of the map did not download. Resume to try again." }
        if error.networkUnavailableReason == .cellular {
            return "Waiting for Wi-Fi. Turn on mobile data downloads to carry on now."
        }
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost, .cannotFindHost:
            return "Lost signal. Resume when you are back online."
        case .badServerResponse:
            return "The map server is busy. Resume in a few minutes."
        default:
            return "Some of the map did not download. Resume to try again."
        }
    }

    // MARK: Preview

    /// Stitches the map's own overview tiles into a square, so the picture
    /// works with no signal.
    private static func stitch(_ pack: OfflinePack, pixels: CGFloat) -> UIImage? {
        let files = OfflineTileFiles.shared
        let b = pack.bounds
        var z = min(pack.overviewZoom, 14)
        while z > OfflinePlanner.minZoom {
            let cols = TileMath.x(b.maxLon, z) - TileMath.x(b.minLon, z) + 1
            let rows = TileMath.y(b.minLat, z) - TileMath.y(b.maxLat, z) + 1
            if cols <= 3 && rows <= 3 { break }
            z -= 1
        }
        let x0 = TileMath.x(b.minLon, z), x1 = TileMath.x(b.maxLon, z)
        let y0 = TileMath.y(b.maxLat, z), y1 = TileMath.y(b.minLat, z)
        guard x1 >= x0, y1 >= y0 else { return nil }
        let tile: CGFloat = 256
        let canvas = CGSize(width: CGFloat(x1 - x0 + 1) * tile, height: CGFloat(y1 - y0 + 1) * tile)
        var found = false
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
        let full = renderer.image { _ in
            for tx in x0...x1 {
                for ty in y0...y1 {
                    guard let data = files.tile(pack.id, z: z, x: TileMath.wrap(tx, z), y: ty),
                          let img = UIImage(data: data) else { continue }
                    found = true
                    img.draw(in: CGRect(x: CGFloat(tx - x0) * tile, y: CGFloat(ty - y0) * tile, width: tile, height: tile))
                }
            }
        }
        guard found, let cg = full.cgImage else { return nil }
        // Crop to a square on the area's middle.
        let n = Double(1 << z)
        func px(_ lon: Double) -> CGFloat { CGFloat(((lon + 180) / 360 * n - Double(x0)) * 256) }
        func py(_ lat: Double) -> CGFloat {
            let l = min(max(lat, -TileMath.maxLatitude), TileMath.maxLatitude) * .pi / 180
            return CGFloat(((1 - log(tan(l) + 1 / cos(l)) / .pi) / 2 * n - Double(y0)) * 256)
        }
        let rect = CGRect(x: px(b.minLon), y: py(b.maxLat), width: px(b.maxLon) - px(b.minLon), height: py(b.minLat) - py(b.maxLat))
        let sideLength = min(max(rect.width, rect.height, 64), canvas.width, canvas.height)
        var crop = CGRect(x: rect.midX - sideLength / 2, y: rect.midY - sideLength / 2, width: sideLength, height: sideLength)
        crop.origin.x = min(max(crop.origin.x, 0), canvas.width - sideLength)
        crop.origin.y = min(max(crop.origin.y, 0), canvas.height - sideLength)
        guard let cut = cg.cropping(to: crop.integral) else { return nil }
        let out = UIGraphicsImageRenderer(size: CGSize(width: pixels, height: pixels), format: format)
        return out.image { _ in
            UIImage(cgImage: cut).draw(in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        }
    }
}

/// The tile files of maps saved tile by tile. The map overlay reads from here
/// on its own queue while a download writes, so access to the open files is
/// locked.
final class OfflineTileFiles: @unchecked Sendable {
    static let shared = OfflineTileFiles()

    private let lock = NSLock()
    private var pools: [String: DatabasePool] = [:]
    /// Maps the overlay may read, with how far they reach.
    private var coverage: [String: (bounds: GeoRect, maxZoom: Int)] = [:]

    private func url(_ id: String) -> URL {
        OfflinePackStore.shared.fileURL(id, suffix: "sqlite")
    }

    /// Opens (creating if needed) the map's tile file.
    private func pool(_ id: String) throws -> DatabasePool {
        lock.lock()
        defer { lock.unlock() }
        if let pool = pools[id] { return pool }
        var config = Configuration()
        config.label = "offline-map"
        let pool = try DatabasePool(path: url(id).path, configuration: config)
        try pool.write { db in
            try db.execute(sql: "CREATE TABLE IF NOT EXISTS tiles (k INTEGER PRIMARY KEY, data BLOB NOT NULL)")
        }
        pools[id] = pool
        return pool
    }

    func setCoverage(_ pack: OfflinePack, visible: Bool) {
        lock.lock()
        coverage[pack.id] = visible ? (pack.bounds, max(pack.overviewZoom, pack.closeUpZoom)) : nil
        lock.unlock()
    }

    /// A saved tile from any visible offline map that covers it.
    func tile(z: Int, x: Int, y: Int) -> Data? {
        let tileRect = GeoRect(minLat: TileMath.lat(ofY: Double(y + 1), z),
                               minLon: TileMath.lon(ofX: Double(x), z),
                               maxLat: TileMath.lat(ofY: Double(y), z),
                               maxLon: TileMath.lon(ofX: Double(x + 1), z))
        lock.lock()
        let candidates = coverage.filter { $0.value.maxZoom >= z && $0.value.bounds.intersects(tileRect) }.map { $0.key }
        lock.unlock()
        for id in candidates {
            if let data = tile(id, z: z, x: x, y: y) { return data }
        }
        return nil
    }

    /// A saved tile from one map.
    func tile(_ id: String, z: Int, x: Int, y: Int) -> Data? {
        guard FileManager.default.fileExists(atPath: url(id).path), let pool = try? pool(id) else { return nil }
        let key = TileMath.key(z, x, y)
        return try? pool.read { db in
            try Data.fetchOne(db, sql: "SELECT data FROM tiles WHERE k = ?", arguments: [key])
        }
    }

    func existingKeys(_ id: String) -> Set<Int64> {
        guard let pool = try? pool(id),
              let keys = try? pool.read({ db in try Int64.fetchAll(db, sql: "SELECT k FROM tiles") }) else { return [] }
        return Set(keys)
    }

    func write(_ id: String, tiles: [(Int64, Data)]) throws {
        guard !tiles.isEmpty else { return }
        let pool = try pool(id)
        try pool.write { db in
            for (key, data) in tiles {
                try db.execute(sql: "INSERT OR REPLACE INTO tiles (k, data) VALUES (?, ?)", arguments: [key, data])
            }
        }
    }

    /// Folds the write-ahead log back into the file once a download ends.
    func compact(_ id: String) {
        guard let pool = try? pool(id) else { return }
        try? pool.writeWithoutTransaction { db in
            _ = try db.checkpoint(.truncate)
        }
    }

    /// Closes the map's file so it can be deleted.
    func close(_ id: String) {
        lock.lock()
        let pool = pools.removeValue(forKey: id)
        coverage.removeValue(forKey: id)
        lock.unlock()
        try? pool?.close()
    }
}
