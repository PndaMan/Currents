import SwiftUI
import CoreLocation

// MARK: - Row

/// The "Targeting" row on Today and the day page. Opens the target page; a
/// long press switches to a recent target or clears it.
struct TargetRow: View {
    let store: ForecastStore

    @Environment(AppState.self) private var appState
    @AppStorage("targetSpeciesId") private var targetSpeciesId: Int = 0
    @AppStorage(RecentTargets.key) private var recentTargets = ""
    @State private var recents: [Species] = []

    var body: some View {
        NavigationLink(value: ForecastRoute.target) {
            if let species = store.species {
                ArtRow(over: "Targeting", title: species.commonName,
                       subtitle: TargetText.comfortLine(species), subtitleIcon: "thermometer.medium",
                       chevron: true) {
                    ThumbView(species: species, size: 52)
                }
            } else {
                ArtRow(over: "Targeting", title: "Any species",
                       subtitle: "Pick a fish to tune the score and lures to it", chevron: true) {
                    ThumbView(systemImage: "scope", tint: DS.accent, size: 52)
                }
            }
        }
        .buttonStyle(.dsRow)
        .contextMenu {
            ForEach(recents.filter { $0.id != store.species?.id }) { species in
                Button {
                    targetSpeciesId = Int(species.id)
                    store.setSpecies(species)
                    TargetText.announce(species)
                } label: {
                    Label("Target \(species.commonName)", systemImage: "scope")
                }
            }
            if store.species != nil {
                Button("Clear target", systemImage: "xmark") {
                    targetSpeciesId = 0
                    store.setSpecies(nil)
                    TargetText.announce(nil)
                }
            }
        }
        .task(id: recentTargets) {
            recents = TargetData.species(RecentTargets.ids(recentTargets), appState: appState)
        }
    }
}

// MARK: - Standalone

/// The target page with its own forecast, for screens outside Today (the
/// species page's Target button). Push it inside a NavigationStack; it
/// registers the forecast pages it links to.
struct TargetScreen: View {
    /// Off when pushed from the species page, so it does not link back.
    var showsSpeciesLink: Bool = false

    @Environment(AppState.self) private var appState
    @AppStorage("targetSpeciesId") private var targetSpeciesId: Int = 0
    /// Today's chosen place, so both show the same forecast.
    @AppStorage("todaySpotId") private var spotId = ""
    @State private var store = ForecastStore()
    @State private var ready = false

    var body: some View {
        Group {
            if ready {
                TargetPage(store: store, showsSpeciesLink: showsSpeciesLink)
            } else {
                Color.dsBackground.ignoresSafeArea()
            }
        }
        .navigationDestination(for: ForecastRoute.self) { route in
            ForecastDestination(store: store, route: route)
        }
        .syncsTargetSpecies(store)
        .task {
            guard !ready else { return }
            let id = Int64(targetSpeciesId)
            if id != 0, let species = (try? appState.speciesRepository.fetch(id: id)) ?? nil {
                store.setSpecies(species)
            }
            let spots = spotId.isEmpty ? [] : ((try? appState.spotRepository.fetchAll()) ?? [])
            let spot = spots.first(where: { $0.id == spotId })
            if let spot {
                store.setLocation(CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude),
                                  name: spot.name)
            } else if let loc = appState.locationManager.currentLocation {
                store.setLocation(loc.coordinate, name: "Current location")
            }
            ready = true
            await store.load()
        }
    }
}

// MARK: - Page

/// Everything about the target species in one place: today's bite for it and
/// why, the best window and day, what to throw, where to find it, the rules
/// and your record. With nothing targeted it explains what targeting does.
struct TargetPage: View {
    let store: ForecastStore
    var showsSpeciesLink: Bool = true

    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("targetSpeciesId") private var targetSpeciesId: Int = 0
    @AppStorage(RecentTargets.key) private var recentTargets = ""
    @AppStorage("waterClarityOverride") private var clarityOverride = ""
    @AppStorage("use24HourTime") private var use24 = true
    @AppStorage("units") private var units = "metric"

