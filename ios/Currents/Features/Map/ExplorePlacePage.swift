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
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("cloudSyncEnabled") private var cloudSyncEnabled = false
    /// The header's over line and large title, which grow with the text
    /// size. On the page they sit under the 190 point map cover and its
    /// padding (218 points), so the inline title waits for both.
    @ScaledMetric(relativeTo: .largeTitle) private var titleBlock: CGFloat = 63

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
    @State private var showingLog = false
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

    /// Fresh or salt water, for whether the fish you track belongs here.
    private var freshwater: Bool? {
        if let w = waterbody { return ThrowSpeciesChoice.isFreshwater(SpotFormat.spotType(for: w.type)) }
        return spot.flatMap { ThrowSpeciesChoice.isFreshwater($0.type) }
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
                             distance: waterbody.map { max($0.approximateRadiusM * 3, 3000) } ?? 2500)
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
                    ExploreConditions(weather: weather, isLoading: bite == nil,
                                      coordinate: coord, freshwater: freshwater)
                    if let reason = bite?.reasons.first {
                        ExploreFootnote(ExploreFormat.sentence(reason))
                    }
                }

                section {
                    ExploreThrowSection(weather: weather,
                                        caught: speciesHere.map { $0.species },
                                        inWater: allSpeciesWithBaits,
                                        freshwater: freshwater,
                                        coordinate: coord)
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
                    spotActions(spot)
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
        .exploreInlineTitle(name, threshold: style == .page ? 218 + titleBlock : nil)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingPlan = true } label: {
                    Image(systemName: "calendar.badge.plus")
                }
                .accessibilityLabel("Plan session")
            }
            if style == .sheet {
                ToolbarItem(placement: .confirmationAction) {
                    SheetDoneButton()
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showingPlan) { PlanSessionSheet() }
        .fullScreenCover(isPresented: $showingLog, onDismiss: reloadCatches) { logSheet }
        .sheet(isPresented: $showingEdit) {
            if let spot {
                // A failed save throws back to the sheet, which stays open
                // with an error instead of claiming success.
                EditSpotSheet(spot: spot) { updated in
                    var record = updated
                    try appState.spotRepository.save(&record)
                    ToastCenter.shared.show("Spot updated")
                    self.spot = record
                    onSavedChange?()
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let shareImage, let spot {
                SpotSharePreview(image: shareImage, name: spot.name,
                                 caption: SpotShareCard.caption(for: spot))
                    .dsSheet([.large])
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
    }

    // MARK: Header and actions

    /// Name and the day's grade beside the ring (the ring under them at
    /// accessibility sizes). The windows are told once, under the bite strip.
    private var header: some View {
        headerLayout {
            DetailHeader(
                over: overLine,
                title: name,
                subtitle: bite.map { (bite: BiteSnapshot) -> String in
                    "\(ForecastFormat.grade(bite.day)) today"
                }
            )
            if let bite {
                ScoreRing(score: bite.day, size: 88, caption: "today")
                    .padding(typeSize.isAccessibilitySize ? Edge.Set.leading : Edge.Set.trailing, DS.gutter)
            }
        }
        .padding(.top, style == .page ? DS.Space.s5 : DS.Space.s2)
    }

    private var headerLayout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Space.s3))
            : AnyLayout(HStackLayout(alignment: .center, spacing: DS.Space.s3))
    }

    /// Save spot, Directions and Share, in the order of every place sheet.
    /// Planning a session sits in the toolbar.
    private var actions: some View {
        ActionTriple {
            Button {
                if isSaved { confirmingRemove = true } else { save() }
            } label: {
                Label(isSaved ? "Saved" : "Save spot", systemImage: isSaved ? "bookmark.fill" : "bookmark")
            }
            .buttonStyle(ActionTileStyle(isSaved ? .tonal : .primary))
            .symbolEffect(.bounce, value: savedTick)
            .accessibilityHint(isSaved ? "Removes it from your spots" : "Adds it to your spots")
            DirectionsMenu(coordinate: coord, name: name) {
                ActionTileLabel("Directions", systemImage: "location.north.line")
            }
            shareTile
        }
        .padding(.top, DS.Space.s5)
    }

    /// A saved spot shares its card; anywhere else shares a map link.
    @ViewBuilder
    private var shareTile: some View {
        if savedSpot != nil {
            Button { generateShareCard() } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(ActionTileStyle())
            .disabled(isGeneratingShare)
            .accessibilityHint("Shares a card of this spot")
        } else if let mapsURL {
            ShareLink(item: mapsURL) {
                ActionTileLabel("Share", systemImage: "square.and.arrow.up")
            }
        }
    }

    // MARK: Spot sections

    private var catchesSection: some View {
        section {
            SectionTitle("Your catches here", detail: catches.isEmpty ? nil : "\(catches.count)")
            if catches.isEmpty {
                InlineEmpty(systemImage: "fish",
                            text: "No catches here yet. Log one and it shows on this page and on the map.",
                            actionTitle: "Log catch",
                            action: logCatch)
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

    /// Equal-width tiles inside the gutter, stacked at accessibility sizes
    /// where a third of the width would squash them, as Stats lays out its
    /// totals.
    private var tileRow: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
    }

    /// Long names anglers shorten to the first word, because the last word
    /// alone names another fish: a kingfish here is a giant or bluefin.
    private static let firstWordNames: Set<String> = ["Yellowtail Kingfish"]

    /// A species name short enough for a third-width footnote: "Leervis"
    /// for "Leervis (Garrick)", "Bass" for "Largemouth Bass" and "Yellowtail"
    /// for "Yellowtail Kingfish". Whole at accessibility sizes, where the
    /// footnote wraps.
    private func tileName(_ name: String) -> String {
        let plain = name.range(of: " (").map { String(name[..<$0.lowerBound]) } ?? name
        guard !typeSize.isAccessibilitySize, plain.count > 12,
              let last = plain.split(separator: " ").last else { return plain }
        if Self.firstWordNames.contains(plain), let first = plain.split(separator: " ").first {
            return String(first)
        }
        return String(last)
    }

    private var catchStats: some View {
        let released = catches.filter { $0.catchRecord.released }.count
        // Every tile in the row has a footnote; Heaviest names the fish.
        let heaviest = catches
            .filter { $0.catchRecord.weightKg != nil }
            .max { ($0.catchRecord.weightKg ?? 0) < ($1.catchRecord.weightKg ?? 0) }
        let species = Set(catches.compactMap { $0.species?.id }).count
        return tileRow {
            StatTile("Caught", systemImage: "fish.fill", tint: DS.accent, value: "\(catches.count)",
                     footnote: "\(species) species", width: nil)
            if let heaviest, let best = heaviest.catchRecord.weightKg {
                let parts = Units.weightParts(kg: best)
                StatTile("Heaviest", systemImage: "trophy.fill", tint: .dsScoreFair, value: parts.0, unit: parts.1,
                         footnote: heaviest.species.map { tileName($0.commonName) }
                            ?? ExploreFormat.shortDate(heaviest.catchRecord.caughtAt),
                         width: nil)
            }
            StatTile("Released", systemImage: "arrow.uturn.backward", tint: .dsScoreLow,
                     value: "\(Int((Double(released) / Double(max(catches.count, 1)) * 100).rounded()))",
                     unit: "%", footnote: "\(released) of \(catches.count)", width: nil)
        }
        .padding(.horizontal, DS.gutter)
        .padding(.bottom, DS.Space.s2)
    }

    private func catchRow(_ detail: CatchDetail) -> some View {
        let title = detail.species?.commonName ?? "Catch"
        let length = detail.catchRecord.lengthCm.map { ", \(Units.length(cm: $0))" } ?? ""
        return ArtRow(title: title + length,
                      subtitle: ExploreFormat.shortDate(detail.catchRecord.caughtAt),
                      chevron: true) {
            CatchThumb(detail: detail, size: 56)
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
            KVRow("Saved", LogbookFormat.fullDate(spot.createdAt),
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

    private func spotActions(_ spot: Spot) -> some View {
        section {
            Button { showingEdit = true } label: {
                ExploreActionRow(title: "Edit spot", systemImage: "pencil")
            }
            .buttonStyle(.dsRow)
            NavigationLink {
                SpotAlertsView(spot: spot)
            } label: {
                ExploreActionRow(title: "Notifications", systemImage: "bell")
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
            ExploreFootnote(savedWhere)
        }
    }

    /// Where the spot is kept, which is also the iCloud account when sync is on.
    private var savedWhere: String {
        let place = cloudSyncEnabled && CloudCapability.isAvailable
            ? "Saved on this phone and your iCloud."
            : "Saved on this phone."
        return place + " Exact locations are never shared unless you share them."
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
                    .buttonStyle(TonalButtonStyle(fullWidth: false))
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
        // The footnote under the list names the sources.
        let records = "\(fish.observationCount) \(fish.observationCount == 1 ? "record" : "records")"
        return ArtRow(title: fish.commonName, subtitle: records, chevron: fish.localSpecies != nil) {
            if let local = fish.localSpecies {
                ThumbView(species: local, size: 56)
            } else {
                // A fish the guide has no record of: the neutral silhouette
                // the size limits use, not a bright stand-in colour.
                ThumbView(systemImage: "fish.fill", tint: Color.dsText3, size: 56)
            }
        }
    }

    /// Species with a real bait record, not the stand-in list: curated ones
    /// first, then recorded ones.
    private var allSpeciesWithBaits: [Species] {
        var result = seedSpecies
        for fish in observedFish {
            if let local = fish.localSpecies, !result.contains(where: { $0.id == local.id }) {
                result.append(local)
            }
        }
        return result.filter { LureEngine.hasBaitRecord($0) }
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
        // A dam, lake or river leaves out the sea fish recorded on the coast nearby.
        observedFish = await appState.observedSpeciesRepository.fishNear(
            latitude: water.latitude,
            longitude: water.longitude,
            speciesRepository: appState.speciesRepository,
            freshwater: freshwater == true
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
            ToastCenter.shared.show("Couldn't save the spot", style: .error)
        }
    }

    /// Removes the spot only. Catches and plans made there are kept and
    /// unlinked; a water goes back to being plain water on the map.
    private func remove(closing: Bool) {
        guard let spot = savedSpot else { return }
        do {
            detached = try ExploreSpots.remove(spot, in: appState)
        } catch {
            ToastCenter.shared.show("Couldn't remove the spot", style: .error)
            return
        }
        isSaved = false
        catches = []
        if waterbody != nil { self.spot = nil }
        onSavedChange?()
        Haptics.warning()
        ToastCenter.shared.show("Removed from your spots", style: .info, haptic: false, icon: "bookmark")
        if closing { dismiss() }
    }

    /// The log opens over this page, filed under the saved spot, or pinned
    /// to the place when it is not saved.
    private func logCatch() {
        showingLog = true
    }

    @ViewBuilder
    private var logSheet: some View {
        if let spot = savedSpot {
            LogCatchView(presetSpot: spot)
        } else {
            LogCatchView(presetCoordinate: coord)
        }
    }

    private func reloadCatches() {
        guard let spot = savedSpot else { return }
        catches = (try? appState.catchRepository.fetchForSpot(spot.id)) ?? []
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
            } else {
                ToastCenter.shared.show("Couldn't make the share card", style: .error)
            }
        }
    }
}

// MARK: - Share preview

/// The spot card before it goes out, like the profile share card: the card,
/// a note that it shows the exact spot, and the share button.
private struct SpotSharePreview: View {
    let image: UIImage
    let name: String
    let caption: String

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Space.s4) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                        .padding(.horizontal, DS.gutter)
                        .accessibilityLabel("Share card for \(name)")
                    SectionFootnote("This card shows the exact spot.")
                }
                .padding(.top, DS.Space.s4)
                .padding(.bottom, DS.Space.s8)
                .frame(maxWidth: .infinity)
            }
            .detailTint(nil)
            .safeAreaInset(edge: .bottom) { shareButton }
            .navigationTitle("Share card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { SheetDoneButton() }
            }
        }
    }

    private var shareButton: some View {
        let card = Image(uiImage: image)
        return ShareLink(item: card, message: Text(caption), preview: SharePreview(name, image: card)) {
            Label("Share card", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(.dsPrimary)
        .padding(.horizontal, DS.gutter)
        .padding(.bottom, DS.Space.s4)
    }
}

// MARK: - The water

/// Depth profile, size, height, access and structure of a water body.
struct ExploreWaterFacts: View {
    let waterbody: Waterbody
    @AppStorage("units") private var units = "metric"

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
        let imperial = units == "imperial"
        if let maxD = waterbody.maxDepthM { s.append(("Max depth", Units.depth(m: maxD, imperial: imperial))) }
        if let avgD = waterbody.averageDepthM { s.append(("Average depth", Units.depth(m: avgD, imperial: imperial))) }
        if let area = waterbody.surfaceAreaKm2 {
            s.append(("Surface area", Units.area(km2: area, imperial: imperial, smallInHectares: true)))
        }
        if let elev = waterbody.elevation { s.append(("Elevation", Units.elevation(m: elev, imperial: imperial))) }
        s.append(("Access", waterbody.isPublic ? "Public" : "Private, ask first"))
        s.append(("Location", ExploreFormat.coords(coord)))
        return s
    }
}
