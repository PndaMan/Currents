import Foundation
import CoreLocation
import UIKit

/// What one tile request came back with.
enum TileFetch: Sendable {
    /// The tile image.
    case tile(Data)
    /// The source has nothing there (open sea, the poles), so there is
    /// nothing to save and nothing to retry.
    case empty
    /// Worth another go later: no signal, a timeout, or the server is busy.
    case failed(URLError)
}

/// A source of map tiles for the offline map style and for offline
/// downloads, with the limits it sets on them.
///
/// Everything that shows, caches or downloads tiles reads
/// `TileSources.current`: the map overlay, the browse cache, the download
/// planner and the download engine. Moving to another provider (another XYZ
/// raster service, or vector tiles saved as one extract file per area) is a
/// change here: a new source, and if it saves maps differently, its own
/// `OfflineEngine`. Downloaded maps record the source they came from, and maps
/// from an earlier source stop showing until they are updated.
protocol TileSource: Sendable {
    /// Saved with each downloaded map.
    var id: String { get }
    /// The provider's name, for About.
    var name: String { get }
    /// The credit the provider asks for wherever its tiles are shown.
    var attribution: String { get }
    /// Shallowest and deepest zoom the map asks for.
    var minZoom: Int { get }
    var maxZoom: Int { get }
    /// Deepest zoom an offline download saves.
    var maxDownloadZoom: Int { get }
    /// Hard cap on tiles in one downloaded map, however big the area.
    var maxTilesPerDownload: Int { get }
    /// Folder for tiles cached while browsing, under Caches.
    var cacheFolder: String { get }
    /// How this source saves an area for use with no signal.
    var offlineEngine: any OfflineEngine { get }

    /// Typical bytes for one tile at a zoom, for size estimates before any
    /// map from this source has been measured.
    func typicalTileBytes(zoom: Int) -> Int64

    /// One 256 pixel tile in the XYZ (slippy map) scheme.
    func fetch(z: Int, x: Int, y: Int, session: URLSession) async -> TileFetch
}

/// The source in use. Change `current` to switch provider.
enum TileSources {
    static let current: any TileSource = XYZRasterSource.esriWorldImagery
}

// MARK: - Download engines

/// How far a download has got. `done` and `total` count whatever the engine
/// works in (tiles for a tile by tile download, bytes for a single extract
/// file); screens only show the fraction and `bytes`.
struct OfflineProgress: Sendable {
    var done: Int
    var total: Int
    /// On disk so far.
    var bytes: Int64
    /// The engine's own place to carry on an update from.
    var cursor: Int
}

enum OfflineOutcome: Sendable {
    case finished
    /// Stopped by itself, with the reason to show.
    case stalled(String)
    /// The task was cancelled: paused, cancelled or deleted by the person,
    /// or iOS ran out of background time.
    case stopped
}

/// One run of a download.
struct OfflineJob: Sendable {
    var pack: OfflinePack
    /// The outline when the map is a country or region, else empty.
    var outline: [[CLLocationCoordinate2D]]
    /// Fetch everything again (an update), from `pack.updateCursor`, instead
    /// of carrying on from what is already saved.
    var refresh: Bool
    var allowCellular: Bool
}

/// Saves an offline map's data and shows it on the map. Packs keep their
/// plan (area, outline, overview zoom, close-ups), so an engine can save them
/// tile by tile, as now, or as one extract file per area. Each engine keeps
/// its files in `OfflinePackStore.directory`, named with the pack id as a
/// prefix (`<id>.sqlite`, `<id>.pmtiles`), so sizes and deletes work for any
/// engine.
protocol OfflineEngine: Sendable {
    /// Downloads the map, or carries on from where it stopped, until it is
    /// done, the task is cancelled, or it cannot go on.
    func download(_ job: OfflineJob, report: @escaping @Sendable (OfflineProgress) async -> Void) async -> OfflineOutcome
    /// Shows a map's saved data on the map view, or hides it when it came
    /// from another source.
    func register(_ pack: OfflinePack)
    /// Closes anything held open for a map before its files are deleted.
    func close(_ packId: String)
    /// A small square picture of the map from its own saved data, or nil.
    func preview(_ pack: OfflinePack, pixels: CGFloat) -> UIImage?
}

// MARK: - XYZ raster

/// A raster tile service addressed by a URL template with `{z}`, `{x}` and
/// `{y}`, which covers most imagery providers. Offline maps are saved tile by
/// tile.
struct XYZRasterSource: TileSource {
    let id: String
    let name: String
    let attribution: String
    let urlTemplate: String
    var headers: [String: String] = [:]
    var minZoom = 3
    var maxZoom = 19
    var maxDownloadZoom = 17
    var maxTilesPerDownload = 30_000
    /// Requests at once while downloading.
    var maxConcurrentRequests = 6
    /// Satellite tiles are much the same size at every zoom.
    var tileBytes: Int64 = 22_000
    var cacheFolder: String

    var offlineEngine: any OfflineEngine { TileByTileEngine(source: self, parallel: maxConcurrentRequests) }

    func typicalTileBytes(zoom: Int) -> Int64 { tileBytes }

    func url(z: Int, x: Int, y: Int) -> URL? {
        URL(string: urlTemplate
            .replacingOccurrences(of: "{z}", with: "\(z)")
            .replacingOccurrences(of: "{x}", with: "\(x)")
            .replacingOccurrences(of: "{y}", with: "\(y)"))
    }

    func fetch(z: Int, x: Int, y: Int, session: URLSession) async -> TileFetch {
        guard let url = url(z: z, x: x, y: y) else { return .empty }
        var request = URLRequest(url: url)
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            if status == 200, !data.isEmpty { return .tile(data) }
            if status == 429 || status >= 500 { return .failed(URLError(.badServerResponse)) }
            return .empty
        } catch let error as URLError {
            return .failed(error)
        } catch {
            return .failed(URLError(.unknown))
        }
    }
}

extension XYZRasterSource {
    /// Esri World Imagery. Esri's terms do not allow bulk downloading its
    /// tiles for offline use, so this is for test builds until offline maps
    /// move to a source licensed for it.
    static let esriWorldImagery = XYZRasterSource(
        id: "esri-world-imagery",
        name: "Esri World Imagery",
        attribution: "Imagery from Esri, Maxar, Earthstar Geographics, and the GIS User Community",
        urlTemplate: "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}",
        cacheFolder: "MapTiles"
    )
}
