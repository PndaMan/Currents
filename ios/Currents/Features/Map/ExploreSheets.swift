import SwiftUI
import MapKit

// MARK: - Catch peek sheet

/// What a tapped catch pin opens: a half sheet with the catch, and buttons to
/// open it in full or read about the species. Spots and water open their full
/// page as a sheet instead (ExplorePlacePage).
struct PinPeek: Identifiable {
    enum Target {
        case catchItem(CatchDetail)
    }
    let target: Target

    var id: String {
        switch target {
        case .catchItem(let c): "catch:\(c.catchRecord.id)"
        }
    }
}

struct PinPeekSheet: View {
    let peek: PinPeek
    /// Closes the sheet and pushes a page on the Explore stack.
    var onOpen: (ExploreRoute) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch peek.target {
                case .catchItem(let c): catchContent(c)
                }
            }
            .padding(.bottom, DS.Space.s6)
            .pageWidth()
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color.dsBackground.ignoresSafeArea())
        .dsSheet([.medium, .large])
    }

    @ViewBuilder
    private func catchContent(_ c: CatchDetail) -> some View {
        let name = c.species?.commonName ?? "Catch"
        let length = c.catchRecord.lengthCm.map { ", \(Units.length(cm: $0))" } ?? ""
        HStack(spacing: 14) {
            CatchThumb(detail: c, size: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text(name + length)
                    .font(.title2.bold())
                    .foregroundStyle(.dsText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(ExploreFormat.shortDate(c.catchRecord.caughtAt))
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.gutter)
        .padding(.top, DS.Space.s6)
        .padding(.bottom, DS.Space.s4)

        if let kg = c.catchRecord.weightKg { KVRow("Weight", Units.weight(kg: kg)) }
        KVRow("Spot", c.spot?.name ?? "Unsaved place")
        KVRow("Released", c.catchRecord.released ? "Yes" : "No, kept", divider: false)
        HStack(spacing: DS.Space.s2) {
            Button { onOpen(.catchDetail(CatchRef(c))) } label: { Label("Open catch", systemImage: "book.closed") }
                .buttonStyle(ActionTileStyle(.primary))
            if let sp = c.species {
                Button { onOpen(.species(sp)) } label: { Label("Open species", systemImage: "fish") }
                    .buttonStyle(ActionTileStyle())
                    .accessibilityHint("Opens the \(sp.commonName) page")
            }
        }
        .padding(.horizontal, DS.gutter)
        .padding(.top, DS.Space.s4)
    }
}

enum SpotFormat {
    static func spotType(for type: Waterbody.WaterbodyType) -> Spot.SpotType {
        switch type {
        case .dam: .dam
        case .lake: .lake
        case .river: .river
        case .estuary: .estuary
        case .coast: .beach
        }
    }
}

// MARK: - Ramp sheet

/// Tap a ramp or fishing access point: what it is, then Save spot,
/// Directions and Share, the same three actions as every other place.
struct RampDetailSheet: View {
    @Environment(AppState.self) private var appState
    let ramp: BoatRamp
    @State private var savedSpot: Spot?
    @State private var savedTick = 0
    @State private var confirmingRemove = false

    private var shareURL: URL? {
        let q = ramp.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://maps.apple.com/?ll=\(ramp.lat),\(ramp.lon)&q=\(q)")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                actions
                VStack(spacing: 0) {
                    KVRow("Type", ramp.kind.label)
                    KVRow("Location", ExploreFormat.coords(ramp.coordinate), divider: false)
                }
                .padding(.top, DS.Space.s4)
                ExploreFootnote(BoatRampService.shared.isNamedAfterTown(ramp)
                    ? "From OpenStreetMap, town name from GeoNames. Check access and fees at the gate."
                    : "From OpenStreetMap. Check access and fees at the gate.")
            }
            .padding(.bottom, DS.Space.s6)
            .pageWidth()
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color.dsBackground.ignoresSafeArea())
        .dsSheet([.medium, .large])
        .confirmationDialog("Remove \(ramp.name) from your spots?", isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("Remove spot", role: .destructive) { Haptics.warning(); remove() }
        } message: {
            Text("Catches logged here stay in your Logbook.")
        }
        .task {
            savedSpot = ((try? appState.spotRepository.fetchAll()) ?? []).first {
                abs($0.latitude - ramp.lat) < 0.0002 && abs($0.longitude - ramp.lon) < 0.0002
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            PlaceSnapshotThumb(place: ramp)
            VStack(alignment: .leading, spacing: 2) {
                Text(ramp.name)
                    .font(.title2.bold())
                    .foregroundStyle(.dsText)
                    .fixedSize(horizontal: false, vertical: true)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.dsText2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.gutter)
        .padding(.top, DS.Space.s6)
    }

    /// Save spot, Directions and Share, in the order of every place sheet.
    private var actions: some View {
        ActionTriple {
            Button {
                if savedSpot == nil { save() } else { confirmingRemove = true }
            } label: {
                Label(savedSpot == nil ? "Save spot" : "Saved", systemImage: savedSpot == nil ? "bookmark" : "bookmark.fill")
            }
            .buttonStyle(ActionTileStyle(savedSpot == nil ? .primary : .tonal))
            .symbolEffect(.bounce, value: savedTick)
            .accessibilityHint(savedSpot == nil ? "Adds it to your spots" : "Removes it from your spots")
            DirectionsMenu(coordinate: ramp.coordinate, name: ramp.name) {
                ActionTileLabel("Directions", systemImage: "location.north.line")
            }
            if let shareURL {
                ShareLink(item: shareURL) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(ActionTileStyle())
            }
        }
        .padding(.top, DS.Space.s5)
    }

    private var subtitle: String {
        let d = ExploreFormat.distance(from: appState.locationManager.currentLocation?.coordinate, to: ramp.coordinate)
        return ExploreFormat.rampLine(ramp, distance: d.map { "\($0) away" },
                                      side: BoatRampService.shared.side(of: ramp))
    }

    private func remove() {
        guard let savedSpot else { return }
        do {
            try ExploreSpots.remove(savedSpot, in: appState)
            self.savedSpot = nil
            ToastCenter.shared.show("Removed from your spots", style: .info, haptic: false, icon: "bookmark")
        } catch {
            ToastCenter.shared.show("Couldn't remove the spot", style: .error)
        }
    }

    private func save() {
        var spot = Spot(name: ramp.name, latitude: ramp.lat, longitude: ramp.lon,
                        spotType: ramp.kind == .ramp ? .harbour : .general)
        do {
            try appState.spotRepository.save(&spot)
            savedSpot = spot
            savedTick += 1
            ToastCenter.shared.show("\(ramp.name) saved to your spots", icon: "bookmark.fill")
        } catch {
            ToastCenter.shared.show("Couldn't save the spot", style: .error)
        }
    }
}

// MARK: - Layers sheet

/// Map style tiles, what shows on the map, and the overlays that draw on the
/// offline map. Every choice is stored by MapTab.
struct MapLayersSheet: View {
    @Binding var style: MapTab.MapStyleOption
    @Binding var showSpots: Bool
    @Binding var showCatches: Bool
    @Binding var showWater: Bool
    @Binding var showRamps: Bool
    @Binding var nautical: Bool
    @Binding var radar: Bool
    @Binding var wind: Bool
    @Binding var current: Bool
    /// Opens the offline download for the area the map shows. The row is
    /// left out when nil.
    var onDownloadArea: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DS.Space.s3) {
                            ForEach(MapTab.MapStyleOption.allCases, id: \.self) { option in
                                styleTile(option)
                            }
                        }
                        .padding(.horizontal, DS.gutter)
                    }
                    if style == .imagery || style == .hybrid {
                        ExploreFootnote("Satellite needs a connection. The offline map keeps the tiles you have viewed.")
                    }

                    GroupLabel("Show on map")
                    toggle("Your spots", "mappin", $showSpots)
                    toggle("Your catches", "fish", $showCatches)
                    toggle("Water bodies", "water.waves", $showWater)
                    toggle("Ramps and access", "figure.fishing", $showRamps, divider: false)

                    GroupLabel("Overlays")
                    toggle("Depth and sea marks", "ruler", $nautical, detail: "From OpenSeaMap")
                    toggle("Weather radar", "cloud.rain", $radar, detail: "Live rain from RainViewer")
                    toggle("Wind", "wind", $wind, detail: "Animated, from the latest weather")
                    toggle("Current", "arrow.left.arrow.right", $current, detail: "Animated surface drift", divider: false)
                    ExploreFootnote("Overlays draw on the offline map, so turning one on switches to it.")

                    if let onDownloadArea {
                        GroupLabel("Offline")
                        Button {
                            dismiss()
                            onDownloadArea()
                        } label: {
                            ExploreActionRow(title: "Download this area", systemImage: "arrow.down.circle",
                                             showsDivider: false)
                        }
                        .buttonStyle(.dsRow)
                        ExploreFootnote("Keeps the map you are looking at, and the water in it, for when there is no signal.")
                    }
                }
                .padding(.vertical, DS.Space.s3)
            }
            .background(Color.dsBackground.ignoresSafeArea())
            .detailScrollEdge()
            .navigationTitle("Map layers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    SheetDoneButton()
                }
            }
        }
        .dsSheet([.medium, .large])
    }

    private func styleTile(_ option: MapTab.MapStyleOption) -> some View {
        let selected = style == option
        return Button {
            style = option
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon(option))
                    .font(.title2)
                    .foregroundStyle(selected ? Color.dsText : Color.dsText2)
                    .frame(width: 104, height: 72)
                    .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
                            .stroke(selected ? DS.accent : Color.clear, lineWidth: 2.5)
                    )
                Text(option.title)
                    .font(.subheadline.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.dsText : Color.dsText2)
            }
        }
        .buttonStyle(.dim)
        .buttonHaptic(.selection)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func icon(_ option: MapTab.MapStyleOption) -> String {
        switch option {
        case .offline: "wifi.slash"
        case .standard: "map"
        case .imagery: "globe.europe.africa.fill"
        case .hybrid: "square.split.2x2"
        case .fishing: "fish"
        }
    }

    private func toggle(_ title: String, _ icon: String, _ binding: Binding<Bool>,
                        detail: String? = nil, divider: Bool = true) -> some View {
        VStack(spacing: 0) {
            Toggle(isOn: binding) {
                HStack(spacing: 14) {
                    Image(systemName: icon)
                        .foregroundStyle(.dsText2)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).foregroundStyle(.dsText)
                        if let detail {
                            Text(detail).font(.subheadline).foregroundStyle(.dsText2)
                        }
                    }
                }
            }
            .tint(Color.dsScoreGood)
            .padding(.vertical, 10)
            if divider {
                Rectangle().fill(Color.dsSeparator).frame(height: 0.5).padding(.leading, 38)
            }
        }
        .padding(.horizontal, DS.gutter)
    }
}
