import SwiftUI
import CoreLocation
import MapKit

/// Offline maps, as in Apple Maps' Settings: what is on the phone and how
/// much room it takes, each downloaded map with its size, date, update and
/// delete, suggestions from the angler's own places, and the two ways to
/// download (a square on the map, or any country or province).
struct OfflineMapsView: View {
    @Environment(AppState.self) private var appState
    @State private var request: OfflineDownloadRequest?
    @State private var suggestions: [OfflineSuggestion] = []
    @State private var showAllSuggestions = false
    @State private var packToDelete: OfflinePack?
    @State private var legacyToDelete: OfflineRegion?
    @State private var confirmClearCache = false
    @State private var cacheBytes: Int64 = 0
    @State private var freeBytes: Int64 = 0
    @State private var titleShown = false

    private var manager: MapManager { appState.mapManager }

    var body: some View {
        List {
            Section {
                DetailHeader(title: "Offline maps", subtitle: headerSubtitle)
                    .padding(.bottom, DS.Space.s2)
                    .pfBareRow()
                HStack(spacing: DS.Space.s2) {
                    StatTile("Maps", systemImage: "map.fill", tint: .green,
                             value: OfflineFormat.bytes(mapsBytes),
                             footnote: mapsFootnote, width: nil)
                    StatTile("Free", systemImage: "internaldrive", tint: .blue,
                             value: OfflineFormat.bytes(freeBytes),
                             footnote: "On this phone", width: nil)
                }
                .padding(.horizontal, DS.gutter)
                .padding(.bottom, DS.Space.s2)
                .pfBareRow()
            }

            Section {
                Button {
                    request = OfflineDownloadRequest(target: .area(nil, name: ""))
                } label: {
                    PFRowLabel(title: "Pick an area on the map", systemImage: "square.dashed", color: .green)
                }
                NavigationLink(value: OfflineMapsRoute.regions) {
                    PFRowLabel(title: "Countries and provinces", systemImage: "globe.europe.africa.fill", color: .blue)
                }
            } header: {
                Text("Download a map")
            } footer: {
                PFFootnote("Provinces and countries come as an overview with close-ups around their lakes, rivers and coast, and your own spots.")
            }
            .pfRows()

            yourMaps

            if !suggestions.isEmpty {
                Section {
                    ForEach(showAllSuggestions ? suggestions : Array(suggestions.prefix(5))) { s in
                        Button {
                            request = OfflineDownloadRequest(target: s.target)
                        } label: {
                            SuggestionRow(suggestion: s)
                        }
                        .accessibilityHint("Opens the download options")
                    }
                    if suggestions.count > 5 {
                        Button(showAllSuggestions ? "Show fewer" : "Show all \(suggestions.count)") {
                            withAnimation(DS.Motion.fast) { showAllSuggestions.toggle() }
                        }
                    }
                } header: {
                    Text("Suggested")
                }
                .pfRows()
            }

            Section {
                PFToggleRow(title: "Cache maps as I browse",
                            detail: "Keeps satellite tiles around you for no signal",
                            isOn: Binding(get: { manager.autoCacheEnabled },
                                          set: { manager.autoCacheEnabled = $0 }))
                PFToggleRow(title: "Download on mobile data",
                            detail: "When off, map downloads wait for Wi-Fi",
                            isOn: Binding(get: { manager.downloadOnCellular },
                                          set: { manager.downloadOnCellular = $0 }))
                LabeledContent("Cached as you browse", value: OfflineFormat.bytes(cacheBytes))
                Button("Clear map cache", role: .destructive) { confirmClearCache = true }
                    .disabled(cacheBytes == 0)
            } header: {
                Text("Cache and downloads")
            }
            .pfRows()

            if !manager.legacyMaps.isEmpty {
                legacySection
            }

            Section {
                PFFootnote("\(OfflineTileOverlay.attribution). Country and province outlines from Natural Earth.")
                    .padding(.horizontal, DS.gutter)
                    .padding(.vertical, DS.Space.s2)
                    .pfBareRow()
            }
        }
        .pfGroupedList()
        .detailTint(.green)
        .pfTrackScroll($titleShown)
        .pfScrollTitle("Offline maps", shown: titleShown)
        .navigationDestination(for: OfflineMapsRoute.self) { route in
            switch route {
            case .regions: OfflineRegionBrowser()
            case .country(let country): OfflineCountryView(country: country)
            case .pack(let id): OfflinePackDetailView(packId: id)
            }
        }
        .sheet(item: $request) { OfflineDownloadSheet(target: $0.target) }
        .task {
            manager.refreshDownloadedRegions()
            await measure()
        }
        .task(id: suggestionKey) { await loadSuggestions() }
        .confirmationDialog("Delete \(packToDelete?.name ?? "this map")?",
                            isPresented: Binding(get: { packToDelete != nil },
                                                 set: { if !$0 { packToDelete = nil } }),
                            titleVisibility: .visible,
                            presenting: packToDelete) { pack in
            Button("Delete map", role: .destructive) {
                Haptics.warning()
                manager.delete(pack.id)
                ToastCenter.shared.show("\(pack.name) deleted", style: .info, haptic: false)
                Task { await measure() }
            }
        } message: { pack in
            Text("Frees \(OfflineFormat.bytes(manager.liveProgress[pack.id]?.bytes ?? pack.bytes)). The map there will need signal until you download it again.")
        }
        .confirmationDialog("Delete \(legacyToDelete?.name ?? "this picture")?",
                            isPresented: Binding(get: { legacyToDelete != nil },
                                                 set: { if !$0 { legacyToDelete = nil } }),
                            titleVisibility: .visible,
                            presenting: legacyToDelete) { region in
            Button("Delete picture", role: .destructive) {
                Haptics.warning()
                manager.deleteRegion(region)
                ToastCenter.shared.show("\(region.name) deleted", style: .info, haptic: false)
            }
        } message: { region in
            Text("Frees \(region.formattedSize).")
        }
        .confirmationDialog("Clear the map cache?", isPresented: $confirmClearCache, titleVisibility: .visible) {
            Button("Clear cache", role: .destructive) {
                Haptics.warning()
                manager.clearTileCache()
                ToastCenter.shared.show("Map cache cleared", style: .info, haptic: false)
                Task { await measure() }
            }
        } message: {
            Text("Frees \(OfflineFormat.bytes(cacheBytes)). Downloaded maps are kept.")
        }
    }

