import SwiftUI
import CoreLocation
import MapKit

/// Offline maps: the browse cache that follows the angler, and the maps
/// they download on purpose (regions and squares), with their downloads.
@MainActor
@Observable
final class MapManager {
    /// Shared cacheable satellite overlay + background prefetcher used for the
    /// offline map. Not observed (they aren't view state), and @Observable
    /// rewrites stored vars into computed properties which can't be `lazy`.
    @ObservationIgnored let offlineOverlay = OfflineTileOverlay()
    @ObservationIgnored private(set) lazy var prefetcher = OfflineTilePrefetcher(overlay: offlineOverlay)

    /// Downloaded maps, newest first, including ones still downloading.
    private(set) var packs: [OfflinePack] = []
    /// Live progress for maps downloading right now.
    private(set) var liveProgress: [String: OfflineProgress] = [:]
    /// Saved map pictures from before offline maps (not used by the map).
    private(set) var legacyMaps: [OfflineRegion] = []

    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var stopping: [String: StopReason] = [:]
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var lastSaved = Date.distantPast
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    /// Downloads iOS stopped when the app went to the background, to carry
    /// on when it comes back (or at the next launch).
    @ObservationIgnored private var resumeWhenActive: Set<String> = []

    private enum StopReason { case pause, cancel, delete }