    @State private var catches: [CatchDetail] = []
    @State private var spots: [Spot] = []
    @State private var waters: [Waterbody] = []
    @State private var ownedGear: [OwnedGear] = []
    @State private var regulation: FishingRegulation?
    @State private var recents: [Species] = []
    @State private var mostCaught: [Species] = []
    @State private var loaded = false
    @State private var loggingCatch = false

    private var imperial: Bool { units == "imperial" }

    private var loadKey: String {
        let c = store.coordinate
        return "\(store.species?.id ?? 0)|\(recentTargets)|\((c.latitude * 100).rounded())|\((c.longitude * 100).rounded())"
    }

    var body: some View {
        // Read so the page follows new weather and a changed target.
        let _ = store.revision
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let species = store.species {
                    targeted(species)
                } else {
                    untargeted
                }
            }
            .padding(.top, DS.Space.s2)
            .padding(.bottom, 40)
            .animation(reduceMotion ? nil : DS.Motion.softSpring, value: store.species?.id)
            .pageWidth()
        }
        .detailTint(store.species?.artTint ?? DS.accent)
        .navigationTitle(store.species?.commonName ?? "Target")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await store.load(force: true)
            Haptics.softPress()
        }
        .task(id: loadKey) { load() }
        .fullScreenCover(isPresented: $loggingCatch, onDismiss: { load() }) {
            // Same composer as the species page, with the target already chosen.
            LogCatchView(presetSpecies: store.species)
        }
    }

    // MARK: Targeted

    @ViewBuilder
    private func targeted(_ species: Species) -> some View {
        let today = store.day(0)
        header(species)
        if let reg = regulation, let season = TargetClosedSeason(reg.closedSeason), season.isClosed() {
            closedBanner(species, season: season)
        }
        actions(species)
            .padding(.top, DS.Space.s5)
        todaySection(species, day: today)
            .padding(.top, DS.Space.s6)
        bestTimes(today)
            .padding(.top, DS.Space.s6)
        lureSection(species)
            .padding(.top, DS.Space.s6)
        placesSection(species)
            .padding(.top, DS.Space.s6)
        rulesSection(species)
            .padding(.top, DS.Space.s6)
        recordSection(species)
            .padding(.top, DS.Space.s6)
        switchSection(excluding: species.id)
        if showsSpeciesLink {
            guideLink(species)
                .padding(.top, DS.Space.s6)
        }
        Text("Worked out on your phone from the species guide and your own catches. No signal needed.")
            .font(.footnote)
            .foregroundStyle(.dsText2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, DS.gutter)
            .padding(.top, DS.Space.s6)
    }

    private func header(_ species: Species) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            ThumbView(species: species, size: 112)
                .padding(.horizontal, DS.gutter)
                .accessibilityHidden(true)
            DetailHeader(over: "Your target", title: species.commonName, subtitle: species.scientificName)
        }
    }

    private func closedBanner(_ species: Species, season: TargetClosedSeason) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.title3)
                .foregroundStyle(Color.dsScoreSlow)
            VStack(alignment: .leading, spacing: 2) {
                Text("Closed season today")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.dsText)
                Text("\(species.commonName) may not be kept from \(season.label). Release any you catch.")
                    .font(.footnote)
                    .foregroundStyle(.dsText2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.dsScoreSlow.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
        .accessibilityElement(children: .combine)
        .padding(.horizontal, DS.gutter)
        .padding(.top, DS.Space.s4)
    }

    private func actions(_ species: Species) -> some View {
        ActionTriple {
            Button {
                loggingCatch = true
            } label: {
                Label("Log catch", systemImage: "plus")
            }
            .buttonStyle(ActionTileStyle(.primary))

            NavigationLink(value: ForecastRoute.targetSpecies) {
                ActionTileLabel("Change", systemImage: "arrow.left.arrow.right")
            }
            .buttonStyle(.dim)
            .accessibilityLabel("Change target")

            Button {
                targetSpeciesId = 0
                store.setSpecies(nil)
                TargetText.announce(nil)
            } label: {
                Label("Clear", systemImage: "xmark")
            }
            .buttonStyle(ActionTileStyle(.tonal))
            .accessibilityLabel("Clear target")
        }
    }

    // MARK: Today

    private func todaySection(_ species: Species, day: ForecastDay) -> some View {
        let score = day.result.score
        let reasons = Array(day.result.reasons.prefix(4)).map(ForecastFormat.clean)
        return VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: ForecastRoute.day(offset: 0, hour: nil)) {
                SectionTitle("Today", chevron: true)
            }
            .buttonStyle(.dim)

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bite right now")
                        .font(.subheadline)
                        .foregroundStyle(.dsText2)
                    Text(ForecastFormat.verdict(score))
                        .font(.title2.bold())
                        .foregroundStyle(.dsText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                ScoreRing(score: score, size: 84, caption: "of 100")
            }
            .padding(.horizontal, DS.gutter)
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(reasons, id: \.self) { reason in
                    TargetBullet(text: reason, systemImage: "circle.fill", tint: DS.scoreColor(score), small: true)
                }
            }
            .padding(.horizontal, DS.gutter)
            .padding(.top, DS.Space.s4)

            SectionTitle("How targeting changes the score")
                .padding(.top, DS.Space.s5)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(TargetText.changes(for: species)) { item in
                    TargetBullet(text: item.text, systemImage: item.icon, tint: species.artTint)
                }
            }
            .padding(.horizontal, DS.gutter)
        }
    }

    private func bestTimes(_ today: ForecastDay) -> some View {
        let week = (0..<7).map { store.day($0) }
        let best = week.max { $0.peakScore < $1.peakScore }
        return VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Best times")
            HStack(alignment: .top, spacing: 10) {
                if let window = today.bestWindow {
                    NavigationLink(value: ForecastRoute.day(offset: 0, hour: window.startHour)) {
                        StatTile("Best window today", systemImage: ForecastFormat.windowIcon(window.startHour),
                                 tint: DS.scoreColor(window.peakScore),
                                 value: ForecastFormat.hour(window.startHour, use24: use24),
                                 footnote: "To \(ForecastFormat.hour(window.endHour + 1, use24: use24)), score \(window.peakScore)",
                                 width: nil)
                    }
                    .buttonStyle(.dim)
                } else {
                    StatTile("Best window today", systemImage: "clock", tint: .dsText2,
                             value: ConditionText.missing, footnote: "No hour stands out", width: nil)
                }
                if let best {
                    NavigationLink(value: ForecastRoute.day(offset: best.offset, hour: nil)) {
                        StatTile("Best day this week", systemImage: "calendar",
                                 tint: DS.scoreColor(best.peakScore),
                                 value: best.offset < 2 ? ForecastFormat.dayName(best.offset, date: best.date)
                                                        : ForecastFormat.shortDay(best.date),
                                 footnote: "Peaks at \(best.peakScore) around \(ForecastFormat.hour(best.bestHour, use24: use24))",
                                 width: nil)
                    }
                    .buttonStyle(.dim)
                }
            }
            .padding(.horizontal, DS.gutter)
        }
    }

    // MARK: Lures

    private func lureSection(_ species: Species) -> some View {
        let weather = store.weather(for: 0)
        let clarity = WaterClarity(rawValue: clarityOverride) ?? WaterClarity.inferred(precipMm: weather?.precipMm)
        let conditions = LureEngine.Conditions(
            waterTempC: weather?.waterTempC,
            clarity: clarity,
            cloudCoverPct: weather?.cloudCoverPct,
            windSpeedKmh: weather?.windSpeedKmh,
            pressureChange6h: weather?.pressureChange6h
        )
        let picks = LureEngine.recommend(conditions: conditions, species: species,
                                         ownedGear: ownedGear, history: catches, limit: 3)
        let baits = species.parsedBaits
        return VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: ForecastRoute.lures) {
                SectionTitle("What to throw", chevron: true)
            }
            .buttonStyle(.dim)

            ForEach(Array(picks.enumerated()), id: \.element.id) { index, pick in
                LureSuggestionRow(suggestion: pick, rank: index + 1)
                if index < picks.count - 1 {
                    Divider()
                        .overlay(Color.dsSeparator)
                        .padding(.leading, DS.gutter + 28 + 56 + 12)
                }
            }

            if !baits.isEmpty || species.baitNotes != nil {
                VStack(alignment: .leading, spacing: 10) {
                    if !baits.isEmpty {
                        TargetBullet(text: "Known baits: \(baits.joined(separator: ", ")).",
                                     systemImage: "fish", tint: species.artTint)
                    }
                    if let notes = species.baitNotes, !notes.isEmpty {
                        TargetBullet(text: ForecastFormat.clean(notes), systemImage: "lightbulb", tint: species.artTint)
                    }
                }
                .padding(.horizontal, DS.gutter)
                .padding(.top, DS.Space.s4)
            }
        }
    }

    // MARK: Places

    private func placesSection(_ species: Species) -> some View {
        let holding = Set(waters.compactMap(\.id))
        let mine = TargetData.spots(catches: catches, saved: spots, holdingWaterIds: holding, from: store.coordinate)
        let savedWaterIds = Set(spots.compactMap(\.waterbodyId))
        let near = Array(waters
            .filter { water in water.id.map { !savedWaterIds.contains($0) } ?? true }
            .map { TargetWaterPlace(water: $0, km: TargetData.km(from: store.coordinate, $0.latitude, $0.longitude)) }
            .sorted { $0.km < $1.km }
            .prefix(5))
        return VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Where to find it")
            if mine.isEmpty && near.isEmpty {
                if loaded {
                    TargetEmptyNote(systemImage: "mappin.slash",
                                    text: "No places for it yet. Spots where you catch \(species.commonName), and waters within \(Units.distance(km: TargetData.radiusKm, imperial: imperial)) known to hold it, show here.")
                }
            } else {
                ForEach(mine.prefix(5)) { item in
                    Button {
                        appState.pendingDeepLink = URL(string: "currents://map/spot/\(item.spot.id)")
                    } label: {
                        ArtRow(title: item.spot.name,
                               subtitle: item.count > 0
                                   ? "\(item.count) caught here, \(Units.distance(km: item.km, imperial: imperial)) away"
                                   : "Your spot, known to hold it, \(Units.distance(km: item.km, imperial: imperial)) away",
                               chevron: true) {
                            ThumbView(systemImage: item.spot.type.icon, tint: species.artTint, size: 48)
                        }
                    }
                    .buttonStyle(.dsRow)
                    .accessibilityHint("Shows it on the Explore map")
                }
                ForEach(near) { item in
                    Button {
                        if let id = item.water.id {
                            appState.pendingDeepLink = URL(string: "currents://map/water/\(id)")
                        }
                    } label: {
                        ArtRow(title: item.water.name,
                               subtitle: "\(item.water.type.rawValue.capitalized), \(Units.distance(km: item.km, imperial: imperial)) away, known to hold it",
                               chevron: true) {
                            ThumbView(systemImage: "water.waves", tint: ForecastCondition.tide.tint, size: 48)
                        }
                    }
                    .buttonStyle(.dsRow)
                    .accessibilityHint("Shows it on the Explore map")
                }
            }
        }
    }

    // MARK: Rules

    private func rulesSection(_ species: Species) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Rules", detail: regulation?.region)
            if let reg = regulation {
                ConditionFigures(items: TargetText.ruleFigures(reg, imperial: imperial))
                Text("A quick reference. Rules change and differ by place, so check the local rules before you keep a fish.")
                    .font(.footnote)
                    .foregroundStyle(.dsText2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, 10)
            } else if loaded {
                TargetEmptyNote(systemImage: "book.closed",
                                text: "No size or bag limits on file for \(species.commonName). Check the local rules before you keep one.")
            }
        }
    }

    // MARK: Record

    private func recordSection(_ species: Species) -> some View {
        let longest = catches.compactMap(\.catchRecord.lengthCm).max()
        let heaviest = catches.compactMap(\.catchRecord.weightKg).max()
        let released = catches.filter(\.catchRecord.released).count
        let last = catches.max { $0.catchRecord.caughtAt < $1.catchRecord.caughtAt }
        return VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Your record", detail: catches.isEmpty ? nil : "\(catches.count)")
            if catches.isEmpty {
                if loaded {
                    TargetEmptyNote(systemImage: "fish",
                                    text: "You have not logged \(species.commonName) yet. Your count, best fish and last catch show here.")
                }
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10, alignment: .top),
                                    GridItem(.flexible(), alignment: .top)],
                          alignment: .leading, spacing: 10) {
                    StatTile("Caught", systemImage: "fish", tint: species.artTint,
                             value: "\(catches.count)",
                             footnote: released > 0 ? "\(released) released" : "None released", width: nil)
                    if let last {
                        NavigationLink {
                            CatchDetailView(detail: last)
                        } label: {
                            StatTile("Last caught", systemImage: "clock", tint: species.artTint,
                                     value: TargetText.shortDate(last.catchRecord.caughtAt),
                                     footnote: last.spot?.name ?? "No spot saved", width: nil)
                        }
                        .buttonStyle(.dim)
                    }
                    if let longest {
                        StatTile("Longest", systemImage: "ruler", tint: species.artTint,
                                 value: Units.length(cm: longest, imperial: imperial), width: nil)
                    }
                    if let heaviest {
                        StatTile("Heaviest", systemImage: "scalemass", tint: species.artTint,
                                 value: Units.weight(kg: heaviest, imperial: imperial), width: nil)
                    }
                }
                .padding(.horizontal, DS.gutter)
            }
        }
    }

    // MARK: Switching

    @ViewBuilder
    private func switchSection(excluding id: Int64?) -> some View {
        let others = recents.filter { $0.id != id }
        if !others.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionTitle("Recent targets")
                ForEach(others.prefix(4)) { species in
                    targetButton(species)
                }
            }
            .padding(.top, DS.Space.s6)
        }
    }

    private func targetButton(_ species: Species) -> some View {
        Button {
            targetSpeciesId = Int(species.id)
            store.setSpecies(species)
            TargetText.announce(species)
        } label: {
            ArtRow(title: species.commonName, subtitle: TargetText.comfortLine(species)) {
                ThumbView(species: species, size: 48)
            } trailing: {
                Image(systemName: "scope")
                    .font(.body)
                    .foregroundStyle(DS.accent)
            }
        }
        .buttonStyle(.dsRow)
        .accessibilityLabel("Target \(species.commonName)")
    }

    private func guideLink(_ species: Species) -> some View {
        NavigationLink {
            SpeciesDetailView(species: species)
        } label: {
            ArtRow(title: "Species guide", subtitle: "Season, range, facts and the field guide entry", chevron: true) {
                ThumbView(systemImage: "book", tint: species.artTint, size: 48)
            }
        }
        .buttonStyle(.dsRow)
    }

    // MARK: Untargeted

    @ViewBuilder
    private var untargeted: some View {
        ThumbView(systemImage: "scope", tint: DS.accent, size: 112)
            .padding(.horizontal, DS.gutter)
            .accessibilityHidden(true)
        DetailHeader(title: "Target a species",
                     subtitle: "Pick the fish you are after and the forecast tunes itself to it.")
            .padding(.top, DS.Space.s4)

        NavigationLink(value: ForecastRoute.targetSpecies) {
            Label("Choose a species", systemImage: "magnifyingglass")
        }
        .buttonStyle(.dsPrimary)
        .padding(.horizontal, DS.gutter)
        .padding(.top, DS.Space.s5)

        SectionTitle("What targeting does")
            .padding(.top, DS.Space.s6)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(TargetText.general) { item in
                TargetBullet(text: item.text, systemImage: item.icon, tint: DS.accent)
            }
        }
        .padding(.horizontal, DS.gutter)

        switchSection(excluding: nil)

        let fromCatches = mostCaught.filter { sp in !recents.contains { $0.id == sp.id } }
        if !fromCatches.isEmpty {
            SectionTitle("From your catches")
                .padding(.top, DS.Space.s6)
            ForEach(fromCatches.prefix(3)) { species in
                targetButton(species)
            }
        }
    }

    // MARK: Data

    private func load() {
        recents = TargetData.species(RecentTargets.ids(recentTargets), appState: appState)
        guard let species = store.species else {
            let counts = (try? appState.catchRepository.speciesCounts()) ?? []
            mostCaught = TargetData.species(counts.prefix(6).map { $0.speciesId }, appState: appState)
            loaded = true
            return
        }
        catches = (try? appState.catchRepository.fetchForSpecies(species.id)) ?? []
        spots = (try? appState.spotRepository.fetchAll()) ?? []
        ownedGear = (try? appState.ownedGearRepository.fetchAll()) ?? []
        RegulationsService.shared.load()
        regulation = RegulationsService.shared.regulation(for: species)
        waters = TargetData.waters(holding: species.id, near: store.coordinate, appState: appState)
        loaded = true
    }
}

