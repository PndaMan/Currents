import SwiftUI
import MapKit

/// One downloaded map: where it covers and where the close-ups are, its
/// size and detail, and update, rename, pause, resume, cancel and delete.
struct OfflinePackDetailView: View {
    let packId: String
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var outline: [[CLLocationCoordinate2D]] = []
    @State private var place: String?
    @State private var confirmDelete = false
    @State private var confirmCancel = false
    @State private var renaming = false
    @State private var draftName = ""
    @State private var titleShown = false

    private var manager: MapManager { appState.mapManager }
    private var pack: OfflinePack? { manager.pack(packId) }

    var body: some View {
        Group {
            if let pack {
                content(pack)
            } else {
                ContentUnavailableView("Map removed", systemImage: "map",
                                       description: Text("This offline map is no longer on your phone."))
                    .dsScreenBackground()
            }
        }
        .pfScrollTitle(pack?.name ?? "Offline map", shown: titleShown)
        .task {
            guard let pack, pack.kind == .region, let id = pack.regionId else { return }
            // The bundled outlines decode off the main thread.
            let found = await Task.detached(priority: .userInitiated) { () -> ([[CLLocationCoordinate2D]], String) in
                (OfflineRegionCatalog.outline(id), Self.place(of: id))
            }.value
            outline = found.0
            place = found.1
        }
    }

