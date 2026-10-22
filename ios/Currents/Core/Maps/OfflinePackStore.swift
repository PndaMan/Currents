import Foundation
import CoreLocation
import GRDB

/// How much detail an offline map carries.
enum OfflineDetail: String, Codable, CaseIterable, Sendable {
    /// The whole area at the overview zoom, no close-ups.
    case overview
    /// Close-ups to zoom 16, where banks, roads and launch sites are clear.
    case standard
    /// Close-ups to zoom 17, where rocks, weed beds and drop-offs show.
    case maximum

    /// Never deeper than the tile source allows downloads to go.
    var closeUpZoom: Int? {
        let limit = TileSources.current.maxDownloadZoom
        switch self {
        case .overview: return nil
        case .standard: return min(16, limit)
        case .maximum: return min(17, limit)
        }
    }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .standard: "Standard"
        case .maximum: "Maximum"
        }
    }
}

/// One offline map: what it covers, how it was planned (so a paused or
/// interrupted download picks up exactly where it stopped) and how far it got.
struct OfflinePack: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// A country or first-level region from the bundled list, masked by its outline.
        case region
        /// A square picked on the map, or a suggested area.
        case area
    }

    enum Status: String, Codable, Sendable {
        case downloading, paused, complete
    }

    var id: String
    var name: String
    var kind: Kind
    /// The bundled country or region id when `kind == .region`.
    var regionId: String?
    var bounds: GeoRect
    var detail: OfflineDetail
    /// The whole area is saved up to this zoom.
    var overviewZoom: Int
    /// Close-ups go from `overviewZoom + 1` to this zoom.
    var closeUpZoom: Int
    var closeUps: [GeoRect]
    var watersIncluded: Int
    var placesIncluded: Int
    var tileCount: Int
    var savedTiles: Int
    var bytes: Int64
    var status: Status
    /// Why it stopped, when it stopped by itself.
    var pauseReason: String?
    /// Set while updating: how many tiles, in plan order, are already fresh.
    var updateCursor: Int?
    var createdAt: Date
    var completedAt: Date?
    /// The tile source the pack was saved from.
    var source: String

    var progress: Double {
        tileCount > 0 ? min(Double(savedTiles) / Double(tileCount), 1) : 0
    }

    var isUpdating: Bool { updateCursor != nil }
}

/// The tiles of every offline map, one SQLite file per map under
/// Application Support/OfflineMaps, plus the list of maps in packs.json.
/// The tile overlay reads from here on its own queue while a download writes,
/// so access to the open files is locked.
final class OfflinePackStore: @unchecked Sendable {
    static let shared = OfflinePackStore()

    let directory: URL
    private let lock = NSLock()
    private var pools: [String: DatabasePool] = [:]
    private var coverage: [String: (bounds: GeoRect, maxZoom: Int)] = [:]

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        var dir = support.appendingPathComponent("OfflineMaps", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Maps can be downloaded again, so they stay out of iCloud backups.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        directory = dir
    }

    // MARK: List of maps

    private var manifestURL: URL { directory.appendingPathComponent("packs.json") }

    func loadPacks() -> [OfflinePack] {
        guard let data = try? Data(contentsOf: manifestURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([OfflinePack].self, from: data)) ?? []
    }

    func savePacks(_ packs: [OfflinePack]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(packs) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }

    // MARK: Tile files

    func fileURL(_ id: String) -> URL {
        directory.appendingPathComponent("\(id).sqlite")
    }

    /// Opens (creating if needed) the map's tile file.
    func pool(_ id: String) throws -> DatabasePool {
        lock.lock()
        defer { lock.unlock() }
        if let pool = pools[id] { return pool }
        var config = Configuration()
        config.label = "offline-map"
        let pool = try DatabasePool(path: fileURL(id).path, configuration: config)
        try pool.write { db in
            try db.execute(sql: "CREATE TABLE IF NOT EXISTS tiles (k INTEGER PRIMARY KEY, data BLOB NOT NULL)")
        }
        pools[id] = pool
        return pool
    }

    /// Lets the tile overlay find this map's tiles. Maps saved from another
    /// tile source are left out until they are updated.
    func register(_ pack: OfflinePack) {
        lock.lock()
        coverage[pack.id] = pack.source == TileSources.current.id
            ? (pack.bounds, max(pack.overviewZoom, pack.closeUpZoom)) : nil
        lock.unlock()
    }

    /// A saved tile from any offline map that covers it.
    func tile(z: Int, x: Int, y: Int) -> Data? {
        let tileRect = GeoRect(minLat: TileMath.lat(ofY: Double(y + 1), z),
                               minLon: TileMath.lon(ofX: Double(x), z),
                               maxLat: TileMath.lat(ofY: Double(y), z),
                               maxLon: TileMath.lon(ofX: Double(x + 1), z))
        lock.lock()
        let candidates = coverage.filter { $0.value.maxZoom >= z && $0.value.bounds.intersects(tileRect) }.map { $0.key }
        lock.unlock()
        let key = TileMath.key(z, x, y)
        for id in candidates {
            guard let pool = try? pool(id) else { continue }
            if let data = try? pool.read({ db in
                try Data.fetchOne(db, sql: "SELECT data FROM tiles WHERE k = ?", arguments: [key])
            }) {
                return data
            }
        }
        return nil
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

    func tileCount(_ id: String) -> Int {
        guard let pool = try? pool(id) else { return 0 }
        return (try? pool.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tiles") }) ?? 0
    }

    /// Folds the write-ahead log back into the file once a download ends.
    func compact(_ id: String) {
        guard let pool = try? pool(id) else { return }
        try? pool.writeWithoutTransaction { db in
            _ = try db.checkpoint(.truncate)
        }
    }

    /// Bytes on disk, including the write-ahead log while downloading.
    func size(_ id: String) -> Int64 {
        let base = fileURL(id).path
        return [base, base + "-wal", base + "-shm"].reduce(Int64(0)) { total, path in
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0
            return total + size
        }
    }

    /// Closes the map's file and deletes it.
    func remove(_ id: String) {
        lock.lock()
        let pool = pools.removeValue(forKey: id)
        coverage.removeValue(forKey: id)
        lock.unlock()
        try? pool?.close()
        let base = fileURL(id).path
        for path in [base, base + "-wal", base + "-shm"] {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    /// Free space for new maps, as iOS reports it for things the person asked for.
    static var freeBytes: Int64 {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }
}
