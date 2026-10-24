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
    @Environment(\.dynamicTypeSize) private var typeSize

    private var manager: MapManager { appState.mapManager }

    // The page is built in steps (page, routes, then each dialog) so the
    // type checker handles each part on its own.
    var body: some View {
        withLegacyDialog
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

    private var page: some View {
        TodayPage("Offline maps", subtitle: headerSubtitle) {
            statTiles
            downloadSection
            yourMaps
            suggestedSection
            cacheSection
            if !manager.legacyMaps.isEmpty {
                legacySection
            }
            SectionFootnote("\(OfflineTileOverlay.attribution). Country and province outlines from Natural Earth.")
        }
    }

    private var routed: some View {
        page
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
    }

    private var withPackDialog: some View {
        routed
            .confirmationDialog(packDialogTitle,
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
    }

    private var withLegacyDialog: some View {
        withPackDialog
            .confirmationDialog(legacyDialogTitle,
                                isPresented: Binding(get: { legacyToDelete != nil },
                                                     set: { if !$0 { legacyToDelete = nil } }),
                                titleVisibility: .visible,
                                presenting: legacyToDelete) { region in
                Button("Delete region", role: .destructive) {
                    Haptics.warning()
                    manager.deleteRegion(region)
                    ToastCenter.shared.show("\(region.name) deleted", style: .info, haptic: false)
                }
            } message: { region in
                Text("Frees \(region.formattedSize).")
            }
    }

    private var packDialogTitle: String { "Delete \(packToDelete?.name ?? "this map")?" }
    private var legacyDialogTitle: String { "Delete \(legacyToDelete?.name ?? "this region")?" }

    // MARK: Sections

    /// Room taken by maps and room left; stacked at accessibility sizes.
    private var statTiles: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: DS.Space.s2))
            : AnyLayout(HStackLayout(spacing: DS.Space.s2))
        return layout {
            StatTile("Maps", systemImage: "map.fill", tint: .green,
                     value: OfflineFormat.bytes(mapsBytes),
                     footnote: mapsFootnote, width: nil)
            StatTile("Free", systemImage: "internaldrive", tint: .blue,
                     value: OfflineFormat.bytes(freeBytes),
                     footnote: "On this phone", width: nil)
        }
        .padding(.horizontal, DS.gutter)
    }

    private var downloadSection: some View {
        CardSection("Download a map", note: "Close-ups around water and your spots.") {
            Button {
                request = OfflineDownloadRequest(target: .area(nil, name: ""))
            } label: {
                CardRow("Pick an area on the map", systemImage: "square.dashed", tint: .green)
            }
            .buttonStyle(.dsCardRow)
            NavigationLink(value: OfflineMapsRoute.regions) {
                CardRow("Countries and regions", systemImage: "globe.europe.africa.fill", tint: .blue, chevron: true)
            }
            .buttonStyle(.dsCardRow)
        }
    }

    @ViewBuilder
    private var suggestedSection: some View {
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionTitle("Suggested")
                CardGroup(separatorInset: Self.thumbInset) {
                    ForEach(showAllSuggestions ? suggestions : Array(suggestions.prefix(5))) { s in
                        Button {
                            request = OfflineDownloadRequest(target: s.target)
                        } label: {
                            SuggestionRow(suggestion: s)
                        }
                        .buttonStyle(.dsCardRow)
                        .accessibilityHint("Opens the download options")
                    }
                }
                if suggestions.count > 5 {
                    Button(showAllSuggestions ? "Show fewer" : "Show all \(suggestions.count)") {
                        withAnimation(.easeInOut(duration: DS.Motion.fast)) { showAllSuggestions.toggle() }
                    }
                    .buttonStyle(TonalButtonStyle(fullWidth: false))
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, DS.Space.s3)
                }
            }
        }
    }

    private var cacheSection: some View {
        CardSection("Cache and downloads") {
            CardToggleRow("Cache maps as I browse",
                          subtitle: "Keeps tiles around you for no signal",
                          systemImage: "square.stack.3d.down.right.fill", tint: .cyan,
                          isOn: Binding(get: { manager.autoCacheEnabled },
                                        set: { manager.autoCacheEnabled = $0 }))
            CardToggleRow("Download on mobile data",
                          subtitle: "Off waits for Wi-Fi",
                          systemImage: "antenna.radiowaves.left.and.right", tint: .green,
                          isOn: Binding(get: { manager.downloadOnCellular },
                                        set: { manager.downloadOnCellular = $0 }))
            CardRow("Cached as you browse", systemImage: "internaldrive.fill", tint: .blue,
                    value: OfflineFormat.bytes(cacheBytes))
            Button { confirmClearCache = true } label: {
                CardRow("Clear map cache", systemImage: "trash.fill", tint: .red)
            }
            .buttonStyle(.dsCardRow)
            .disabled(cacheBytes == 0)
            .opacity(cacheBytes == 0 ? 0.5 : 1)
        }
    }

    // MARK: Your maps

    /// Each map opens its page, which has update, pause and delete; a touch
    /// and hold offers the same here.
    @ViewBuilder
    private var yourMaps: some View {
        if manager.packs.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionTitle("Your maps")
                InlineEmpty(systemImage: "map",
                            text: "No offline maps yet. Download your waters before you lose signal.")
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                SectionTitle("Your maps")
                CardGroup(separatorInset: Self.thumbInset) {
                    ForEach(manager.packs) { pack in
                        NavigationLink(value: OfflineMapsRoute.pack(pack.id)) {
                            OfflinePackRow(pack: pack, live: manager.liveProgress[pack.id])
                        }
                        .buttonStyle(.dsCardRow)
                        .contextMenu { packMenu(pack) }
                    }
                }
                SectionFootnote("Touch and hold a map to update, pause or delete it.")
            }
        }
    }

    @ViewBuilder
    private func packMenu(_ pack: OfflinePack) -> some View {
        switch pack.status {
        case .downloading:
            Button { Haptics.toggle(); manager.pause(pack.id) } label: { Label("Pause", systemImage: "pause") }
        case .paused:
            Button { Haptics.toggle(); manager.resume(pack.id) } label: { Label("Resume", systemImage: "play") }
        case .complete:
            Button { manager.update(pack.id) } label: { Label("Update", systemImage: "arrow.clockwise") }
        }
        Button(role: .destructive) { packToDelete = pack } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private var legacySection: some View {
        CardSection("Older saved regions", note: "These can't be used with no signal. Download the area again.") {
            ForEach(manager.legacyMaps) { region in
                CardRow(region.name,
                        subtitle: "\(region.formattedSize), saved \(OfflineFormat.date(region.downloadedAt))",
                        systemImage: "photo", tint: .orange, combinesChildren: false) {
                    Button { legacyToDelete = region } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(Color.dsScoreSlow)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.dim)
                    .accessibilityLabel("Delete \(region.name)")
                }
            }
        }
    }

    /// Hairlines start past the 44 pt pictures on map and suggestion rows.
    private static let thumbInset: CGFloat = DS.Space.s4 + 44 + 14

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
                                               packs: manager.packs, scale: manager.estimateScale())
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