// MARK: - Pieces

/// An icon and a sentence, for reasons and explanations.
private struct TargetBullet: View {
    let text: String
    let systemImage: String
    let tint: Color
    var small = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: systemImage)
                .font(small ? .caption2 : .subheadline)
                .foregroundStyle(tint)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.dsText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A block's empty state: what will show here and how it gets there.
private struct TargetEmptyNote: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.dsText2)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.dsText2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
        .padding(.horizontal, DS.gutter)
    }
}

// MARK: - Words

struct TargetNoteItem: Identifiable {
    let icon: String
    let text: String
    var id: String { text }
}

@MainActor
enum TargetText {
    static func announce(_ species: Species?) {
        ToastCenter.shared.show(species.map { "Targeting \($0.commonName)" } ?? "Target cleared",
                                style: .info, icon: "scope")
    }

    /// "Happiest in 18°C to 24°C water", the feeding band the score uses.
    static func comfortLine(_ species: Species) -> String {
        guard species.optimalTempC != nil || species.minTempC != nil else { return "Score and lures tuned for it" }
        let band = ConditionText.comfort(for: species)
        return "Happiest in \(Units.temperature(band.lowerBound)) to \(Units.temperature(band.upperBound)) water"
    }

    /// What targeting this species changes, from what its record supports.
    static func changes(for species: Species) -> [TargetNoteItem] {
        var items: [TargetNoteItem] = []
        if species.optimalTempC != nil || species.minTempC != nil {
            let band = ConditionText.comfort(for: species)
            items.append(TargetNoteItem(icon: "thermometer.medium",
                                        text: "Water temperature is scored against its comfort band, \(Units.temperature(band.lowerBound)) to \(Units.temperature(band.upperBound))."))
        }
        let traits = ForecastEngine.SpeciesTraits(species)
        switch traits.tide {
        case .heavier:
            items.append(TargetNoteItem(icon: "water.waves",
                                        text: "Tide counts for more, because saltwater and estuary fish feed on the moving tide."))
        case .ignored:
            items.append(TargetNoteItem(icon: "water.waves.slash",
                                        text: "Tide is left out, because it lives in fresh water."))
        case .general:
            break
        }
        if traits.feedsAtNight {
            items.append(TargetNoteItem(icon: "moon.stars",
                                        text: "Night hours score well, because it feeds after dark."))
        }
        if !species.parsedBaits.isEmpty {
            items.append(TargetNoteItem(icon: "fish",
                                        text: "Lures that match its known baits rank higher in what to throw."))
        }
        if species.habitat == .marine || species.habitat == .brackish {
            items.append(TargetNoteItem(icon: "xmark.circle",
                                        text: "Bass lures such as frogs, spinnerbaits and Texas rigs are left out."))
        }
        return items
    }

