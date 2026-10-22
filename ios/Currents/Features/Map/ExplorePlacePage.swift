import SwiftUI
import MapKit

/// One page for a place: a saved spot, a water body, or a saved water, which
/// is both at once. A saved water shows the spot's things (your catches,
/// notes, stats) and the water's things (type, area, depth, species, what to
/// throw, access nearby) together. Pushed from lists, or shown over the map
/// as a half-height sheet that swipes up to full screen.
struct ExplorePlacePage: View {
    enum Style { case page, sheet }

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("use24HourTime") private var use24HourTime = true

    let style: Style
    /// Called after the place is saved or removed, so the map can swap the
    /// water and spot pins while the sheet is still up.
    var onSavedChange: (() -> Void)?
    @State private var spot: Spot?
    @State private var waterbody: Waterbody?
    @State private var isSaved: Bool
    /// What the last removal unlinked, so saving again links it back.
    @State private var detached = ExploreSpots.Detached()

    @State private var catches: [CatchDetail] = []
    @State private var weather: WeatherService.WeatherData?
    @State private var bite: BiteSnapshot?
    @State private var seedSpecies: [Species] = []
    @State private var observedFish: [ObservedSpeciesRepository.FishResult] = []
    @State private var isLoadingSpecies = false
    @State private var showsAllFish = false

    @State private var showingPlan = false
    @State private var showingEdit = false
    @State private var confirmingRemove = false
    @State private var confirmingDelete = false
    @State private var shareImage: UIImage?
    @State private var showingShareSheet = false
    @State private var isGeneratingShare = false
    @State private var savedTick = 0

    init(spot: Spot, style: Style = .page, onSavedChange: (() -> Void)? = nil) {
        self.style = style
        self.onSavedChange = onSavedChange
        _spot = State(initialValue: spot)
        _waterbody = State(initialValue: nil)
        _isSaved = State(initialValue: true)
    }

    init(waterbody: Waterbody, style: Style = .page, onSavedChange: (() -> Void)? = nil) {
        self.style = style
        self.onSavedChange = onSavedChange
        _spot = State(initialValue: nil)
        _waterbody = State(initialValue: waterbody)
        _isSaved = State(initialValue: false)
    }

    // MARK: Derived

    /// A saved spot is on the page (a plain spot, or a saved water).
    private var savedSpot: Spot? { isSaved ? spot : nil }