    // MARK: Your maps

    @ViewBuilder
    private var yourMaps: some View {
        Section {
            if manager.packs.isEmpty {
                HStack(spacing: 14) {
                    ThumbView(systemImage: "map", tint: .green, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No offline maps yet")
                            .foregroundStyle(.dsText)
                        Text("Download your waters before you head out of signal.")
                            .font(.subheadline)
                            .foregroundStyle(.dsText2)
                    }
                }
                .accessibilityElement(children: .combine)
            } else {
                ForEach(manager.packs) { pack in
                    NavigationLink(value: OfflineMapsRoute.pack(pack.id)) {
                        OfflinePackRow(pack: pack, live: manager.liveProgress[pack.id])
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { packToDelete = pack } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        switch pack.status {
                        case .downloading:
                            Button { manager.pause(pack.id) } label: { Label("Pause", systemImage: "pause.fill") }
                                .tint(.orange)
                        case .paused:
                            Button { manager.resume(pack.id) } label: { Label("Resume", systemImage: "play.fill") }
                                .tint(.green)
                        case .complete:
                            Button { manager.update(pack.id) } label: { Label("Update", systemImage: "arrow.clockwise") }
                                .tint(.blue)
                        }
                    }
                    .contextMenu {
                        switch pack.status {
                        case .downloading:
                            Button { manager.pause(pack.id) } label: { Label("Pause", systemImage: "pause") }
                        case .paused:
                            Button { manager.resume(pack.id) } label: { Label("Resume", systemImage: "play") }
                        case .complete:
                            Button { manager.update(pack.id) } label: { Label("Update", systemImage: "arrow.clockwise") }
                        }
                        Button(role: .destructive) { packToDelete = pack } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        } header: {
            Text("Your maps")
        } footer: {
            if !manager.packs.isEmpty {
                PFFootnote("Swipe right to update or pause, left to delete. Maps show on the Offline map style in Explore.")
            }
        }
        .pfRows()
    }

    private var legacySection: some View {
        Section {
            ForEach(manager.legacyMaps) { region in
                HStack(spacing: 14) {
                    ThumbView(systemImage: "photo", tint: .gray, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(region.name).foregroundStyle(.dsText)
                        Text("\(region.formattedSize), saved \(OfflineFormat.date(region.downloadedAt))")
                            .font(.subheadline)
                            .foregroundStyle(.dsText2)
                    }
                    Spacer()
                    Button { legacyToDelete = region } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.dsText2)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.dim)
                    .accessibilityLabel("Delete \(region.name)")
                }
            }
        } header: {
            Text("Older saved regions")
        } footer: {
            PFFootnote("Earlier versions saved a flat picture of each region, which the map can't use. Download the area again for a map that works with no signal.")
        }
        .pfRows()
    }

    // MARK: Data

    private var mapsBytes: Int64 {
        manager.packBytes + manager.legacyMaps.reduce(Int64(0)) { $0 + $1.sizeBytes }
    }

    private var mapsFootnote: String {
        let n = manager.packs.count
        return n == 1 ? "1 map" : "\(n) maps"
    }

    private var headerSubtitle: String {
        if let active = manager.packs.first(where: { $0.status == .downloading }) {
            return OfflineFormat.status(active, live: manager.liveProgress[active.id])
                .replacingOccurrences(of: "Downloading", with: "Downloading \(active.name)")
                .replacingOccurrences(of: "Updating", with: "Updating \(active.name)")
        }
        return "Satellite maps that work with no signal."
    }

    /// Suggestions change when maps are added or removed.
    private var suggestionKey: String {
        manager.packs.filter { $0.status == .complete || $0.status == .downloading || $0.status == .paused }
            .map(\.id).joined(separator: ",")
    }

    private func loadSuggestions() async {
        let places = OfflineUserPlaces.load(appState)
        let location = places.location
        let home = await Task.detached(priority: .utility) {
            location.flatMap { OfflineRegionCatalog.region(containing: $0) }
        }.value
        guard !Task.isCancelled else { return }
        suggestions = OfflineSuggestions.build(appState: appState, places: places, homeRegion: home,
                                               packs: manager.packs, tileBytes: manager.measuredTileBytes())
    }

    private func measure() async {
        let overlay = manager.offlineOverlay
        let sizes = await Task.detached(priority: .utility) { () -> (Int64, Int64) in
            (overlay.cacheSizeBytes, OfflinePackStore.freeBytes)
        }.value
        cacheBytes = sizes.0
        freeBytes = sizes.1
    }
}

// MARK: - Rows

/// A downloaded map: its own picture, name, and size or progress.
struct OfflinePackRow: View {
    let pack: OfflinePack
    let live: OfflineDownloader.Progress?
    @State private var thumbnail: UIImage?

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let thumbnail {
                    ThumbView(image: thumbnail, tint: .green, size: 44)
                } else {
                    ThumbView(systemImage: pack.kind == .area ? "square.dashed" : "map.fill", tint: .green, size: 44)
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(pack.name)
                    .foregroundStyle(.dsText)
                    .lineLimit(1)
                Text(pack.pauseReason ?? OfflineFormat.status(pack, live: live))
                    .font(.subheadline)
                    .foregroundStyle(pack.pauseReason == nil ? Color.dsText2 : Color.orange)
                    .lineLimit(2)
                if pack.status != .complete {
                    ProgressView(value: Double(live?.done ?? pack.savedTiles),
                                 total: Double(max(live?.total ?? pack.tileCount, 1)))
                        .tint(pack.status == .paused ? Color.dsText3 : DS.accent)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .task(id: thumbnailKey) {
            thumbnail = OfflinePackThumbnail.cached(pack)
            if thumbnail == nil || pack.status == .complete {
                thumbnail = await OfflinePackThumbnail.image(for: pack) ?? thumbnail
            }
        }
    }

    /// A fresh picture every few hundred tiles while it downloads.
    private var thumbnailKey: Int {
        let saved = live?.done ?? pack.savedTiles
        return pack.status == .complete ? -1 : min(saved / 500, 4)
    }
}

/// A suggested download: what and where, and roughly how big.
private struct SuggestionRow: View {
    let suggestion: OfflineSuggestion

    var body: some View {
        HStack(spacing: 14) {
            ThumbView(systemImage: suggestion.systemImage, tint: suggestion.tint, size: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.title)
                    .foregroundStyle(.dsText)
                    .lineLimit(1)
                Text(suggestion.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let estimate = suggestion.estimate {
                Text(OfflineFormat.estimate(estimate))
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                    .monospacedDigit()
            }
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
