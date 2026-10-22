import SwiftUI

/// A species page: art hero on the species colour, title block, Target / Log
/// catch / Share, then your stats and catches, season, temperature, baits,
/// limits, tips and the field guide entry. Pushed from the species guide, the
/// Fishdex, water pages and regulations.
struct SpeciesDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL
    let species: Species
    /// Set when pushed from a thumbnail that registered a zoom source.
    var zoom: SpeciesZoomSource? = nil

    @State private var catches: [CatchDetail] = []
    @State private var info: SpeciesInfoService.Info?
    @State private var loaded = false
    @State private var showingLogCatch = false
    @State private var openCatchId: String?
    @State private var openSpotId: String?
    @State private var aboutExpanded = false
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
                hero
                header
                    .padding(.top, DS.Space.s5)
                actions
                    .padding(.top, DS.Space.s5)

                if loaded && catches.isEmpty {
                    notFoundYet
                        .padding(.top, DS.Space.s6)
                }
                if !catches.isEmpty {
                    section("Your stats") { statTiles }
                    catchHistory
                }
                seasonSection
                if species.minTempC != nil || species.optimalTempC != nil || species.maxTempC != nil {
                    temperatureSection
                }
                if !species.parsedBaits.isEmpty {
                    baitsSection
                }
                if !gearGroups.isEmpty {
                    bestGearSection
                }
                if !spotGroups.isEmpty {
                    whereSection
                }
                limitsSection
                tipsSection
                if let info {
                    aboutSection(info)
                }
            }
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
        }
        .detailTint(tint)
        .speciesScrollTitle(species.commonName, threshold: 300)
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

    private var hero: some View {
        ZStack {
            Color.dsFill
            tint.opacity(DS.thumbTintOpacity(scheme))
            SpeciesArtworkView(species: species, caught: true, size: 150, fillWidth: true)
                .padding(.horizontal, DS.Space.s8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .padding(.horizontal, DS.gutter)
        .padding(.top, DS.Space.s2)
        .accessibilityLabel(species.commonName)
        .accessibilityAddTraits(.isImage)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DetailHeader(over: overLine, title: species.commonName, subtitle: species.scientificName)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if let first = catches.last?.catchRecord.caughtAt {
                        SpeciesTag(text: "Found \(first.formatted(.dateTime.day().month(.abbreviated).year()))",
                                   systemImage: "checkmark.circle.fill", tint: Color.dsScoreGood)
                    } else if loaded {
                        SpeciesTag(text: "Not found yet")
                    }
                    SpeciesTag(text: inSeasonNow ? "In season now" : "Out of season now")
                    SpeciesTag(text: species.rarity.label, systemImage: species.rarity.symbol,
                               tint: species.rarity.color)
                    if let family = species.family, !family.isEmpty {
                        SpeciesTag(text: family)
                    }
                }
                .padding(.horizontal, DS.gutter)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
    }

    private var overLine: String {
        if let habitat = SpeciesSeason.habitatName(species.habitat) {
            return "Fishdex \(species.fishdexNumber), \(habitat.lowercased())"
        }
        return "Fishdex \(species.fishdexNumber)"
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

    private var shareText: String {
        var text = "\(species.commonName) (\(species.scientificName))"
        if let wiki = info?.wikipediaURL { text += "\n\(wiki)" }
        return text
    }

    // MARK: - Your catches

    private var notFoundYet: some View {
        HStack(spacing: DS.Space.s3) {
            ThumbView(systemImage: "book.closed.fill", tint: Color.dsScoreGood, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Not in your Fishdex yet")
                    .font(.headline)
                    .foregroundStyle(.dsText)
                Text("Log one to add it.")
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Space.s3)
        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .padding(.horizontal, DS.gutter)
        .accessibilityElement(children: .combine)
    }

    /// Caught, heaviest, longest and released, as the tiles on spot pages.
    private var statTiles: some View {
        let heaviest = catches.compactMap { $0.catchRecord.weightKg }.max()
        let longest = catches.compactMap { $0.catchRecord.lengthCm }.max()
        let released = catches.filter { $0.catchRecord.released }.count
        // `catches` is newest first.
        let first = catches.last?.catchRecord.caughtAt
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                StatTile("Caught", systemImage: "fish", value: "\(catches.count)",
                         footnote: first.map { "Since \($0.formatted(.dateTime.day().month(.abbreviated).year()))" })
                if let heaviest {
                    let parts = Units.weightParts(kg: heaviest, imperial: imperial)
                    StatTile("Heaviest", systemImage: "scalemass", tint: .dsScoreFair,
                             value: parts.0, unit: parts.1)
                }
                if let longest {
                    let parts = Units.lengthParts(cm: longest, imperial: imperial)
                    StatTile("Longest", systemImage: "ruler", tint: .dsScoreFair,
                             value: parts.0, unit: parts.1)
                }
                StatTile("Released", systemImage: "arrow.uturn.backward", tint: .dsScoreGood,
                         value: "\(released)", unit: "of \(catches.count)")
            }
            .padding(.horizontal, DS.gutter)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private var catchHistory: some View {
        section("Catch history", detail: "\(catches.count)") {
            VStack(spacing: 0) {
                ForEach(catches.prefix(5)) { detail in
                    Button {
                        openCatchId = detail.id
                    } label: {
                        ArtRow(over: detail.catchRecord.caughtAt.formatted(date: .abbreviated, time: .omitted),
                               title: measureText(detail.catchRecord),
                               subtitle: detail.spot?.name,
                               subtitleIcon: detail.spot == nil ? nil : "mappin",
                               chevron: true) {
                            catchThumb(detail)
                        }
                    }
                    .buttonStyle(.dsRow)
                }
                if catches.count > 5 {
                    SectionFootnote("\(catches.count - 5) more in your Logbook.")
                }
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
            PhotoThumbnail(path: path, size: 64, cornerRadius: DS.Radius.thumb) {
                ThumbView(species: species)
            }
            .frame(width: 64, height: 64)
        } else {
            ThumbView(species: species)
        }
    }

    // MARK: - Season and temperature

    private var seasonSection: some View {
        section("Season") {
            VStack(alignment: .leading, spacing: 0) {
                SeasonChart(scores: seasonScores,
                            inSeason: (1...12).map { SpeciesSeason.isInSeason(species, month: $0) },
                            tint: tint)
                SectionFootnote(SpeciesSeason.peakText(seasonScores).map { "\($0), estimated from water temperatures." }
                                ?? "Estimated from water temperatures.")
            }
        }
    }

    @ViewBuilder
    private var temperatureSection: some View {
        let water = SpeciesSeason.waterTemp(for: month)
        section("Water temperature") {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                if let band = SpeciesSeason.band(species) {
                    TemperatureRangeBar(lower: band.lower, optimal: band.optimal, upper: band.upper,
                                        water: water, tint: tint, imperial: imperial)
                        .padding(.horizontal, DS.gutter)
                }
                SpeciesFacts(rows: temperatureRows(water: water))
            }
        }
    }

    private func temperatureRows(water: Double) -> [(String, String)] {
        var rows: [(String, String)] = []
        if let comfort = SpeciesSeason.comfortText(species, imperial: imperial) {
            rows.append(("Feeds best", comfort))
        }
        if let lo = species.minTempC, let hi = species.maxTempC {
            rows.append(("Survives", SpeciesSeason.rangeText(lo, hi, imperial: imperial)))
        }
        var waterText = Units.temperature(water, imperial: imperial)
        if let band = SpeciesSeason.band(species) {
            if abs(water - band.optimal) <= 3 { waterText += ", ideal" }
            else if water < band.optimal { waterText += ", cool" }
            else { waterText += ", warm" }
        }
        rows.append(("Water in \(SpeciesSeason.fullMonths[month - 1])", waterText))
        return rows
    }

    // MARK: - Baits and gear

    private var baitsSection: some View {
        section("Best lures and baits") {
            VStack(spacing: 0) {
                ForEach(Array(species.parsedBaits.enumerated()), id: \.offset) { index, bait in
                    BaitRow(rank: index + 1, name: sentenceCase(bait))
                }
                if let notes = species.baitNotes, !notes.isEmpty {
                    SectionFootnote(notes)
                }
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

    private var bestGearSection: some View {
        section("Your best gear") {
            VStack(spacing: 0) {
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
    }

    /// Your spots where this species was caught, most catches first.
    private var spotGroups: [Tally] {
        let spots = catches.compactMap(\.spot)
        let grouped = Dictionary(grouping: spots, by: \.id)
        let tallies = grouped.map { id, value in
            Tally(key: id, name: value.first?.name ?? "Spot", detail: nil, count: value.count)
        }
        return Array(tallies.sorted { $0.count > $1.count }.prefix(5))
    }

    private var whereSection: some View {
        section("Where you caught it") {
            VStack(spacing: 0) {
                ForEach(spotGroups, id: \.key) { spot in
                    Button {
                        openSpotId = spot.key
                    } label: {
                        ArtRow(title: spot.name, subtitle: tallySubtitle(spot), chevron: true) {
                            ThumbView(systemImage: "mappin.and.ellipse", tint: DS.accent, size: 56)
                        }
                    }
                    .buttonStyle(.dsRow)
                }
            }
        }
    }

    private func tallySubtitle(_ tally: Tally) -> String {
        let count = tally.count == 1 ? "1 catch" : "\(tally.count) catches"
        guard let detail = tally.detail, !detail.isEmpty else { return count }
        return "\(detail), \(count.lowercased())"
    }

    // MARK: - Limits, tips, about

    @ViewBuilder
    private var limitsSection: some View {
        if let reg = RegulationsService.shared.regulation(for: species) {
            section("Size and bag limits", detail: reg.region) {
                VStack(alignment: .leading, spacing: 0) {
                    SpeciesFacts(rows: limitRows(reg))
                    if let closed = reg.closedSeason, !closed.isEmpty {
                        Label(closed, systemImage: "calendar.badge.exclamationmark")
                            .font(.subheadline)
                            .foregroundStyle(.dsScoreLow)
                            .padding(.horizontal, DS.gutter)
                            .padding(.top, DS.Space.s3)
                    }
                    if let notes = reg.notes, !notes.isEmpty {
                        SectionFootnote(notes)
                    }
                    SectionFootnote("Check the current local rules before you keep a fish.")
                }
            }
        } else {
            section("Size and bag limits") {
                SectionFootnote("None on file. Check the local rules before you keep one.")
                    .padding(.top, -DS.Space.s2)
            }
        }
    }

    private func limitRows(_ reg: FishingRegulation) -> [(String, String)] {
        var rows: [(String, String)] = []
        rows.append(("Minimum size", reg.minSizeCm.map { Units.length(cm: $0, imperial: imperial) } ?? "None"))
        if let max = reg.maxSizeCm {
            rows.append(("Maximum size", Units.length(cm: max, imperial: imperial)))
        }
        rows.append(("Bag limit", reg.bagLimit.map { "\($0) a day" } ?? "None"))
        rows.append(("Closed season", (reg.closedSeason?.isEmpty == false) ? "Yes" : "None"))
        return rows
    }

    private var tipsSection: some View {
        section("How to find it") {
            VStack(spacing: 0) {
                if let habitat = species.habitat {
                    tipRow(habitatIcon(habitat), habitatTip(habitat))
                }
                if let opt = species.optimalTempC {
                    tipRow("thermometer.medium",
                           "Look for water near \(Units.temperature(opt, imperial: imperial)).")
                }
                tipRow("sunrise.fill", "Dawn, dusk and new or full moons are usually best.")
            }
        }
    }

    private func tipRow(_ icon: String, _ text: String) -> some View {
        ArtRow(title: text) {
            ThumbView(systemImage: icon, tint: tint, size: 44)
        }
    }

    private func habitatIcon(_ habitat: Species.Habitat) -> String {
        switch habitat {
        case .freshwater: "tree.fill"
        case .marine: "water.waves"
        case .brackish: "leaf.fill"
        }
    }

    private func habitatTip(_ habitat: Species.Habitat) -> String {
        switch habitat {
        case .freshwater: "Fish structure: fallen trees, rocks and weed beds."
        case .marine: "Work reefs, jetties and current lines around the tide."
        case .brackish: "Try estuaries, river mouths and mangroves."
        }
    }

    private func aboutSection(_ info: SpeciesInfoService.Info) -> some View {
        section("About") {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                aboutTags(info)

                if let summary = info.summary, !summary.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        Text(summary)
                            .font(.body)
                            .foregroundStyle(.dsText)
                            .lineLimit(aboutExpanded ? nil : 5)
                        Button(aboutExpanded ? "Less" : "More") {
                            withAnimation(DS.Motion.easeOut) { aboutExpanded.toggle() }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.accent)
                        .buttonStyle(.dim)
                    }
                    .padding(.horizontal, DS.gutter)
                }

                if let taxonId = info.taxonId {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Where it is seen")
                            .font(.headline)
                            .foregroundStyle(.dsText)
                            .padding(.horizontal, DS.gutter)
                            .padding(.bottom, DS.Space.s2)
                        SpeciesRangeMapView(taxonId: taxonId)
                            .frame(maxWidth: .infinity)
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                            .padding(.horizontal, DS.gutter)
                            .accessibilityLabel("Map of where \(species.commonName) has been seen")
                        SectionFootnote("Sightings from iNaturalist. Needs a connection.")
                    }
                }
            }
        }
    }

    /// Conservation status, sightings and the Wikipedia link, scrolling
    /// sideways if they do not fit.
    private func aboutTags(_ info: SpeciesInfoService.Info) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.s2) {
                if let status = info.conservationStatus, !status.isEmpty {
                    SpeciesTag(text: sentenceCase(status),
                               systemImage: "leaf.fill", tint: conservationColor(status))
                }
                if let count = info.observationsCount {
                    SpeciesTag(text: "\(count.formatted()) sightings", systemImage: "eye")
                }
                if let wiki = info.wikipediaURL, let url = URL(string: wiki) {
                    OutlineChip("Wikipedia", systemImage: "arrow.up.right.square") {
                        openURL(url)
                    }
                }
            }
            .padding(.horizontal, DS.gutter)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private func conservationColor(_ status: String) -> Color {
        let s = status.lowercased()
        if s.contains("least") { return .dsScoreGood }
        if s.contains("near") || s.contains("vulnerable") { return .dsScoreLow }
        if s.contains("endangered") || s.contains("critical") { return .dsScoreSlow }
        return .dsText2
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
    }

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

/// A ranked bait: rank, picture, name. Matches the picks on Today.
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
            VStack(alignment: .leading, spacing: 2) {
                if rank == 1 {
                    Text("Top pick")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DS.accent)
                }
                Text(name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.dsText)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.gutter)
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rank == 1 ? "Top pick, \(name)" : "Pick \(rank), \(name)")
    }
}

