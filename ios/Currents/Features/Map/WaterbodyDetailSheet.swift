import SwiftUI
import MapKit

struct WaterbodyDetailSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let waterbody: Waterbody
    @State private var weather: WeatherService.WeatherData?
    @State private var forecast: ForecastEngine.ForecastResult?
    @State private var species: [Species] = []          // From seed data (fishSpeciesIds)
    @State private var observedFish: [ObservedSpeciesRepository.FishResult] = [] // From iNaturalist/GBIF
    @State private var isLoadingSpecies = false
    @State private var showingAddSpot = false

    private var coord: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: waterbody.latitude, longitude: waterbody.longitude)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CurrentsTheme.paddingM) {
                    // Map preview
                    Map(initialPosition: .camera(.init(
                        centerCoordinate: coord,
                        distance: max(waterbody.approximateRadiusM * 3, 3000)
                    ))) {
                        MapCircle(center: coord, radius: waterbody.approximateRadiusM)
                            .foregroundStyle(CurrentsTheme.accent.opacity(0.2))
                            .stroke(CurrentsTheme.accent.opacity(0.6), lineWidth: 2)
                    }
                    .mapStyle(.hybrid)
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .allowsHitTesting(false)

                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(waterbody.name)
                                .font(.title2.bold())
                            Text(String(format: "%.3f, %.3f", waterbody.latitude, waterbody.longitude))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(waterbody.type.rawValue.capitalized)
                            .font(.caption.bold())
                            .glassPill()
                    }

                    // Access status
                    HStack(spacing: 6) {
                        Image(systemName: waterbody.isPublic ? "checkmark.shield.fill" : "lock.fill")
                            .foregroundStyle(waterbody.isPublic ? .green : .red)
                        Text(waterbody.isPublic ? "Public Access" : "Private — Permission Required")
                            .font(.subheadline.bold())
                            .foregroundStyle(waterbody.isPublic ? .green : .red)
                    }

                    // Bite Score
                    biteScoreCard

                    // Fish Species — from iNaturalist/GBIF observations
                    if isLoadingSpecies {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Loading species from iNaturalist & GBIF...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .glassCard()
                    }

                    if !observedFish.isEmpty {
                        observedFishCard
                    }

                    // Seed data species (for curated waterbodies)
                    if !species.isEmpty {
                        fishSpeciesCard
                    }

                    // Underwater Profile
                    underwaterProfileCard

                    // Bait Recommendations (from matched species)
                    if !allSpeciesWithBaits.isEmpty {
                        baitRecommendationsCard
                    }

                    // Description
                    if let desc = waterbody.description, !desc.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("About")
                                .font(.headline)
                            Text(desc)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        .glassCard()
                    }

                    // Actions
                    HStack(spacing: 12) {
                        Button {
                            showingAddSpot = true
                        } label: {
                            Label("Save as Spot", systemImage: "mappin.and.ellipse")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(CurrentsTheme.accent)
                    }
                }
                .padding()
            }
            .navigationTitle(waterbody.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            // Load weather + forecast
            let w = await WeatherService.shared.current(for: coord)
            weather = w
            forecast = ForecastEngine.forecast(
                coordinate: coord,
                currentPressureHpa: w?.pressureHpa,
                pressureChange6h: w?.pressureChange6h,
                waterTempC: w?.waterTempC,
                windSpeedKmh: w?.windSpeedKmh,
                windDirection: w?.windDirectionDeg,
                species: nil,
                isInSpawningZone: false
            )

            // Load seed-data species for this waterbody (curated entries)
            let ids = waterbody.decodedFishSpeciesIds
            species = ids.compactMap { try? appState.speciesRepository.fetch(id: $0) }

            // Fetch real-world species observations from iNaturalist + GBIF
            isLoadingSpecies = true
            observedFish = await appState.observedSpeciesRepository.fishNear(
                latitude: waterbody.latitude,
                longitude: waterbody.longitude,
                speciesRepository: appState.speciesRepository
            )
            isLoadingSpecies = false
        }
        .sheet(isPresented: $showingAddSpot) {
            AddSpotSheet(prefillCoordinate: coord)
                .presentationDetents([.medium])
                .presentationBackground(.ultraThinMaterial)
        }
    }

    // MARK: - Bite Score Card

    private var biteScoreCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Bite Forecast", systemImage: "cloud.sun.fill")
                    .font(.headline)
                Spacer()
                if let f = forecast {
                    ScoreGauge(score: f.score, label: "", size: 44)
                }
            }

            if let weather {
                HStack(spacing: 16) {
                    VStack(spacing: 2) {
                        WeatherIcon(condition: weather.condition)
                        Text("\(Int(weather.temperatureC))°")
                            .font(.subheadline.bold().monospacedDigit())
                        Text("Air")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let wt = weather.waterTempC {
                        VStack(spacing: 2) {
                            Image(systemName: "drop.fill")
                                .foregroundStyle(.cyan)
                            Text("\(Int(wt))°")
                                .font(.subheadline.bold().monospacedDigit())
                            Text("Water")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    VStack(spacing: 2) {
                        Image(systemName: "wind")
                            .foregroundStyle(.secondary)
                        Text("\(Int(weather.windSpeedKmh))")
                            .font(.subheadline.bold().monospacedDigit())
                        Text("km/h")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    VStack(spacing: 2) {
                        Image(systemName: "barometer")
                            .foregroundStyle(.secondary)
                        Text("\(Int(weather.pressureHpa))")
                            .font(.subheadline.bold().monospacedDigit())
                        Text("hPa")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let f = forecast {
                if !f.bestHours.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.caption2)
                            .foregroundStyle(CurrentsTheme.accent)
                        Text("Best hours: \(f.bestHours.map { "\($0):00" }.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(f.reasons.prefix(3), id: \.self) { reason in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(CurrentsTheme.scoreColor(f.score))
                            .frame(width: 5, height: 5)
                        Text(reason)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .glassCard()
    }

    // MARK: - All species with baits (for recommendations card)

    /// All species that have bait data — from seed data + iNaturalist-matched species.
    private var allSpeciesWithBaits: [Species] {
        var result = species
        for fish in observedFish {
            if let local = fish.localSpecies, !result.contains(where: { $0.id == local.id }) {
                result.append(local)
            }
        }
        return result.filter { !$0.parsedBaits.isEmpty }
    }

    // MARK: - Observed Fish Card (iNaturalist + GBIF)

    private var observedFishCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Species Observed Nearby")
                    .font(.headline)
                Spacer()
                Text("via iNaturalist & GBIF")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text("\(observedFish.count) species recorded within 10km")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(Array(observedFish.prefix(20).enumerated()), id: \.offset) { _, fish in
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(fish.localSpecies != nil
                                  ? habitatColor(fish.localSpecies!).opacity(0.15)
                                  : Color.gray.opacity(0.15))
                            .frame(width: 36, height: 36)
                        Image(systemName: "fish.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(fish.localSpecies != nil
                                             ? habitatColor(fish.localSpecies!)
                                             : .gray)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(fish.commonName)
                            .font(.subheadline.bold())
                        HStack(spacing: 6) {
                            Text(fish.scientificName)
                                .font(.caption2)
                                .italic()
                                .foregroundStyle(.secondary)
                            if fish.observationCount > 1 {
                                Text("·")
                                    .foregroundStyle(.tertiary)
                                Text("\(fish.observationCount) obs")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        // Show baits if matched to our species DB
                        if let local = fish.localSpecies, !local.parsedBaits.isEmpty {
                            Text(local.parsedBaits.prefix(3).joined(separator: " · "))
                                .font(.caption2)
                                .foregroundStyle(CurrentsTheme.accent)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    // Source badge
                    Text(fish.source == "iNaturalist" ? "iNat" : "GBIF")
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(fish.source == "iNaturalist" ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
                        .foregroundStyle(fish.source == "iNaturalist" ? .green : .blue)
                        .clipShape(Capsule())

                    if fish.localSpecies != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
                if fish.scientificName != observedFish.prefix(20).last?.scientificName {
                    Divider()
                }
            }

            if observedFish.count > 20 {
                Text("+ \(observedFish.count - 20) more species")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Legend
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    Text("Matched — has bait data")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Circle()
                        .fill(.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                    Text("Unmatched — observation only")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
        }
        .glassCard()
    }

    // MARK: - Fish Species Card (from seed data)

    private var fishSpeciesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What's in the Water")
                .font(.headline)
            Text("\(species.count) species known")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(species) { sp in
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(habitatColor(sp).opacity(0.15))
                            .frame(width: 36, height: 36)
                        Image(systemName: "fish.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(habitatColor(sp))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(sp.commonName)
                            .font(.subheadline.bold())
                        HStack(spacing: 8) {
                            if let habitat = sp.habitat {
                                Text(habitat.rawValue.capitalized)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if let opt = sp.optimalTempC {
                                Text("Best at \(Int(opt))°C")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        // Show baits if available
                        if let baits = sp.recommendedBaits,
                           let data = baits.data(using: .utf8),
                           let parsed = try? JSONDecoder().decode([String].self, from: data),
                           !parsed.isEmpty {
                            Text(parsed.prefix(3).joined(separator: " · "))
                                .font(.caption2)
                                .foregroundStyle(CurrentsTheme.accent)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    if let min = sp.minTempC, let max = sp.maxTempC {
                        Text("\(Int(min))-\(Int(max))°")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if sp.id != species.last?.id {
                    Divider()
                }
            }
        }
        .glassCard()
    }

    // MARK: - Underwater Profile Card

    private var underwaterProfileCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Underwater Profile")
                .font(.headline)

            HStack(spacing: 12) {
                if let maxD = waterbody.maxDepthM {
                    depthStat(value: String(format: "%.0fm", maxD), label: "Max Depth", icon: "arrow.down.to.line")
                }
                if let avgD = waterbody.averageDepthM {
                    depthStat(value: String(format: "%.0fm", avgD), label: "Avg Depth", icon: "minus")
                }
                if let area = waterbody.surfaceAreaKm2 {
                    depthStat(value: formatArea(area), label: "Area", icon: "square.dashed")
                }
                if let elev = waterbody.elevation {
                    depthStat(value: String(format: "%.0fm", elev), label: "Elevation", icon: "mountain.2.fill")
                }
            }

            // Structure types
            let structures = waterbody.decodedStructureTypes
            if !structures.isEmpty {
                Text("Bottom Structure")
                    .font(.subheadline.bold())
                    .padding(.top, 4)
                FlowLayout(spacing: 6) {
                    ForEach(structures, id: \.self) { structure in
                        Text(structure.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.caption)
                            .glassPill()
                    }
                }
            }
        }
        .glassCard()
    }

    // MARK: - Bait Recommendations Card

    private var baitRecommendationsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recommended Baits")
                .font(.headline)
            Text("Top baits for species in this water")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Aggregate baits across all species
            let baitMap = aggregateBaits()
            let sortedBaits = baitMap.sorted { $0.value.count > $1.value.count }

            ForEach(sortedBaits.prefix(10), id: \.key) { bait, speciesNames in
                HStack(spacing: 8) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(CurrentsTheme.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(bait.capitalized)
                            .font(.subheadline.bold())
                        Text("For: \(speciesNames.joined(separator: ", "))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .glassCard()
    }

    // MARK: - Helpers

    private func habitatColor(_ sp: Species) -> Color {
        switch sp.habitat {
        case .freshwater: .green
        case .marine: .blue
        case .brackish: .teal
        case nil: .gray
        }
    }

    private func depthStat(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .foregroundStyle(CurrentsTheme.accent)
                .font(.caption)
            Text(value)
                .font(.subheadline.bold())
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatArea(_ km2: Double) -> String {
        if km2 >= 1000 {
            return String(format: "%.0fkm²", km2)
        } else if km2 >= 1 {
            return String(format: "%.1fkm²", km2)
        } else {
            return String(format: "%.0fha", km2 * 100)
        }
    }

    private func aggregateBaits() -> [String: [String]] {
        var result: [String: [String]] = [:]
        for sp in allSpeciesWithBaits {
            guard let baitsJSON = sp.recommendedBaits,
                  let data = baitsJSON.data(using: .utf8),
                  let baits = try? JSONDecoder().decode([String].self, from: data) else { continue }
            for bait in baits {
                let key = bait.lowercased()
                if result[key] == nil {
                    result[key] = []
                }
                if !(result[key]?.contains(sp.commonName) ?? false) {
                    result[key]?.append(sp.commonName)
                }
            }
        }
        return result
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
