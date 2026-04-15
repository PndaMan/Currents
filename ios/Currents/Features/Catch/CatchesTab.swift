import SwiftUI

struct CatchesTab: View {
    @Environment(AppState.self) private var appState
    @State private var catches: [CatchDetail] = []
    @State private var showingLogCatch = false
    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .recent

    enum SortOrder: String, CaseIterable {
        case recent = "Recent"
        case oldest = "Oldest"
        case species = "Species"
        case size = "Biggest"
        case longest = "Longest"
        case spot = "Spot"
        case score = "Best Score"
    }

    var filteredCatches: [CatchDetail] {
        var result = catches
        if !searchText.isEmpty {
            result = result.filter { detail in
                detail.species?.commonName.localizedCaseInsensitiveContains(searchText) == true ||
                detail.spot?.name.localizedCaseInsensitiveContains(searchText) == true ||
                detail.catchRecord.notes?.localizedCaseInsensitiveContains(searchText) == true ||
                detail.gearLoadout?.name.localizedCaseInsensitiveContains(searchText) == true
            }
        }
        switch sortOrder {
        case .recent:
            break // already sorted by date desc
        case .oldest:
            result.reverse()
        case .species:
            result.sort { ($0.species?.commonName ?? "") < ($1.species?.commonName ?? "") }
        case .size:
            result.sort { ($0.catchRecord.weightKg ?? 0) > ($1.catchRecord.weightKg ?? 0) }
        case .longest:
            result.sort { ($0.catchRecord.lengthCm ?? 0) > ($1.catchRecord.lengthCm ?? 0) }
        case .spot:
            result.sort { ($0.spot?.name ?? "zzz") < ($1.spot?.name ?? "zzz") }
        case .score:
            result.sort { ($0.catchRecord.forecastScoreAtCapture ?? 0) > ($1.catchRecord.forecastScoreAtCapture ?? 0) }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            Group {
                if catches.isEmpty {
                    ContentUnavailableView(
                        "No Catches Yet",
                        systemImage: "fish.fill",
                        description: Text("Tap + to log your first catch")
                    )
                } else {
                    List {
                        // Stats header
                        CatchStatsHeader(catches: catches)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())

                        // Streak (only shown when active)
                        if BadgeDefinition.streakDays(from: catches) > 0 {
                            FishingStreakView(catches: catches)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets())
                                .padding(.horizontal)
                        }

                        ForEach(filteredCatches, id: \.catchRecord.id) { detail in
                            NavigationLink(value: detail.catchRecord.id) {
                                CatchRow(detail: detail)
                            }
                        }
                        .onDelete { offsets in
                            let toDelete = offsets.map { filteredCatches[$0] }
                            for detail in toDelete {
                                try? appState.catchRepository.delete(detail.catchRecord)
                            }
                            Task { await loadCatches() }
                        }
                    }
                    .listStyle(.plain)
                    .searchable(text: $searchText, prompt: "Search catches")
                }
            }
            .navigationTitle("Catches")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingLogCatch = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        ForEach(SortOrder.allCases, id: \.self) { order in
                            Button {
                                sortOrder = order
                            } label: {
                                Label(order.rawValue, systemImage: sortOrder == order ? "checkmark" : "")
                            }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                }
            }
            .fullScreenCover(isPresented: $showingLogCatch, onDismiss: {
                Task { await loadCatches() }
            }) {
                LogCatchView()
            }
            .navigationDestination(for: String.self) { catchId in
                if let detail = filteredCatches.first(where: { $0.catchRecord.id == catchId }) {
                    CatchDetailView(detail: detail)
                }
            }
            .task {
                await loadCatches()
            }
            .refreshable {
                await loadCatches()
            }
        }
    }

    private func loadCatches() async {
        catches = (try? appState.catchRepository.fetchAll()) ?? []
    }
}

// MARK: - Catch Stats Header

struct CatchStatsHeader: View {
    let catches: [CatchDetail]

    var totalCatches: Int { catches.count }
    var uniqueSpecies: Int {
        Set(catches.compactMap { $0.species?.id }).count
    }
    var releaseRate: Int {
        guard !catches.isEmpty else { return 0 }
        let released = catches.filter { $0.catchRecord.released }.count
        return Int(Double(released) / Double(catches.count) * 100)
    }
    var biggestCatch: CatchDetail? {
        catches.max(by: { ($0.catchRecord.weightKg ?? 0) < ($1.catchRecord.weightKg ?? 0) })
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                StatCard(value: "\(totalCatches)", label: "Total", icon: "fish.fill")
                StatCard(value: "\(uniqueSpecies)", label: "Species", icon: "leaf.fill")
                StatCard(value: "\(releaseRate)%", label: "Released", icon: "arrow.uturn.backward")
                if let biggest = biggestCatch, let weight = biggest.catchRecord.weightKg {
                    StatCard(
                        value: String(format: "%.1fkg", weight),
                        label: biggest.species?.commonName ?? "PB",
                        icon: "trophy.fill"
                    )
                }
            }
            .padding()
        }
    }
}

struct StatCard: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(CurrentsTheme.accent)
            Text(value)
                .font(.title3.bold())
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 80)
        .glassCard()
    }
}

// MARK: - Catch Row

struct CatchRow: View {
    let detail: CatchDetail

    var body: some View {
        HStack(spacing: 12) {
            // Photo thumbnail or species icon
            if let photoPath = detail.catchRecord.allPhotoPaths.first,
               let image = PhotoManager.load(photoPath) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Image(systemName: "fish.fill")
                    .font(.title2)
                    .frame(width: 56, height: 56)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(detail.species?.commonName ?? "Unknown Species")
                    .font(.headline)

                HStack(spacing: 8) {
                    if let spot = detail.spot {
                        Label(spot.name, systemImage: "mappin")
                    }
                    if let weight = detail.catchRecord.weightKg {
                        Label(String(format: "%.1f kg", weight), systemImage: "scalemass")
                    }
                    if let length = detail.catchRecord.lengthCm {
                        Label(String(format: "%.0f cm", length), systemImage: "ruler")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(detail.catchRecord.caughtAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if detail.catchRecord.released {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