    private func content(_ pack: OfflinePack) -> some View {
        let live = manager.liveProgress[pack.id]
        return ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s5) {
                preview(pack)
                    .padding(.horizontal, DS.gutter)
                DetailHeader(over: pack.kind == .area ? "Area" : place, title: pack.name, subtitle: OfflineFormat.status(pack, live: live))

                if pack.status != .complete {
                    progress(pack, live: live)
                }

                actions(pack)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.Space.s2), GridItem(.flexible())],
                          spacing: DS.Space.s2) {
                    StatTile("Size", systemImage: "internaldrive", tint: .green,
                             value: OfflineFormat.bytes(live?.bytes ?? pack.bytes),
                             footnote: pack.status == .complete ? nil : "So far", width: nil)
                    StatTile("Detail", systemImage: "square.3.layers.3d", tint: .blue,
                             value: pack.detail.title,
                             footnote: detailNote(pack.detail), width: nil)
                    StatTile("Close-ups", systemImage: "scope", tint: .teal,
                             value: closeUpValue(pack),
                             footnote: closeUpFootnote(pack), width: nil)
                    StatTile("Saved", systemImage: "calendar", tint: .orange,
                             value: OfflineFormat.date(pack.completedAt ?? pack.createdAt),
                             footnote: pack.completedAt == nil ? "Started" : "Last updated", width: nil)
                }
                .padding(.horizontal, DS.gutter)

                PFFootnote("\(OfflineTileOverlay.attribution). Works on the Offline map style in Explore.")
            }
            .padding(.top, DS.Space.s2)
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
        }
        .detailTint(.green)
        .pfTrackScroll($titleShown, threshold: 260)
        .confirmationDialog("Delete \(pack.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete map", role: .destructive) {
                Haptics.warning()
                manager.delete(pack.id)
                ToastCenter.shared.show("\(pack.name) deleted", style: .info, haptic: false)
                dismiss()
            }
        } message: {
            Text("Frees \(OfflineFormat.bytes(pack.bytes)). The map there will need signal until you download it again.")
        }
        .confirmationDialog(pack.isUpdating ? "Stop updating?" : "Cancel this download?",
                            isPresented: $confirmCancel, titleVisibility: .visible) {
            Button(pack.isUpdating ? "Stop updating" : "Cancel download", role: .destructive) {
                Haptics.warning()
                let wasNew = pack.completedAt == nil
                manager.cancel(pack.id)
                if wasNew { dismiss() }
            }
        } message: {
            Text(pack.isUpdating
                 ? "The map keeps everything it has, fresh or not."
                 : "What has downloaded so far is deleted.")
        }
        .alert("Rename map", isPresented: $renaming) {
            TextField("Name", text: $draftName)
            Button("Save") { manager.rename(pack.id, to: draftName) }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Parts

    private func preview(_ pack: OfflinePack) -> some View {
        Map(initialPosition: .region(pack.bounds.region(padding: pack.kind == .area ? 1.3 : 1.1)),
            interactionModes: [.pan, .zoom]) {
            if pack.kind == .area {
                MapPolygon(coordinates: corners(pack.bounds))
                    .foregroundStyle(DS.accent.opacity(0.14))
                    .stroke(DS.accent, lineWidth: 2)
            }
            ForEach(Array(outline.enumerated()), id: \.offset) { _, ring in
                MapPolygon(coordinates: ring)
                    .foregroundStyle(DS.accent.opacity(0.14))
                    .stroke(DS.accent, lineWidth: 2)
            }
            ForEach(Array(pack.closeUps.prefix(400).enumerated()), id: \.offset) { _, rect in
                MapPolygon(coordinates: corners(rect))
                    .foregroundStyle(Color.white.opacity(0.32))
                    .stroke(.white, lineWidth: 1)
            }
        }
        .mapStyle(.hybrid(elevation: .flat))
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .accessibilityLabel("Map of the area \(pack.name) covers")
    }

    private func progress(_ pack: OfflinePack, live: OfflineDownloader.Progress?) -> some View {
        let done = live?.done ?? pack.savedTiles
        let total = max(live?.total ?? pack.tileCount, 1)
        return VStack(alignment: .leading, spacing: DS.Space.s2) {
            ProgressView(value: Double(done), total: Double(total))
                .tint(pack.status == .paused ? Color.dsText3 : DS.accent)
            Text(pack.pauseReason ?? "\(done.formatted()) of \(total.formatted()) tiles. Keep Currents open to finish sooner.")
                .font(.footnote)
                .foregroundStyle(.dsText2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DS.gutter)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func actions(_ pack: OfflinePack) -> some View {
        switch pack.status {
        case .downloading:
            ActionTriple([
                ActionItem("Pause", systemImage: "pause.fill") { Haptics.tap(); manager.pause(pack.id) },
                ActionItem(pack.isUpdating ? "Stop" : "Cancel", systemImage: "xmark", isDestructive: true) {
                    confirmCancel = true
                },
            ])
        case .paused:
            ActionTriple([
                ActionItem("Resume", systemImage: "play.fill") { Haptics.tap(); manager.resume(pack.id) },
                ActionItem(pack.isUpdating ? "Stop" : "Cancel", systemImage: "xmark", isDestructive: true) {
                    confirmCancel = true
                },
            ], firstIsPrimary: true)
        case .complete:
            ActionTriple([
                ActionItem("Update", systemImage: "arrow.clockwise") { Haptics.tap(); manager.update(pack.id) },
                ActionItem("Rename", systemImage: "pencil") { draftName = pack.name; renaming = true },
                ActionItem("Delete", systemImage: "trash", isDestructive: true) { confirmDelete = true },
            ])
        }
    }

    /// "Province in South Africa", or "Country".
    nonisolated private static func place(of id: String) -> String {
        guard let region = OfflineRegionCatalog.region(id) else { return "Country" }
        let country = OfflineRegionCatalog.country(region.countryId).map(OfflineRegionCatalog.displayName)
        return [OfflineFormat.kind(region), country].compactMap { $0 }.joined(separator: " in ")
    }

    private func detailNote(_ detail: OfflineDetail) -> String {
        switch detail {
        case .overview: "Roads and shorelines"
        case .standard: "Banks and launch sites"
        case .maximum: "Rocks and weed beds"
        }
    }

    private func closeUpValue(_ pack: OfflinePack) -> String {
        if pack.kind == .area { return "Whole area" }
        if pack.closeUpZoom <= pack.overviewZoom { return "None" }
        return "\(pack.watersIncluded + pack.placesIncluded)"
    }

    private func closeUpFootnote(_ pack: OfflinePack) -> String? {
        guard pack.kind == .region, pack.closeUpZoom > pack.overviewZoom else { return nil }
        var parts: [String] = []
        if pack.watersIncluded > 0 { parts.append(OfflineFormat.waters(pack.watersIncluded)) }
        if pack.placesIncluded > 0 { parts.append(OfflineFormat.places(pack.placesIncluded)) }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private func corners(_ r: GeoRect) -> [CLLocationCoordinate2D] {
        [CLLocationCoordinate2D(latitude: r.maxLat, longitude: r.minLon),
         CLLocationCoordinate2D(latitude: r.maxLat, longitude: r.maxLon),
         CLLocationCoordinate2D(latitude: r.minLat, longitude: r.maxLon),
         CLLocationCoordinate2D(latitude: r.minLat, longitude: r.minLon)]
    }
}
