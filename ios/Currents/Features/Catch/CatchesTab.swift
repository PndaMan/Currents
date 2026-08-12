import SwiftUI

struct CatchesTab: View {
    @Environment(AppState.self) private var appState
    @State private var catches: [CatchDetail] = []
    @State private var showingLogCatch = false
    @State private var searchText = ""
    @AppStorage("catchesSortOrder") private var sortOrder: SortOrder = .recent
    @State private var filter: CatchFilter = .all
    @FocusState private var searchFocused: Bool
    /// Gallery (photo-first 2-up grid, the default) or list; the choice sticks.
    @AppStorage("catchesLayout") private var layoutRaw = LayoutMode.gallery.rawValue
    /// Programmatic push target for gallery cells (see the Button note there).
    @State private var openCatchId: String?
    private var layout: LayoutMode { LayoutMode(rawValue: layoutRaw) ?? .list }

    enum LayoutMode: String {
        case list, gallery
    }

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

                        if layout == .gallery {
                            // Photo-first 2-up gallery: the image IS the cell,
                            // info on a scrim. Long-press for favourite/delete
                            // (grids have no swipe actions).
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                                GridItem(.flexible(), spacing: 10)],
                                      spacing: 10) {
                                ForEach(filteredCatches, id: \.catchRecord.id) { detail in
                                    // Buttons + programmatic push, NOT
                                    // NavigationLinks: a List fires every
                                    // link in a row at once (one tap pushed
                                    // a whole stack of catches) and pins a
                                    // chevron on each.
                                    Button {
                                        openCatchId = detail.catchRecord.id
                                    } label: {
                                        CatchGalleryCell(detail: detail)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button {
                                            toggleFavourite(detail)
                                        } label: {
                                            Label(detail.catchRecord.isFavorite ? "Unfavourite" : "Favourite",
                                                  systemImage: detail.catchRecord.isFavorite ? "star.slash.fill" : "star.fill")
                                        }
                                        Button(role: .destructive) {
                                            delete(detail)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        } else {
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
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        delete(detail)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    Button {
                                        toggleFavourite(detail)
                                    } label: {
                                        Label(detail.catchRecord.isFavorite ? "Unfavourite" : "Favourite",
                                              systemImage: detail.catchRecord.isFavorite ? "star.slash.fill" : "star.fill")
                                    }
                                    .tint(.yellow)
                                }
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
                    .searchFocused($searchFocused)
                    // Pull-to-refresh is gone (the list reloads itself); the
                    // pull-down gesture now opens search with the keyboard up.
                    .onScrollGeometryChange(for: Bool.self) { geo in
                        geo.contentOffset.y + geo.contentInsets.top < -60
                    } action: { wasPulled, isPulled in
                        if isPulled, !wasPulled, !searchFocused {
                            Haptics.tap()
                            searchFocused = true
                        }
                    }
                }
            }
            .smartSwipe(.catches)
            .navigationTitle("Catches")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Haptics.tap()
                        showingLogCatch = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                // Sessions, analytics and your tackle box are all about your
                // fishing rather than app settings, so they live here now
                // instead of in a separate "More" list.
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        if FeatureFlags.liveTrips {
                            NavigationLink { SessionsView() } label: {
                                Label("Fishing Sessions", systemImage: "figure.fishing")
                            }
                        }
                        NavigationLink { AnalyticsView() } label: {
                            Label("Analytics & Personal Bests", systemImage: "chart.xyaxis.line")
                        }
                        NavigationLink { GearTab() } label: {
                            Label("Gear & Tackle", systemImage: "wrench.and.screwdriver.fill")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                // Gallery ↔ list, one tap, sticky.
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.tap()
                        withAnimation(.snappy(duration: 0.25)) {
                            layoutRaw = (layout == .list ? LayoutMode.gallery : .list).rawValue
                        }
                    } label: {
                        Image(systemName: layout == .list ? "square.grid.2x2" : "list.bullet")
                    }
                    .accessibilityLabel(layout == .list ? "Gallery view" : "List view")
                }
                // Sort was the only thing behind the overflow "..." — a menu
                // wrapping a menu. It's a direct control with a sort glyph now.
                ToolbarItem(placement: .topBarTrailing) {
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
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel("Sort")
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
            .navigationDestination(item: $openCatchId) { catchId in
                if let detail = filteredCatches.first(where: { $0.catchRecord.id == catchId }) {
                    CatchDetailView(detail: detail)
                }
            }
            .task {
                await loadCatches()
            }
            .sensoryFeedback(.selection, trigger: filter)
            .sensoryFeedback(.selection, trigger: sortOrder)
        }
    }

    private func loadCatches() async {
        catches = (try? appState.catchRepository.fetchAll()) ?? []
    }

    private func delete(_ detail: CatchDetail) {
        PhotoManager.deleteAll(detail.catchRecord.allPhotoPaths)
        try? appState.catchRepository.delete(detail.catchRecord)
        let id = detail.catchRecord.id
        Task {
            await CommunityService.shared.removeCatch(id: id)
            await loadCatches()
        }
    }

    private func toggleFavourite(_ detail: CatchDetail) {
        var record = detail.catchRecord
        record.isFavorite.toggle()
        try? appState.catchRepository.save(&record)
        Haptics.tap()
        Task { await loadCatches() }
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

// MARK: - Gallery cell

/// A photo-first catch card for the 2-up gallery: the image (or the species'
/// artwork when there's no photo) IS the cell, species and size on a bottom
/// scrim, status icons floating top-right.
struct CatchGalleryCell: View {
    let detail: CatchDetail
    @Environment(\.displayScale) private var displayScale
    @State private var photo: UIImage?
    @AppStorage("selectedTheme") private var selectedTheme = ""

    private static let height: CGFloat = 208

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            background
                .frame(height: Self.height)
                .frame(maxWidth: .infinity)
                .clipped()

            LinearGradient(colors: [.clear, .black.opacity(photo == nil ? 0.55 : 0.78)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 96)
                .frame(maxWidth: .infinity, alignment: .bottom)

            VStack(alignment: .leading, spacing: 2) {
                Text(detail.species?.commonName ?? "Unknown Species")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    if let w = detail.catchRecord.weightKg {
                        Text(Units.weight(kg: w))
                    }
                    if let l = detail.catchRecord.lengthCm {
                        Text(Units.length(cm: l))
                    }
                    Text(detail.catchRecord.caughtAt.formatted(.dateTime.day().month()))
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
            }
            .padding(10)
        }
        .frame(height: Self.height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 4) {
                if detail.catchRecord.isFavorite {
                    statusIcon("star.fill", tint: .yellow)
                }
                if detail.catchRecord.released {
                    statusIcon("arrow.uturn.backward", tint: CurrentsTheme.accent)
                }
            }
            .padding(6)
        }
        .task(id: detail.catchRecord.id) {
            guard photo == nil, let path = detail.catchRecord.allPhotoPaths.first else { return }
            let px = Self.height * displayScale
            let scale = displayScale
            photo = await Task.detached { PhotoManager.thumbnail(path, maxPixel: px, scale: scale) }.value
        }
    }

    @ViewBuilder private var background: some View {
        // Color.clear owns the cell's size; the photo is an overlay cropped
        // to it. Letting scaledToFill size the cell directly stretched the
        // layout to whatever aspect the photo happened to have.
        Color.clear
            .overlay {
                if let photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                } else if let species = detail.species {
                    ZStack {
                        LinearGradient(colors: [CurrentsTheme.accent.opacity(0.30),
                                                CurrentsTheme.accent.opacity(0.10)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                        SpeciesArtworkView(species: species, caught: true, size: 96)
                            .padding(.bottom, 26)
                    }
                } else {
                    ZStack {
                        CurrentsTheme.accent.opacity(0.15)
                        Image(systemName: "fish.fill")
                            .font(.largeTitle)
                            .foregroundStyle(CurrentsTheme.accent)
                    }
                }
            }
    }

    private func statusIcon(_ name: String, tint: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 22, height: 22)
            .background(.ultraThinMaterial, in: Circle())
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
