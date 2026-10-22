import SwiftUI
import MapKit

/// A water body (dam, lake, river, estuary, coast), pushed on the Explore
/// stack: satellite cover, the bite today, what lives there (recorded
/// observations and curated species), the underwater profile, baits and
/// regulations.
struct WaterbodyDetailView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("use24HourTime") private var use24HourTime = true
    let waterbody: Waterbody
    @State private var weather: WeatherService.WeatherData?
    @State private var bite: BiteSnapshot?
    @State private var species: [Species] = []          // From seed data (fishSpeciesIds)
    @State private var observedFish: [ObservedSpeciesRepository.FishResult] = [] // From iNaturalist/GBIF
    @State private var isLoadingSpecies = false
    @State private var savedSpot: Spot?
    @State private var showingPlan = false
    @State private var confirmingUnsave = false
    @State private var savedTick = 0
    @State private var showsAllFish = false

    private var coord: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: waterbody.latitude, longitude: waterbody.longitude)
    }

    private static let waterTint = Color.exploreWater

    private var overLine: String {
        let type = ExploreFormat.waterType(waterbody.type)
        if let d = ExploreFormat.distance(from: appState.locationManager.currentLocation?.coordinate, to: coord) {
            return "\(type), \(d) away"
        }
        return type
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                MapCover(coordinate: coord,
                         distance: max(waterbody.approximateRadiusM * 3, 3000),
                         radius: waterbody.approximateRadiusM)
                    .padding(.top, DS.Space.s2)

                HStack(alignment: .center, spacing: DS.Space.s3) {
                    DetailHeader(
                        over: overLine,
                        title: waterbody.name,
                        subtitle: bite.map { "\(ExploreFormat.verdict($0.day)), best \(ExploreFormat.window($0.best, use24Hour: use24HourTime))" }
                    )
                    if let bite {
                        ScoreRing(score: bite.day, size: 88, caption: "today")
                            .padding(.trailing, DS.gutter)
                    }
                }
                .padding(.top, DS.Space.s5)

                ActionTriple {
                    Button {
                        if savedSpot == nil { save() } else { confirmingUnsave = true }
                    } label: {
                        Label(savedSpot == nil ? "Save as spot" : "Saved",
                              systemImage: savedSpot == nil ? "bookmark" : "bookmark.fill")
                    }
                    .buttonStyle(ActionTileStyle(savedSpot == nil ? .primary : .tonal))
                    .symbolEffect(.bounce, value: savedTick)
                    DirectionsMenu(coordinate: coord, name: waterbody.name) {
                        ActionTileLabel("Directions", systemImage: "location.north.line")
                    }
                    Button { showingPlan = true } label: {
                        Label("Plan", systemImage: "calendar.badge.plus")
                    }
                    .buttonStyle(ActionTileStyle())
                }
                .padding(.top, DS.Space.s5)

                if let bite {
                    section {
                        SectionTitle("Bite today")
                        BiteStrip(bite: bite)
                    }
                }

                section {
                    SectionTitle("Conditions")
                    ExploreConditions(weather: weather, isLoading: bite == nil)
                }

                section {
                    ExploreThrowSection(weather: weather, species: allSpeciesWithBaits.first)
                }

                if isLoadingSpecies && observedFish.isEmpty {
                    section {
                        SectionTitle("What is in the water")
                        FishLoader(message: "Finding species here")
                            .frame(height: 90)
                            .frame(maxWidth: .infinity)
                    }
                } else if !observedFish.isEmpty || !species.isEmpty {
                    section {
                        SectionTitle("What is in the water",
                                     detail: "\(fishCount)")
                        ForEach(Array(shownFish.enumerated()), id: \.offset) { _, fish in
                            if let local = fish.localSpecies {
                                NavigationLink(value: ExploreRoute.species(local)) {
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
                            NavigationLink(value: ExploreRoute.species(sp)) {
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

                section {
                    SectionTitle("Baits that work here")
                    if allSpeciesWithBaits.isEmpty {
                        ExploreBaitRows(baits: genericBaitsForType(waterbody.type).prefix(6).map { ExploreBait(name: $0, takers: []) })
                        ExploreFootnote("Common picks for \(ExploreFormat.waterType(waterbody.type).lowercased()) water.")
                    } else {
                        ExploreBaitRows(baits: rankedBaits)
                    }
                }

                ExploreNearbyPlaces(coordinate: coord)

                section {
                    SectionTitle("The water")
                    underwaterProfile
                }

                section {
                    SectionTitle("Regulations")
                    NavigationLink(value: ExploreRoute.regulations) {
                        ExploreActionRow(title: "Size and bag limits", systemImage: "ruler", showsDivider: false)
                    }
                    .buttonStyle(.dsRow)
                }

                if let desc = waterbody.description, !desc.isEmpty {
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
        .detailTint(Self.waterTint)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: URL(string: "https://maps.apple.com/?ll=\(waterbody.latitude),\(waterbody.longitude)&q=\(waterbody.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share")
            }
        }
        .sheet(isPresented: $showingPlan) { PlanSessionSheet() }
        .confirmationDialog("Remove \(waterbody.name) from your spots?", isPresented: $confirmingUnsave, titleVisibility: .visible) {
            Button("Remove spot", role: .destructive) { unsave() }
        } message: {
            Text("Catches logged here stay in your Logbook.")
        }
        .sensoryFeedback(.success, trigger: savedTick)
        .task { await load() }
    }

    // MARK: - Pieces

    private func section<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.top, DS.Space.s8)
    }

    private var fishCount: Int {
        observedFish.count + extraSeedSpecies.count
    }

    private var shownFish: [ObservedSpeciesRepository.FishResult] {
        showsAllFish ? observedFish : Array(observedFish.prefix(8))
    }

    /// Seed species not already listed from the observations.
    private var extraSeedSpecies: [Species] {
        let seen = Set(observedFish.compactMap { $0.localSpecies?.id })
        return species.filter { !seen.contains($0.id) }
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

    // MARK: - Underwater profile

    @ViewBuilder
    private var underwaterProfile: some View {
        if let maxD = waterbody.maxDepthM, maxD > 0 {
            DepthProfileView(maxDepthM: maxD, avgDepthM: waterbody.averageDepthM)
                .frame(height: 110)
                .padding(.horizontal, DS.gutter)
                .padding(.bottom, DS.Space.s3)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Depth profile, \(Units.depth(m: maxD)) at the deepest point")
        }

        let rows = profileRows
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

    private var profileRows: [(String, String)] {
        var s: [(String, String)] = [("Type", ExploreFormat.waterType(waterbody.type))]
        if let maxD = waterbody.maxDepthM { s.append(("Max depth", Units.depth(m: maxD))) }
        if let avgD = waterbody.averageDepthM { s.append(("Average depth", Units.depth(m: avgD))) }
        if let area = waterbody.surfaceAreaKm2 { s.append(("Surface area", ExploreFormat.area(area))) }
        if let elev = waterbody.elevation { s.append(("Elevation", String(format: "%.0f m", elev))) }
        s.append(("Access", waterbody.isPublic ? "Public" : "Private, ask first"))
        s.append(("Location", ExploreFormat.coords(coord)))
        return s
    }

    // MARK: - Baits

    /// All species that have bait data, from seed data + iNaturalist-matched species.
    private var allSpeciesWithBaits: [Species] {
        var result = species
        for fish in observedFish {
            if let local = fish.localSpecies, !result.contains(where: { $0.id == local.id }) {
                result.append(local)
            }
        }
        return result.filter { !$0.parsedBaits.isEmpty }
    }

    /// Baits the species here take, the ones most species share first.
    private var rankedBaits: [ExploreBait] {
        aggregateBaits()
            .sorted { ($0.takers.count, $1.name) > ($1.takers.count, $0.name) }
            .prefix(6)
            .map { $0 }
    }

    private func genericBaitsForType(_ type: Waterbody.WaterbodyType) -> [String] {
        switch type {
        case .lake:
            return ["Plastic worms (Texas rig)", "Crankbaits", "Spinnerbaits", "Live worms", "Jigs", "Topwater frogs", "Drop shot rigs", "Swimbaits"]
        case .dam:
            return ["Deep diving crankbaits", "Spoons", "Soft plastics (Carolina rig)", "Live bait (shad)", "Jerkbaits", "Football jigs", "Umbrella rigs", "Cut bait"]
        case .river:
            return ["Spinners (inline)", "Nymphs and flies", "Live minnows", "Rooster tails", "Rapala lures", "Dough bait", "Crawfish imitations", "Drift worms"]
        case .estuary:
            return ["Shrimp (live or artificial)", "Soft plastic jerkbaits", "Topwater poppers", "Spoons (gold)", "Cut mullet", "Bucktail jigs", "Suspending lures", "DOA shrimp"]
        case .coast:
            return ["Poppers", "Stickbaits", "Metal jigs", "Live bait (pilchards)", "Trolling lures", "Squid strips", "Bucktail jigs", "Surface plugs"]
        }
    }

    private func aggregateBaits() -> [ExploreBait] {
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
        return order.map { ExploreBait(name: names[$0] ?? $0, takers: takers[$0] ?? []) }
    }

    // MARK: - Actions

    private func load() async {
        if let id = waterbody.id {
            savedSpot = ((try? appState.spotRepository.fetchAll()) ?? []).first { $0.waterbodyId == id }
        }

        let (b, w) = await BiteSnapshot.load(at: coord)
        bite = b
        weather = w

        // Seed-data species for this waterbody (curated entries)
        let ids = waterbody.decodedFishSpeciesIds
        species = ids.compactMap { try? appState.speciesRepository.fetch(id: $0) }

        // Real-world species observations from iNaturalist + GBIF
        isLoadingSpecies = true
        observedFish = await appState.observedSpeciesRepository.fishNear(
            latitude: waterbody.latitude,
            longitude: waterbody.longitude,
            speciesRepository: appState.speciesRepository
        )
        isLoadingSpecies = false
    }

    private func save() {
        var spot = Spot(name: waterbody.name, latitude: waterbody.latitude, longitude: waterbody.longitude,
                        waterbodyId: waterbody.id, spotType: SpotFormat.spotType(for: waterbody.type))
        do {
            try appState.spotRepository.save(&spot)
            savedSpot = spot
            savedTick += 1
            ToastCenter.shared.show("\(waterbody.name) saved to your spots", icon: "bookmark.fill")
        } catch {
            ToastCenter.shared.show("Could not save this spot", style: .error)
        }
    }

    private func unsave() {
        guard let savedSpot else { return }
        try? appState.spotRepository.delete(savedSpot)
        self.savedSpot = nil
        ToastCenter.shared.show("Removed from your spots", style: .info, icon: "bookmark")
    }
}

// MARK: - Depth Profile Cross-Section

/// Stylised cross-section of the water column: shoreline on both sides
/// sloping down to the maximum depth, with a dashed average-depth line.
struct DepthProfileView: View {
    let maxDepthM: Double
    var avgDepthM: Double?

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                // Water fill
                bedPath(in: size)
                    .fill(Color.exploreWater.opacity(0.22))

                // Lakebed outline
                bedPath(in: size)
                    .stroke(Color.exploreWater.opacity(0.6), lineWidth: 1.5)

                // Surface line
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 1))
                    p.addLine(to: CGPoint(x: size.width, y: 1))
                }
                .stroke(Color.exploreWater, lineWidth: 2)

                // Average depth dashed line
                if let avg = avgDepthM, maxDepthM > 0, avg < maxDepthM {
                    let y = size.height * CGFloat(min(0.9, avg / maxDepthM))
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.dsText3)

                    Text("Average \(Units.depth(m: avg))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.dsText2)
                        .padding(.horizontal, 4)
                        .background(Color.dsBackground, in: Capsule())
                        .offset(x: 6, y: y - 14)
                }

                // Max depth label at the deepest point
                Text(Units.depth(m: maxDepthM))
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.dsText2)
                    .position(x: size.width * 0.55, y: size.height - 10)

                // Surface label
                Text("Surface")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.dsText2)
                    .offset(x: 6, y: 5)
            }
        }
    }

    /// Asymmetric basin: gentle slope from the left shore, deepest at ~55%
    /// of the width, steeper climb to the right shore.
    private func bedPath(in size: CGSize) -> Path {
        let w = size.width
        let h = size.height
        return Path { p in
            p.move(to: .zero)
            p.addCurve(
                to: CGPoint(x: w * 0.55, y: h * 0.92),
                control1: CGPoint(x: w * 0.12, y: h * 0.25),
                control2: CGPoint(x: w * 0.38, y: h * 0.92)
            )
            p.addCurve(
                to: CGPoint(x: w, y: 0),
                control1: CGPoint(x: w * 0.75, y: h * 0.92),
                control2: CGPoint(x: w * 0.9, y: h * 0.3)
            )
            p.closeSubpath()
        }
    }
}

// MARK: - Flow Layout (for structure type pills)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(
                x: bounds.minX + position.x,
                y: bounds.minY + position.y
            ), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (positions, CGSize(width: maxWidth, height: y + rowHeight))
    }
}
