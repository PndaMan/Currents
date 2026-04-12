import SwiftUI
import CoreLocation
import MapKit

/// Manages offline map state, region snapshots, and saved areas.
@Observable
final class MapManager {
    /// Downloaded/cached offline regions.
    var downloadedRegions: [OfflineRegion] = []
    var isDownloading = false

    /// Path to the app's tile storage directory.
    var tilesDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let tiles = docs.appendingPathComponent("tiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: tiles, withIntermediateDirectories: true)
        return tiles
    }

    /// Path to saved map regions metadata.
    private var regionsFile: URL {
        tilesDirectory.appendingPathComponent("regions.json")
    }

    /// Check which regions are saved locally.
    func refreshDownloadedRegions() {
        // Load from PMTiles files
        var regions: [OfflineRegion] = []

        if let files = try? FileManager.default.contentsOfDirectory(
            at: tilesDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey]
        ) {
            let pmtiles = files
                .filter { $0.pathExtension == "pmtiles" }
                .compactMap { url -> OfflineRegion? in
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
            regions.append(contentsOf: pmtiles)
        }

        // Load saved region snapshots
        if let data = try? Data(contentsOf: regionsFile),
           let saved = try? JSONDecoder().decode([SavedRegion].self, from: data) {
            for r in saved {
                let snapURL = tilesDirectory.appendingPathComponent(r.snapshotFile)
                let values = try? snapURL.resourceValues(forKeys: [.fileSizeKey])
                regions.append(OfflineRegion(
                    name: r.name,
                    fileURL: snapURL,
                    sizeBytes: Int64(values?.fileSize ?? 0),
                    downloadedAt: r.savedAt
                ))
            }
        }

        downloadedRegions = regions
    }

    /// Save a map region for offline reference.
    func saveRegion(name: String, center: CLLocationCoordinate2D, spanDegrees: Double) async {
        isDownloading = true
        defer { isDownloading = false }

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: spanDegrees, longitudeDelta: spanDegrees)
        )
        options.size = CGSize(width: 1024, height: 1024)
        options.mapType = .hybrid

        let snapshotter = MKMapSnapshotter(options: options)
        guard let snapshot = try? await snapshotter.start() else { return }

        let fileName = name.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .appending("_\(Int(Date().timeIntervalSince1970)).png")
        let fileURL = tilesDirectory.appendingPathComponent(fileName)

        if let data = snapshot.image.pngData() {
            try? data.write(to: fileURL)
        }

        // Save metadata
        var saved: [SavedRegion] = []
        if let data = try? Data(contentsOf: regionsFile),
           let existing = try? JSONDecoder().decode([SavedRegion].self, from: data) {
            saved = existing
        }
        saved.append(SavedRegion(
            name: name,
            latitude: center.latitude,
            longitude: center.longitude,
            spanDegrees: spanDegrees,
            snapshotFile: fileName,
            savedAt: .now
        ))
        if let data = try? JSONEncoder().encode(saved) {
            try? data.write(to: regionsFile)
        }

        refreshDownloadedRegions()
    }

    /// Delete a saved region.
    func deleteRegion(_ region: OfflineRegion) {
        try? FileManager.default.removeItem(at: region.fileURL)

        // Remove from metadata
        if let data = try? Data(contentsOf: regionsFile),
           var saved = try? JSONDecoder().decode([SavedRegion].self, from: data) {
            saved.removeAll { $0.snapshotFile == region.fileURL.lastPathComponent }
            if let newData = try? JSONEncoder().encode(saved) {
                try? newData.write(to: regionsFile)
            }
        }

        refreshDownloadedRegions()
    }
}

struct SavedRegion: Codable {
    let name: String
    let latitude: Double
    let longitude: Double
    let spanDegrees: Double
    let snapshotFile: String
    let savedAt: Date
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
