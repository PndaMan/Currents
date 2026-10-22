import SwiftUI
import MapKit

// MARK: - Pin peek sheet

/// What a tapped pin opens: a half sheet that loads behind a skeleton, with
/// the bite today and the main actions. "Open" pushes the full page.
struct PinPeek: Identifiable {
    enum Target {
        case spot(Spot)
        case water(Waterbody)
        case catchItem(CatchDetail)
    }
    let target: Target

    var id: String {
        switch target {
        case .spot(let s): "spot:\(s.id)"
        case .water(let w): "water:\(w.id ?? 0):\(w.name)"
        case .catchItem(let c): "catch:\(c.catchRecord.id)"
        }
    }

    var coordinate: CLLocationCoordinate2D {
        switch target {
        case .spot(let s): CLLocationCoordinate2D(latitude: s.latitude, longitude: s.longitude)
        case .water(let w): CLLocationCoordinate2D(latitude: w.latitude, longitude: w.longitude)
        case .catchItem(let c): CLLocationCoordinate2D(latitude: c.catchRecord.latitude, longitude: c.catchRecord.longitude)
        }
    }
}

struct PinPeekSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("use24HourTime") private var use24HourTime = true
    let peek: PinPeek
    /// Closes the sheet and pushes a page on the Explore stack.
    var onOpen: (ExploreRoute) -> Void

    @State private var bite: BiteSnapshot?
    @State private var species: [Species] = []
    @State private var loaded = false
    @State private var showingPlan = false
    @State private var savedWater = false

    private var userCoord: CLLocationCoordinate2D? { appState.locationManager.currentLocation?.coordinate }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if loaded {
                    content
                        .transition(.opacity.combined(with: .offset(y: 8)))
                } else {
                    SheetSkeleton().padding(.top, DS.Space.s6)
                }
            }
            .padding(.bottom, DS.Space.s6)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color.dsElevated.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.dsElevated)
        .task { await load() }
        .sheet(isPresented: $showingPlan) { PlanSessionSheet() }
        .sensoryFeedback(.success, trigger: savedWater)
    }

    @ViewBuilder
    private var content: some View {
        switch peek.target {
        case .spot(let spot):
            header(thumb: AnyView(spotThumb(spot)), title: spot.name,
                   subtitle: subtitle(ExploreFormat.spotType(spot), peek.coordinate))
            biteBlock
            ActionTriple {
                Button { onOpen(.spot(SpotRef(spot))) } label: { Label("Open", systemImage: "mappin") }
                    .buttonStyle(ActionTileStyle(.primary))
                DirectionsMenu(coordinate: peek.coordinate, name: spot.name) {
                    ActionTileLabel("Directions", systemImage: "location.north.line")
                }
                Button { showingPlan = true } label: { Label("Plan", systemImage: "calendar.badge.plus") }
                    .buttonStyle(ActionTileStyle())
            }
            .padding(.top, DS.Space.s4)
            speciesMinis(title: "Species caught here")
        case .water(let w):
            header(thumb: AnyView(ThumbView(systemImage: ExploreFormat.waterIcon(w.type), tint: .exploreWater)),
                   title: w.name,
                   subtitle: subtitle(ExploreFormat.waterType(w.type) + (w.surfaceAreaKm2.map { ", \(ExploreFormat.area($0))" } ?? ""),
                                      peek.coordinate))
            biteBlock
            ActionTriple {
                Button { onOpen(.waterbody(WaterbodyRef(w))) } label: { Label("Open", systemImage: "water.waves") }
                    .buttonStyle(ActionTileStyle(.primary))
                DirectionsMenu(coordinate: peek.coordinate, name: w.name) {
                    ActionTileLabel("Directions", systemImage: "location.north.line")
                }
                Button { saveWater(w) } label: {
                    Label(savedWater ? "Saved" : "Save", systemImage: savedWater ? "bookmark.fill" : "bookmark")
                }
                .buttonStyle(ActionTileStyle())
                .disabled(savedWater)
            }
            .padding(.top, DS.Space.s4)
            speciesMinis(title: "Species here")
        case .catchItem(let c):
            catchContent(c)
        }
    }

    // MARK: Pieces

    private func header(thumb: AnyView, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            thumb
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(.dsText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.gutter)
        .padding(.top, DS.Space.s6)
        .padding(.bottom, DS.Space.s4)
    }

    @ViewBuilder
    private func spotThumb(_ spot: Spot) -> some View {
        if let top = species.first {
            ThumbView(species: top)
        } else {
            ThumbView(systemImage: spot.type.icon, tint: DS.accent)
        }
    }

    private func subtitle(_ type: String, _ coord: CLLocationCoordinate2D) -> String {
        if let d = ExploreFormat.distance(from: userCoord, to: coord) { return "\(type), \(d) away" }
        return type
    }

    @ViewBuilder
    private var biteBlock: some View {
        if let bite {
            BiteBlock(
                score: bite.day,
                title: "\(ExploreFormat.verdict(bite.day)) today",
                detail: "Best \(ExploreFormat.window(bite.best, use24Hour: use24HourTime)). Right now \(bite.now)."
            )
        }
    }

    @ViewBuilder
    private func speciesMinis(title: String) -> some View {
        if !species.isEmpty {
            GroupLabel(title)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: DS.Space.s3) {
                    ForEach(species) { sp in
                        Button { onOpen(.species(sp)) } label: {
                            VStack(spacing: 6) {
                                ThumbView(species: sp, size: 76)
                                Text(sp.commonName)
                                    .font(.footnote)
                                    .foregroundStyle(.dsText2)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .frame(width: 84)
                            }
                        }
                        .buttonStyle(.dim)
                    }
                }
                .padding(.horizontal, DS.gutter)
            }
        }
    }

    @ViewBuilder
    private func catchContent(_ c: CatchDetail) -> some View {
        let name = c.species?.commonName ?? "Catch"
        let length = c.catchRecord.lengthCm.map { ", \(Units.length(cm: $0))" } ?? ""
        header(
            thumb: AnyView(Group {
                if let sp = c.species { ThumbView(species: sp) } else { ThumbView(systemImage: "fish.fill", tint: DS.accent) }
            }),
            title: name + length,
            subtitle: ExploreFormat.shortDate(c.catchRecord.caughtAt)
        )
        if let kg = c.catchRecord.weightKg { KVRow("Weight", Units.weight(kg: kg)) }
        KVRow("Spot", c.spot?.name ?? "Unsaved place")
        KVRow("Released", c.catchRecord.released ? "Yes" : "No, kept", divider: false)
        HStack(spacing: DS.Space.s2) {
            Button { onOpen(.catchDetail(CatchRef(c))) } label: { Label("Open catch", systemImage: "book.closed") }
                .buttonStyle(ActionTileStyle(.primary))
            if let sp = c.species {
                Button { onOpen(.species(sp)) } label: { Label(sp.commonName, systemImage: "fish") }
                    .buttonStyle(ActionTileStyle())
            }
        }
        .padding(.horizontal, DS.gutter)
        .padding(.top, DS.Space.s4)
    }

    // MARK: Data

    private func load() async {
        switch peek.target {
        case .spot(let spot):
            let catches = (try? appState.catchRepository.fetchForSpot(spot.id)) ?? []
            var seen = Set<Int64>()
            var ordered: [Species] = []
            let counts = Dictionary(grouping: catches.compactMap(\.species), by: \.id).mapValues(\.count)
            for c in catches {
                if let sp = c.species, !seen.contains(sp.id) { seen.insert(sp.id); ordered.append(sp) }
            }
            species = ordered.sorted { (counts[$0.id] ?? 0) > (counts[$1.id] ?? 0) }
        case .water(let w):
            species = w.decodedFishSpeciesIds.compactMap { try? appState.speciesRepository.fetch(id: $0) }
            let spots = (try? appState.spotRepository.fetchAll()) ?? []
            savedWater = spots.contains { $0.waterbodyId != nil && $0.waterbodyId == w.id }
        case .catchItem:
            break
        }
        if case .catchItem = peek.target {} else {
            bite = await BiteSnapshot.load(at: peek.coordinate).0
        }
        withAnimation(DS.Motion.easeOut) { loaded = true }
    }

    private func saveWater(_ w: Waterbody) {
        var spot = Spot(name: w.name, latitude: w.latitude, longitude: w.longitude,
                        waterbodyId: w.id, spotType: SpotFormat.spotType(for: w.type))
        do {
            try appState.spotRepository.save(&spot)
            savedWater = true
            ToastCenter.shared.show("\(w.name) saved to your spots", icon: "bookmark.fill")
        } catch {
            ToastCenter.shared.show("Could not save this spot", style: .error)
        }
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

/// Tap a ramp or fishing access point: what it is, then Directions, Save
/// and Share, the same three actions as every other place.
struct RampDetailSheet: View {
    @Environment(AppState.self) private var appState
    let ramp: BoatRamp
    @State private var savedSpot: Spot?
    @State private var savedTick = 0

    private var shareURL: URL? {
        let q = ramp.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://maps.apple.com/?ll=\(ramp.lat),\(ramp.lon)&q=\(q)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                ThumbView(systemImage: ramp.kind.icon, tint: ExploreFormat.placeTint(ramp.kind))
                VStack(alignment: .leading, spacing: 2) {
                    Text(ramp.name)
                        .font(.title2.bold())
                        .foregroundStyle(.dsText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.dsText2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.gutter)
            .padding(.top, DS.Space.s6)

            ActionTriple {
                DirectionsMenu(coordinate: ramp.coordinate, name: ramp.name) {
                    ActionTileLabel("Directions", systemImage: "location.north.line", kind: .primary)
                }
                Button { toggleSaved() } label: {
                    Label(savedSpot == nil ? "Save" : "Saved", systemImage: savedSpot == nil ? "bookmark" : "bookmark.fill")
                }
                .buttonStyle(ActionTileStyle())
                .symbolEffect(.bounce, value: savedTick)
                if let shareURL {
                    ShareLink(item: shareURL) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(ActionTileStyle())
                }
            }
            .padding(.top, DS.Space.s5)

            VStack(spacing: 0) {
                KVRow("Type", ramp.kind.label)
                KVRow("Location", ExploreFormat.coords(ramp.coordinate), divider: false)
            }
            .padding(.top, DS.Space.s4)
            ExploreFootnote("From OpenStreetMap. Check access and fees at the gate.")
            Spacer(minLength: 0)
        }
        .background(Color.dsElevated.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.dsElevated)
        .sensoryFeedback(.success, trigger: savedTick)
        .task {
            savedSpot = ((try? appState.spotRepository.fetchAll()) ?? []).first {
                abs($0.latitude - ramp.lat) < 0.0002 && abs($0.longitude - ramp.lon) < 0.0002
            }
        }
    }

    private var subtitle: String {
        let d = ExploreFormat.distance(from: appState.locationManager.currentLocation?.coordinate, to: ramp.coordinate)
        return d.map { "\(ramp.kind.label), \($0) away" } ?? ramp.kind.label
    }

    private func toggleSaved() {
        if let savedSpot {
            try? appState.spotRepository.delete(savedSpot)
            self.savedSpot = nil
            ToastCenter.shared.show("Removed from your spots", style: .info, icon: "bookmark")
            return
        }
        var spot = Spot(name: ramp.name, latitude: ramp.lat, longitude: ramp.lon,
                        spotType: ramp.kind == .ramp ? .harbour : .general)
        do {
            try appState.spotRepository.save(&spot)
            savedSpot = spot
            savedTick += 1
            ToastCenter.shared.show("\(ramp.name) saved to your spots", icon: "bookmark.fill")
        } catch {
            ToastCenter.shared.show("Could not save this spot", style: .error)
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
                    toggle("Fishing access and ramps", "figure.fishing", $showRamps, divider: false)

                    GroupLabel("Overlays")
                    toggle("Depth and sea marks", "ruler", $nautical, detail: "From OpenSeaMap")
                    toggle("Weather radar", "cloud.rain", $radar, detail: "Live rain from RainViewer")
                    toggle("Wind", "wind", $wind, detail: "Animated, from the latest weather")
                    toggle("Current", "arrow.left.arrow.right", $current, detail: "Animated surface drift", divider: false)
                    ExploreFootnote("Overlays draw on the offline map, so turning one on switches to it.")
                }
                .padding(.vertical, DS.Space.s3)
            }
            .background(Color.dsElevated.ignoresSafeArea())
            .detailScrollEdge()
            .navigationTitle("Map layers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.dsElevated)
        .sensoryFeedback(.selection, trigger: style)
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
        .sensoryFeedback(.selection, trigger: binding.wrappedValue)
    }
}
