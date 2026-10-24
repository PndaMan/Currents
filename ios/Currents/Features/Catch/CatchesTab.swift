import SwiftUI
import CoreLocation

/// The Logbook tab root: streak, Fishdex, badges and stats cards, then
/// Catches / Sessions / Plans. ContentView owns the NavigationStack.
struct CatchesTab: View {
    @Environment(AppState.self) private var appState
    @Namespace private var zoom
    @State private var catches: [CatchDetail] = []
    @State private var loadState: LoadState = .loading
    @State private var summary = LogbookSummary()
    @State private var showingLogCatch = false
    @State private var showingSearch = false
    @AppStorage("catchesSortOrder") private var sortOrder: SortOrder = .recent
    @State private var filter: CatchFilter = .all
    /// Gallery (the default) or list; the choice sticks.
    @AppStorage("catchesLayout") private var layoutRaw = LayoutMode.gallery.rawValue
    @State private var segment: Segment = .catches
    /// Programmatic push target for the long-press menu's Open.
    @State private var openCatchId: String?
    /// Deleting is confirmed first: a long-press should never be able to
    /// destroy a catch (and its photos) in one accidental gesture.
    @State private var catchToDelete: CatchDetail?
    @State private var catchToEdit: CatchDetail?
    @State private var shareItem: CatchShareItem?
    /// A share card is being drawn for the long-press menu's Share.
    @State private var isPreparingShare = false

    // Sessions and plans
    @State private var sessions: [Trip] = []
    @State private var planned: [Trip] = []
    @State private var planOutlooks: [String: PlanOutlook] = [:]
    @AppStorage("use24HourTime") private var use24 = true
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The show-and-sort and layout buttons grow with the text.
    @ScaledMetric(relativeTo: .subheadline) private var toolIconSize: CGFloat = 36
    @State private var showingNewSession = false
    @State private var showingPlanner = false
    @State private var planToEdit: Trip?
    @State private var sessionToEdit: Trip?
    @State private var tripToDelete: Trip?
    /// The session or plan list could not be read; the pane offers a retry
    /// rather than claiming there is nothing there.
    @State private var sessionsFailed = false
    @State private var plansFailed = false

    private var layout: LayoutMode { LayoutMode(rawValue: layoutRaw) ?? .gallery }
    private var tracker: TripTracker { appState.tripTracker }

    enum LoadState { case loading, loaded, failed }

    enum LayoutMode: String {
        case list, gallery
    }

    enum Segment: String, CaseIterable {
        case catches = "Catches"
        case sessions = "Sessions"
        case plans = "Plans"
    }

    enum CatchFilter: String, CaseIterable {
        case all = "All"
        case favourites = "Favourites"
        case released = "Released"
        case kept = "Kept"

        /// What the menu shows.
        var title: String { self == .all ? "All catches" : rawValue }
    }

    /// Raw values are stored in user defaults, so they stay as they were;
    /// `title` is what the menu shows.
    enum SortOrder: String, CaseIterable {
        case recent = "Recent"
        case oldest = "Oldest"
        case species = "Species"
        case size = "Biggest"
        case longest = "Longest"
        case spot = "Spot"
        case score = "Best Score"

        static let defaultOrder: SortOrder = .recent

        var title: String {
            switch self {
            case .recent: "Most recent"
            case .oldest: "Oldest first"
            case .species: "Species"
            case .size: "Heaviest"
            case .longest: "Longest"
            case .spot: "Spot"
            case .score: "Best bite score"
            }
        }
    }

