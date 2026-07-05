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

                    // Bait Recommendations (from matched species, or generic by type)
                    if !allSpeciesWithBaits.isEmpty {
                        baitRecommendationsCard
                    } else {
                        genericBaitCard
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
            .navigationDestination(for: Species.self) { sp in
                SpeciesDetailView(species: sp)
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
                                .foregroundStyle(CurrentsTheme.accent)
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
                Group {
                    if let local = fish.localSpecies {
                        NavigationLink(value: local) {
                            observedFishRow(fish)
                        }
                        .buttonStyle(.plain)
                    } else {
                        observedFishRow(fish)
                    }
                }
                if fish.scientificName != observedFish.prefix(20).last?.scientificName {
                    SoftDivider()
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
                        .foregroundStyle(CurrentsTheme.accent)
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
                NavigationLink(value: sp) {
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
                }
                .buttonStyle(.plain)
                if sp.id != species.last?.id {
                    SoftDivider()
                }
            }
        }
        .glassCard()
    }

    // MARK: - Underwater Profile Card

    private var underwaterProfileCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Underwater Profile", systemImage: "water.waves.and.arrow.down")
                .font(.headline)

            // Stylised depth cross-section when we know how deep it goes
            if let maxD = waterbody.maxDepthM, maxD > 0 {
                DepthProfileView(
                    maxDepthM: maxD,
                    avgDepthM: waterbody.averageDepthM
                )
                .frame(height: 110)
            }

            let stats: [(String, String, String)] = {
                var s: [(String, String, String)] = []
                if let maxD = waterbody.maxDepthM {
                    s.append((String(format: "%.0f m", maxD), "Max Depth", "arrow.down.to.line"))
                }
                if let avgD = waterbody.averageDepthM {
                    s.append((String(format: "%.0f m", avgD), "Avg Depth", "water.waves"))
                }
                if let area = waterbody.surfaceAreaKm2 {
                    s.append((formatArea(area), "Surface Area", "square.dashed"))
                }
                if let elev = waterbody.elevation {
                    s.append((String(format: "%.0f m", elev), "Elevation", "mountain.2.fill"))
                }
                return s
            }()

            if stats.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(.secondary)
                    Text("No bathymetry data recorded for this water yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(stats, id: \.1) { value, label, icon in
                        HStack(spacing: 10) {
                            Image(systemName: icon)
                                .font(.subheadline)
                                .foregroundStyle(CurrentsTheme.accent)
                                .frame(width: 28, height: 28)
                                .background(CurrentsTheme.accent.opacity(0.12), in: Circle())
                            VStack(alignment: .leading, spacing: 1) {
                                Text(value)
                                    .font(.subheadline.bold())
                                    .monospacedDigit()
                                Text(label)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(8)
                        .background(.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
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
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(CurrentsTheme.accent.opacity(0.12))
                            .foregroundStyle(CurrentsTheme.accent)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        // Stretch to the full card width even when only the "no bathymetry
        // data" line renders — otherwise the card hugs the text.
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: - Bait Recommendations Card

    private var baitRecommendationsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Recommended Baits", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                Text("ranked by species")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Aggregate baits across all species, ranked by how many species hit them
            let baitMap = aggregateBaits()
            let sortedBaits = baitMap.sorted {
                ($0.value.count, $0.key) > ($1.value.count, $1.key)
            }

            VStack(spacing: 0) {
                ForEach(Array(sortedBaits.prefix(8).enumerated()), id: \.element.key) { index, entry in
                    let (bait, speciesNames) = entry
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption.bold())
                            .monospacedDigit()
                            .foregroundStyle(index < 3 ? .white : .secondary)
                            .frame(width: 24, height: 24)
                            .background(
                                index < 3 ? CurrentsTheme.accent : Color.secondary.opacity(0.15),
                                in: Circle()
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(bait.capitalized)
                                .font(.subheadline.bold())
                            let shown = speciesNames.prefix(3).joined(separator: ", ")
                            let extra = speciesNames.count > 3 ? " +\(speciesNames.count - 3) more" : ""
                            Text("Works for \(shown)\(extra)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text("\(speciesNames.count)")
                            .font(.caption2.bold())
                            .monospacedDigit()
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(CurrentsTheme.accent.opacity(0.12))
                            .foregroundStyle(CurrentsTheme.accent)
                            .clipShape(Capsule())
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .glassCard()
    }

    // MARK: - Observed Fish Row

    private func observedFishRow(_ fish: ObservedSpeciesRepository.FishResult) -> some View {
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
                .background(CurrentsTheme.accent.opacity(0.2))
                .foregroundStyle(CurrentsTheme.accent)
                .clipShape(Capsule())

            if fish.localSpecies != nil {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(CurrentsTheme.accent)
            }
        }
    }

    // MARK: - Helpers

    private func habitatColor(_ sp: Species) -> Color {
        switch sp.habitat {
        case .freshwater: CurrentsTheme.accent
        case .marine: CurrentsTheme.accent.opacity(0.7)
        case .brackish: CurrentsTheme.accent.opacity(0.5)
        case nil: .gray
        }
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

    // MARK: - Generic Bait Card (fallback when no species matched)

    private var genericBaitCard: some View {
        let baits = genericBaitsForType(waterbody.type)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Suggested Baits", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                Text("for \(waterbody.type.rawValue)s")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            FlowLayout(spacing: 8) {
                ForEach(baits, id: \.self) { bait in
                    Text(bait)
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(CurrentsTheme.accent.opacity(0.12))
                        .foregroundStyle(.primary)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(CurrentsTheme.accent.opacity(0.25)))
                }
            }
        }
        .glassCard()
    }

    private func genericBaitsForType(_ type: Waterbody.WaterbodyType) -> [String] {
        switch type {
        case .lake:
            return ["Plastic worms (Texas rig)", "Crankbaits", "Spinnerbaits", "Live worms", "Jigs", "Topwater frogs", "Drop shot rigs", "Swimbaits"]
        case .dam:
            return ["Deep diving crankbaits", "Spoons", "Soft plastics (Carolina rig)", "Live bait (shad)", "Jerkbaits", "Football jigs", "Umbrella rigs", "Cut bait"]
        case .river:
            return ["Spinners (inline)", "Nymphs & flies", "Live minnows", "Rooster tails", "Rapala lures", "Dough bait", "Crawfish imitations", "Drift worms"]
        case .estuary:
            return ["Shrimp (live or artificial)", "Soft plastic jerkbaits", "Topwater poppers", "Spoons (gold)", "Cut mullet", "Bucktail jigs", "Suspending lures", "DOA shrimp"]
        case .coast:
            return ["Poppers", "Stickbaits", "Metal jigs", "Live bait (pilchards)", "Trolling lures", "Squid strips", "Bucktail jigs", "Surface plugs"]
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
                    .fill(
                        LinearGradient(
                            colors: [
                                CurrentsTheme.accent.opacity(0.45),
                                CurrentsTheme.accent.opacity(0.08),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // Lakebed outline
                bedPath(in: size)
                    .stroke(CurrentsTheme.accent.opacity(0.55), lineWidth: 1.5)

                // Surface line
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 1))
                    p.addLine(to: CGPoint(x: size.width, y: 1))
                }
                .stroke(CurrentsTheme.accent.opacity(0.8), lineWidth: 2)

                // Average depth dashed line
                if let avg = avgDepthM, maxDepthM > 0, avg < maxDepthM {
                    let y = size.height * CGFloat(min(0.9, avg / maxDepthM))
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.secondary)

                    Text("avg \(Int(avg)) m")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .offset(x: 6, y: y - 14)
                }

                // Max depth label at the deepest point
                Text("\(Int(maxDepthM)) m")
                    .font(.system(size: 10, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .position(x: size.width * 0.55, y: size.height - 10)

                // Surface label
                Text("0 m")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
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
