import SwiftUI
import MapKit

// MARK: - Picks

/// What a search result opens.
enum ExploreSearchPick {
    case spot(Spot)
    case water(Waterbody)
    case ramp(BoatRamp)
    case species(Species)
    case place(CLLocationCoordinate2D, String)
}

/// Quick categories under the search field.
enum ExploreSearchCategory: String, CaseIterable, Identifiable {
    case dams, rivers, estuaries, ramps, spots, species

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dams: "Dams and lakes"
        case .rivers: "Rivers"
        case .estuaries: "Estuaries"
        case .ramps: "Ramps"
        case .spots: "My spots"
        case .species: "Species"
        }
    }

    var icon: String {
        switch self {
        case .dams: ExploreFormat.waterIcon(.dam)
        case .rivers: ExploreFormat.waterIcon(.river)
        case .estuaries: ExploreFormat.waterIcon(.estuary)
        case .ramps: "sailboat.fill"
        case .spots: "mappin"
        case .species: "fish"
        }
    }

    /// The water a category lists. Reservoirs are often mapped as lakes, so
    /// the two go together.
    var waterTypes: Set<Waterbody.WaterbodyType>? {
        switch self {
        case .dams: [.dam, .lake]
        case .rivers: [.river]
        case .estuaries: [.estuary]
        case .ramps, .spots, .species: nil
        }
    }

    /// Heading over the list a category shows before anything is typed.
    var nearbyTitle: String {
        switch self {
        case .spots: "Your spots"
        case .species: "All species"
        case .ramps: "Ramps and access near you"
        case .dams, .rivers, .estuaries: "\(title) near you"
        }
    }
}

// MARK: - Recents

/// A recent pick, newest first, kept on this phone. Enough is stored to draw
/// the row and to open the place again without a lookup.
struct ExploreRecent: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case spot, water, ramp, species, place }
    let kind: Kind
    let key: String
    let title: String
    let subtitle: String
    let lat: Double
    let lon: Double
    /// Water type or ramp kind, for the thumbnail.
    var extra: String?

    var id: String { "\(kind.rawValue):\(key)" }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}

enum ExploreRecents {
    private static let key = "exploreSearchRecents"
    private static let limit = 8

    static func load() -> [ExploreRecent] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([ExploreRecent].self, from: data) else { return [] }
        return list
    }

    static func save(_ list: [ExploreRecent]) {
        if let data = try? JSONEncoder().encode(Array(list.prefix(limit))) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func adding(_ recent: ExploreRecent, to list: [ExploreRecent]) -> [ExploreRecent] {
        Array(([recent] + list.filter { $0.id != recent.id }).prefix(limit))
    }
}

// MARK: - Search pane

/// Explore search, with the field at the top of the screen. Before typing:
/// recent picks, quick categories and the nearest water. While typing:
/// your spots, water, ramps and access, species and places, each with a
/// square thumbnail, distance and the matched text in bold.
struct ExploreSearchPane: View {
    @Environment(AppState.self) private var appState
    let spots: [Spot]
    let topSpecies: [String: Species]
    /// Where distances are measured from: the angler, else the map centre.
    let origin: CLLocationCoordinate2D?
    let onClose: () -> Void
    let onPick: (ExploreSearchPick) -> Void

    @ObservedObject private var rampService = BoatRampService.shared
    @State private var text = ""
    @State private var category: ExploreSearchCategory?
    @State private var completer = MapSearchCompleter()
    @State private var waters: [Waterbody] = []
    @State private var allSpecies: [Species] = []
    @State private var recents: [ExploreRecent] = []
    @State private var isResolving = false
    @FocusState private var focused: Bool

