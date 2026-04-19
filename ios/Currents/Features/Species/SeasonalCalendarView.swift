import SwiftUI

struct SeasonalCalendarView: View {
    @Environment(AppState.self) private var appState
    @State private var species: [Species] = []
    @State private var selectedMonth: Int = Calendar.current.component(.month, from: .now)
    @State private var searchText = ""
    @State private var habitatFilter: Species.Habitat?

    /// Approximate monthly water temperatures in Celsius (Northern Hemisphere).
    /// Index 1 = January, 12 = December.
    private static let northernTemps: [Int: Double] = [
        1: 8, 2: 7, 3: 9, 4: 13, 5: 17, 6: 21,
        7: 24, 8: 23, 9: 20, 10: 16, 11: 12, 12: 9
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
            // Flip by 6 months
            let flipped = ((month - 1 + 6) % 12) + 1
            return Self.northernTemps[flipped] ?? 15
        }
        return Self.northernTemps[month] ?? 15
    }

    // MARK: - Scoring

    private func matchScore(species sp: Species, month: Int) -> Double {
        guard let optimal = sp.optimalTempC else { return 0 }
        let temp = waterTemp(for: month)
        let diff = abs(temp - optimal)
        // Score from 100 (exact match) down to 0 at 20 degrees off
        return max(0, 100 - diff * 5)
    }

    private func isInSeason(species sp: Species, month: Int) -> Bool {
        guard let optimal = sp.optimalTempC else { return false }
        let temp = waterTemp(for: month)
        return abs(temp - optimal) <= 5
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

    private var inSeasonSpecies: [Species] {
        filteredSpecies
            .filter { isInSeason(species: $0, month: selectedMonth) }
            .sorted { matchScore(species: $0, month: selectedMonth) > matchScore(species: $1, month: selectedMonth) }
    }

    private var offSeasonSpecies: [Species] {
        filteredSpecies
            .filter { !isInSeason(species: $0, month: selectedMonth) }
            .sorted { matchScore(species: $0, month: selectedMonth) > matchScore(species: $1, month: selectedMonth) }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: CurrentsTheme.paddingM) {
                monthSelector

                // Search + habitat filter
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search species...", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    Menu {
                        Button("All") { habitatFilter = nil }
                        Button("Freshwater") { habitatFilter = .freshwater }
                        Button("Marine") { habitatFilter = .marine }
                        Button("Brackish") { habitatFilter = .brackish }
                    } label: {
                        Image(systemName: habitatFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                            .foregroundStyle(CurrentsTheme.accent)
                    }
                }

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
                    .fill(dimmed ? .secondary.opacity(0.4) : CurrentsTheme.accent)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.headline)
                Text("\(list.count)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            ForEach(list) { sp in
                speciesRow(sp, dimmed: dimmed)
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
                    .stroke(dimmed ? .secondary.opacity(0.2) : CurrentsTheme.accent.opacity(0.3), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(
                        dimmed ? .secondary : CurrentsTheme.accent,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text("\(score)")
                    .font(.caption2.bold())
                    .monospacedDigit()
                    .foregroundStyle(dimmed ? .secondary : CurrentsTheme.accent)
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
                                    ? .secondary.opacity(0.1)
                                    : CurrentsTheme.accent.opacity(0.15)
                            )
                            .foregroundStyle(dimmed ? .secondary : CurrentsTheme.accent)
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

            // Match indicator
            if !dimmed {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(CurrentsTheme.accent)
                    .font(.body)
            }
        }
        .padding(CurrentsTheme.paddingS)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: CurrentsTheme.cornerRadius))
        .opacity(dimmed ? 0.6 : 1.0)
    }
}
