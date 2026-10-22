import Foundation
import CoreLocation

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
    /// Progress in the engine's own units (see `OfflineProgress`).
    var doneUnits: Int
    var totalUnits: Int
    /// The size worked out before downloading.
    var estimatedBytes: Int64
    /// On disk.
    var bytes: Int64
    var status: Status
    /// Why it stopped, when it stopped by itself.
    var pauseReason: String?
    /// Set while updating: the engine's place in the update.
    var updateCursor: Int?
    var createdAt: Date
    var completedAt: Date?
    /// The tile source the pack was saved from.
    var source: String

    var progress: Double {
        totalUnits > 0 ? min(Double(doneUnits) / Double(totalUnits), 1) : 0
    }

    var isUpdating: Bool { updateCursor != nil }

    /// Saved from a source other than the one in use, so hidden until updated.
    var isFromEarlierSource: Bool { source != TileSources.current.id }
}

/// The list of offline maps (packs.json) and the folder their files live in,
/// Application Support/OfflineMaps. What is in each map's files is up to the
/// download engine; every file is named with the map's id as a prefix, so
/// sizes and deletes here work for any engine.
final class OfflinePackStore: @unchecked Sendable {
    static let shared = OfflinePackStore()

    let directory: URL

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

    // MARK: Files

    /// A file for a map, named `<id>.<suffix>`.
    func fileURL(_ id: String, suffix: String) -> URL {
        directory.appendingPathComponent("\(id).\(suffix)")
    }

    /// Every file belonging to a map.
    func files(_ id: String) -> [URL] {
        let all = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return all.filter { $0.lastPathComponent.hasPrefix(id + ".") }
    }

    /// Bytes on disk for a map, whatever its engine keeps.
    func size(_ id: String) -> Int64 {
        files(id).reduce(Int64(0)) { total, url in
            total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
    }

    /// Deletes a map's files. Close them with the engine first.
    func removeFiles(_ id: String) {
        for url in files(id) { try? FileManager.default.removeItem(at: url) }
    }

    /// Free space for new maps, as iOS reports it for things the person asked for.
    static var freeBytes: Int64 {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }
}
