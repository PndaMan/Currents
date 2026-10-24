import SwiftUI

/// A species page, laid out like a catch page: art cover, title block and
/// tags, Target / Log catch / Share, your stats and catches, season, water
/// temperature tiles, baits, limits with a link to every rule, tips and the
/// field guide entry. Pushed from the species guide, the Fishdex, catch
/// pages, water pages and regulations.
struct SpeciesDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL
    let species: Species
    /// Set when pushed from a thumbnail that registered a zoom source.
    var zoom: SpeciesZoomSource? = nil

    @State private var catches: [CatchDetail] = []
    @State private var info: SpeciesInfoService.Info?
    @State private var loaded = false
    @State private var showingLogCatch = false
    @State private var showingRules = false
    @State private var showingTarget = false
    @State private var openCatchId: String?
    @State private var aboutExpanded = false
    @State private var titleShown = false
    @State private var showingAllCatches = false
    @State private var showingRangeMap = false
    /// The estimated water through the year at the forecast's place, as the
    /// species guide reads it. Starts from the time zone's hemisphere until
    /// the first load.
    @State private var water = SpeciesSeason.waterYear(latitude: nil)
    @AppStorage("units") private var units = "metric"
    /// Shared with Today's target species (0 means any species).
    @AppStorage("targetSpeciesId") private var targetSpeciesId: Int = 0

    private var imperial: Bool { units == "imperial" }
    private var tint: Color { species.artTint }
    /// The Size and bag limits colour, as on the Profile row.
    private static let limitsTint: Color = .purple
    private var isTargeted: Bool { targetSpeciesId == Int(species.id) }
    private var month: Int { SpeciesSeason.currentMonth }
    private var knowsSeason: Bool { SpeciesSeason.knowsSeason(species) }
    private var seasonScores: [Int] { SpeciesSeason.scores(species, water: water) }
    private var inSeasonNow: Bool { SpeciesSeason.isInSeason(species, month: month, water: water) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                cover
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, DS.Space.s2)

                DetailHeader(over: overLine, title: species.commonName, subtitle: species.scientificName)
                    .padding(.top, DS.Space.s4)

                tags
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, DS.Space.s3)

                actions
                    .padding(.top, DS.Space.s5)

                if isTargeted {
                    targetRow
                        .padding(.top, DS.Space.s4)
                        .transition(.opacity)
                }

                if !catches.isEmpty {
                    statsSection
                    historySection
                } else if loaded {
                    notFoundRow
                        .padding(.top, DS.Space.s6)
                }

                if knowsSeason {
                    seasonSection
                }
                temperatureSection
                if !species.parsedBaits.isEmpty {
                    baitsSection
                }
                if !gearGroups.isEmpty {
                    gearSection
                }
                if !spotGroups.isEmpty {
                    whereSection
                }
                limitsSection
                tipsSection
                if hasAbout {
                    aboutSection
                }
                if let taxonId = info?.taxonId {
                    rangeSection(taxonId)
                }
            }
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
        }
        .detailTint(tint)
        .pfTrackScroll($titleShown, threshold: 320)
        .pfScrollTitle(species.commonName, shown: titleShown)
        .modifier(SpeciesZoomDestination(zoom: zoom))
        .navigationDestination(item: $openCatchId) { id in
            if let detail = catches.first(where: { $0.id == id }) {
                CatchDetailView(detail: detail)
            }
        }
        .navigationDestination(isPresented: $showingRules) {
            RegulationsView()
        }
        .navigationDestination(isPresented: $showingTarget) {
            TargetScreen()
        }
        .navigationDestination(isPresented: $showingAllCatches) {
            SpeciesCatchesList(species: species)
        }
        .fullScreenCover(isPresented: $showingRangeMap) {
            if let taxonId = info?.taxonId {
                NavigationStack {
                    SpeciesRangeMapView(taxonId: taxonId, interactive: true)
                        .ignoresSafeArea(edges: .bottom)
                        .navigationTitle("Where it is seen")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) { SheetDoneButton() }
                        }
                }
            }
        }
        .fullScreenCover(isPresented: $showingLogCatch, onDismiss: {
            Task { await load() }
        }) {
            LogCatchView(presetSpecies: species)
        }
        .task { await load() }
    }

    private func load() async {
        FishdexNumbers.countIfNeeded(appState.speciesRepository)
        water = await SpeciesSeason.waterYear(appState)
        catches = (try? appState.catchRepository.fetchForSpecies(species.id)) ?? []
        loaded = true
        if info == nil {
            info = await SpeciesInfoService.shared.info(scientificName: species.scientificName)
        }
    }

    // MARK: - Top

    /// The species art on its colour, as on a catch page without a photo.
    private var cover: some View {
        SpeciesArtworkView(species: species, caught: true, size: 200, fillWidth: true)
            .padding(.horizontal, DS.Space.s6)
            .frame(maxWidth: .infinity)
            .frame(height: 240)
            .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .accessibilityElement()
            .accessibilityLabel(species.commonName)
            .accessibilityAddTraits(.isImage)
    }

    private var overLine: String {
        if let habitat = SpeciesSeason.habitatName(species.habitat) {
            return "Fishdex \(species.fishdexNumber), \(habitat.lowercased())"
        }
        return "Fishdex \(species.fishdexNumber)"
    }

    private var tags: some View {
        SpeciesTagFlow {
            // `catches` is newest first.
            if let first = catches.last?.catchRecord.caughtAt {
                SpeciesTag(text: "Found \(LogbookFormat.fullDate(first))",
                           systemImage: "checkmark.circle.fill", tint: .dsScoreGood)
            } else if loaded {
                SpeciesTag(text: "Not found yet")
            }
            if knowsSeason {
                SpeciesTag(text: inSeasonNow ? "In season now" : "Out of season now")
            }
            SpeciesTag(text: "\(species.rarity.label) find")
        }
    }

    private var actions: some View {
        ActionTriple {
            Button {
                withAnimation(DS.Motion.softSpring) {
                    targetSpeciesId = isTargeted ? 0 : Int(species.id)
                }
                ToastCenter.shared.show(isTargeted ? "Targeting \(species.commonName)" : "Target cleared",
                                        style: .info, icon: "scope")
            } label: {
                Label(isTargeted ? "Targeting" : "Target", systemImage: "scope")
                    .contentTransition(.symbolEffect(.replace))
            }
            // As the place pages' Save tile: primary to set, tonal once set.
            .buttonStyle(ActionTileStyle(isTargeted ? .tonal : .primary))
            .accessibilityHint("Sets this species as the target for your bite forecast")

            Button {
                showingLogCatch = true
            } label: {
                Label("Log catch", systemImage: "plus")
            }
            .buttonStyle(ActionTileStyle(.tonal))

            ShareLink(item: shareText) {
                ActionTileLabel("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.dim)
        }
    }

    /// Once targeted, the way into the target page, as on Today.
    private var targetRow: some View {
        Button {
            showingTarget = true
        } label: {
            ArtRow(title: "Best times today", subtitle: "Bite score and where to go", chevron: true) {
                ThumbView(systemImage: "scope", tint: DS.accent, size: 52)
            }
        }
        .buttonStyle(.dsRow)
    }

    private var shareText: String {
        var text = "\(species.commonName) (\(species.scientificName))"
        if let wiki = info?.wikipediaURL { text += "\n\(wiki)" }
        return text
    }

    // MARK: - Your catches

    /// Opens the log flow with this species filled in.
    private var notFoundRow: some View {
        Button {
            showingLogCatch = true
        } label: {
            ArtRow(title: "Not in your Fishdex yet", subtitle: "Log one to add it", chevron: true) {
                ThumbView(systemImage: "book.closed.fill", tint: .dsScoreGood, size: 52)
            }
        }
        .buttonStyle(.dsRow)
    }

    /// Count, heaviest, longest and released as tiles, as on a place page,
    /// then when the first and the latest were caught. No tile has a
    /// footnote, so the row stays one height.
    private var statsSection: some View {
        let records = catches.map(\.catchRecord)
        let released = records.filter(\.released).count
        let heaviest = records.compactMap(\.weightKg).max()
        let longest = records.compactMap(\.lengthCm).max()
        // Newest first, so the last is the first one caught.
        let first = records.last?.caughtAt
        let latest = records.count > 1 ? records.first?.caughtAt : nil
        return section("Your stats") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    StatTile("Caught", systemImage: "fish.fill", value: "\(records.count)")
                    if let heaviest {
                        let parts = Units.weightParts(kg: heaviest, imperial: imperial)
                        StatTile("Heaviest", systemImage: "trophy.fill", tint: .dsScoreFair,
                                 value: parts.0, unit: parts.1)
                    }
                    if let longest {
                        let parts = Units.lengthParts(cm: longest, imperial: imperial)
                        StatTile("Longest", systemImage: "ruler", tint: .indigo,
                                 value: parts.0, unit: parts.1)
                    }
                    StatTile("Released", systemImage: "arrow.uturn.backward", tint: .dsScoreGood,
                             value: "\(released)", unit: "of \(records.count)")
                }
                .padding(.horizontal, DS.gutter)
            }
            if first != nil || latest != nil {
                CardGroup {
                    if let first {
                        CardRow("First caught", systemImage: "flag.fill", tint: .green,
                                value: LogbookFormat.fullDate(first))
                    }
                    if let latest {
                        CardRow("Last caught", systemImage: "clock.fill", tint: .blue,
                                value: LogbookFormat.fullDate(latest))
                    }
                }
                .padding(.top, DS.Space.s3)
            }
        }
    }

    private var historySection: some View {
        section("Catch history", detail: "\(catches.count)") {
            ForEach(catches.prefix(5)) { detail in
                Button {
                    openCatchId = detail.id
                } label: {
                    ArtRow(over: LogbookFormat.relativeDay(detail.catchRecord.caughtAt),
                           title: measureText(detail.catchRecord),
                           subtitle: detail.spot?.name,
                           chevron: true) {
                        catchThumb(detail)
                    }
                }
                .buttonStyle(.dsRow)
            }
            if catches.count > 5 {
                CardGroup {
                    Button { showingAllCatches = true } label: {
                        CardRow("See all \(catches.count) catches", chevron: true)
                    }
                    .buttonStyle(.dsCardRow)
                }
                .padding(.top, DS.Space.s2)
            }
        }
    }

    private func measureText(_ record: Catch) -> String {
        let parts = [record.lengthCm.map { Units.length(cm: $0, imperial: imperial) },
                     record.weightKg.map { Units.weight(kg: $0, imperial: imperial) }].compactMap { $0 }
        if parts.isEmpty { return record.released ? "Released" : "Kept" }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private func catchThumb(_ detail: CatchDetail) -> some View {
        if let path = detail.catchRecord.allPhotoPaths.first {
            PhotoThumbnail(path: path, size: 52, cornerRadius: DS.Radius.thumb) {
                ThumbView(species: species, size: 52)
            }
            .frame(width: 52, height: 52)
        } else {
            ThumbView(species: species, size: 52)
        }
    }

    // MARK: - Season and temperature

    private var seasonSection: some View {
        section("Season") {
            SeasonChart(scores: seasonScores,
                        inSeason: (1...12).map { SpeciesSeason.isInSeason(species, month: $0, water: water) },
                        tint: tint)
            SectionFootnote(SpeciesSeason.peakText(seasonScores, month: month).map { "\($0), estimated from typical water temperatures." }
                        ?? "Estimated from typical water temperatures.")
        }
    }

    /// Two condition tiles, as on Today: this month's typical water against
    /// the species' range, and where it feeds best. Left out when the record
    /// holds the seed's stand-in band rather than real temperatures.
    @ViewBuilder
    private var temperatureSection: some View {
        if SpeciesSeason.hasPlaceholderTemps(species) {
            EmptyView()
        } else if let band = SpeciesSeason.band(species) {
            let monthWater = water.temp(month)
            let feeds = ConditionText.comfort(for: species)
            section("Water temperature") {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                    ConditionTile("Water in \(SpeciesSeason.fullMonths[month - 1])",
                                  systemImage: "thermometer.medium", iconTint: .dsScoreLow,
                                  value: degreesValue(monthWater), unit: imperial ? "°F" : "°C",
                                  footnote: waterFootnote(monthWater, band: band, feeds: feeds)) {
                        SpeciesTempBar(low: band.lower, high: band.upper, value: monthWater)
                    }
                    ConditionTile("Feeds best", systemImage: "fish.fill", iconTint: tint,
                                  value: "\(degreesValue(feeds.lowerBound)) to \(degreesValue(feeds.upperBound))",
                                  unit: imperial ? "°F" : "°C",
                                  footnote: survivesText.map { "Survives \($0)" })
                }
                .padding(.horizontal, DS.gutter)
                SectionFootnote("Typical surface water for the month, not a reading.")
            }
        } else if let survives = survivesText {
            section("Water temperature") {
                KeyValueList(rows: [("Survives", survives)])
            }
        }
    }

    /// The recorded tolerance range, only when both ends are known.
    private var survivesText: String? {
        guard let lo = species.minTempC, let hi = species.maxTempC else { return nil }
        return SpeciesSeason.rangeText(lo, hi, imperial: imperial)
    }

    private func degreesValue(_ celsius: Double) -> String {
        "\(Int((imperial ? celsius * 9 / 5 + 32 : celsius).rounded()))"
    }

    private func waterFootnote(_ water: Double, band: (lower: Double, optimal: Double, upper: Double),
                               feeds: ClosedRange<Double>) -> String {
        let scale = imperial ? 9.0 / 5.0 : 1.0
        if water < band.lower { return "\(Int(((band.lower - water) * scale).rounded()))° below their range" }
        if water > band.upper { return "\(Int(((water - band.upper) * scale).rounded()))° above their range" }
        if feeds.contains(water) { return "Where they feed best" }
        return water < band.optimal ? "In range, on the cool side" : "In range, on the warm side"
    }

    // MARK: - Baits and gear

    private var baitsSection: some View {
        section("Best lures and baits") {
            ForEach(Array(species.parsedBaits.enumerated()), id: \.offset) { index, bait in
                BaitRow(rank: index + 1, name: sentenceCase(bait))
            }
            if let notes = species.baitNotes, !notes.isEmpty {
                SectionFootnote(notes)
            }
        }
    }

    /// Gear loadouts this species was caught on, most catches first.
    private var gearGroups: [Tally] {
        let withGear = catches.filter { $0.gearLoadout != nil }
        let grouped = Dictionary(grouping: withGear, by: { $0.gearLoadout?.name ?? "" })
        let tallies = grouped.map { key, value in
            Tally(key: key, name: key, detail: value.first?.gearLoadout?.lure, count: value.count)
        }
        return Array(tallies.sorted { $0.count > $1.count }.prefix(5))
    }

    private var gearSection: some View {
        section("Your best gear") {
            ForEach(gearGroups, id: \.key) { group in
                ArtRow(title: group.name, subtitle: tallySubtitle(group)) {
                    if let lure = group.detail, !lure.isEmpty {
                        LureArtView(name: lure, size: 56)
                    } else {
                        ThumbView(systemImage: "wrench.and.screwdriver.fill", tint: DS.accent, size: 56)
                    }
                }
            }
        }
    }

    /// Your spots where this species was caught, most catches first.
    private var spotGroups: [Tally] {
        let spots = catches.compactMap(\.spot)
        let grouped = Dictionary(grouping: spots, by: \.id)
        let tallies = grouped.map { id, value in
            Tally(key: id, name: value.first?.name ?? "Spot", detail: nil, count: value.count,
                  icon: value.first?.type.icon, spot: value.first)
        }
        return Array(tallies.sorted { $0.count > $1.count }.prefix(5))
    }

    private var whereSection: some View {
        section("Where you caught it") {
            ForEach(spotGroups, id: \.key) { spot in
                // A spot opens on the Explore map in its sheet.
                Button {
                    if let place = spot.spot { appState.pendingDeepLink = MapLink.spot(place) }
                } label: {
                    ArtRow(title: spot.name, subtitle: tallySubtitle(spot), chevron: true) {
                        spotThumb(spot)
                    }
                }
                .buttonStyle(.dsRow)
            }
        }
    }

    /// The spot's map render, or its symbol when the group has no spot.
    @ViewBuilder
    private func spotThumb(_ tally: Tally) -> some View {
        if let spot = tally.spot {
            PlaceSnapshotThumb(spot: spot, size: 52)
        } else {
            ThumbView(systemImage: tally.icon ?? "mappin.and.ellipse", tint: DS.accent, size: 52)
        }
    }

    private func tallySubtitle(_ tally: Tally) -> String {
        let count = tally.count == 1 ? "1 catch" : "\(tally.count) catches"
        guard let detail = tally.detail, !detail.isEmpty else { return count }
        return "\(detail), \(count)"
    }

    // MARK: - Limits, tips, about

    @ViewBuilder
    private var limitsSection: some View {
        let reg = RegulationsService.shared.regulation(for: species)
        section("Size and bag limits", detail: reg?.region) {
            if let reg {
                KeyValueList(rows: limitRows(reg))
                if let notes = reg.notes, !notes.isEmpty {
                    SectionFootnote(notes)
                }
            } else {
                InlineEmpty(systemImage: "list.bullet.clipboard",
                            text: "None on file for this species. Check the local rules before you keep one.")
            }
            Button {
                showingRules = true
            } label: {
                ArtRow(title: "All size and bag limits", subtitle: "Every species, works offline", chevron: true) {
                    ThumbView(systemImage: "list.bullet.clipboard", tint: Self.limitsTint, size: 52)
                }
            }
            .buttonStyle(.dsRow)
            .padding(.top, DS.Space.s2)
        }
    }

    private func limitRows(_ reg: FishingRegulation) -> [(String, String)] {
        var rows: [(String, String)] = []
        rows.append(("Minimum size", reg.minSizeCm.map { Units.length(cm: $0, imperial: imperial) } ?? "None"))
        if let max = reg.maxSizeCm {
            rows.append(("Maximum size", Units.length(cm: max, imperial: imperial)))
        }
        rows.append(("Bag limit", reg.bagLimit.map { "\($0) a day" } ?? "None"))
        if let closed = reg.closedSeason, !closed.isEmpty {
            rows.append(("Closed season", closed))
        } else {
            rows.append(("Closed season", "None"))
        }
        return rows
    }

    @ViewBuilder
    private var tipsSection: some View {
        let place = whereToLook
        // The seed's stand-in band is not a water temperature to look for.
        let water = SpeciesSeason.hasPlaceholderTemps(species) ? nil : species.optimalTempC
        if place != nil || water != nil {
            section("Tips") {
                CardGroup {
                    if let place {
                        CardRow("Where to look", subtitle: place, systemImage: "scope", tint: DS.accent)
                    }
                    if let water {
                        CardRow("Water to look for", systemImage: "thermometer.medium", tint: .dsScoreLow,
                                value: Units.temperature(water, imperial: imperial))
                    }
                }
            }
        }
    }

    /// Where to look, from its habitat.
    private var whereToLook: String? {
        switch species.habitat {
        case .freshwater: "Fish structure: fallen trees, rocks and weed beds."
        case .marine: "Work reefs, jetties and current lines around the tide."
        case .brackish: "Try estuaries, river mouths and mangroves."
        case nil: nil
        }
    }

    /// The field guide entry: the summary when it has loaded, then family,
    /// conservation status and sightings, and the Wikipedia link.
    private var aboutSection: some View {
        section("About") {
            if let summary = info?.summary, !summary.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Text(summary)
                        .font(.body)
                        .foregroundStyle(.dsText)
                        .lineLimit(aboutExpanded ? nil : 4)
                    Button(aboutExpanded ? "Show less" : "Show more") {
                        withAnimation(DS.Motion.easeOut) { aboutExpanded.toggle() }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.accent)
                    .buttonStyle(.dim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.gutter)
                .padding(.bottom, DS.Space.s2)
            }
            if !aboutRows.isEmpty {
                KeyValueList(rows: aboutRows)
            }
            if let wiki = info?.wikipediaURL, let url = URL(string: wiki) {
                Button {
                    openURL(url)
                } label: {
                    ArtRow(title: "Wikipedia", subtitle: "Read the full article") {
                        ThumbView(systemImage: "book.pages", tint: DS.accent, size: 52)
                    } trailing: {
                        Image(systemName: "arrow.up.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.dsText3)
                    }
                }
                .buttonStyle(.dsRow)
                .accessibilityHint("Opens in Safari")
                .padding(.top, DS.Space.s2)
            }
        }
    }

    private var hasAbout: Bool {
        info?.summary?.isEmpty == false || !aboutRows.isEmpty || info?.wikipediaURL != nil
    }

    private var aboutRows: [(String, String)] {
        var rows: [(String, String)] = []
        if let family = species.family, !family.isEmpty {
            rows.append(("Family", family))
        }
        if let status = info?.conservationStatus, !status.isEmpty {
            rows.append(("Status", sentenceCase(status)))
        }
        if let count = info?.observationsCount {
            rows.append(("Sightings", count.formatted()))
        }
        return rows
    }

    private func rangeSection(_ taxonId: Int) -> some View {
        section("Where it is seen") {
            // Static in the page, so a swipe scrolls; a tap opens it full screen.
            Button { showingRangeMap = true } label: {
                SpeciesRangeMapView(taxonId: taxonId)
                    .allowsHitTesting(false)
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.dim)
            .padding(.horizontal, DS.gutter)
            .accessibilityLabel("Map of where \(species.commonName) has been seen")
            .accessibilityHint("Opens the map full screen")
            SectionFootnote("Sightings from iNaturalist. Needs a connection.")
        }
    }

    // MARK: - Layout

    private func sentenceCase(_ text: String) -> String {
        guard let first = text.first else { return text }
        return String(first).uppercased() + String(text.dropFirst())
    }

    private struct Tally {
        let key: String
        let name: String
        let detail: String?
        let count: Int
        var icon: String? = nil
        /// The spot behind a "where you caught it" group.
        var spot: Spot? = nil
    }

    /// A section title and its content, spaced like the sections on a catch page.
    private func section<Content: View>(_ title: String, detail: String? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle(title, detail: detail)
            content()
        }
        .padding(.top, DS.Space.s8)
    }
}

