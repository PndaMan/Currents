import Foundation

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

/// A source of satellite tiles for the offline map style and for offline
/// downloads, with the limits it sets on them.
///
/// Everything that shows, caches or downloads tiles reads
/// `TileSources.current`: the map overlay, the browse cache, the download
/// planner and the downloader. Moving to another provider (another XYZ raster
/// service, or a PMTiles basemap read with range requests) is a change to this
/// file alone. Downloaded maps record the source they came from, and maps from
/// an earlier source stop showing until they are updated.
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
    /// Requests at once while downloading.
    var maxConcurrentRequests: Int { get }
    /// Typical bytes per tile, for size estimates before any are measured.
    var typicalTileBytes: Int64 { get }
    /// Folder for tiles cached while browsing, under Caches.
    var cacheFolder: String { get }

    /// One 256 pixel tile in the XYZ (slippy map) scheme.
    func fetch(z: Int, x: Int, y: Int, session: URLSession) async -> TileFetch
}

/// The source in use. Change `current` to switch provider.
enum TileSources {
    static let current: any TileSource = XYZRasterSource.esriWorldImagery
}

/// A raster tile service addressed by a URL template with `{z}`, `{x}` and
/// `{y}`, which covers most imagery providers.
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
    var maxConcurrentRequests = 6
    var typicalTileBytes: Int64 = 22_000
    var cacheFolder: String

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
    /// tiles for offline use, so this is for test builds until a source
    /// licensed for offline use replaces it here.
    static let esriWorldImagery = XYZRasterSource(
        id: "esri-world-imagery",
        name: "Esri World Imagery",
        attribution: "Imagery from Esri, Maxar, Earthstar Geographics, and the GIS User Community",
        urlTemplate: "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}",
        cacheFolder: "MapTiles"
    )
}