    /// What targeting does, for the page with nothing targeted.
    static let general: [TargetNoteItem] = [
        TargetNoteItem(icon: "thermometer.medium",
                       text: "The bite score checks the water against that fish's own comfort band."),
        TargetNoteItem(icon: "water.waves",
                       text: "Tide counts for more for saltwater and estuary fish, and is left out for freshwater fish."),
        TargetNoteItem(icon: "moon.stars",
                       text: "Night feeders such as catfish and eels score well after dark."),
        TargetNoteItem(icon: "fish",
                       text: "What to throw favours lures that match its known baits."),
        TargetNoteItem(icon: "mappin.and.ellipse",
                       text: "You see waters that hold it, your spots for it, its size and bag limits, and your record with it."),
    ]

    static func ruleFigures(_ reg: FishingRegulation, imperial: Bool) -> [(String, String)] {
        var items: [(String, String)] = []
        switch (reg.minSizeCm, reg.maxSizeCm) {
        case let (lo?, hi?):
            items.append(("Legal size", "\(Units.length(cm: lo, imperial: imperial)) to \(Units.length(cm: hi, imperial: imperial))"))
        case let (lo?, nil):
            items.append(("Legal size", "\(Units.length(cm: lo, imperial: imperial)) or more"))
        case let (nil, hi?):
            items.append(("Legal size", "Up to \(Units.length(cm: hi, imperial: imperial))"))
        case (nil, nil):
            items.append(("Legal size", "None on file"))
        }
        items.append(("Bag limit", reg.bagLimit.map { "\($0) a day" } ?? "None on file"))
        if let text = reg.closedSeason, !text.isEmpty {
            if let season = TargetClosedSeason(text) {
                items.append(("Closed season", season.label))
                items.append(("Today", season.isClosed() ? "Closed, release it" : "Open"))
            } else {
                items.append(("Closed season", ForecastFormat.clean(text)))
            }
        } else {
            items.append(("Closed season", "None on file"))
        }
        return items
    }

