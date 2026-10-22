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
                        .padding(.top, DS.Space.s8)
                }
                if !catches.isEmpty {
                    section("Your stats") { SpeciesFacts(rows: statRows) }
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
        HStack(alignment: .top, spacing: DS.Space.s3) {
            Image(systemName: "book.closed")
                .font(.title3)
                .foregroundStyle(.dsText2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Not found yet")
                    .font(.headline)
                    .foregroundStyle(.dsText)
                Text("Catch one and it joins your Fishdex. Your personal best and history show up here.")
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Space.s4)
        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .padding(.horizontal, DS.gutter)
    }

    private var statRows: [(String, String)] {
        var rows: [(String, String)] = [("Caught", "\(catches.count)")]
        if let heaviest = catches.compactMap({ $0.catchRecord.weightKg }).max() {
            rows.append(("Heaviest", Units.weight(kg: heaviest, imperial: imperial)))
        }
        if let longest = catches.compactMap({ $0.catchRecord.lengthCm }).max() {
            rows.append(("Longest", Units.length(cm: longest, imperial: imperial)))
        }
        let released = catches.filter { $0.catchRecord.released }.count
        rows.append(("Released", "\(released) of \(catches.count)"))
        // `catches` is newest first.
        if let first = catches.last?.catchRecord.caughtAt {
            rows.append(("First caught", first.formatted(date: .abbreviated, time: .omitted)))
        }
        if catches.count > 1, let last = catches.first?.catchRecord.caughtAt {
            rows.append(("Last caught", last.formatted(date: .abbreviated, time: .omitted)))
        }
        return rows
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
                SectionFootnote(seasonFootnote)
            }
        }
    }

    private var seasonFootnote: String {
        let source = "\(SpeciesSeason.hemisphereName), estimated from typical water temperatures."
        if let peak = SpeciesSeason.peakText(seasonScores) { return "\(peak). \(source)" }
        return source
    }

    @ViewBuilder
    private var temperatureSection: some View {
        let water = SpeciesSeason.waterTemp(for: month)
        section("Comfort temperature") {
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
        if let lo = species.minTempC, let hi = species.maxTempC {
            rows.append(("Survives", SpeciesSeason.rangeText(lo, hi, imperial: imperial)))
        }
        if let opt = species.optimalTempC {
            rows.append(("Optimal", Units.temperature(opt, imperial: imperial)))
        }
        if let comfort = SpeciesSeason.comfortText(species, imperial: imperial) {
            rows.append(("Feeds best", comfort))
        }
        var waterText = Units.temperature(water, imperial: imperial)
        if let band = SpeciesSeason.band(species) {
            if abs(water - band.optimal) <= 3 { waterText += ", in range" }
            else if water < band.optimal { waterText += ", on the cold side" }
            else { waterText += ", on the warm side" }
        }
        rows.append(("Typical water this month", waterText))
        return rows
    }

    // MARK: - Baits and gear

    private var baitsSection: some View {
        section("Best lures and baits") {
            VStack(spacing: 0) {
                ForEach(Array(species.parsedBaits.enumerated()), id: \.offset) { index, bait in
                    ArtRow(title: sentenceCase(bait)) {
                        ThumbView(tint: tint, size: 44) {
                            Text("\(index + 1)")
                                .font(.headline)
                                .foregroundStyle(.dsText)
                        }
                    }
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
            Tally(name: key, detail: value.first?.gearLoadout?.lure, count: value.count)
        }
        return Array(tallies.sorted { $0.count > $1.count }.prefix(5))
    }

    private var bestGearSection: some View {
        section("Your best gear") {
            VStack(spacing: 0) {
                ForEach(gearGroups, id: \.name) { group in
                    ArtRow(title: group.name, subtitle: group.detail) {
                        ThumbView(systemImage: "wrench.and.screwdriver.fill", tint: DS.accent, size: 44)
                    } trailing: {
                        Text("\(group.count)")
                    }
                }
                SectionFootnote("What has worked for you with \(species.commonName).")
            }
        }
    }

    /// Your spots where this species was caught, most catches first.
    private var spotGroups: [Tally] {
        let named = catches.compactMap { $0.spot?.name }
        let grouped = Dictionary(grouping: named, by: { $0 })
        let tallies = grouped.map { key, value in Tally(name: key, detail: nil, count: value.count) }
        return Array(tallies.sorted { $0.count > $1.count }.prefix(5))
    }

    private var whereSection: some View {
        section("Where you caught it") {
            VStack(spacing: 0) {
                ForEach(spotGroups, id: \.name) { spot in
                    ArtRow(title: spot.name, subtitle: spot.count == 1 ? "1 catch" : "\(spot.count) catches") {
                        ThumbView(systemImage: "mappin.and.ellipse", tint: DS.accent, size: 44)
                    }
                }
            }
        }
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
                    SectionFootnote("For information only. Confirm the current local rules before you keep a fish.")
                }
            }
        } else {
            section("Size and bag limits") {
                SectionFootnote("No size or bag limits on file for this species. Check the local rules before you keep one.")
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
        section("Tips") {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                if let habitat = species.habitat {
                    tipRow("water.waves", habitatTip(habitat))
                }
                if let opt = species.optimalTempC {
                    tipRow("thermometer.medium",
                           "Look for water around \(Units.temperature(opt, imperial: imperial)) for the best results.")
                }
                tipRow("sunrise", "Dawn and dusk are usually the best times for most species.")
                tipRow("moon", "Full and new moon phases tend to lift feeding activity.")
            }
            .padding(.horizontal, DS.gutter)
        }
    }

    private func tipRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
            Image(systemName: icon)
                .foregroundStyle(.dsText2)
                .frame(width: 22)
            Text(text)
                .font(.body)
                .foregroundStyle(.dsText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func habitatTip(_ habitat: Species.Habitat) -> String {
        switch habitat {
        case .freshwater: "Found in lakes, rivers and streams. Look for structure like fallen trees, rocks and weed beds."
        case .marine: "A saltwater species. Fish around reefs, jetties and current breaks, and plan around the tide."
        case .brackish: "Found where fresh and salt water mix, in estuaries, river mouths and mangroves."
        }
    }

    private func aboutSection(_ info: SpeciesInfoService.Info) -> some View {
        section("About") {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                if let status = info.conservationStatus, !status.isEmpty {
                    SpeciesTag(text: sentenceCase(status),
                               systemImage: "leaf.fill", tint: conservationColor(status))
                        .padding(.horizontal, DS.gutter)
                }
                if let summary = info.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.body)
                        .foregroundStyle(.dsText)
                        .lineLimit(10)
                        .padding(.horizontal, DS.gutter)
                }
                HStack(spacing: DS.Space.s2) {
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

                if let taxonId = info.taxonId {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Distribution")
                            .font(.headline)
                            .foregroundStyle(.dsText)
                            .padding(.horizontal, DS.gutter)
                            .padding(.bottom, DS.Space.s2)
                        SpeciesRangeMapView(taxonId: taxonId)
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                            .padding(.horizontal, DS.gutter)
                            .accessibilityLabel("Map of where \(species.commonName) has been observed")
                        SectionFootnote("Where it has been observed worldwide, from iNaturalist. The map needs a connection.")
                    }
                }
            }
        }
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

    private func x(_ value: Double, _ width: CGFloat) -> CGFloat {
        let t = (value - scaleLow) / (scaleHigh - scaleLow)
        return width * CGFloat(min(max(t, 0), 1))
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.dsFill2)
                    Capsule().fill(tint.opacity(0.35))
                        .frame(width: max(8, x(upper, w) - x(lower, w)))
                        .offset(x: x(lower, w))
                    Capsule().fill(tint)
                        .frame(width: max(8, x(optimal + 3, w) - x(optimal - 3, w)))
                        .offset(x: x(optimal - 3, w))
                    Circle()
                        .fill(Color.dsText)
                        .overlay(Circle().stroke(Color.dsBackground, lineWidth: 2))
                        .frame(width: 16, height: 16)
                        .offset(x: x(water, w) - 8)
                }
                .frame(height: 16)
            }
            .frame(height: 16)
            HStack {
                Text(Units.temperature(scaleLow, imperial: imperial))
                Spacer()
                Text("Dot: typical water this month")
                Spacer()
                Text(Units.temperature(scaleHigh, imperial: imperial))
            }
            .font(.caption)
            .foregroundStyle(.dsText2)
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
