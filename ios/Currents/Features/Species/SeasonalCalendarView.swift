import SwiftUI

struct SeasonalCalendarView: View {
    @Environment(AppState.self) private var appState
    @State private var species: [Species] = []
    @State private var selectedMonth: Int = Calendar.current.component(.month, from: .now)
    @State private var searchText = ""
    @State private var habitatFilter: Species.Habitat?
    @AppStorage("seasonalSortOrder") private var sortOrder: SortOrder = .match

    enum SortOrder: String, CaseIterable, Identifiable {
        case match = "Best Match"
        case name = "Name"
        case temp = "Optimal Temp"
        var id: String { rawValue }
    }

    /// Approximate monthly surface water temperatures in Celsius across a full
    /// temperate year (Northern Hemisphere), from a cold late-winter to a warm
    /// late-summer. Index 1 = January, 12 = December. The range is deliberately
    /// wide (≈4–27°C) so that every species — cold-water, temperate and
    /// warm/tropical alike — has a month where local water reaches its
    /// preferred band, instead of only the mid-range curated few.
    private static let northernTemps: [Int: Double] = [
        1: 5, 2: 4, 3: 6, 4: 10, 5: 15, 6: 20,
        7: 24, 8: 27, 9: 23, 10: 18, 11: 12, 12: 7
    ]

