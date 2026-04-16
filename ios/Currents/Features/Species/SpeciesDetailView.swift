import SwiftUI
import Charts

struct SpeciesDetailView: View {
    @Environment(AppState.self) private var appState
    let species: Species
    @State private var catches: [CatchDetail] = []
    @State private var personalBest: PersonalBest?

    var body: some View {
        ScrollView {
            VStack(spacing: CurrentsTheme.paddingM) {
                // Header
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(habitatColor.opacity(0.15))
                            .frame(width: 80, height: 80)
                        Image(systemName: "fish.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(habitatColor)
                    }

                    Text(species.commonName)
                        .font(.title2.bold())
                    Text(species.scientificName)
                        .font(.subheadline)
                        .italic()
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        if let habitat = species.habitat {
                            Text(habitat.rawValue.capitalized)
                                .glassPill()
                        }
                        if let family = species.family {
                            Text(family)
                                .glassPill()
                        }
                    }
                }

                // Temperature range
                if species.minTempC != nil || species.optimalTempC != nil || species.maxTempC != nil {
                    temperatureCard
                }

                // Your stats for this species
                if !catches.isEmpty {
                    yourStatsCard
                }

                // Best gear for this species
                if !catches.isEmpty {
                    bestGearCard
                }

                // Catch history
                if !catches.isEmpty {
                    catchHistoryCard
                }

                // Bait recommendations
                if !species.parsedBaits.isEmpty {
                    baitCard
                }

                // Tips
                tipsCard
            }
            .padding()
        }
        .navigationTitle(species.commonName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            catches = (try? appState.catchRepository.fetchForSpecies(species.id)) ?? []
            let pbs = (try? appState.catchRepository.personalBests()) ?? []
            personalBest = pbs.first(where: { $0.speciesId == species.id })
        }
    }

    private var habitatColor: Color {
        switch species.habitat {
        case .freshwater: return CurrentsTheme.accent
        case .marine: return CurrentsTheme.accent.opacity(0.7)
        case .brackish: return CurrentsTheme.accent.opacity(0.5)
        case nil: return .gray
        }
    }

    private var temperatureCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Temperature Range")
                .font(.headline)

            HStack(spacing: 0) {
                if let min = species.minTempC {
                    tempBlock(value: min, label: "Min", color: CurrentsTheme.accent.opacity(0.5))
                }
                if let optimal = species.optimalTempC {
                    tempBlock(value: optimal, label: "Optimal", color: CurrentsTheme.accent)
                }
                if let max = species.maxTempC {
                    tempBlock(value: max, label: "Max", color: CurrentsTheme.accent.opacity(0.7))
                }
            }

            // Visual temperature bar
            if let min = species.minTempC, let max = species.maxTempC {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [CurrentsTheme.accent.opacity(0.4), CurrentsTheme.accent, CurrentsTheme.accent.opacity(0.7), CurrentsTheme.accent.opacity(0.3)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 8)

                        if let optimal = species.optimalTempC {
                            let range = max - min
                            let pos = (optimal - min) / range
                            Circle()
                                .fill(.white)
                                .frame(width: 14, height: 14)
                                .shadow(radius: 2)
                                .offset(x: geo.size.width * pos - 7)
                        }
                    }
                }
                .frame(height: 14)

                HStack {
                    Text("\(Int(min))°C")
                        .font(.caption2)
                    Spacer()
                    Text("\(Int(max))°C")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
        }
        .glassCard()
    }

    private func tempBlock(value: Double, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(String(format: "%.0f°C", value))
                .font(.title3.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var yourStatsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Stats")
                .font(.headline)

            HStack(spacing: 12) {
                StatCard(value: "\(catches.count)", label: "Caught", icon: "fish.fill")
                if let pb = personalBest, let kg = pb.heaviestKg {
                    StatCard(value: String(format: "%.2fkg", kg), label: "PB Weight", icon: "trophy.fill")
                }
                if let pb = personalBest, let cm = pb.longestCm {
                    StatCard(value: String(format: "%.0fcm", cm), label: "PB Length", icon: "ruler")
                }
                let released = catches.filter { $0.catchRecord.released }.count
                StatCard(value: "\(released)", label: "Released", icon: "arrow.uturn.backward")
            }

            if let pb = personalBest {
                HStack {
                    Text("First caught:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let first = pb.firstCaught {
                        Text(first, style: .date)
                            .font(.caption.bold())
                    }
                    Spacer()
                    Text("Last caught:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let last = pb.lastCaught {
                        Text(last, style: .date)
                            .font(.caption.bold())
                    }
                }
            }
        }
        .glassCard()
    }

    private var bestGearCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Best Gear")
                .font(.headline)
            Text("What's worked for you with \(species.commonName)")
                .font(.caption)
                .foregroundStyle(.secondary)

            let gearCatches = catches.filter { $0.gearLoadout != nil }
            let gearGroups = Dictionary(grouping: gearCatches, by: { $0.gearLoadout!.name })
            let sorted = gearGroups.sorted { $0.value.count > $1.value.count }

            if sorted.isEmpty {
                Text("Log catches with gear to see recommendations")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(sorted.prefix(5), id: \.key) { gearName, gearCatches in
                    HStack {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .foregroundStyle(CurrentsTheme.accent)
                            .frame(width: 24)
                        VStack(alignment: .leading) {
                            Text(gearName)
                                .font(.subheadline.bold())
                            if let lure = gearCatches.first?.gearLoadout?.lure {
                                Text(lure)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text("\(gearCatches.count)")
                            .font(.title3.bold())
                            .monospacedDigit()
                    }
                    Divider()
                }
            }
        }
        .glassCard()
    }

    private var catchHistoryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Catch History")
                .font(.headline)

            ForEach(catches.prefix(10), id: \.catchRecord.id) { detail in
                CatchRow(detail: detail)
                Divider()
            }

            if catches.count > 10 {
                Text("+ \(catches.count - 10) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .glassCard()
    }

    private var baitCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recommended Baits & Lures")
                .font(.headline)

            ForEach(species.parsedBaits, id: \.self) { bait in
                HStack(spacing: 8) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(CurrentsTheme.accent)
                    Text(bait.capitalized)
                        .font(.subheadline)
                }
            }

            if let notes = species.baitNotes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .glassCard()
    }

    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fishing Tips")
                .font(.headline)

            if let habitat = species.habitat {
                tipRow(icon: "water.waves", text: habitatTip(habitat))
            }
            if let opt = species.optimalTempC {
                tipRow(icon: "thermometer.medium", text: "Target water temperature around \(Int(opt))°C for best results")
            }
            tipRow(icon: "sunrise.fill", text: "Dawn and dusk are typically the best times for most species")
            tipRow(icon: "moon.fill", text: "Full moon and new moon phases increase feeding activity")
        }
        .glassCard()
    }

    private func tipRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(CurrentsTheme.accent)
                .frame(width: 20)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func habitatTip(_ habitat: Species.Habitat) -> String {
        switch habitat {
        case .freshwater: return "Found in lakes, rivers, and streams. Look for structure like fallen trees, rocks, and weed beds."
        case .marine: return "Saltwater species. Fish around reefs, jetties, and current breaks. Tide changes are crucial."
        case .brackish: return "Found where fresh and salt water mix — estuaries, river mouths, and mangroves."
        }
    }
}
