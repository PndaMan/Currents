import SwiftUI
import CoreLocation

/// Manages offline map state, region downloads, and tile sources.
/// MapLibre integration will wrap this — for now this handles the data layer.
@Observable
final class MapManager {
    /// Downloaded offline regions stored in Documents/tiles/
    var downloadedRegions: [OfflineRegion] = []

    /// Path to the app's tile storage directory.
    var tilesDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let tiles = docs.appendingPathComponent("tiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: tiles, withIntermediateDirectories: true)
        return tiles
    }

    /// Check which PMTiles files are available locally.
    func refreshDownloadedRegions() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: tilesDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey]
        ) else {
            downloadedRegions = []
            return
        }

        downloadedRegions = files
            .filter { $0.pathExtension == "pmtiles" }
            .compactMap { url in
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
                return OfflineRegion(
                    name: url.deletingPathExtension().lastPathComponent
                        .replacingOccurrences(of: "_", with: " ")
                        .capitalized,
                    fileURL: url,
                    sizeBytes: Int64(values?.fileSize ?? 0),
                    downloadedAt: values?.creationDate ?? .now
                )
            }
    }
}

struct OfflineRegion: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let fileURL: URL
    let sizeBytes: Int64
    let downloadedAt: Date

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}