// MARK: - All catches

/// Every catch of one species, newest first, pushed from "See all" on the
/// species page. Rows match the page's catch history.
private struct SpeciesCatchesList: View {
    let species: Species
    @Environment(AppState.self) private var appState
    @AppStorage("units") private var units = "metric"
    @State private var catches: [CatchDetail] = []
    @State private var loaded = false
    @State private var openCatchId: String?
    @State private var titleShown = false

    private var imperial: Bool { units == "imperial" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DetailHeader(over: species.commonName, title: "Your catches",
                             subtitle: catches.count == 1 ? "1 catch" : "\(catches.count) catches")
                    .padding(.top, DS.Space.s2)
                    .padding(.bottom, DS.Space.s4)
                if loaded && catches.isEmpty {
                    InlineEmpty(systemImage: "fish", text: "No catches of this species yet.")
                }
                ForEach(catches) { detail in
                    Button {
                        openCatchId = detail.id
                    } label: {
                        ArtRow(over: LogbookFormat.relativeDay(detail.catchRecord.caughtAt),
                               title: measureText(detail.catchRecord),
                               subtitle: detail.spot?.name,
                               chevron: true) {
                            thumb(detail)
                        }
                    }
                    .buttonStyle(.dsRow)
                }
            }
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
        }
        .detailTint(nil)
        .pfTrackScroll($titleShown, threshold: 60)
        .pfScrollTitle("Your catches", shown: titleShown)
        .navigationDestination(item: $openCatchId) { id in
            if let detail = catches.first(where: { $0.id == id }) {
                CatchDetailView(detail: detail)
            }
        }
        // Reload on every return, so an edit or delete on a catch page shows.
        .onAppear {
            catches = (try? appState.catchRepository.fetchForSpecies(species.id)) ?? []
            loaded = true
        }
    }

    private func measureText(_ record: Catch) -> String {
        let parts = [record.lengthCm.map { Units.length(cm: $0, imperial: imperial) },
                     record.weightKg.map { Units.weight(kg: $0, imperial: imperial) }].compactMap { $0 }
        if parts.isEmpty { return record.released ? "Released" : "Kept" }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private func thumb(_ detail: CatchDetail) -> some View {
        if let path = detail.catchRecord.allPhotoPaths.first {
            PhotoThumbnail(path: path, size: 52, cornerRadius: DS.Radius.thumb) {
                ThumbView(species: species, size: 52)
            }
            .frame(width: 52, height: 52)
        } else {
            ThumbView(species: species, size: 52)
        }
    }
}

// MARK: - Bait row

/// A ranked bait, laid out like the picks in Today's What to throw: rank,
/// picture, name.
private struct BaitRow: View {
    let rank: Int
    let name: String

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(.dsText2)
                .frame(minWidth: 16, alignment: .leading)
            LureArtView(name: name, size: 56)
            Text(name)
                .font(.headline)
                .foregroundStyle(.dsText)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DS.gutter)
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pick \(rank), \(name)")
    }
}

/// Applies the zoom push transition when the page was opened from a
/// thumbnail that registered a matching source.
struct SpeciesZoomDestination: ViewModifier {
    let zoom: SpeciesZoomSource?

    func body(content: Content) -> some View {
        if let zoom {
            content.navigationTransition(.zoom(sourceID: zoom.id, in: zoom.namespace))
        } else {
            content
        }
    }
}
