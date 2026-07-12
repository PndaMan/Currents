import SwiftUI

struct CatchesTab: View {
    @Environment(AppState.self) private var appState
    @State private var catches: [CatchDetail] = []
    @State private var showingLogCatch = false
    @State private var searchText = ""
    @AppStorage("catchesSortOrder") private var sortOrder: SortOrder = .recent
    @State private var filter: CatchFilter = .all

    enum CatchFilter: String, CaseIterable {
        case all = "All"
        case favourites = "Favourites"
        case released = "Released"
        case kept = "Kept"
    }

    enum SortOrder: String, CaseIterable {
        case recent = "Recent"
        case oldest = "Oldest"
        case species = "Species"
        case size = "Biggest"
        case longest = "Longest"
        case spot = "Spot"
        case score = "Best Score"

        static let defaultOrder: SortOrder = .recent
    }

    var filteredCatches: [CatchDetail] {
        var result = catches
        switch filter {
        case .all: break
        case .favourites: result = result.filter { $0.catchRecord.isFavorite }
        case .released: result = result.filter { $0.catchRecord.released }
        case .kept: result = result.filter { !$0.catchRecord.released }
        }
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
                        if BadgeDefinition.streakWeeks(from: catches) > 0 {
                            FishingStreakView(catches: catches)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets())
                                .padding(.horizontal)
                        }

                        // Filter chips
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(CatchFilter.allCases, id: \.self) { f in
                                    FilterChip(title: f.rawValue, isSelected: filter == f) {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            filter = f
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)

                        ForEach(filteredCatches, id: \.catchRecord.id) { detail in
                            ZStack {
                                // Invisible NavigationLink so the row keeps
                                // swipe-to-delete but the card draws its own
                                // chevron-free glass styling.
                                NavigationLink(value: detail.catchRecord.id) {
                                    EmptyView()
                                }
                                .opacity(0)
                                CatchRow(detail: detail, style: .card)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        }
                        .onDelete { offsets in
                            let toDelete = offsets.map { filteredCatches[$0] }
                            let ids = toDelete.map { $0.catchRecord.id }
                            for detail in toDelete {
                                PhotoManager.deleteAll(detail.catchRecord.allPhotoPaths)
                                try? appState.catchRepository.delete(detail.catchRecord)
                            }
                            Task {
                                for id in ids { await CommunityService.shared.removeCatch(id: id) }
                                await loadCatches()
                            }
                        }

                        if filteredCatches.isEmpty {
                            ContentUnavailableView(
                                "Nothing matches",
                                systemImage: "line.3.horizontal.decrease.circle",
                                description: Text("Try a different search or filter.")
                            )
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
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
                        Divider()
                        Button {
                            sortOrder = SortOrder.defaultOrder
                        } label: {
                            Label("Default (\(SortOrder.defaultOrder.rawValue))", systemImage: "arrow.uturn.backward")
                        }
                        .disabled(sortOrder == SortOrder.defaultOrder)
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                }
            }
            .sheet(isPresented: $showingLogCatch, onDismiss: {
                Task { await loadCatches() }
            }) {
                LogCatchView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .onChange(of: appState.siriRequestedLogCatch) { _, requested in
                if requested {
                    showingLogCatch = true
                    appState.siriRequestedLogCatch = false
                }
            }
            .onAppear {
                // Handle the flag if it was set before this tab appeared.
                if appState.siriRequestedLogCatch {
                    showingLogCatch = true
                    appState.siriRequestedLogCatch = false
                }
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

    var body: some View {
        HStack(spacing: 12) {
            StatCard(value: "\(totalCatches)", label: "Total", icon: "fish.fill")
            StatCard(value: "\(uniqueSpecies)", label: "Species", icon: "leaf.fill")
            StatCard(value: "\(releaseRate)%", label: "Released", icon: "arrow.uturn.backward")
        }
        .padding()
    }
}

struct StatCard: View {
    let value: String
    let label: String
    let icon: String
    @AppStorage("selectedTheme") private var selectedTheme = ""

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(CurrentsTheme.accent)
            Text(value)
                .font(.title3.bold())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        // Flexible width so any number of cards tile evenly on one row.
        .frame(maxWidth: .infinity)
        .glassCard()
    }
}

// MARK: - Catch Row

struct CatchRow: View {
    let detail: CatchDetail
    /// Compact mode (default) is used inside cards/sheets; the Catches tab
    /// uses the full glass-card styling via `style: .card`.
    var style: Style = .plain
    @AppStorage("selectedTheme") private var selectedTheme = ""

    enum Style { case plain, card }

    var body: some View {
        HStack(spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 4) {
                // Full species name — wraps to two lines instead of clipping.
                Text(detail.species?.commonName ?? "Unknown Species")
                    .font(.subheadline.bold())
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Text(detail.catchRecord.caughtAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if let spot = detail.spot {
                        HStack(spacing: 2) {
                            Image(systemName: "mappin")
                                .font(.system(size: 9))
                            Text(spot.name)
                                .lineLimit(1)
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 6) {
                    if let weight = detail.catchRecord.weightKg {
                        statChip(String(format: "%.1f kg", weight))
                    }
                    if let length = detail.catchRecord.lengthCm {
                        statChip(String(format: "%.0f cm", length))
                    }
                    if let score = detail.catchRecord.forecastScoreAtCapture {
                        HStack(spacing: 2) {
                            Image(systemName: "gauge.medium")
                                .font(.system(size: 9))
                            Text("\(score)")
                        }
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(CurrentsTheme.scoreColor(score).opacity(0.18))
                        .foregroundStyle(CurrentsTheme.scoreColor(score))
                        .clipShape(Capsule())
                    }
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 4) {
                    if detail.catchRecord.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                    }
                    if detail.catchRecord.released {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .foregroundStyle(CurrentsTheme.accent)
                            .font(.caption)
                    }
                }
                if style == .card {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(style == .card ? 12 : 0)
        .padding(.vertical, style == .card ? 0 : 6)
        .background {
            if style == .card {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(.secondary.opacity(0.12), lineWidth: 1)
                    )
            }
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let photoPath = detail.catchRecord.allPhotoPaths.first {
            PhotoThumbnail(path: photoPath, size: 68) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(CurrentsTheme.accent.opacity(0.10))
            }
        } else if let species = detail.species {
            // No photo — fall back to the species artwork, not a generic symbol.
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(CurrentsTheme.accent.opacity(0.12))
                SpeciesArtworkView(species: species, caught: true, size: 60)
            }
            .frame(width: 68, height: 68)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(CurrentsTheme.accent.opacity(0.15))
                Image(systemName: "fish.fill")
                    .font(.title2)
                    .foregroundStyle(CurrentsTheme.accent)
            }
            .frame(width: 68, height: 68)
        }
    }

    private func statChip(_ text: String) -> some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(CurrentsTheme.accent.opacity(0.12))
            .foregroundStyle(CurrentsTheme.accent)
            .clipShape(Capsule())
    }
}