/// A downloaded map on a card: its own picture, name, and size or progress.
struct OfflinePackRow: View {
    let pack: OfflinePack
    let live: OfflineProgress?
    @State private var thumbnail: UIImage?
    @Environment(\.dynamicTypeSize) private var typeSize

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
                    .font(.body)
                    .foregroundStyle(.dsText)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                Text(pack.pauseReason ?? OfflineFormat.status(pack, live: live))
                    .font(.subheadline)
                    .foregroundStyle(pack.pauseReason == nil ? Color.dsText2 : DS.ink(Color.dsScoreLow))
                    .lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
                if pack.status != .complete {
                    ProgressView(value: Double(live?.done ?? pack.doneUnits),
                                 total: Double(max(live?.total ?? pack.totalUnits, 1)))
                        .tint(pack.status == .paused ? Color.dsText3 : DS.accent)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.dsText3)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, 10)
        .frame(minHeight: 54)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .task(id: thumbnailKey) {
            thumbnail = OfflinePackThumbnail.cached(pack)
            if thumbnail == nil || pack.status == .complete {
                thumbnail = await OfflinePackThumbnail.image(for: pack) ?? thumbnail
            }
        }
    }

    /// A fresh picture every fifth of the way while it downloads.
    private var thumbnailKey: Int {
        pack.status == .complete ? -1 : OfflinePackThumbnail.stage(pack, live: live)
    }
}

/// A suggested download on a card: what and where, and roughly how big.
private struct SuggestionRow: View {
    let suggestion: OfflineSuggestion
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 14) {
            ThumbView(systemImage: suggestion.systemImage, tint: suggestion.tint, size: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.title)
                    .font(.body)
                    .foregroundStyle(.dsText)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                Text(suggestion.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                    .lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let estimate = suggestion.estimate {
                Text(OfflineFormat.estimate(estimate))
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                    .monospacedDigit()
            }
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(DS.accent)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, 10)
        .frame(minHeight: 54)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