    private var coord: CLLocationCoordinate2D {
        if let spot { return CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude) }
        if let w = waterbody { return CLLocationCoordinate2D(latitude: w.latitude, longitude: w.longitude) }
        return CLLocationCoordinate2D()
    }

    private var name: String { spot?.name ?? waterbody?.name ?? "Spot" }

    private var typeLabel: String {
        if let w = waterbody { return ExploreFormat.waterType(w.type) }
        if let spot { return ExploreFormat.spotType(spot) }
        return "Spot"
    }

    private var overLine: String {
        var parts = [typeLabel]
        if let area = waterbody?.surfaceAreaKm2, area > 0 { parts.append(ExploreFormat.area(area)) }
        if let d = ExploreFormat.distance(from: appState.locationManager.currentLocation?.coordinate, to: coord) {
            parts.append("\(d) away")
        }
        return parts.joined(separator: ", ")
    }

    /// Species caught here, most caught first.
    private var speciesHere: [(species: Species, count: Int)] {
        let grouped = Dictionary(grouping: catches.compactMap(\.species), by: \.id)
        return grouped.values
            .compactMap { list in list.first.map { (species: $0, count: list.count) } }
            .sorted { $0.count > $1.count }
    }

    private var tint: Color {
        if let top = speciesHere.first?.species.artTint { return top }
        return waterbody != nil ? Color.exploreWater : DS.accent
    }

    private var throwSpecies: Species? {
        speciesHere.first?.species ?? allSpeciesWithBaits.first
    }

    private var mapsURL: URL? {
        let q = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://maps.apple.com/?ll=\(coord.latitude),\(coord.longitude)&q=\(q)")
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if style == .page {
                    MapCover(coordinate: coord,
                             distance: waterbody.map { max($0.approximateRadiusM * 3, 3000) } ?? 2500,
                             radius: waterbody?.approximateRadiusM)
                        .padding(.top, DS.Space.s2)
                }
                header
                actions

                if let bite {
                    section {
                        SectionTitle("Bite today")
                        BiteStrip(bite: bite)
                    }
                }

                section {
                    SectionTitle("Conditions")
                    ExploreConditions(weather: weather, isLoading: bite == nil)
                    if let reason = bite?.reasons.first {
                        ExploreFootnote(ExploreFormat.sentence(reason))
                    }
                }

                section {
                    ExploreThrowSection(weather: weather, species: throwSpecies)
                }

                if savedSpot != nil {
                    catchesSection
                }

                if !speciesHere.isEmpty {
                    section {
                        SectionTitle("Species you caught here")
                        ForEach(speciesHere, id: \.species.id) { entry in
                            NavigationLink {
                                SpeciesDetailView(species: entry.species)
                            } label: {
                                ArtRow(title: entry.species.commonName,
                                       subtitle: "\(entry.count) caught here",
                                       chevron: true) {
                                    ThumbView(species: entry.species, size: 56)
                                }
                            }
                            .buttonStyle(.dsRow)
                        }
                    }
                }

                if let w = waterbody {
                    waterSpeciesSection
                    section {
                        SectionTitle("Baits that work here")
                        if allSpeciesWithBaits.isEmpty {
                            ExploreBaitRows(baits: Self.genericBaits(for: w.type).prefix(6).map { ExploreBait(name: $0, takers: []) })
                            ExploreFootnote("Common picks for \(ExploreFormat.waterType(w.type).lowercased()) water.")
                        } else {
                            ExploreBaitRows(baits: rankedBaits)
                        }
                    }
                }

                ExploreNearbyPlaces(coordinate: coord)

                if let w = waterbody {
                    section {
                        SectionTitle("The water")
                        ExploreWaterFacts(waterbody: w)
                    }
                }

                section {
                    SectionTitle("Regulations")
                    NavigationLink {
                        RegulationsView()
                    } label: {
                        ExploreActionRow(title: "Size and bag limits", systemImage: "ruler", showsDivider: false)
                    }
                    .buttonStyle(.dsRow)
                    ExploreFootnote("Limits come from the bundled regulations. Check before you keep a fish.")
                }

                if let spot = savedSpot {
                    aboutSpot(spot)
                    spotActions
                }

                if let desc = waterbody?.description, !desc.isEmpty {
                    section {
                        SectionTitle("About")
                        Text(desc)
                            .font(.body)
                            .foregroundStyle(.dsText2)
                            .padding(.horizontal, DS.gutter)
                    }
                }
            }
            .padding(.bottom, 40)
            .pageWidth()
        }
        .detailTint(tint)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                shareButton
                if style == .sheet {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showingPlan) { PlanSessionSheet() }
        .sheet(isPresented: $showingEdit) {
            if let spot {
                EditSpotSheet(spot: spot) { updated in
                    var record = updated
                    try? appState.spotRepository.save(&record)
                    ToastCenter.shared.show("Spot updated")
                    self.spot = record
                    onSavedChange?()
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let shareImage, let spot {
                ImageShareSheet(image: shareImage, filename: "Currents-\(spot.name)",
                                caption: SpotShareCard.caption(for: spot))
            }
        }
        .confirmationDialog("Remove \(name) from your spots?", isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("Remove spot", role: .destructive) { remove(closing: false) }
        } message: {
            Text(waterbody == nil
                 ? "Catches logged here stay in your Logbook."
                 : "Catches logged here stay in your Logbook. The water stays on the map.")
        }
        .confirmationDialog("Delete \(name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete spot", role: .destructive) { remove(closing: true) }
        } message: {
            Text("This removes the spot but keeps any catches you logged here.")
        }
        .sensoryFeedback(.success, trigger: savedTick)
    }

    // MARK: Header and actions

    private var header: some View {
        HStack(alignment: .center, spacing: DS.Space.s3) {
            DetailHeader(
                over: overLine,
                title: name,
                subtitle: bite.map { "\(ExploreFormat.verdict($0.day)), best \(ExploreFormat.window($0.best, use24Hour: use24HourTime))" }
            )
            if let bite {
                ScoreRing(score: bite.day, size: 88, caption: "today")
                    .padding(.trailing, DS.gutter)
            }
        }
        .padding(.top, style == .page ? DS.Space.s5 : DS.Space.s2)
    }

    private var actions: some View {
        ActionTriple {
            Button {
                if isSaved { confirmingRemove = true } else { save() }
            } label: {
                Label(isSaved ? "Saved" : "Save", systemImage: isSaved ? "bookmark.fill" : "bookmark")
            }
            .buttonStyle(ActionTileStyle(isSaved ? .tonal : .primary))
            .symbolEffect(.bounce, value: savedTick)
            .accessibilityHint(isSaved ? "Removes it from your spots" : "Adds it to your spots")
            DirectionsMenu(coordinate: coord, name: name) {
                ActionTileLabel("Directions", systemImage: "location.north.line")
            }
            Button { showingPlan = true } label: {
                Label("Plan", systemImage: "calendar.badge.plus")
            }
            .buttonStyle(ActionTileStyle())
        }
        .padding(.top, DS.Space.s5)
    }

    @ViewBuilder
    private var shareButton: some View {
        if savedSpot != nil {
            Button { generateShareCard() } label: { Image(systemName: "square.and.arrow.up") }
                .accessibilityLabel("Share spot")
                .disabled(isGeneratingShare)
        } else if let mapsURL {
            ShareLink(item: mapsURL) { Image(systemName: "square.and.arrow.up") }
                .accessibilityLabel("Share")
        }
    }

    // MARK: Spot sections

    private var catchesSection: some View {
        section {
            SectionTitle("Your catches here", detail: catches.isEmpty ? nil : "\(catches.count)")
            if catches.isEmpty {
                ContentUnavailableView {
                    Label("No catches here yet", systemImage: "fish")
                } description: {
                    Text("Log a catch here and it shows on this page and on the map.")
                } actions: {
                    Button("Log catch") { logCatch() }
                        .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                }
            } else {
                catchStats
                ForEach(catches, id: \.catchRecord.id) { detail in
                    NavigationLink {
                        CatchDetailView(detail: detail)
                    } label: {
                        catchRow(detail)
                    }
                    .buttonStyle(.dsRow)
                }
            }
        }
    }

    private var catchStats: some View {
        let released = catches.filter { $0.catchRecord.released }.count
        let best = catches.compactMap(\.catchRecord.weightKg).max()
        let species = Set(catches.compactMap { $0.species?.id }).count
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                StatTile("Caught", systemImage: "fish", value: "\(catches.count)",
                         footnote: "\(species) species")
                if let best {
                    let parts = Units.weightParts(kg: best)
                    StatTile("Best", systemImage: "trophy", tint: .dsScoreFair, value: parts.0, unit: parts.1)
                }
                StatTile("Released", systemImage: "arrow.uturn.backward", tint: .dsScoreGood,
                         value: "\(Int((Double(released) / Double(max(catches.count, 1)) * 100).rounded()))",
                         unit: "%", footnote: "\(released) of \(catches.count)")
            }
            .padding(.horizontal, DS.gutter)
        }
        .padding(.bottom, DS.Space.s2)
    }

    private func catchRow(_ detail: CatchDetail) -> some View {
        let title = detail.species?.commonName ?? "Catch"
        let length = detail.catchRecord.lengthCm.map { ", \(Units.length(cm: $0))" } ?? ""
        return ArtRow(title: title + length,
                      subtitle: ExploreFormat.shortDate(detail.catchRecord.caughtAt),
                      chevron: true) {
            if let sp = detail.species {
                ThumbView(species: sp, size: 56)
            } else {
                ThumbView(systemImage: "fish.fill", tint: DS.accent, size: 56)
            }
        }
    }

    private func aboutSpot(_ spot: Spot) -> some View {
        section {
            SectionTitle(waterbody == nil ? "About this spot" : "Your spot")
            if waterbody == nil {
                KVRow("Type", ExploreFormat.spotType(spot))
                KVRow("Location", ExploreFormat.coords(coord))
            }
            if FeatureFlags.spotPrivacy {
                KVRow("Visibility", spot.isPrivate ? "Private" : "Shared")
            }
            KVRow("Saved", spot.createdAt.formatted(.dateTime.day().month(.wide).year()),
                  divider: spot.notes?.isEmpty == false)
            if let notes = spot.notes, !notes.isEmpty {
                Text(notes)
                    .font(.body)
                    .foregroundStyle(.dsText)
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, DS.Space.s3)
            }
        }
    }

    private var spotActions: some View {
        section {
            Button { showingEdit = true } label: {
                ExploreActionRow(title: "Edit spot", systemImage: "pencil")
            }
            .buttonStyle(.dsRow)
            Button { generateShareCard() } label: {
                ExploreActionRow(title: isGeneratingShare ? "Preparing" : "Share spot", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.dsRow)
            .disabled(isGeneratingShare)
            Button {
                if waterbody == nil { confirmingDelete = true } else { confirmingRemove = true }
            } label: {
                ExploreActionRow(title: waterbody == nil ? "Delete spot" : "Remove from your spots",
                                 systemImage: waterbody == nil ? "trash" : "bookmark.slash",
                                 isDestructive: true, chevron: false, showsDivider: false)
            }
            .buttonStyle(.dsRow)
            ExploreFootnote("Spots stay on this phone. Exact locations are never shared unless you share them.")
        }
    }

    // MARK: Water sections

    @ViewBuilder
    private var waterSpeciesSection: some View {
        if isLoadingSpecies && observedFish.isEmpty {
            section {
                SectionTitle("What is in the water")
                FishLoader(message: "Finding species here")
                    .frame(height: 90)
                    .frame(maxWidth: .infinity)
            }
        } else if !observedFish.isEmpty || !seedSpecies.isEmpty {
            section {
                SectionTitle("What is in the water", detail: "\(observedFish.count + extraSeedSpecies.count)")
                ForEach(Array(shownFish.enumerated()), id: \.offset) { _, fish in
                    if let local = fish.localSpecies {
                        NavigationLink {
                            SpeciesDetailView(species: local)
                        } label: {
                            fishRow(fish)
                        }
                        .buttonStyle(.dsRow)
                    } else {
                        fishRow(fish)
                    }
                }
                if observedFish.count > 8 && !showsAllFish {
                    Button("Show \(observedFish.count - 8) more species") {
                        withAnimation(DS.Motion.easeOut) { showsAllFish = true }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.dsText)
                    .padding(.horizontal, DS.gutter)
                    .padding(.vertical, DS.Space.s2)
                }
                // Curated species for this water that the records missed.
                ForEach(extraSeedSpecies) { sp in
                    NavigationLink {
                        SpeciesDetailView(species: sp)
                    } label: {
                        ArtRow(title: sp.commonName, subtitle: seedSubtitle(sp), chevron: true) {
                            ThumbView(species: sp, size: 56)
                        }
                    }
                    .buttonStyle(.dsRow)
                }
                if !observedFish.isEmpty {
                    ExploreFootnote("Recorded within 10 km, from iNaturalist and GBIF observations.")
                }
            }
        }
    }

    private var shownFish: [ObservedSpeciesRepository.FishResult] {
        showsAllFish ? observedFish : Array(observedFish.prefix(8))
    }

    /// Curated species not already listed from the observations.
    private var extraSeedSpecies: [Species] {
        let seen = Set(observedFish.compactMap { $0.localSpecies?.id })
        return seedSpecies.filter { !seen.contains($0.id) }
    }

    private func seedSubtitle(_ sp: Species) -> String {
        var parts = [ExploreFormat.habitat(sp.habitat)]
        if let opt = sp.optimalTempC { parts.append("best at \(Units.temperature(opt))") }
        return parts.joined(separator: ", ")
    }

    private func fishRow(_ fish: ObservedSpeciesRepository.FishResult) -> some View {
        let records = "\(fish.observationCount) \(fish.observationCount == 1 ? "record" : "records") on \(fish.source == "iNaturalist" ? "iNaturalist" : "GBIF")"
        return ArtRow(title: fish.commonName, subtitle: records, chevron: fish.localSpecies != nil) {
            if let local = fish.localSpecies {
                ThumbView(species: local, size: 56)
            } else {
                ThumbView(systemImage: "fish", tint: .gray, size: 56)
            }
        }
    }

    /// Species with bait data: curated ones first, then recorded ones.
    private var allSpeciesWithBaits: [Species] {
        var result = seedSpecies
        for fish in observedFish {
            if let local = fish.localSpecies, !result.contains(where: { $0.id == local.id }) {
                result.append(local)
            }
        }
        return result.filter { !$0.parsedBaits.isEmpty }
    }

    /// Baits the species here take, the ones most species share first.
    private var rankedBaits: [ExploreBait] {
        var order: [String] = []
        var names: [String: String] = [:]
        var takers: [String: [String]] = [:]
        for sp in allSpeciesWithBaits {
            for bait in sp.parsedBaits {
                let key = bait.lowercased()
                if names[key] == nil {
                    names[key] = bait
                    order.append(key)
                }
                if !(takers[key]?.contains(sp.commonName) ?? false) {
                    takers[key, default: []].append(sp.commonName)
                }
            }
        }
        return order
            .map { ExploreBait(name: names[$0] ?? $0, takers: takers[$0] ?? []) }
            .sorted { ($0.takers.count, $1.name) > ($1.takers.count, $0.name) }
            .prefix(6)
            .map { $0 }
    }

    static func genericBaits(for type: Waterbody.WaterbodyType) -> [String] {
        switch type {
        case .lake:
            ["Plastic worms (Texas rig)", "Crankbaits", "Spinnerbaits", "Live worms", "Jigs", "Topwater frogs", "Drop shot rigs", "Swimbaits"]
        case .dam:
            ["Deep diving crankbaits", "Spoons", "Soft plastics (Carolina rig)", "Live bait (shad)", "Jerkbaits", "Football jigs", "Umbrella rigs", "Cut bait"]
        case .river:
            ["Spinners (inline)", "Nymphs and flies", "Live minnows", "Rooster tails", "Rapala lures", "Dough bait", "Crawfish imitations", "Drift worms"]
        case .estuary:
            ["Shrimp (live or artificial)", "Soft plastic jerkbaits", "Topwater poppers", "Spoons (gold)", "Cut mullet", "Bucktail jigs", "Suspending lures", "DOA shrimp"]
        case .coast:
            ["Poppers", "Stickbaits", "Metal jigs", "Live bait (pilchards)", "Trolling lures", "Squid strips", "Bucktail jigs", "Surface plugs"]
        }
    }

    // MARK: Layout

    private func section<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.top, DS.Space.s8)
    }

    // MARK: Loading

    private func load() async {
        // Join the two halves: a spot saved from a water brings the water,
        // and a water that is already saved brings its spot.
        if let spot, waterbody == nil, let id = spot.waterbodyId {
            waterbody = try? appState.waterbodyRepository.fetch(id: id)
        }
        if spot == nil, let w = waterbody, let saved = ExploreSpots.savedSpot(for: w, in: appState) {
            spot = saved
            isSaved = true
        }
        if let spot = savedSpot {
            catches = (try? appState.catchRepository.fetchForSpot(spot.id)) ?? []
        }

        let (b, w) = await BiteSnapshot.load(at: coord)
        withAnimation(DS.Motion.easeOut) {
            bite = b
            weather = w
        }

        guard let water = waterbody else { return }
        seedSpecies = water.decodedFishSpeciesIds.compactMap { try? appState.speciesRepository.fetch(id: $0) }
        isLoadingSpecies = true
        observedFish = await appState.observedSpeciesRepository.fishNear(
            latitude: water.latitude,
            longitude: water.longitude,
            speciesRepository: appState.speciesRepository
        )
        isLoadingSpecies = false
    }

    // MARK: Actions

    private func save() {
        do {
            let record: Spot
            if let w = waterbody {
                record = try ExploreSpots.save(w, in: appState)
            } else if var existing = spot {
                try appState.spotRepository.save(&existing)
                record = existing
            } else {
                return
            }
            ExploreSpots.reattach(detached, to: record, in: appState)
            detached = ExploreSpots.Detached()
            spot = record
            isSaved = true
            savedTick += 1
            catches = (try? appState.catchRepository.fetchForSpot(record.id)) ?? []
            onSavedChange?()
            ToastCenter.shared.show("\(record.name) saved to your spots", icon: "bookmark.fill")
        } catch {
            ToastCenter.shared.show("Could not save this spot", style: .error)
        }
    }

    /// Removes the spot only. Catches and plans made there are kept and
    /// unlinked; a water goes back to being plain water on the map.
    private func remove(closing: Bool) {
        guard let spot = savedSpot else { return }
        do {
            detached = try ExploreSpots.remove(spot, in: appState)
        } catch {
            ToastCenter.shared.show("Could not remove this spot", style: .error)
            return
        }
        isSaved = false
        catches = []
        if waterbody != nil { self.spot = nil }
        onSavedChange?()
        ToastCenter.shared.show("Removed from your spots", style: .info, icon: "bookmark")
        if closing { dismiss() }
    }

    private func logCatch() {
        guard style == .sheet else {
            AppState.shared?.pendingDeepLink = URL(string: "currents://log")
            return
        }
        // The log sheet comes from the app shell, so this sheet goes first.
        dismiss()
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            AppState.shared?.pendingDeepLink = URL(string: "currents://log")
        }
    }

    private func generateShareCard() {
        guard let spot else { return }
        isGeneratingShare = true
        Task {
            let card = await SpotShareCard.render(spot: spot, catchCount: catches.count, biteScore: bite?.now)
            isGeneratingShare = false
            if let card {
                shareImage = card
                showingShareSheet = true
            }
        }
    }
}