    private var query: String { text.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            categoryChips
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if query.isEmpty, let category {
                        categoryList(category)
                    } else if query.isEmpty {
                        startPage
                    } else {
                        results
                    }
                }
                .padding(.bottom, DS.Space.s8)
                .pageWidth()
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(Color.dsBackground.ignoresSafeArea())
        .task {
            recents = ExploreRecents.load()
            waters = (try? appState.waterbodyRepository.fetchAll()) ?? []
            allSpecies = (try? appState.speciesRepository.fetchAll()) ?? []
            focused = true
        }
        .onChange(of: text) { _, newValue in
            if category == nil {
                completer.update(query: newValue, near: origin)
            }
        }
    }

    // MARK: Bar

    private var searchBar: some View {
        HStack(spacing: DS.Space.s3) {
            HStack(spacing: DS.Space.s2) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.dsText2)
                    .accessibilityHidden(true)
                TextField(category.map { "Search \($0.title.lowercased())" } ?? "Spots, water, ramps, species, places",
                          text: $text)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit(submit)
                if isResolving {
                    ProgressView().controlSize(.small)
                }
                if !text.isEmpty {
                    Button {
                        text = ""
                        completer.clear()
                        focused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.dsText3)
                    }
                    .buttonStyle(.dim)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Color.dsFill, in: Capsule())

            Button("Cancel") {
                focused = false
                completer.clear()
                onClose()
            }
            .foregroundStyle(.dsText)
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s2)
        .padding(.bottom, DS.Space.s2)
    }

    /// The quick categories wrap onto a second line rather than scroll
    /// sideways. While typing only the chosen one stays, so the results get
    /// the room, as in Apple Maps.
    @ViewBuilder
    private var categoryChips: some View {
        let shown = query.isEmpty ? ExploreSearchCategory.allCases : category.map { [$0] } ?? []
        if !shown.isEmpty {
            FlowLayout(spacing: DS.Space.s2) {
                ForEach(shown) { item in
                    Chip(item.title, systemImage: item.icon, isSelected: category == item) {
                        category = category == item ? nil : item
                        if category != nil { completer.clear() } else { completer.update(query: text, near: origin) }
                    }
                    .accessibilityHint(category == item ? "Shows everything again" : "Shows only \(item.title.lowercased())")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Space.s4)
            .padding(.bottom, DS.Space.s2)
            .sensoryFeedback(.selection, trigger: category)
        }
    }

    // MARK: Before typing

    @ViewBuilder
    private var startPage: some View {
        if !recents.isEmpty {
            header("Recents") {
                Button("Clear") {
                    recents = []
                    ExploreRecents.save([])
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.dsText2)
                .accessibilityLabel("Clear recents")
            }
            ForEach(recents) { recent in
                Button { open(recent) } label: { recentRow(recent) }
                    .buttonStyle(.dsRow)
            }
        }

        let near = nearestWaters(of: nil, limit: 5, includeSaved: false)
        if !near.isEmpty {
            header("Water near you")
            ForEach(near) { entry in
                waterButton(entry.water, distance: entry.metres)
            }
        }

        if recents.isEmpty && near.isEmpty {
            quietMessage("Search for a dam, river, ramp, town or species.")
        }
    }

    @ViewBuilder
    private func categoryList(_ category: ExploreSearchCategory) -> some View {
        header(category.nearbyTitle)
        switch category {
        case .dams, .rivers, .estuaries:
            let list = nearestWaters(of: category.waterTypes, limit: 25, includeSaved: true)
            if list.isEmpty {
                quietMessage("Nothing mapped within 100 km. Move the map over an area while online to load it.")
            }
            ForEach(list) { entry in
                // A saved water is listed as your spot.
                if let spot = savedSpot(for: entry.water) {
                    spotButton(spot)
                } else {
                    waterButton(entry.water, distance: entry.metres)
                }
            }
        case .ramps:
            let list = sortedRamps(rampService.ramps).prefix(25)
            if list.isEmpty {
                quietMessage("No ramps or access loaded here yet. Move the map to load them.")
            }
            ForEach(Array(list), id: \.id) { ramp in rampButton(ramp) }
        case .spots:
            let list = sortedSpots(spots)
            if list.isEmpty {
                quietMessage("No saved spots yet. Save a water or long press the map to add one.")
            }
            ForEach(list, id: \.id) { spot in spotButton(spot) }
        case .species:
            ForEach(allSpecies.sorted { $0.commonName < $1.commonName }.prefix(80)) { sp in
                speciesButton(sp)
            }
        }
    }

    // MARK: While typing

    @ViewBuilder
    private var results: some View {
        let spotHits = category == nil || category == .spots ? spotMatches : []
        let waterHits = category == nil || category?.waterTypes != nil ? waterMatches : []
        let rampHits = category == nil || category == .ramps ? rampMatches : []
        let speciesHits = category == nil || category == .species ? speciesMatches : []
        let places = category == nil ? Array(completer.completions.prefix(5)) : []
        let searchingPlaces = category == nil && completer.isWorking && places.isEmpty
        let nothing = spotHits.isEmpty && waterHits.isEmpty && rampHits.isEmpty && speciesHits.isEmpty && places.isEmpty

        if nothing && !searchingPlaces {
            ContentUnavailableView {
                Label("No results for \u{201C}\(query)\u{201D}", systemImage: "magnifyingglass")
            } description: {
                Text(category == nil
                     ? "Check the spelling, or search for a town to move the map there."
                     : "Nothing in \(category?.title.lowercased() ?? "this list") matches. Clear the category to search everything.")
            }
            .padding(.top, DS.Space.s8)
        } else {
            if !spotHits.isEmpty {
                header("Your spots")
                ForEach(spotHits, id: \.id) { spotButton($0) }
            }
            if !waterHits.isEmpty {
                header("Water")
                ForEach(waterHits) { waterButton($0.water, distance: $0.metres) }
            }
            if !rampHits.isEmpty {
                header("Ramps and access")
                ForEach(rampHits, id: \.id) { rampButton($0) }
            }
            if !speciesHits.isEmpty {
                header("Species")
                ForEach(speciesHits) { speciesButton($0) }
            }
            if !places.isEmpty || searchingPlaces {
                header("Places")
                if places.isEmpty {
                    HStack(spacing: DS.Space.s2) {
                        ProgressView().controlSize(.small)
                        Text("Searching places")
                            .font(.subheadline)
                            .foregroundStyle(.dsText2)
                    }
                    .padding(.horizontal, DS.gutter)
                    .padding(.vertical, DS.Space.s2)
                }
                ForEach(Array(places.enumerated()), id: \.offset) { _, completion in
                    Button { select(completion) } label: {
                        ExploreSearchRow(title: Self.highlight(completion.title, query),
                                         subtitle: completion.subtitle.isEmpty ? nil : completion.subtitle) {
                            ThumbView(systemImage: "mappin.and.ellipse", tint: .gray, size: 48)
                        }
                    }
                    .buttonStyle(.dsRow)
                    .disabled(isResolving)
                }
            }
        }
    }

    private var spotMatches: [Spot] {
        let q = query.lowercased()
        // A saved water is found by the water's name too.
        let names = waterNames
        let hits = spots.filter { spot in
            spot.name.localizedStandardContains(query)
                || (spot.waterbodyId.flatMap { names[$0] }?.localizedStandardContains(query) ?? false)
        }
        return Array(hits.sorted { a, b in
            let ap = a.name.lowercased().hasPrefix(q), bp = b.name.lowercased().hasPrefix(q)
            if ap != bp { return ap }
            return (metres(to: a.coordinate) ?? .infinity) < (metres(to: b.coordinate) ?? .infinity)
        }.prefix(4))
    }

    /// Names that start with the query first, then the nearest.
    private var waterMatches: [WaterHit] {
        let q = query.lowercased()
        let types = category?.waterTypes
        var seen = Set<Int64>()
        let saved = savedWaterIds
        // Saved water shows under your spots instead.
        let hits = waters.filter { wb in
            !saved.contains(wb.id ?? -1)
                && (types?.contains(wb.type) ?? true)
                && wb.name.localizedStandardContains(query)
                && seen.insert(wb.id ?? -1).inserted
        }
        return Array(hits
            .map { WaterHit(water: $0, metres: metres(to: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude))) }
            .sorted { a, b in
                let ap = a.water.name.lowercased().hasPrefix(q), bp = b.water.name.lowercased().hasPrefix(q)
                if ap != bp { return ap }
                return (a.metres ?? .infinity, -(a.water.surfaceAreaKm2 ?? 0)) < (b.metres ?? .infinity, -(b.water.surfaceAreaKm2 ?? 0))
            }
            .prefix(category == nil ? 5 : 25))
    }

    private var rampMatches: [BoatRamp] {
        Array(sortedRamps(rampService.ramps.filter {
            $0.name.localizedStandardContains(query) || $0.kind.label.localizedStandardContains(query)
        }).prefix(category == nil ? 4 : 25))
    }

    private var speciesMatches: [Species] {
        let q = query.lowercased()
        let hits = allSpecies.filter {
            $0.commonName.localizedStandardContains(query) || $0.scientificName.localizedStandardContains(query)
        }
        let first = hits.filter { $0.commonName.lowercased().hasPrefix(q) }
        let rest = hits.filter { !$0.commonName.lowercased().hasPrefix(q) }
        return Array((first + rest).prefix(category == nil ? 4 : 40))
    }

    // MARK: Rows

    private func header<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.dsText)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, DS.gutter)
        .padding(.top, DS.Space.s5)
        .padding(.bottom, DS.Space.s1)
    }

    private func header(_ title: String) -> some View {
        header(title) { EmptyView() }
    }

    private func quietMessage(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.dsText2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.gutter)
            .padding(.vertical, DS.Space.s2)
    }

    private func spotButton(_ spot: Spot) -> some View {
        Button { pick(.spot(spot), recent: recent(for: spot)) } label: {
            ExploreSearchRow(title: Self.highlight(spot.name, query),
                             subtitle: ExploreFormat.spotType(spot),
                             trailing: distanceText(to: spot.coordinate)) {
                spotThumb(spot)
            }
        }
        .buttonStyle(.dsRow)
    }

    private func waterButton(_ water: Waterbody, distance: Double?) -> some View {
        Button { pick(.water(water), recent: recent(for: water)) } label: {
            ExploreSearchRow(title: Self.highlight(water.name, query),
                             subtitle: waterSubtitle(water),
                             trailing: distance.map { Units.distance(m: $0) }) {
                ThumbView(systemImage: ExploreFormat.waterIcon(water.type), tint: Color.exploreWater, size: 48)
            }
        }
        .buttonStyle(.dsRow)
    }

    private func rampButton(_ ramp: BoatRamp) -> some View {
        Button { pick(.ramp(ramp), recent: recent(for: ramp)) } label: {
            ExploreSearchRow(title: Self.highlight(ramp.name, query),
                             subtitle: ramp.kind.label,
                             trailing: distanceText(to: ramp.coordinate)) {
                PlaceSnapshotThumb(place: ramp, size: 48)
            }
        }
        .buttonStyle(.dsRow)
    }

    private func speciesButton(_ sp: Species) -> some View {
        Button { pick(.species(sp), recent: recent(for: sp)) } label: {
            ExploreSearchRow(title: Self.highlight(sp.commonName, query),
                             subtitle: sp.scientificName) {
                ThumbView(species: sp, size: 48)
            }
        }
        .buttonStyle(.dsRow)
    }

    private func recentRow(_ recent: ExploreRecent) -> some View {
        ExploreSearchRow(title: AttributedString(recent.title),
                         subtitle: recent.subtitle.isEmpty ? nil : recent.subtitle,
                         trailing: recent.kind == .species ? nil : distanceText(to: recent.coordinate)) {
            recentThumb(recent)
        }
    }

    @ViewBuilder
    private func recentThumb(_ recent: ExploreRecent) -> some View {
        switch recent.kind {
        case .spot:
            if let spot = spots.first(where: { $0.id == recent.key }) {
                spotThumb(spot)
            } else {
                ThumbView(systemImage: "mappin", tint: DS.accent, size: 48)
            }
        case .water:
            ThumbView(systemImage: ExploreFormat.waterIcon(Waterbody.WaterbodyType(rawValue: recent.extra ?? "") ?? .lake),
                      tint: Color.exploreWater, size: 48)
        case .ramp:
            PlaceSnapshotThumb(place: ramp(from: recent), size: 48)
        case .species:
            if let sp = allSpecies.first(where: { String($0.id) == recent.key }) {
                ThumbView(species: sp, size: 48)
            } else {
                ThumbView(systemImage: "fish", tint: .gray, size: 48)
            }
        case .place:
            ThumbView(systemImage: "mappin.and.ellipse", tint: .gray, size: 48)
        }
    }

    @ViewBuilder
    private func spotThumb(_ spot: Spot) -> some View {
        if let sp = topSpecies[spot.id] {
            ThumbView(species: sp, size: 48)
        } else {
            ThumbView(systemImage: spot.type.icon, tint: DS.accent, size: 48)
        }
    }

    private func waterSubtitle(_ wb: Waterbody) -> String {
        let type = ExploreFormat.waterType(wb.type)
        guard let area = wb.surfaceAreaKm2, area > 0 else { return type }
        return "\(type), \(ExploreFormat.area(area))"
    }

    // MARK: Saved water

    private var savedWaterIds: Set<Int64> { Set(spots.compactMap(\.waterbodyId)) }

    private var waterNames: [Int64: String] {
        let ids = savedWaterIds
        guard !ids.isEmpty else { return [:] }
        var names: [Int64: String] = [:]
        for wb in waters { if let id = wb.id, ids.contains(id) { names[id] = wb.name } }
        return names
    }

    private func savedSpot(for wb: Waterbody) -> Spot? {
        guard let id = wb.id else { return nil }
        return spots.first { $0.waterbodyId == id }
    }

    // MARK: Distance

    private func metres(to target: CLLocationCoordinate2D) -> Double? {
        guard let origin else { return nil }
        return CLLocation(latitude: origin.latitude, longitude: origin.longitude)
            .distance(from: CLLocation(latitude: target.latitude, longitude: target.longitude))
    }

    private func distanceText(to target: CLLocationCoordinate2D) -> String? {
        metres(to: target).map { Units.distance(m: $0) }
    }

    /// The nearest water within about 100 km, of one type or any.
    private func nearestWaters(of types: Set<Waterbody.WaterbodyType>?, limit: Int, includeSaved: Bool) -> [WaterHit] {
        guard origin != nil else { return [] }
        let saved = includeSaved ? [] : savedWaterIds
        return Array(waters
            .filter { (types?.contains($0.type) ?? true) && !saved.contains($0.id ?? -1) }
            .map { WaterHit(water: $0, metres: metres(to: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude))) }
            .filter { ($0.metres ?? .infinity) < 100_000 }
            .sorted { ($0.metres ?? .infinity) < ($1.metres ?? .infinity) }
            .prefix(limit))
    }

    private func sortedRamps(_ list: [BoatRamp]) -> [BoatRamp] {
        list.sorted { (metres(to: $0.coordinate) ?? .infinity) < (metres(to: $1.coordinate) ?? .infinity) }
    }

    private func sortedSpots(_ list: [Spot]) -> [Spot] {
        guard origin != nil else { return list }
        return list.sorted { (metres(to: $0.coordinate) ?? .infinity) < (metres(to: $1.coordinate) ?? .infinity) }
    }

    // MARK: Picking

    private func pick(_ pick: ExploreSearchPick, recent: ExploreRecent) {
        recents = ExploreRecents.adding(recent, to: recents)
        ExploreRecents.save(recents)
        focused = false
        onPick(pick)
    }

    private func submit() {
        if let spot = spotMatches.first {
            pick(.spot(spot), recent: recent(for: spot))
        } else if let water = waterMatches.first?.water {
            pick(.water(water), recent: recent(for: water))
        } else if let ramp = rampMatches.first {
            pick(.ramp(ramp), recent: recent(for: ramp))
        } else if let sp = speciesMatches.first {
            pick(.species(sp), recent: recent(for: sp))
        } else if let completion = completer.completions.first {
            select(completion)
        }
    }

    /// Resolves a place suggestion to coordinates.
    private func select(_ completion: MKLocalSearchCompletion) {
        focused = false
        isResolving = true
        Task {
            let search = MKLocalSearch(request: MKLocalSearch.Request(completion: completion))
            let response = try? await search.start()
            isResolving = false
            guard let coord = response?.mapItems.first?.placemark.location?.coordinate else {
                ToastCenter.shared.show("Could not find that place", style: .error)
                return
            }
            let recent = ExploreRecent(kind: .place, key: "\(coord.latitude),\(coord.longitude)",
                                       title: completion.title, subtitle: completion.subtitle,
                                       lat: coord.latitude, lon: coord.longitude)
            pick(.place(coord, completion.title), recent: recent)
        }
    }

    private func open(_ recent: ExploreRecent) {
        switch recent.kind {
        case .spot:
            if let spot = spots.first(where: { $0.id == recent.key }) {
                pick(.spot(spot), recent: recent)
            } else {
                // The spot was removed since; go to where it was.
                pick(.place(recent.coordinate, recent.title), recent: recent)
            }
        case .water:
            if let id = Int64(recent.key), let wb = try? appState.waterbodyRepository.fetch(id: id) {
                pick(.water(wb), recent: recent)
            } else {
                pick(.place(recent.coordinate, recent.title), recent: recent)
            }
        case .ramp:
            pick(.ramp(ramp(from: recent)), recent: recent)
        case .species:
            if let sp = allSpecies.first(where: { String($0.id) == recent.key }) {
                pick(.species(sp), recent: recent)
            } else {
                recents.removeAll { $0.id == recent.id }
                ExploreRecents.save(recents)
            }
        case .place:
            pick(.place(recent.coordinate, recent.title), recent: recent)
        }
    }

    private func ramp(from recent: ExploreRecent) -> BoatRamp {
        BoatRamp(id: recent.key, name: recent.title,
                 kind: BoatRamp.Kind(rawValue: recent.extra ?? "") ?? .ramp,
                 lat: recent.lat, lon: recent.lon)
    }

    private func recent(for spot: Spot) -> ExploreRecent {
        ExploreRecent(kind: .spot, key: spot.id, title: spot.name, subtitle: ExploreFormat.spotType(spot),
                      lat: spot.latitude, lon: spot.longitude)
    }

    private func recent(for water: Waterbody) -> ExploreRecent {
        ExploreRecent(kind: .water, key: String(water.id ?? 0), title: water.name, subtitle: waterSubtitle(water),
                      lat: water.latitude, lon: water.longitude, extra: water.type.rawValue)
    }

    private func recent(for ramp: BoatRamp) -> ExploreRecent {
        ExploreRecent(kind: .ramp, key: ramp.id, title: ramp.name, subtitle: ramp.kind.label,
                      lat: ramp.lat, lon: ramp.lon, extra: ramp.kind.rawValue)
    }

    private func recent(for sp: Species) -> ExploreRecent {
        ExploreRecent(kind: .species, key: String(sp.id), title: sp.commonName, subtitle: sp.scientificName,
                      lat: 0, lon: 0)
    }

    // MARK: Highlight

    /// The title with the typed text in bold, the rest in the secondary colour.
    static func highlight(_ title: String, _ query: String) -> AttributedString {
        var text = AttributedString(title)
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return text }
        text.foregroundColor = Color.dsText2
        if let range = text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) {
            text[range].foregroundColor = Color.dsText
            text[range].font = .body.weight(.semibold)
        }
        return text
    }
}