    init() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.resumeAfterBackground() }
        }
    }

    /// Whether to automatically cache surrounding tiles as the user moves.
    var autoCacheEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "autoCacheMaps") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoCacheMaps") }
    }

    /// Whether map downloads may use mobile data. Off by default, as in
    /// Google Maps, because a region can run to hundreds of megabytes.
    var downloadOnCellular: Bool {
        get { access(keyPath: \.downloadOnCellular); return UserDefaults.standard.bool(forKey: "offlineMapsCellular") }
        set {
            withMutation(keyPath: \.downloadOnCellular) {
                UserDefaults.standard.set(newValue, forKey: "offlineMapsCellular")
            }
        }
    }

    /// Bytes of satellite tiles cached on disk for offline viewing.
    var tileCacheSizeBytes: Int64 { offlineOverlay.cacheSizeBytes }

    /// Bytes of downloaded maps.
    var packBytes: Int64 { packs.reduce(Int64(0)) { $0 + (liveProgress[$1.id]?.bytes ?? $1.bytes) } }

    /// Downloaded maps that are ready to use, for badges and counts.
    var downloadedRegions: [OfflineRegion] {
        packs.filter { $0.status == .complete || $0.isUpdating }.map { pack in
            OfflineRegion(name: pack.name,
                          fileURL: OfflinePackStore.shared.directory.appendingPathComponent(pack.id),
                          sizeBytes: pack.bytes,
                          downloadedAt: pack.completedAt ?? pack.createdAt)
        }
    }

    var isDownloading: Bool { packs.contains { $0.status == .downloading } }

    /// Prefetch tiles around a coordinate for offline use (background, bounded).
    func prefetchOfflineTiles(around center: CLLocationCoordinate2D) {
        guard autoCacheEnabled else { return }
        Task.detached(priority: .background) { [prefetcher] in
            await prefetcher.prefetch(around: center)
        }
    }

    /// Keep the offline cache anchored to the PERSON, not wherever they last
    /// browsed: when the user has moved ≥ 15 km from the stored anchor, drop
    /// tiles far from their new position and prefetch a fresh ring around it,
    /// so the cache follows them instead of wasting space on old areas.
    func maintainOfflineCache(around userLocation: CLLocationCoordinate2D) {
        guard autoCacheEnabled else { return }
        let defaults = UserDefaults.standard
        let lastLat = defaults.object(forKey: "offlineCacheAnchorLat") as? Double
        let lastLon = defaults.object(forKey: "offlineCacheAnchorLon") as? Double
        if let lastLat, let lastLon {
            let moved = CLLocation(latitude: lastLat, longitude: lastLon)
                .distance(from: CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude))
            guard moved >= 15_000 else { return }
        }
        defaults.set(userLocation.latitude, forKey: "offlineCacheAnchorLat")
        defaults.set(userLocation.longitude, forKey: "offlineCacheAnchorLon")

        Task.detached(priority: .background) { [offlineOverlay, prefetcher] in
            offlineOverlay.pruneTiles(farFrom: userLocation, keepKm: 60)
            await prefetcher.prefetch(around: userLocation, zoomLevels: [10, 12, 14, 16])
        }
    }

    func clearTileCache() {
        offlineOverlay.clearCache()
    }

    // MARK: Downloaded maps

    /// Loads the list of maps on first call and carries on any download the
    /// app was closed during; later calls refresh sizes and older pictures.
    func refreshDownloadedRegions() {
        if !loaded {
            loaded = true
            packs = OfflinePackStore.shared.loadPacks().sorted { $0.createdAt > $1.createdAt }
            for pack in packs { engine.register(pack) }
            for i in packs.indices where packs[i].status == .downloading {
                adoptCurrentSource(i)
                run(packs[i].id)
            }
        }
        for i in packs.indices where tasks[packs[i].id] == nil {
            packs[i].bytes = OfflinePackStore.shared.size(packs[i].id)
        }
        legacyMaps = loadLegacyMaps()
    }

    func pack(_ id: String) -> OfflinePack? { packs.first { $0.id == id } }

    /// Starts downloading a new map and returns its id.
    @discardableResult
    func startDownload(name: String, kind: OfflinePack.Kind, regionId: String?, bounds: GeoRect,
                       plan: OfflinePlan) -> String {
        let pack = OfflinePack(
            id: UUID().uuidString, name: name, kind: kind, regionId: regionId, bounds: bounds,
            detail: plan.detail, overviewZoom: plan.overviewZoom, closeUpZoom: plan.closeUpZoom,
            closeUps: plan.closeUps, watersIncluded: plan.watersIncluded, placesIncluded: plan.placesIncluded,
            doneUnits: 0, totalUnits: plan.tileCount, estimatedBytes: plan.estimatedBytes, bytes: 0,
            status: .downloading, pauseReason: nil,
            updateCursor: nil, createdAt: .now, completedAt: nil, source: TileSources.current.id)
        packs.insert(pack, at: 0)
        engine.register(pack)
        persist()
        run(pack.id)
        return pack.id
    }

    func pause(_ id: String) {
        if resumeWhenActive.remove(id) != nil, let i = packs.firstIndex(where: { $0.id == id }) {
            packs[i].pauseReason = nil
            persist()
        }
        guard tasks[id] != nil else { return }
        stopping[id] = .pause
        tasks[id]?.cancel()
    }

    func resume(_ id: String) {
        resumeWhenActive.remove(id)
        guard let i = packs.firstIndex(where: { $0.id == id }), tasks[id] == nil else { return }
        packs[i].status = .downloading
        packs[i].pauseReason = nil
        adoptCurrentSource(i)
        persist()
        run(id)
    }

    /// Stops a download. A new map is removed; an update keeps the map as it was.
    func cancel(_ id: String) {
        guard let pack = pack(id) else { return }
        if tasks[id] != nil {
            stopping[id] = .cancel
            tasks[id]?.cancel()
        } else {
            finishCancel(pack)
        }
    }

    /// Fetches every tile of a finished map again, from the current tile
    /// source (which also brings back a map saved from an earlier one).
    func update(_ id: String) {
        guard let i = packs.firstIndex(where: { $0.id == id }), tasks[id] == nil else { return }
        packs[i].updateCursor = 0
        packs[i].status = .downloading
        packs[i].pauseReason = nil
        adoptCurrentSource(i)
        persist()
        run(id)
    }

    /// Moves a map onto the current tile source. Its tiles from the earlier
    /// source are fetched again in place.
    private func adoptCurrentSource(_ i: Int) {
        let source = TileSources.current
        guard packs[i].source != source.id else { return }
        packs[i].source = source.id
        packs[i].closeUpZoom = min(packs[i].closeUpZoom, source.maxDownloadZoom)
        if packs[i].updateCursor == nil { packs[i].updateCursor = 0 }
        engine.register(packs[i])
    }

    func rename(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = packs.firstIndex(where: { $0.id == id }) else { return }
        packs[i].name = trimmed
        persist()
    }

    func delete(_ id: String) {
        if tasks[id] != nil {
            stopping[id] = .delete
            tasks[id]?.cancel()
            return
        }
        removePack(id)
    }

    /// Older saved map pictures can only be deleted.
    func deleteRegion(_ region: OfflineRegion) {
        try? FileManager.default.removeItem(at: region.fileURL)
        if let data = try? Data(contentsOf: regionsFile),
           var saved = try? JSONDecoder().decode([SavedRegion].self, from: data) {
            saved.removeAll { $0.snapshotFile == region.fileURL.lastPathComponent }
            if let newData = try? JSONEncoder().encode(saved) {
                try? newData.write(to: regionsFile)
            }
        }
        refreshDownloadedRegions()
    }

    /// How far finished downloads from the current source came out from
    /// their estimates, so new estimates match what the source really sends.
    func estimateScale() -> Double {
        let done = packs.filter {
            $0.status == .complete && !$0.isFromEarlierSource && $0.estimatedBytes > 0 && $0.bytes > 2_000_000
        }
        let estimated = done.reduce(Int64(0)) { $0 + $1.estimatedBytes }
        let actual = done.reduce(Int64(0)) { $0 + $1.bytes }
        guard estimated > 0 else { return 1 }
        return min(max(Double(actual) / Double(estimated), 0.25), 4)
    }

    /// The engine the current tile source saves maps with.
    private var engine: any OfflineEngine { TileSources.current.offlineEngine }

    // MARK: Running downloads

    private func run(_ id: String) {
        guard let pack = pack(id), tasks[id] == nil else { return }
        beginBackgroundTime()
        let allowCellular = downloadOnCellular
        let engine = self.engine
        tasks[id] = Task { [weak self] in
            let outline = await Task.detached(priority: .utility) { () -> [[CLLocationCoordinate2D]] in
                pack.kind == .region ? (pack.regionId.map(OfflineRegionCatalog.outline) ?? []) : []
            }.value
            let job = OfflineJob(pack: pack, outline: outline, refresh: pack.isUpdating, allowCellular: allowCellular)
            let outcome = await engine.download(job) { progress in
                await MainActor.run { self?.apply(progress, to: id) }
            }
            self?.finish(id, outcome: outcome)
        }
    }

    private func apply(_ progress: OfflineProgress, to id: String) {
        liveProgress[id] = progress
        guard let i = packs.firstIndex(where: { $0.id == id }) else { return }
        packs[i].doneUnits = progress.done
        packs[i].totalUnits = progress.total
        packs[i].bytes = progress.bytes
        if packs[i].isUpdating { packs[i].updateCursor = progress.cursor }
        // Write the list now and then so a crash loses little.
        if Date.now.timeIntervalSince(lastSaved) > 5 { persist() }
    }

    private func finish(_ id: String, outcome: OfflineOutcome) {
        tasks[id] = nil
        liveProgress[id] = nil
        let reason = stopping.removeValue(forKey: id)
        defer {
            if tasks.isEmpty { endBackgroundTime() }
        }
        switch reason {
        case .delete:
            removePack(id)
            return
        case .cancel:
            if let pack = pack(id) { finishCancel(pack) }
            return
        case .pause, nil:
            break
        }
        guard let i = packs.firstIndex(where: { $0.id == id }) else { return }
        packs[i].bytes = OfflinePackStore.shared.size(id)
        switch outcome {
        case .finished:
            packs[i].status = .complete
            packs[i].doneUnits = packs[i].totalUnits
            packs[i].updateCursor = nil
            packs[i].completedAt = .now
            packs[i].pauseReason = nil
            ToastCenter.shared.show("\(packs[i].name) is ready offline")
        case .stalled(let message):
            packs[i].status = .paused
            packs[i].pauseReason = message
        case .stopped:
            packs[i].status = .paused
            if reason == nil {
                // iOS ran out the clock in the background.
                packs[i].pauseReason = "Carries on when you come back to Currents."
                resumeWhenActive.insert(id)
            }
        }
        persist()
    }

    private func resumeAfterBackground() {
        let ids = resumeWhenActive
        resumeWhenActive = []
        for id in ids { resume(id) }
    }

    private func finishCancel(_ pack: OfflinePack) {
        guard let i = packs.firstIndex(where: { $0.id == pack.id }) else { return }
        if pack.completedAt != nil {
            // An update stopped part way: the map keeps every tile it has.
            packs[i].status = .complete
            packs[i].updateCursor = nil
            packs[i].pauseReason = nil
            packs[i].bytes = OfflinePackStore.shared.size(pack.id)
            persist()
        } else {
            removePack(pack.id)
        }
    }

    private func removePack(_ id: String) {
        engine.close(id)
        OfflinePackStore.shared.removeFiles(id)
        packs.removeAll { $0.id == id }
        liveProgress[id] = nil
        persist()
    }

    private func persist() {
        // Downloads iOS stopped are saved as still downloading, so a relaunch picks them up.
        let saved = packs.map { pack -> OfflinePack in
            var p = pack
            if resumeWhenActive.contains(p.id) { p.status = .downloading; p.pauseReason = nil }
            return p
        }
        OfflinePackStore.shared.savePacks(saved)
        lastSaved = .now
    }

    /// A little time to keep going after the app is switched away; when it
    /// runs out the download stops and carries on at the next launch.
    private func beginBackgroundTime() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Offline map download") { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                for task in self.tasks.values { task.cancel() }
                self.endBackgroundTime()
            }
        }
    }

    private func endBackgroundTime() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    // MARK: Older saved pictures

    /// Folder the earlier map pictures (and any bundled PMTiles) lived in.
    var tilesDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("tiles", isDirectory: true)
    }

    private var regionsFile: URL {
        tilesDirectory.appendingPathComponent("regions.json")
    }

    private func loadLegacyMaps() -> [OfflineRegion] {
        var regions: [OfflineRegion] = []
        if let files = try? FileManager.default.contentsOfDirectory(
            at: tilesDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey]
        ) {
            for url in files where url.pathExtension == "pmtiles" {
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
                regions.append(OfflineRegion(
                    name: url.deletingPathExtension().lastPathComponent
                        .replacingOccurrences(of: "_", with: " ")
                        .capitalized,
                    fileURL: url,
                    sizeBytes: Int64(values?.fileSize ?? 0),
                    downloadedAt: values?.creationDate ?? .now
                ))
            }
        }
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
        return regions
    }
}

/// A map picture saved by earlier versions.
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