    static func shortDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = cal.isDate(date, equalTo: .now, toGranularity: .year) ? "d MMM" : "MMM yyyy"
        return f.string(from: date)
    }
}

// MARK: - Closed season

/// A closed season read from a regulation's free text, such as
/// "Closed 1 Oct - 30 Nov" or "Oct–Nov spawning closure". Nil when the text
/// names no month, so the page shows the text as it is instead.
struct TargetClosedSeason {
    let startMonth: Int
    let startDay: Int
    let endMonth: Int
    let endDay: Int

    private static let months = ["january", "february", "march", "april", "may", "june", "july",
                                 "august", "september", "october", "november", "december"]
    private static let short = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    init?(_ text: String?) {
        guard let text else { return nil }
        let tokens = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        func month(_ token: String) -> Int? {
            guard token.count >= 3 else { return nil }
            return Self.months.firstIndex { $0.hasPrefix(token) }.map { $0 + 1 }
        }
        func day(_ index: Int) -> Int? {
            guard tokens.indices.contains(index), let d = Int(tokens[index]), (1...31).contains(d) else { return nil }
            return d
        }
        var marks: [(month: Int, index: Int)] = []
        for (i, token) in tokens.enumerated() {
            guard let m = month(token) else { continue }
            // "May" and "march" are also plain words; count them only next to a day.
            if (token == "may" || token == "march") && day(i - 1) == nil && day(i + 1) == nil { continue }
            marks.append((m, i))
        }
        guard let first = marks.first else { return nil }
        let last = marks.count > 1 ? marks[1] : first
        // "1 Oct - 30 Nov" puts the day before the month, "Oct 1 - Nov 30" after.
        let dayFirst = day(first.index - 1) != nil
        func dayFor(_ mark: (month: Int, index: Int)) -> Int? {
            dayFirst ? day(mark.index - 1) : day(mark.index + 1)
        }
        startMonth = first.month
        startDay = dayFor(first) ?? 1
        endMonth = last.month
        endDay = dayFor(last) ?? 31
    }

