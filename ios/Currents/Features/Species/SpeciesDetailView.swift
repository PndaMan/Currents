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
    @State private var openSpotId: String?
    @State private var aboutExpanded = false
    @State private var titleShown = false
    @AppStorage("units") private var units = "metric"
    /// Shared with Today's target species (0 means any species).
    @AppStorage("targetSpeciesId") private var targetSpeciesId: Int = 0

    private var imperial: Bool { units == "imperial" }
    private var tint: Color { species.artTint }
    private var isTargeted: Bool { targetSpeciesId == Int(species.id) }
    private var month: Int { SpeciesSeason.currentMonth }
    private var seasonScores: [Int] { SpeciesSeason.scores(species) }
    private var inSeasonNow: Bool { SpeciesSeason.isInSeason(species, month: month) }

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

                seasonSection
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
        .sensoryFeedback(.selection, trigger: targetSpeciesId)
        .navigationDestination(item: $openCatchId) { id in
            if let detail = catches.first(where: { $0.id == id }) {
                CatchDetailView(detail: detail)
            }
        }
        .navigationDestination(item: $openSpotId) { id in
            if let spot = catches.lazy.compactMap(\.spot).first(where: { $0.id == id }) {
                SpotDetailView(spot: spot)
            }
        }
        .navigationDestination(isPresented: $showingRules) {
            RegulationsView()
        }
        .navigationDestination(isPresented: $showingTarget) {
            TargetScreen()
        }
        .fullScreenCover(isPresented: $showingLogCatch, onDismiss: {
            Task { await load() }
        }) {
            LogCatchView(presetSpecies: species)
        }
        .task { await load() }
    }

    private func load() async {
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
                SpeciesTag(text: "Found \(LogbookFormat.shortDay(first))",
                           systemImage: "checkmark.circle.fill", tint: .dsScoreGood)
            } else if loaded {
                SpeciesTag(text: "Not found yet")
            }
            SpeciesTag(text: inSeasonNow ? "In season now" : "Out of season now")
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
                                        style: .info, haptic: false, icon: "scope")
            } label: {
                Label(isTargeted ? "Targeting" : "Target", systemImage: "scope")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(ActionTileStyle(.primary))
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
            ArtRow(over: "Targeting", title: "Today for this fish",
                   subtitle: "Score, best times and where to go", chevron: true) {
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

    private var statsSection: some View {
        section("Your stats") {
            LogbookKeyValueList(rows: statRows)
        }
    }

    private var statRows: [(String, String)] {
        let records = catches.map(\.catchRecord)
        var rows: [(String, String)] = [("Caught", "\(records.count)")]
        if let heaviest = records.compactMap(\.weightKg).max() {
            rows.append(("Heaviest", Units.weight(kg: heaviest, imperial: imperial)))
        }
        if let longest = records.compactMap(\.lengthCm).max() {
            rows.append(("Longest", Units.length(cm: longest, imperial: imperial)))
        }
        rows.append(("Released", "\(records.filter(\.released).count) of \(records.count)"))
        // Newest first, so the last is the first one caught.
        if let first = records.last?.caughtAt {
            rows.append(("First caught", fullDate(first)))
        }
        if records.count > 1, let last = records.first?.caughtAt {
            rows.append(("Last caught", fullDate(last)))
        }
        return rows
    }

    private func fullDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year())
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
                SectionFoot("\(catches.count - 5) more in your Logbook.")
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
                        inSeason: (1...12).map { SpeciesSeason.isInSeason(species, month: $0) },
                        tint: tint)
            SectionFoot(SpeciesSeason.peakText(seasonScores).map { "\($0), estimated from typical water temperatures." }
                        ?? "Estimated from typical water temperatures.")
        }
    }

    /// Two condition tiles, as on Today: this month's typical water against
    /// the species' range, and where it feeds best.
    @ViewBuilder
    private var temperatureSection: some View {
        if let band = SpeciesSeason.band(species) {
            let water = SpeciesSeason.waterTemp(for: month)
            section("Water temperature") {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                    ConditionTile("Water in \(SpeciesSeason.fullMonths[month - 1])",
                                  systemImage: "thermometer.medium", iconTint: .dsScoreLow,
                                  value: degrees(water), footnote: waterFootnote(water, band: band)) {
                        SpeciesTempBar(low: band.lower, high: band.upper, value: water)
                    }
                    ConditionTile("Feeds best", systemImage: "fish.fill", iconTint: tint,
                                  value: "\(degreesValue(band.optimal - 3)) to \(degreesValue(band.optimal + 3))",
                                  unit: imperial ? "°F" : "°C",
                                  footnote: survivesText.map { "Survives \($0)" })
                }
                .padding(.horizontal, DS.gutter)
                SectionFoot("Typical surface water for the month, not a reading.")
            }
        } else if let survives = survivesText {
            section("Water temperature") {
                LogbookKeyValueList(rows: [("Survives", survives)])
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

    private func degrees(_ celsius: Double) -> String {
        "\(degreesValue(celsius))°"
    }

    private func waterFootnote(_ water: Double, band: (lower: Double, optimal: Double, upper: Double)) -> String {
        let scale = imperial ? 9.0 / 5.0 : 1.0
        if water < band.lower { return "\(Int(((band.lower - water) * scale).rounded()))° below their range" }
        if water > band.upper { return "\(Int(((water - band.upper) * scale).rounded()))° above their range" }
        if abs(water - band.optimal) <= 3 { return "Where they feed best" }
        return water < band.optimal ? "In range, on the cool side" : "In range, on the warm side"
    }

    // MARK: - Baits and gear

    private var baitsSection: some View {
        section("Best lures and baits") {
            ForEach(Array(species.parsedBaits.enumerated()), id: \.offset) { index, bait in
                BaitRow(rank: index + 1, name: sentenceCase(bait))
            }
            if let notes = species.baitNotes, !notes.isEmpty {
                SectionFoot(notes)
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
                  icon: value.first?.type.icon)
        }
        return Array(tallies.sorted { $0.count > $1.count }.prefix(5))
    }

    private var whereSection: some View {
        section("Where you caught it") {
            ForEach(spotGroups, id: \.key) { spot in
                Button {
                    openSpotId = spot.key
                } label: {
                    ArtRow(title: spot.name, subtitle: tallySubtitle(spot), chevron: true) {
                        ThumbView(systemImage: spot.icon ?? "mappin.and.ellipse", tint: DS.accent, size: 52)
                    }
                }
                .buttonStyle(.dsRow)
            }
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
                LogbookKeyValueList(rows: limitRows(reg))
                if let notes = reg.notes, !notes.isEmpty {
                    SectionFoot(notes)
                }
            } else {
                Text("None on file for this species. Check the local rules before you keep one.")
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DS.gutter)
            }
            Button {
                showingRules = true
            } label: {
                ArtRow(title: "All size and bag limits", subtitle: "Every species, works offline", chevron: true) {
                    ThumbView(systemImage: "list.bullet.clipboard", tint: .purple, size: 52)
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
        if let tip = tipText {
            section("Tips") {
                Text(tip)
                    .font(.body)
                    .foregroundStyle(.dsText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DS.gutter)
            }
        }
    }

    /// Where to look, from its habitat and the water it likes.
    private var tipText: String? {
        var parts: [String] = []
        switch species.habitat {
        case .freshwater: parts.append("Fish structure: fallen trees, rocks and weed beds.")
        case .marine: parts.append("Work reefs, jetties and current lines around the tide.")
        case .brackish: parts.append("Try estuaries, river mouths and mangroves.")
        case nil: break
        }
        if let opt = species.optimalTempC {
            parts.append("Look for water near \(Units.temperature(opt, imperial: imperial)).")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
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
                LogbookKeyValueList(rows: aboutRows)
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
            SpeciesRangeMapView(taxonId: taxonId)
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                .padding(.horizontal, DS.gutter)
                .accessibilityLabel("Map of where \(species.commonName) has been seen")
            SectionFoot("Sightings from iNaturalist. Needs a connection.")
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