    var filteredCatches: [CatchDetail] {
        var result = catches
        switch filter {
        case .all: break
        case .favourites: result = result.filter { $0.catchRecord.isFavorite }
        case .released: result = result.filter { $0.catchRecord.released }
        case .kept: result = result.filter { !$0.catchRecord.released }
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

    // MARK: - Body

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                LargeTitleHeader("Logbook") {
                    HeaderIconButton("Search catches", systemImage: "magnifyingglass") {
                        showingSearch = true
                    }
                    // The Stats card is the last of the scrolling top cards,
                    // off screen on a phone, so Stats has a way in here too.
                    NavigationLink(value: LogbookRoute.stats) {
                        HeaderIconLabel(systemImage: "chart.bar")
                    }
                    .buttonStyle(.dim)
                    .accessibilityLabel("Stats")
                    HeaderIconButton("Log catch", systemImage: "plus") {
                        showingLogCatch = true
                    }
                }

                topCards
                    .padding(.top, DS.Space.s2)

                if FeatureFlags.liveTrips {
                    // FilterChips pads to the gutter itself.
                    FilterChips(Segment.allCases, selection: $segment.haptic()) { $0.rawValue }
                        .padding(.top, DS.Space.s6)
                        .padding(.bottom, DS.Space.s2)
                }

                switch segment {
                case .catches: catchesPane
                case .sessions: sessionsPane
                case .plans: plansPane
                }
            }
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
        }
        .dsScreenBackground()
        .largeTitleChrome("Logbook")
        .navigationDestination(for: LogbookRoute.self) { route in
            destination(route)
        }
        .navigationDestination(item: $openCatchId) { id in
            catchDestination(id)
        }
        .confirmationDialog("Delete this catch?",
                            isPresented: Binding(get: { catchToDelete != nil },
                                                 set: { if !$0 { catchToDelete = nil } }),
                            titleVisibility: .visible,
                            presenting: catchToDelete) { detail in
            Button("Delete catch", role: .destructive) {
                Haptics.warning()
                catchToDelete = nil
                // CatchActions shows the toast either way; the row only goes
                // when the database row did.
                if CatchActions.delete(detail, appState: appState) {
                    withAnimation(DS.Motion.softSpring) { reload() }
                }
            }
            Button("Cancel", role: .cancel) { catchToDelete = nil }
        } message: { detail in
            Text("\(detail.species?.commonName ?? "This catch"), \(LogbookFormat.shortDay(detail.catchRecord.caughtAt)). Its photos go too, including from shared feeds. This can't be undone.")
        }
        .confirmationDialog(tripToDelete?.isPlanned == true ? "Delete this plan?" : "Delete this session?",
                            isPresented: Binding(get: { tripToDelete != nil },
                                                 set: { if !$0 { tripToDelete = nil } }),
                            titleVisibility: .visible,
                            presenting: tripToDelete) { trip in
            Button(trip.isPlanned ? "Delete plan" : "Delete session", role: .destructive) {
                Haptics.warning()
                tripToDelete = nil
                deleteTrip(trip)
            }
            Button("Cancel", role: .cancel) { tripToDelete = nil }
        } message: { trip in
            Text(trip.isPlanned
                 ? "The plan and its checklist are removed."
                 : "Catches you logged are kept. Only the session and its track are removed.")
        }
        .fullScreenCover(isPresented: $showingLogCatch, onDismiss: {
            // A new catch lands at the top of an unfiltered list.
            filter = .all
            segment = .catches
            withAnimation(DS.Motion.softSpring) { reload() }
        }) {
            LogCatchView()
        }
        .sheet(isPresented: $showingSearch) {
            LogbookSearchSheet(catches: catches) { id in
                openCatchId = id
            }
        }
        .fullScreenCover(item: $catchToEdit, onDismiss: reload) { detail in
            // The composer saves the edit and shows its own toast; the list
            // reloads on dismiss.
            LogCatchView(editing: detail) { _ in }
        }
        .sheet(item: $shareItem) { item in
            // The system share sheet's own heights.
            ImageShareSheet(image: item.image, filename: item.filename)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingNewSession, onDismiss: reload) { NewSessionSheet() }
        .sheet(isPresented: $showingPlanner, onDismiss: reload) { PlanSessionSheet() }
        .sheet(item: $planToEdit, onDismiss: reload) { PlanSessionSheet(editingTrip: $0) }
        .sheet(item: $sessionToEdit, onDismiss: reload) { EditSessionSheet(trip: $0) }
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
            // Coming back from a detail page that edited or deleted something.
            reload()
        }
    }

    // MARK: - Destinations

    @ViewBuilder
    private func destination(_ route: LogbookRoute) -> some View {
        switch route {
        case .catchDetail(let id):
            catchDestination(id)
        case .session(let id):
            if let trip = try? appState.tripRepository.fetch(id) {
                SessionDetailView(trip: trip)
            } else {
                notFound("Session not found", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            }
        case .plan(let id):
            PlanDetailView(tripId: id)
        case .streak:
            StreakView(catches: catches)
        case .achievements:
            AchievementsView(catches: catches)
        case .stats:
            AnalyticsView()
        }
    }

    @ViewBuilder
    private func catchDestination(_ id: String) -> some View {
        if let detail = catches.first(where: { $0.catchRecord.id == id }) {
            CatchDetailView(detail: detail)
                .navigationTransition(.zoom(sourceID: id, in: zoom))
        } else {
            notFound("Catch not found", systemImage: "fish")
        }
    }

    /// A whole page for a link whose record has gone, such as a catch deleted
    /// on another screen while its page was in the back stack. It fills the
    /// screen on its own, so it is the system empty view rather than an
    /// in-section InlineEmpty.
    private func notFound(_ title: String, systemImage: String) -> some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text("It may have been deleted."))
            .dsScreenBackground()
    }

    // MARK: - Top cards

    private var topCards: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                NavigationLink(value: LogbookRoute.streak) {
                    StatTile("Streak", systemImage: "flame.fill", tint: DS.ink(.dsScoreLow),
                             value: "\(summary.streak)",
                             unit: summary.streak == 1 ? "week" : "weeks",
                             footnote: summary.fishedThisWeek ? "Fished this week" : "Fish by Sunday")
                }
                .buttonStyle(.dim)

                NavigationLink(value: AppRoute.fishdex) {
                    StatTile("Fishdex", systemImage: "book.fill", tint: .dsScoreGood,
                             value: "\(summary.speciesFound)",
                             unit: summary.speciesTotal > 0 ? "of \(summary.speciesTotal.formatted())" : nil,
                             footnote: summary.speciesFound == 0 ? "Catch one to start" : "Species found")
                }
                .buttonStyle(.dim)

                NavigationLink(value: LogbookRoute.achievements) {
                    StatTile("Badges", systemImage: "medal.fill", tint: DS.ink(.dsScoreFair),
                             value: "\(summary.badgesEarned)",
                             unit: "of \(summary.badgesVisible)",
                             footnote: summary.nextBadge.map { "\($0) next" })
                }
                .buttonStyle(.dim)

                NavigationLink(value: LogbookRoute.stats) {
                    StatTile("Stats", systemImage: "chart.bar.fill", tint: DS.accent,
                             value: "\(summary.thisYear)",
                             unit: "this year",
                             footnote: "Patterns and bests")
                }
                .buttonStyle(.dim)
            }
            .padding(.horizontal, DS.gutter)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    // MARK: - Catches pane

    @ViewBuilder
    private var catchesPane: some View {
        switch loadState {
        case .loading:
            FishLoader(message: "Opening your logbook")
                .frame(maxWidth: .infinity)
                .frame(height: 260)
        case .failed:
            InlineEmpty(systemImage: "exclamationmark.triangle",
                        text: "Your logbook could not be read. Nothing is lost.",
                        actionTitle: "Try again") { reload() }
                .padding(.top, DS.Space.s3)
        case .loaded:
            if catches.isEmpty {
                InlineEmpty(systemImage: "fish",
                            text: "No catches yet. Log your first fish and the conditions are saved with it.",
                            actionTitle: "Log catch") { showingLogCatch = true }
                    .padding(.top, DS.Space.s3)
            } else {
                catchTools
                let visible = filteredCatches
                if visible.isEmpty {
                    InlineEmpty(systemImage: "line.3.horizontal.decrease.circle",
                                text: filter == .favourites
                                    ? "No favourites yet. Star a catch and it shows up here."
                                    : "No catches match this filter.",
                                actionTitle: "Show all catches") {
                        withAnimation(DS.Motion.softSpring) { filter = .all }
                    }
                    .padding(.top, DS.Space.s3)
                } else {
                    ForEach(groups(for: visible)) { group in
                        if let title = group.title {
                            SectionTitle(title, detail: group.detail, count: group.items.count)
                                .padding(.top, DS.Space.s6)
                        }
                        if layout == .gallery {
                            LazyVGrid(columns: galleryColumns, alignment: .leading, spacing: 18) {
                                ForEach(group.items) { detail in
                                    galleryTile(detail)
                                }
                            }
                            .padding(.horizontal, DS.gutter)
                            .padding(.top, group.title == nil ? DS.Space.s3 : 0)
                        } else {
                            ForEach(group.items) { detail in
                                listRow(detail)
                            }
                        }
                    }
                }
            }
        }
    }

    /// The active filter as a removable chip (or the catch count when
    /// showing everything), then one menu for what to show and how to sort,
    /// then the layout toggle. Fits one line without scrolling.
    private var catchTools: some View {
        HStack(spacing: 0) {
            Group {
                if filter == .all {
                    Text("\(catches.count) \(catches.count == 1 ? "catch" : "catches")")
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.dsText2)
                } else {
                    Chip(filter.rawValue, systemImage: "xmark", isSelected: true) {
                        withAnimation(DS.Motion.softSpring) { filter = .all }
                    }
                    .accessibilityLabel("Showing \(filter.rawValue.lowercased())")
                    .accessibilityHint("Shows all catches")
                    .transition(.scale(scale: 0.8, anchor: .leading).combined(with: .opacity))
                }
            }
            .padding(.leading, DS.gutter)
            Spacer(minLength: DS.Space.s2)
            Menu {
                Section("Show") {
                    Picker("Show", selection: $filter.haptic().animation(DS.Motion.softSpring)) {
                        ForEach(CatchFilter.allCases, id: \.self) { f in
                            Text(f.title).tag(f)
                        }
                    }
                }
                Section("Sort by") {
                    Picker("Sort catches", selection: $sortOrder.haptic().animation(DS.Motion.softSpring)) {
                        ForEach(SortOrder.allCases, id: \.self) { order in
                            Text(order.title).tag(order)
                        }
                    }
                }
            } label: {
                toolIcon("line.3.horizontal.decrease", active: filter != .all)
            }
            .accessibilityLabel("Show and sort")
            .accessibilityValue("\(filter.title), \(sortOrder.title)")
            Button {
                withAnimation(DS.Motion.softSpring) {
                    layoutRaw = (layout == .list ? LayoutMode.gallery : .list).rawValue
                }
            } label: {
                toolIcon(layout == .list ? "square.grid.2x2" : "list.bullet")
            }
            .buttonStyle(.dim)
            .accessibilityLabel(layout == .list ? "Show as gallery" : "Show as list")
            .padding(.trailing, DS.gutter - 4)
        }
        .padding(.top, DS.Space.s2)
    }

    private func toolIcon(_ systemImage: String, active: Bool = false) -> some View {
        Image(systemName: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(active ? Color.dsOnPrimary : Color.dsText)
            .frame(width: toolIconSize, height: toolIconSize)
            .background(active ? Color.dsPrimaryButton : Color.dsFill, in: Circle())
            .padding(.leading, 6)
            .animation(.easeOut(duration: DS.Motion.fast), value: active)
    }

    /// Two columns, one at accessibility sizes so names are not cut short.
    private var galleryColumns: [GridItem] {
        typeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    /// One line per gallery caption, three at accessibility sizes.
    private var tileLines: Int { typeSize.isAccessibilitySize ? 3 : 1 }

    private func galleryTile(_ detail: CatchDetail) -> some View {
        let id = detail.catchRecord.id
        return NavigationLink(value: LogbookRoute.catchDetail(id)) {
            VStack(alignment: .leading, spacing: 2) {
                CatchTileArt(detail: detail)
                    .overlay(alignment: .topTrailing) {
                        if detail.catchRecord.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.dsScoreFair)
                                .frame(width: 26, height: 26)
                                .background(Color.dsScrim, in: Circle())
                                .padding(8)
                                .accessibilityLabel("Favourite")
                        }
                    }
                    .matchedTransitionSource(id: id, in: zoom)
                    .padding(.bottom, 6)
                Text(detail.species?.commonName ?? "Unknown species")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.dsText)
                    .lineLimit(tileLines)
                if let size = LogbookFormat.size(detail.catchRecord) {
                    Text(size)
                        .font(.footnote)
                        .foregroundStyle(.dsText2)
                        .lineLimit(tileLines)
                }
                Text(LogbookFormat.relativeDay(detail.catchRecord.caughtAt))
                    .font(.footnote)
                    .foregroundStyle(.dsText2)
                    .lineLimit(tileLines)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.dim)
        .contextMenu {
            catchMenu(detail)
        } preview: {
            CatchContextPreview(detail: detail)
        }
    }

    private func listRow(_ detail: CatchDetail) -> some View {
        let id = detail.catchRecord.id
        let record = detail.catchRecord
        var sub = LogbookFormat.size(record) ?? ""
        if record.released { sub += sub.isEmpty ? "Released" : ", released" }
        let over = [LogbookFormat.relativeDay(record.caughtAt), detail.spot?.name]
            .compactMap { $0 }.joined(separator: ", ")
        return NavigationLink(value: LogbookRoute.catchDetail(id)) {
            ArtRow(over: over, title: detail.species?.commonName ?? "Unknown species", subtitle: sub) {
                CatchThumb(detail: detail)
                    .matchedTransitionSource(id: id, in: zoom)
            } trailing: {
                HStack(spacing: 6) {
                    if record.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.footnote)
                            .foregroundStyle(DS.ink(.dsScoreFair))
                            .accessibilityLabel("Favourite")
                    }
                    if let score = record.forecastScoreAtCapture {
                        Text("\(score)")
                            .foregroundStyle(DS.scoreInk(score))
                            .accessibilityLabel("Bite score \(score)")
                    }
                }
            }
        }
        .buttonStyle(.dsRow)
        .contextMenu {
            catchMenu(detail)
        } preview: {
            CatchContextPreview(detail: detail)
        }
    }

    @ViewBuilder
    private func catchMenu(_ detail: CatchDetail) -> some View {
        Button {
            openCatchId = detail.catchRecord.id
        } label: {
            Label("Open", systemImage: "arrow.up.right")
        }
        Button {
            toggleFavourite(detail)
        } label: {
            Label(detail.catchRecord.isFavorite ? "Unfavourite" : "Favourite",
                  systemImage: detail.catchRecord.isFavorite ? "star.slash" : "star")
        }
        Button {
            share(detail)
        } label: {
            Label(isPreparingShare ? "Preparing" : "Share", systemImage: "square.and.arrow.up")
        }
        .disabled(isPreparingShare)
        Button {
            catchToEdit = detail
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        Divider()
        Button(role: .destructive) {
            catchToDelete = detail
        } label: {
            Label("Delete catch", systemImage: "trash")
        }
    }

    private struct CatchGroup: Identifiable {
        let id: String
        let title: String?
        let detail: String?
        var items: [CatchDetail]
    }

    /// Month groups for date sorts, name groups for species and spot sorts,
    /// one flat group for the measured sorts.
    private func groups(for list: [CatchDetail]) -> [CatchGroup] {
        var result: [CatchGroup] = []
        for d in list {
            let key: (id: String, title: String?, detail: String?)
            switch sortOrder {
            case .recent, .oldest:
                let date = d.catchRecord.caughtAt
                let month = date.formatted(.dateTime.month(.wide))
                let year = date.formatted(.dateTime.year())
                key = ("\(month)-\(year)", month, year)
            case .species:
                let name = d.species?.commonName ?? "Unknown species"
                key = (name, name, nil)
            case .spot:
                let name = d.spot?.name ?? "No spot"
                key = (name, name, nil)
            case .size, .longest, .score:
                key = ("all", nil, nil)
            }
            if let last = result.indices.last, result[last].id == key.id {
                result[last].items.append(d)
            } else {
                result.append(CatchGroup(id: key.id, title: key.title, detail: key.detail, items: [d]))
            }
        }
        return result
    }

    // MARK: - Sessions pane

    @ViewBuilder
    private var sessionsPane: some View {
        if let active = tracker.activeTrip {
            NavigationLink {
                ActiveSessionView()
            } label: {
                ArtRow(over: "Session running", title: active.name,
                       subtitle: "Started \(LogbookFormat.time(active.startDate, use24: use24))", chevron: true) {
                    ThumbView(systemImage: "dot.radiowaves.left.and.right", tint: .dsScoreSlow)
                } trailing: {
                    let n = summary.catchesByTrip[active.id] ?? 0
                    Text("\(n) \(n == 1 ? "catch" : "catches")")
                        .font(.subheadline)
                        .foregroundStyle(.dsText2)
                }
            }
            .buttonStyle(.dsRow)
        } else {
            Button {
                showingNewSession = true
            } label: {
                ArtRow(title: "Start a session",
                       subtitle: "Records your track, catches and the bite while you fish",
                       chevron: true) {
                    ThumbView(systemImage: "play.fill", tint: .dsScoreGood)
                }
            }
            .buttonStyle(.dsRow)
        }

        let past = sessions.filter(\.isCompleted)
        if sessionsFailed {
            InlineEmpty(systemImage: "exclamationmark.triangle",
                        text: "Your sessions could not be read. Nothing is lost.",
                        actionTitle: "Try again") { reload() }
                .padding(.top, DS.Space.s3)
        } else if past.isEmpty {
            InlineEmpty(systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                        text: "No sessions yet. Start one at the water and your track and catches are saved here.")
                .padding(.top, DS.Space.s3)
        } else {
            ForEach(sessionGroups(past), id: \.id) { group in
                SectionTitle(group.month, detail: group.year, count: group.trips.count)
                    .padding(.top, DS.Space.s6)
                ForEach(group.trips) { trip in
                    sessionRow(trip)
                }
            }
        }
    }

    private struct SessionGroup {
        let id: String
        let month: String
        let year: String
        var trips: [Trip]
    }

    private func sessionGroups(_ trips: [Trip]) -> [SessionGroup] {
        var result: [SessionGroup] = []
        for t in trips {
            let month = t.startDate.formatted(.dateTime.month(.wide))
            let year = t.startDate.formatted(.dateTime.year())
            let id = "\(month)-\(year)"
            if let last = result.indices.last, result[last].id == id {
                result[last].trips.append(t)
            } else {
                result.append(SessionGroup(id: id, month: month, year: year, trips: [t]))
            }
        }
        return result
    }

    /// The Sessions page's row, so both lists show a session the same way.
    private func sessionRow(_ trip: Trip) -> some View {
        NavigationLink(value: LogbookRoute.session(trip.id)) {
            SessionRow(trip: trip, catchCount: summary.catchesByTrip[trip.id] ?? 0,
                       photoPath: summary.photoByTrip[trip.id], bestScore: summary.bestScoreByTrip[trip.id])
        }
        .buttonStyle(.dsRow)
        .contextMenu {
            Button { sessionToEdit = trip } label: { Label("Edit", systemImage: "pencil") }
            Divider()
            Button(role: .destructive) { tripToDelete = trip } label: { Label("Delete session", systemImage: "trash") }
        }
    }

    // MARK: - Plans pane

    @ViewBuilder
    private var plansPane: some View {
        Button {
            showingPlanner = true
        } label: {
            ArtRow(title: "Plan a session",
                   subtitle: "Pick a day and spot, see the best hours",
                   chevron: true) {
                ThumbView(systemImage: "calendar.badge.plus", tint: DS.accent)
            }
        }
        .buttonStyle(.dsRow)

        if plansFailed {
            InlineEmpty(systemImage: "exclamationmark.triangle",
                        text: "Your plans could not be read. Nothing is lost.",
                        actionTitle: "Try again") { reload() }
                .padding(.top, DS.Space.s3)
        } else if planned.isEmpty {
            InlineEmpty(systemImage: "calendar",
                        text: "Nothing planned yet. Pick a day with a good bite and get a reminder before you go.")
                .padding(.top, DS.Space.s3)
        } else {
            SectionTitle("Upcoming", count: planned.count)
                .padding(.top, DS.Space.s6)
            ForEach(planned.sorted { ($0.plannedDate ?? $0.startDate) < ($1.plannedDate ?? $1.startDate) }) { trip in
                planRow(trip)
            }
        }
    }

    /// The Sessions page's Upcoming row, so both lists show a plan the same way.
    private func planRow(_ trip: Trip) -> some View {
        let outlook = planOutlooks[trip.id].map { PlanRowOutlook(score: $0.score, best: $0.best) }
        return NavigationLink(value: LogbookRoute.plan(trip.id)) {
            PlannedRow(trip: trip, outlook: outlook)
        }
        .buttonStyle(.dsRow)
        .contextMenu {
            Button {
                startPlanned(trip)
            } label: { Label("Start now", systemImage: "play.fill") }
            .disabled(tracker.isTracking)
            Button { planToEdit = trip } label: { Label("Edit", systemImage: "pencil") }
            Divider()
            Button(role: .destructive) { tripToDelete = trip } label: { Label("Delete plan", systemImage: "trash") }
        }
    }

    // MARK: - Actions

    private func reload() {
        do {
            // Every catch: the repository's default page is 50.
            catches = try appState.catchRepository.fetchAll(limit: 100_000)
            loadState = .loaded
        } catch {
            loadState = .failed
        }
        if FeatureFlags.liveTrips {
            do {
                sessions = try appState.tripRepository.fetchAll()
                sessionsFailed = false
            } catch {
                sessionsFailed = true
            }
            do {
                planned = try appState.tripRepository.fetchPlanned()
                plansFailed = false
            } catch {
                plansFailed = true
            }
            planOutlooks = Self.planOutlooks(for: planned,
                                             fallback: appState.locationManager.currentLocation?.coordinate)
        }
        let total = summary.speciesTotal > 0
            ? summary.speciesTotal
            : ((try? appState.speciesRepository.fetchAll().count) ?? 0)
        summary = LogbookSummary(catches: catches, speciesTotal: total)
    }

    /// The bite at a plan's start time and its best window, for the plan's
    /// pin or else where you are now. Moon, sun, tide and season only: live
    /// weather is not known days ahead.
    struct PlanOutlook {
        let score: Int
        let best: BiteWindows.Window?
    }

    private static func planOutlooks(for plans: [Trip], fallback: CLLocationCoordinate2D?) -> [String: PlanOutlook] {
        var result: [String: PlanOutlook] = [:]
        for p in plans {
            guard let coord = p.plannedCoordinate ?? fallback else { continue }
            let date = p.plannedDate ?? p.startDate
            let hour = Calendar.current.component(.hour, from: date)
            let f = ForecastEngine.forecast(
                date: date, coordinate: coord,
                currentPressureHpa: nil, pressureChange6h: nil, waterTempC: nil,
                windSpeedKmh: nil, windDirection: nil, species: nil, isInSpawningZone: false
            )
            result[p.id] = PlanOutlook(
                score: f.hourlyScores.first { $0.hour == hour }?.score ?? f.score,
                best: BiteWindows.best(from: f.hourlyScores).max { $0.peakScore < $1.peakScore })
        }
        return result
    }

    /// Deletes a session or plan. A plan's reminder goes with it; a failed
    /// delete keeps the row and says so.
    private func deleteTrip(_ trip: Trip) {
        let isPlan = trip.isPlanned
        do {
            try appState.tripRepository.delete(trip)
        } catch {
            ToastCenter.shared.show(isPlan ? "Couldn't delete the plan" : "Couldn't delete the session",
                                    style: .error)
            return
        }
        if isPlan { NotificationManager.shared.cancelPlannedSessionAlert(tripId: trip.id) }
        withAnimation(DS.Motion.softSpring) { reload() }
        ToastCenter.shared.show(isPlan ? "Plan deleted" : "Session deleted",
                                style: .info, haptic: false, icon: "trash")
    }

    private func toggleFavourite(_ detail: CatchDetail) {
        let record = CatchActions.toggleFavourite(detail, appState: appState)
        // A failed save comes back unchanged with its own error toast.
        if record.isFavorite != detail.catchRecord.isFavorite { Haptics.toggle() }
        withAnimation(DS.Motion.softSpring) {
            if let i = catches.firstIndex(where: { $0.catchRecord.id == record.id }) {
                catches[i].catchRecord = record
            }
        }
    }

    /// The menu closes on tap, so a toast says the card is on its way. A
    /// catch with no photo and no species art gets the fish symbol card.
    private func share(_ detail: CatchDetail) {
        guard !isPreparingShare else { return }
        isPreparingShare = true
        ToastCenter.shared.show("Preparing the share card", style: .info, haptic: false,
                                icon: "square.and.arrow.up")
        Task { @MainActor in
            let image = await CatchActions.shareImage(for: detail)
            isPreparingShare = false
            if let image {
                shareItem = CatchShareItem(image: image, filename: CatchActions.shareFilename(for: detail))
            } else {
                ToastCenter.shared.show("Couldn't make the share card", style: .error)
            }
        }
    }

    private func startPlanned(_ trip: Trip) {
        _ = tracker.startPlanned(trip)
        reload()
        ToastCenter.shared.show("Session started", icon: "play.fill")
    }
}