// MARK: - The water

/// Depth profile, size, height, access and structure of a water body.
struct ExploreWaterFacts: View {
    let waterbody: Waterbody

    private var coord: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: waterbody.latitude, longitude: waterbody.longitude)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let maxD = waterbody.maxDepthM, maxD > 0 {
                DepthProfileView(maxDepthM: maxD, avgDepthM: waterbody.averageDepthM)
                    .frame(height: 110)
                    .padding(.horizontal, DS.gutter)
                    .padding(.bottom, DS.Space.s3)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Depth profile, \(Units.depth(m: maxD)) at the deepest point")
            }

            let rows = self.rows
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                KVRow(row.0, row.1, divider: index < rows.count - 1)
            }

            let structures = waterbody.decodedStructureTypes
            if !structures.isEmpty {
                Text("Bottom structure")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.dsText2)
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, DS.Space.s4)
                    .padding(.bottom, DS.Space.s2)
                FlowLayout(spacing: 6) {
                    ForEach(structures, id: \.self) { structure in
                        Text(ExploreFormat.sentence(structure.replacingOccurrences(of: "_", with: " ")))
                            .font(.subheadline)
                            .foregroundStyle(.dsText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.dsFill, in: Capsule())
                    }
                }
                .padding(.horizontal, DS.gutter)
            }
        }
    }

    private var rows: [(String, String)] {
        var s: [(String, String)] = [("Type", ExploreFormat.waterType(waterbody.type))]
        if let maxD = waterbody.maxDepthM { s.append(("Max depth", Units.depth(m: maxD))) }
        if let avgD = waterbody.averageDepthM { s.append(("Average depth", Units.depth(m: avgD))) }
        if let area = waterbody.surfaceAreaKm2 { s.append(("Surface area", ExploreFormat.area(area))) }
        if let elev = waterbody.elevation { s.append(("Elevation", String(format: "%.0f m", elev))) }
        s.append(("Access", waterbody.isPublic ? "Public" : "Private, ask first"))
        s.append(("Location", ExploreFormat.coords(coord)))
        return s
    }
}
