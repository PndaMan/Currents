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
    @State private var favouriteTick = 0

    // Sessions and plans
    @State private var sessions: [Trip] = []
    @State private var planned: [Trip] = []
    @State private var planOutlooks: [String: PlanOutlook] = [:]
    @AppStorage("use24HourTime") private var use24 = true
    @State private var showingNewSession = false
    @State private var showingPlanner = false
    @State private var planToEdit: Trip?
    @State private var sessionToEdit: Trip?
    @State private var tripToDelete: Trip?

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
                    HeaderIconButton("Log catch", systemImage: "plus") {
                        showingLogCatch = true
                    }
                }

                topCards
                    .padding(.top, DS.Space.s2)

                if FeatureFlags.liveTrips {
                    Picker("Show", selection: $segment) {
                        ForEach(Segment.allCases, id: \.self) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, DS.gutter)
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
                withAnimation(DS.Motion.softSpring) {
                    CatchActions.delete(detail, appState: appState)
                    catchToDelete = nil
                    reload()
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
                try? appState.tripRepository.delete(trip)
                tripToDelete = nil
                withAnimation(DS.Motion.softSpring) { reload() }
                ToastCenter.shared.show(trip.isPlanned ? "Plan deleted" : "Session deleted",
                                        style: .info, haptic: false, icon: "trash")
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
            LogCatchView(editing: detail) { updated in
                CatchActions.saveEdit(updated, appState: appState)
            }
        }
        .sheet(item: $shareItem) { item in
            ImageShareSheet(image: item.image, filename: item.filename)
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
        .sensoryFeedback(.selection, trigger: filter)
        .sensoryFeedback(.selection, trigger: sortOrder)
        .sensoryFeedback(.selection, trigger: segment)
        .sensoryFeedback(.impact(weight: .light), trigger: favouriteTick)
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
                ContentUnavailableView("Session not found", systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                                       description: Text("It may have been deleted."))
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
            ContentUnavailableView("Catch not found", systemImage: "fish",
                                   description: Text("It may have been deleted."))
        }
    }

    // MARK: - Top cards

    private var topCards: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                NavigationLink(value: LogbookRoute.streak) {
                    StatTile("Streak", systemImage: "flame.fill", tint: .dsScoreLow,
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
                    StatTile("Badges", systemImage: "medal.fill", tint: .dsScoreFair,
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
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
        case .failed:
            ContentUnavailableView {
                Label("Your logbook could not be read", systemImage: "exclamationmark.triangle")
            } description: {
                Text("Nothing is lost. Try again in a moment.")
            } actions: {
                Button("Try again") { reload() }
                    .buttonStyle(TonalButtonStyle(fullWidth: false))
            }
            .padding(.top, 24)
        case .loaded:
            if catches.isEmpty {
                ContentUnavailableView {
                    Label("No catches yet", systemImage: "fish")
                } description: {
                    Text("Log your first fish. The conditions are saved with it.")
                } actions: {
                    Button("Log catch") { showingLogCatch = true }
                        .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                }
                .padding(.top, 24)
            } else {
                catchTools
                let visible = filteredCatches
                if visible.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing matches", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text(filter == .favourites ? "Star a catch and it shows up here." : "Try a different filter.")
                    } actions: {
                        Button("Show all catches") {
                            withAnimation(DS.Motion.softSpring) { filter = .all }
                        }
                        .buttonStyle(TonalButtonStyle(fullWidth: false))
                    }
                    .padding(.top, 24)
                } else {
                    ForEach(groups(for: visible)) { group in
                        if let title = group.title {
                            groupHeader(title, detail: group.detail, count: group.items.count)
                        }
                        if layout == .gallery {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                                GridItem(.flexible(), spacing: 12)],
                                      alignment: .leading, spacing: 18) {
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
                    Text("\(visible.count) of \(catches.count) catches. Long-press a catch for more.")
                        .font(.footnote)
                        .foregroundStyle(.dsText3)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DS.gutter)
                        .padding(.top, DS.Space.s6)
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
                    Picker("Show", selection: $filter.animation(DS.Motion.softSpring)) {
                        ForEach(CatchFilter.allCases, id: \.self) { f in
                            Text(f.title).tag(f)
                        }
                    }
                }
                Section("Sort by") {
                    Picker("Sort catches", selection: $sortOrder.animation(DS.Motion.softSpring)) {
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
            .frame(width: 36, height: 36)
            .background(active ? Color.dsPrimaryButton : Color.dsFill, in: Circle())
            .padding(.leading, 6)
            .animation(.easeOut(duration: DS.Motion.fast), value: active)
    }

    private func groupHeader(_ title: String, detail: String?, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.dsText)
            if let detail {
                Text(detail)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.dsText3)
            }
            Spacer()
            Text("\(count)")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.dsText2)
        }
        .padding(.horizontal, DS.gutter)
        .padding(.top, DS.Space.s6)
        .padding(.bottom, DS.Space.s2)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

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
                    .lineLimit(1)
                if let size = LogbookFormat.size(detail.catchRecord) {
                    Text(size)
                        .font(.footnote)
                        .foregroundStyle(.dsText2)
                        .lineLimit(1)
                }
                Text(LogbookFormat.relativeDay(detail.catchRecord.caughtAt))
                    .font(.footnote)
                    .foregroundStyle(.dsText3)
                    .lineLimit(1)
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
                            .foregroundStyle(Color.dsScoreFair)
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
            Label("Share", systemImage: "square.and.arrow.up")
        }
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
                       subtitle: "Started \(LogbookFormat.time(active.startDate))", chevron: true) {
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
        if past.isEmpty {
            ContentUnavailableView("No sessions yet", systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                                   description: Text("Start one at the water. Your track and catches are saved here."))
                .padding(.top, 12)
        } else {
            ForEach(sessionGroups(past), id: \.id) { group in
                groupHeader(group.month, detail: group.year, count: group.trips.count)
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

    private func sessionRow(_ trip: Trip) -> some View {
        let n = summary.catchesByTrip[trip.id] ?? 0
        let best = summary.bestScoreByTrip[trip.id]
        return NavigationLink(value: LogbookRoute.session(trip.id)) {
            ArtRow(over: sessionOver(trip), title: trip.name,
                   subtitle: "\(LogbookFormat.duration(trip.totalDurationSeconds)), \(n) \(n == 1 ? "catch" : "catches")",
                   chevron: best == nil) {
                TrackThumb(points: trip.allTrackPoints, tint: best.map { DS.scoreColor($0) } ?? DS.accent)
            } trailing: {
                if let best {
                    Text("\(best)")
                        .foregroundStyle(DS.scoreInk(best))
                        .accessibilityLabel("Best bite score \(best)")
                }
            }
        }
        .buttonStyle(.dsRow)
        .contextMenu {
            Button { sessionToEdit = trip } label: { Label("Edit", systemImage: "pencil") }
            Divider()
            Button(role: .destructive) { tripToDelete = trip } label: { Label("Delete session", systemImage: "trash") }
        }
    }

    /// The day, plus which shared trip it was: a tournament team, a crew trip
    /// or a plain shared trip.
    private func sessionOver(_ trip: Trip) -> String {
        let day = LogbookFormat.longDay(trip.startDate)
        guard let code = CommunityService.shared.groupCode(forTripId: trip.id),
              let ref = CommunityService.shared.myGroups.first(where: { $0.code == code }) else { return day }
        if let team = ref.teamName { return "\(day), team \(team)" }
        if ref.crewCode != nil { return "\(day), crew trip" }
        return "\(day), shared"
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

        if planned.isEmpty {
            ContentUnavailableView("Nothing planned", systemImage: "calendar",
                                   description: Text("Pick a day with a good bite and get a reminder before you go."))
                .padding(.top, 12)
        } else {
            groupHeader("Upcoming", detail: nil, count: planned.count)
            ForEach(planned.sorted { ($0.plannedDate ?? $0.startDate) < ($1.plannedDate ?? $1.startDate) }) { trip in
                planRow(trip)
            }
        }
    }

    private func planRow(_ trip: Trip) -> some View {
        let date = trip.plannedDate ?? trip.startDate
        let outlook = planOutlooks[trip.id]
        let subtitle: String = {
            guard let outlook else { return "Turn on location to see the bite" }
            guard let best = outlook.best else { return "No strong windows that day" }
            return "Best \(best.peakScore) from \(ForecastFormat.hour(best.startHour, use24: use24))"
        }()
        return NavigationLink(value: LogbookRoute.plan(trip.id)) {
            ArtRow(over: "\(LogbookFormat.time(date)), \(relativePlan(date))",
                   title: trip.name,
                   subtitle: subtitle,
                   chevron: outlook == nil) {
                PlanDateThumb(date: date, size: 64)
            } trailing: {
                if let outlook {
                    ScoreRing(score: outlook.score, size: 44)
                        .accessibilityLabel("Bite \(outlook.score) at the planned time")
                }
            }
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

    private func relativePlan(_ date: Date) -> String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: date)).day ?? 0
        switch days {
        case ..<0: return "overdue"
        case 0: return "today"
        case 1: return "tomorrow"
        default: return "in \(days) days"
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
            sessions = (try? appState.tripRepository.fetchAll()) ?? []
            planned = (try? appState.tripRepository.fetchPlanned()) ?? []
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

    private func toggleFavourite(_ detail: CatchDetail) {
        let record = CatchActions.toggleFavourite(detail, appState: appState)
        favouriteTick += 1
        withAnimation(DS.Motion.softSpring) {
            if let i = catches.firstIndex(where: { $0.catchRecord.id == record.id }) {
                catches[i].catchRecord = record
            }
        }
    }

    private func share(_ detail: CatchDetail) {
        Task {
            if let image = await CatchActions.shareImage(for: detail) {
                shareItem = CatchShareItem(image: image, filename: CatchActions.shareFilename(for: detail))
            } else {
                ToastCenter.shared.show("This catch has nothing to share yet", style: .info)
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

    init() {}

    init(catches: [CatchDetail], speciesTotal: Int) {
        let cal = Calendar.current
        streak = BadgeDefinition.streakWeeks(from: catches)
        if let week = cal.dateInterval(of: .weekOfYear, for: .now) {
            fishedThisWeek = catches.contains { week.contains($0.catchRecord.caughtAt) }
        }
        speciesFound = Set(catches.compactMap { $0.catchRecord.speciesId }).count
        self.speciesTotal = speciesTotal
        let badges = BadgeDefinition.compute(from: catches, streakWeeks: streak)
        badgesEarned = badges.filter(\.earned).count
        badgesVisible = badges.filter { $0.earned || !$0.hidden }.count
        nextBadge = BadgeMetrics(catches: catches, streakWeeks: streak).closest(in: badges)?.title
        let year = cal.component(.year, from: .now)
        thisYear = catches.filter { cal.component(.year, from: $0.catchRecord.caughtAt) == year }.count
        for c in catches {
            guard let trip = c.catchRecord.tripId else { continue }
            catchesByTrip[trip, default: 0] += 1
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

// MARK: - Shared cards and rows (used by other screens)

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

/// A compact catch row for lists inside other pages (species, spots,
/// sessions). Square thumbnail, species, size and day, bite score.
struct CatchRow: View {
    let detail: CatchDetail
    /// Kept for callers; both styles are plain rows now.
    var style: Style = .plain

    enum Style { case plain, card }

    var body: some View {
        let record = detail.catchRecord
        HStack(spacing: 14) {
            CatchThumb(detail: detail, size: 56)

            VStack(alignment: .leading, spacing: 2) {
                Text(LogbookFormat.relativeDay(record.caughtAt))
                    .font(.footnote)
                    .foregroundStyle(.dsText2)
                    .lineLimit(1)
                Text(detail.species?.commonName ?? "Unknown species")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.dsText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let sub = subtitle {
                    Text(sub)
                        .font(.subheadline)
                        .foregroundStyle(.dsText2)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if record.isFavorite {
                Image(systemName: "star.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.dsScoreFair)
                    .accessibilityLabel("Favourite")
            }
            if let score = record.forecastScoreAtCapture {
                Text("\(score)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(DS.scoreInk(score))
                    .accessibilityLabel("Bite score \(score)")
            }
            if style == .card {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.dsText3)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String? {
        var parts: [String] = []
        if let size = LogbookFormat.size(detail.catchRecord) { parts.append(size) }
        if let spot = detail.spot?.name { parts.append(spot) }
        if detail.catchRecord.released { parts.append("released") }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