/// A water with how far away it is.
private struct WaterHit: Identifiable {
    let water: Waterbody
    let metres: Double?
    var id: String { "\(water.id ?? 0)-\(water.name)" }
}

// MARK: - Row

/// A search result: square thumbnail, title with the match emphasised,
/// a subtitle, and the distance on the right.
struct ExploreSearchRow<Thumb: View>: View {
    let title: AttributedString
    var subtitle: String?
    var trailing: String?
    private let thumb: Thumb
    @Environment(\.dynamicTypeSize) private var typeSize

    init(title: AttributedString, subtitle: String? = nil, trailing: String? = nil,
         @ViewBuilder thumb: () -> Thumb) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.thumb = thumb()
    }

    var body: some View {
        HStack(spacing: 14) {
            thumb
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.dsText)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.dsText2)
                        .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let trailing {
                Text(trailing)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.dsText2)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, DS.gutter)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Place suggestions

/// Live type-ahead place suggestions, biased to the area around the angler
/// so nearby towns and landmarks rank first.
@Observable
final class MapSearchCompleter: NSObject, MKLocalSearchCompleterDelegate {
    var completions: [MKLocalSearchCompletion] = []
    /// True while a query is out and nothing has come back yet.
    var isWorking = false
    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address, .query]
    }

    func update(query: String, near coordinate: CLLocationCoordinate2D?) {
        if let coordinate {
            completer.region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 120_000,
                longitudinalMeters: 120_000
            )
        }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            clear()
            return
        }
        isWorking = true
        completer.queryFragment = trimmed
    }

    func clear() {
        completions = []
        isWorking = false
        completer.cancel()
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        completions = completer.results
        isWorking = false
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        completions = []
        isWorking = false
    }
}

private extension Spot {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}