// MARK: - Summary for the top cards

/// Everything the Logbook top cards show, worked out once per reload instead
/// of on every render.
struct LogbookSummary {
    var streak = 0
    var fishedThisWeek = false
    var speciesFound = 0
    var speciesTotal = 0
    var badgesEarned = 0
    var badgesVisible = 0
    var nextBadge: String?
    var thisYear = 0
    var catchesByTrip: [String: Int] = [:]
    var bestScoreByTrip: [String: Int] = [:]
    /// The first catch photo found for each session, for sessions with no track.
    var photoByTrip: [String: String] = [:]

    init() {}

    init(catches: [CatchDetail], speciesTotal: Int) {
        let cal = Calendar.current
        streak = BadgeDefinition.streakWeeks(from: catches)
        // Monday to Sunday, the same weeks as the streak.
        if let week = BadgeDefinition.weekCalendar.dateInterval(of: .weekOfYear, for: .now) {
            fishedThisWeek = catches.contains { week.contains($0.catchRecord.caughtAt) }
        }
        speciesFound = Set(catches.compactMap { $0.catchRecord.speciesId }).count
        self.speciesTotal = speciesTotal
        let badges = BadgeDefinition.compute(from: catches, streakWeeks: streak)
        badgesEarned = badges.filter(\.earned).count
        badgesVisible = badges.filter { $0.earned || !$0.hidden }.count
        nextBadge = BadgeMetrics(catches: catches, streakWeeks: streak).closest(in: badges)?.displayName
        let year = cal.component(.year, from: .now)
        thisYear = catches.filter { cal.component(.year, from: $0.catchRecord.caughtAt) == year }.count
        for c in catches {
            guard let trip = c.catchRecord.tripId else { continue }
            catchesByTrip[trip, default: 0] += 1
            if photoByTrip[trip] == nil, let path = c.catchRecord.allPhotoPaths.first {
                photoByTrip[trip] = path
            }
            if let s = c.catchRecord.forecastScoreAtCapture {
                bestScoreByTrip[trip] = max(bestScoreByTrip[trip] ?? 0, s)
            }
        }
    }
}

// MARK: - Long-press preview

/// The lifted preview for a catch's long-press menu: its art and a caption.
struct CatchContextPreview: View {
    let detail: CatchDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CatchTileArt(detail: detail)
                .frame(width: 280)
            VStack(alignment: .leading, spacing: 2) {
                Text(detail.species?.commonName ?? "Unknown species")
                    .font(.headline)
                    .foregroundStyle(.dsText)
                Text([LogbookFormat.size(detail.catchRecord), LogbookFormat.shortDay(detail.catchRecord.caughtAt)]
                    .compactMap { $0 }.joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
            }
            .padding(14)
        }
        .frame(width: 280, alignment: .leading)
        .background(Color.dsElevated)
    }
}