    /// "1 Oct to 30 Nov", "Oct to Nov" or "All of Nov".
    var label: String {
        if startMonth == endMonth && startDay == 1 && endDay == 31 {
            return "All of \(Self.short[startMonth - 1])"
        }
        let end = endDay == 31 && endMonth != startMonth ? Self.short[endMonth - 1]
            : "\(endDay) \(Self.short[endMonth - 1])"
        let start = startDay == 1 && endDay == 31 ? Self.short[startMonth - 1]
            : "\(startDay) \(Self.short[startMonth - 1])"
        return "\(start) to \(end)"
    }

    func isClosed(on date: Date = .now) -> Bool {
        let parts = Calendar.current.dateComponents([.month, .day], from: date)
        let today = (parts.month ?? 1) * 100 + (parts.day ?? 1)
        let start = startMonth * 100 + startDay
        let end = endMonth * 100 + endDay
        // A season like 15 Oct to 28 Feb runs over the new year.
        return start <= end ? (start...end).contains(today) : (today >= start || today <= end)
    }
}

// MARK: - Data

struct TargetSpotPlace: Identifiable {
    let spot: Spot
    let count: Int
    let km: Double
    var id: String { spot.id }
}

struct TargetWaterPlace: Identifiable {
    let water: Waterbody
    let km: Double
    var id: String { water.id.map { "\($0)" } ?? "\(water.name)|\(water.latitude)|\(water.longitude)" }
}