    private static let monthNames: [String] = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        return formatter.shortMonthSymbols
    }()

    /// Whether the device locale is in the Southern Hemisphere (rough heuristic via timezone).
    private var isSouthernHemisphere: Bool {
        let tz = TimeZone.current.identifier.lowercased()
        let southern = ["australia", "auckland", "wellington", "buenos_aires",
                        "santiago", "johannesburg", "harare", "perth",
                        "sydney", "melbourne", "brasilia", "sao_paulo"]
        return southern.contains(where: { tz.contains($0) })
    }

    private func waterTemp(for month: Int) -> Double {
        if isSouthernHemisphere {
            let flipped = ((month - 1 + 6) % 12) + 1
            return Self.northernTemps[flipped] ?? 15
        }
        return Self.northernTemps[month] ?? 15
    }

    // MARK: - Scoring
    //
    // Seasonality is driven by each species' own thermal tolerance band
    // (minTempC…optimalTempC…maxTempC), all of which are seeded for every
    // species — not just a ±5° window around the optimum. This means the
    // calendar produces a meaningful, differentiated season for all species:
    // a wide-tolerance fish stays catchable across more of the year, a
    // stenothermal one peaks sharply, and cold- or warm-water species map to
    // the cold or warm months instead of never appearing in season.

    /// The comfortable band edges for a species, falling back to a moderate
    /// spread around the optimum when explicit min/max aren't known.
    private func tempBand(_ sp: Species) -> (lower: Double, optimal: Double, upper: Double)? {
        guard let optimal = sp.optimalTempC else { return nil }
        let lower = sp.minTempC ?? (optimal - 6)
        let upper = sp.maxTempC ?? (optimal + 6)
        return (min(lower, optimal), optimal, max(upper, optimal))
    }

    private func matchScore(species sp: Species, month: Int) -> Double {
        guard let band = tempBand(sp) else { return 0 }
        let temp = waterTemp(for: month)
        // Distance from the optimum, normalised by how far it is to the nearer
        // band edge, so the score peaks at 100 at the optimum and falls to 0 at
        // the edge of the fish's tolerance (quadratic falloff for a smooth ramp).
        let span = max(band.upper - band.optimal, band.optimal - band.lower, 3)
        let norm = abs(temp - band.optimal) / span
        return max(0, 100 * (1 - norm * norm))
    }

    private func isInSeason(species sp: Species, month: Int) -> Bool {
        guard let band = tempBand(sp) else { return false }
        let temp = waterTemp(for: month)
        return temp >= band.lower && temp <= band.upper
    }

    private var filteredSpecies: [Species] {
        var result = species
        if !searchText.isEmpty {
            result = result.filter {
                $0.commonName.localizedCaseInsensitiveContains(searchText) ||
                $0.scientificName.localizedCaseInsensitiveContains(searchText)
            }
        }
        if let habitat = habitatFilter {
            result = result.filter { $0.habitat == habitat }
        }
        return result
    }

    private func sorted(_ list: [Species]) -> [Species] {
        switch sortOrder {
        case .match:
            return list.sorted { matchScore(species: $0, month: selectedMonth) > matchScore(species: $1, month: selectedMonth) }
        case .name:
            return list.sorted { $0.commonName < $1.commonName }
        case .temp:
            return list.sorted { ($0.optimalTempC ?? 0) < ($1.optimalTempC ?? 0) }
        }
    }

    private var inSeasonSpecies: [Species] {
        sorted(filteredSpecies.filter { isInSeason(species: $0, month: selectedMonth) })
    }

    private var offSeasonSpecies: [Species] {
        sorted(filteredSpecies.filter { !isInSeason(species: $0, month: selectedMonth) })
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: CurrentsTheme.paddingM) {
                monthSelector
                searchAndFilterBar
                tempBanner

                if !inSeasonSpecies.isEmpty {
                    sectionBlock(title: "In Season", species: inSeasonSpecies, dimmed: false)
                }

                if !offSeasonSpecies.isEmpty {
                    sectionBlock(title: "Off Season", species: offSeasonSpecies, dimmed: true)
                }

                if species.isEmpty {
                    ContentUnavailableView(
                        "No Species Data",
                        systemImage: "fish",
                        description: Text("Species will appear here once loaded.")
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Seasonal Calendar")
        .task {
            species = (try? appState.speciesRepository.fetchAll()) ?? []
        }
    }

    // MARK: - Month Selector

    private var monthSelector: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(1...12, id: \.self) { month in
                        FilterChip(
                            title: Self.monthNames[month - 1],
                            isSelected: selectedMonth == month
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedMonth = month
                            }
                        }
                        .id(month)
                    }
                }
                .padding(.horizontal, 4)
            }
            .onAppear {
                proxy.scrollTo(selectedMonth, anchor: .center)
            }
        }
    }

    // MARK: - Search and Filter Bar

    private var searchAndFilterBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search species...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Menu {
                Picker("Sort by", selection: $sortOrder) {
                    ForEach(SortOrder.allCases) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                Divider()
                Button("All Habitats") { habitatFilter = nil }
                Button("Freshwater") { habitatFilter = .freshwater }
                Button("Marine") { habitatFilter = .marine }
                Button("Brackish") { habitatFilter = .brackish }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .font(.title3)
                    .foregroundStyle(CurrentsTheme.accent)
            }
        }
    }

    // MARK: - Temperature Banner

    private var tempBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "water.waves")
                .font(.title3)
                .foregroundStyle(CurrentsTheme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("Estimated Water Temp")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.0f\u{00B0}C", waterTemp(for: selectedMonth)))
                    .font(.title2.bold())
                    .monospacedDigit()
            }

            Spacer()

            if isSouthernHemisphere {
                Text("Southern Hemisphere")
                    .font(.caption2)
                    .glassPill()
            }
        }
        .glassCard()
    }

    // MARK: - Section Block

    private func sectionBlock(title: String, species list: [Species], dimmed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(dimmed ? Color.secondary.opacity(0.4) : CurrentsTheme.accent)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.headline)
                Text("\(list.count)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            ForEach(list) { sp in
                NavigationLink {
                    SpeciesDetailView(species: sp)
                } label: {
                    speciesRow(sp, dimmed: dimmed)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Species Row

    private func speciesRow(_ sp: Species, dimmed: Bool) -> some View {
        HStack(spacing: 12) {
            // Match score circle
            let score = Int(matchScore(species: sp, month: selectedMonth))
            ZStack {
                Circle()
                    .stroke(dimmed ? Color.secondary.opacity(0.2) : CurrentsTheme.accent.opacity(0.3), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(
                        dimmed ? Color.secondary : CurrentsTheme.accent,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text("\(score)")
                    .font(.caption2.bold())
                    .monospacedDigit()
                    .foregroundStyle(dimmed ? Color.secondary : CurrentsTheme.accent)
            }
            .frame(width: 40, height: 40)

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(sp.commonName)
                    .font(.subheadline.bold())
                    .foregroundStyle(dimmed ? .secondary : .primary)

                HStack(spacing: 6) {
                    if let optimal = sp.optimalTempC {
                        Label(String(format: "%.0f\u{00B0}C", optimal), systemImage: "thermometer.medium")
                            .font(.caption2)
                            .foregroundStyle(dimmed ? .tertiary : .secondary)
                    }
                    if let habitat = sp.habitat {
                        Text(habitat.rawValue.capitalized)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                dimmed
                                    ? Color.secondary.opacity(0.1)
                                    : CurrentsTheme.accent.opacity(0.15)
                            )
                            .foregroundStyle(dimmed ? Color.secondary : CurrentsTheme.accent)
                            .clipShape(Capsule())
                    }
                }

                // Baits subtitle
                let baits = sp.parsedBaits.prefix(3)
                if !baits.isEmpty {
                    Text(baits.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(CurrentsTheme.paddingS)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: CurrentsTheme.cornerRadius))
        .opacity(dimmed ? 0.6 : 1.0)
    }
}