// MARK: - Temperature bar

/// The comfort range on a 0 to 36 °C scale (widened to fit the species): the
/// survival band faint, the feeding band solid, a dot for this month's water.
private struct TemperatureRangeBar: View {
    let lower: Double
    let optimal: Double
    let upper: Double
    let water: Double
    let tint: Color
    let imperial: Bool

    private var scaleLow: Double { min(0, lower - 2) }
    private var scaleHigh: Double { max(36, upper + 2) }

    /// 0 to 1 along the scale.
    private func t(_ value: Double) -> CGFloat {
        CGFloat(min(max((value - scaleLow) / (scaleHigh - scaleLow), 0), 1))
    }

    var body: some View {
        VStack(spacing: 6) {
            // Drawn rather than laid out, so nothing on the bar can widen the page.
            Canvas { context, size in
                let w = size.width, h = size.height
                let track = CGRect(x: 0, y: h / 2 - 4, width: w, height: 8)
                context.fill(Capsule().path(in: track), with: .color(Color.dsFill2))
                let survive = CGRect(x: w * t(lower), y: track.minY,
                                     width: max(8, w * (t(upper) - t(lower))), height: 8)
                context.fill(Capsule().path(in: survive), with: .color(tint.opacity(0.35)))
                let feed = CGRect(x: w * t(optimal - 3), y: track.minY,
                                  width: max(8, w * (t(optimal + 3) - t(optimal - 3))), height: 8)
                context.fill(Capsule().path(in: feed), with: .color(tint))
                let dotX = min(max(w * t(water), 8), w - 8)
                let dot = CGRect(x: dotX - 8, y: h / 2 - 8, width: 16, height: 16)
                context.fill(Circle().path(in: dot), with: .color(Color.dsBackground))
                context.fill(Circle().path(in: dot.insetBy(dx: 2, dy: 2)), with: .color(Color.dsText))
            }
            .frame(height: 16)
            HStack(spacing: DS.Space.s2) {
                Text(Units.temperature(scaleLow, imperial: imperial))
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.dsText)
                        .frame(width: 8, height: 8)
                    Text("This month")
                }
                Spacer(minLength: 0)
                Text(Units.temperature(scaleHigh, imperial: imperial))
            }
            .font(.caption)
            .foregroundStyle(.dsText2)
            .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Comfortable from \(Units.temperature(lower, imperial: imperial)) to \(Units.temperature(upper, imperial: imperial)). Typical water this month is \(Units.temperature(water, imperial: imperial)).")
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