@MainActor
enum TargetData {
    /// How far to look for waters known to hold the target.
    static let radiusKm: Double = 400

    static func species(_ ids: [Int64], appState: AppState) -> [Species] {
        ids.compactMap { id in (try? appState.speciesRepository.fetch(id: id)) ?? nil }
    }

    static func km(from coordinate: CLLocationCoordinate2D, _ latitude: Double, _ longitude: Double) -> Double {
        CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            .distance(from: CLLocation(latitude: latitude, longitude: longitude)) / 1000
    }

    /// Your spots for the target, nearest first: where you have caught it,
    /// and saved waters known to hold it (a saved water is a spot).
    static func spots(catches: [CatchDetail], saved: [Spot], holdingWaterIds: Set<Int64>,
                      from coordinate: CLLocationCoordinate2D) -> [TargetSpotPlace] {
        var counts: [String: Int] = [:]
        var spots: [String: Spot] = [:]
        for detail in catches {
            guard let spot = detail.spot else { continue }
            counts[spot.id, default: 0] += 1
            spots[spot.id] = spot
        }
        for spot in saved {
            if let water = spot.waterbodyId, holdingWaterIds.contains(water) { spots[spot.id] = spot }
        }
        return spots.values
            .map { TargetSpotPlace(spot: $0, count: counts[$0.id] ?? 0, km: km(from: coordinate, $0.latitude, $0.longitude)) }
            .sorted { $0.km < $1.km }
    }

    /// Waters within `radiusKm` whose species list includes the target.
    static func waters(holding speciesId: Int64, near c: CLLocationCoordinate2D, appState: AppState) -> [Waterbody] {
        let latDelta = radiusKm / 111
        let lonDelta = radiusKm / (111 * max(0.2, cos(c.latitude * .pi / 180)))
        let nearby = (try? appState.waterbodyRepository.fetchForRegion(
            minLat: c.latitude - latDelta, maxLat: c.latitude + latDelta,
            minLon: c.longitude - lonDelta, maxLon: c.longitude + lonDelta,
            limit: 2000)) ?? []
        return nearby.filter { $0.fishSpeciesIds != nil && $0.decodedFishSpeciesIds.contains(speciesId) }
    }
}
