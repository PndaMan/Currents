import SwiftUI
import MapKit

/// A catch's page, laid out like an activity in Strava: the photo edge to
/// edge under the navigation bar, the species and when it was caught, the
/// measurements as a stat grid, Share / Edit / Favourite, then where it was
/// caught, the conditions at the time, the gear, notes, and links to its
/// session and Fishdex entry. Tinted with the species' art colour.
struct CatchDetailView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("units") private var units = "metric"
    @AppStorage("use24HourTime") private var use24 = true
    private var imperial: Bool { units == "imperial" }
    @Environment(\.dismiss) private var dismiss
    @State private var detail: CatchDetail
    @State private var showingDeleteConfirm = false
    @State private var showingEdit = false
    @State private var isGeneratingShareCard = false
    @State private var isPostingToCrew = false
    @State private var shareItem: CatchShareItem?
    @State private var trip: Trip?
    @State private var showingPhotoViewer = false
    @State private var carouselIndex = 0
    @State private var isFavorite = false
    @State private var photos: [UIImage] = []
    @State private var photosLoaded = false
    @State private var speciesCatchCount = 0
    @State private var isPersonalBest = false

    init(detail: CatchDetail) {
        _detail = State(initialValue: detail)
    }

    private var record: Catch { detail.catchRecord }
    private var speciesName: String { detail.species?.commonName ?? "Unknown species" }
    private var hasPhotos: Bool { !record.allPhotoPaths.isEmpty }
    private var tint: Color { detail.species?.artTint ?? DS.accent }

    var body: some View {
        ScrollView {
            content
                .padding(.bottom, DS.Space.s8)
                .pageWidth()
        }
        .detailTint(detail.species?.artTint)
        .modifier(CatchHeroChrome(title: speciesName, heroFactor: CatchHero.factor(hasPhoto: hasPhotos)))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isPostingToCrew {
                    ProgressView()
                        .accessibilityLabel("Sharing to your crew")
                } else {
                    moreMenu
                }
            }
        }
        .confirmationDialog("Delete this catch?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Delete catch", role: .destructive) {
                Haptics.warning()
                // CatchActions shows the toast either way; the page only
                // closes when the catch is gone.
                if CatchActions.delete(detail, appState: appState) {
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(speciesName), \(LogbookFormat.shortDay(record.caughtAt)). Its photos go too, including from shared feeds. This can't be undone.")
        }
        .fullScreenCover(isPresented: $showingEdit) {
            LogCatchView(editing: detail) { updated in
                if let saved = CatchActions.saveEditChecked(updated, appState: appState) {
                    reload(with: saved)
                } else {
                    // The composer confirms the edit straight after this
                    // returns, so the failure is shown once it has.
                    Task { @MainActor in ToastCenter.shared.show("Couldn't save the changes", style: .error) }
                }
            }
        }
        .sheet(item: $shareItem) { item in
            ImageShareSheet(image: item.image, filename: item.filename)
        }
        .fullScreenCover(isPresented: $showingPhotoViewer) {
            FullscreenPhotoViewer(
                photoPaths: detail.catchRecord.allPhotoPaths,
                currentIndex: $carouselIndex
            )
        }
        .task(id: detail.catchRecord.id) {
            await load()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero
            header
                .padding(.top, DS.Space.s4)
            statsBlock
                .padding(.top, DS.Space.s6)
            actions
                .padding(.top, DS.Space.s6)

            regulationSection
            whereSection
            conditionsSection
            gearSection
            notesSection
            linksSection
            predictionsSection

            DangerButton(title: "Delete catch", systemImage: "trash") {
                showingDeleteConfirm = true
            }
            .padding(.top, DS.Space.s8)
        }
    }

    // MARK: - Hero and header

    private var hero: some View {
        CatchHero(photos: photos,
                  index: $carouselIndex,
                  species: detail.species,
                  showsPhotos: hasPhotos,
                  isLoading: hasPhotos && !photosLoaded,
                  open: { showingPhotoViewer = true },
                  addPhoto: { showingEdit = true })
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailHeader(over: "\(LogbookFormat.longDay(record.caughtAt)), \(LogbookFormat.time(record.caughtAt, use24: use24))",
                         title: speciesName,
                         subtitle: detail.species?.scientificName)
            CatchFactsLine(facts: facts)
                .padding(.top, DS.Space.s3)
        }
    }

    private var facts: [CatchFact] {
        var list: [CatchFact] = []
        if isPersonalBest {
            list.append(CatchFact(systemImage: "trophy.fill", text: "Personal best", tint: DS.accent))
        }
        if record.released {
            list.append(CatchFact(systemImage: "arrow.uturn.backward", text: "Released"))
        } else {
            list.append(CatchFact(systemImage: "basket", text: "Kept"))
        }
        return list
    }

    // MARK: - Stats

    private var stats: [CatchStat] {
        var list: [CatchStat] = []
        if let kg = record.weightKg {
            list.append(CatchStat("Weight", measured: Units.weight(kg: kg, imperial: imperial)))
        }
        if let cm = record.lengthCm {
            list.append(CatchStat("Length", measured: Units.length(cm: cm, imperial: imperial)))
        }
        if let depth = record.depthM {
            list.append(CatchStat("Depth", measured: Units.depth(m: depth, imperial: imperial)))
        }
        if let score = record.forecastScoreAtCapture {
            list.append(CatchStat("Bite score", value: "\(score)", unit: "of 100"))
        }
        return list
    }

    @ViewBuilder
    private var statsBlock: some View {
        let measured = stats
        if measured.isEmpty {
            InlineEmpty(systemImage: "ruler", text: "No weight or length logged for this one.",
                        actionTitle: "Add size") {
                showingEdit = true
            }
        } else {
            CatchStatGrid(stats: measured)
        }
    }

    // MARK: - Actions

    private var actions: some View {
        ActionTriple {
            Button {
                share()
            } label: {
                Label(isGeneratingShareCard ? "Preparing" : "Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(ActionTileStyle(.primary))
            .disabled(isGeneratingShareCard)

            Button {
                showingEdit = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .buttonStyle(ActionTileStyle(.tonal))

            Button {
                toggleFavorite()
            } label: {
                Label("Favourite", systemImage: isFavorite ? "star.fill" : "star")
                    .symbolEffect(.bounce, value: isFavorite)
            }
            .buttonStyle(ActionTileStyle(.tonal))
            .buttonHaptic(.toggle)
            .accessibilityValue(isFavorite ? "On" : "Off")
        }
    }

    private var moreMenu: some View {
        Menu {
            Button {
                showingEdit = true
            } label: {
                Label("Edit catch", systemImage: "pencil")
            }
            // Manual crew share: without this, a crew feed could only
            // ever contain fish caught after the crew existed
            // (auto-post fires at log time only), and turning auto-post
            // off made posting impossible entirely.
            crewShareMenu
            Divider()
            Button(role: .destructive) {
                showingDeleteConfirm = true
            } label: {
                Label("Delete catch", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("More")
    }

    @ViewBuilder
    private var crewShareMenu: some View {
        let svc = CommunityService.shared
        if svc.joined, !svc.myCrews.isEmpty {
            Menu {
                ForEach(svc.myCrews) { crew in
                    Button(crew.name) {
                        shareToCrew(code: crew.code, name: crew.name)
                    }
                }
            } label: {
                Label("Share to crew", systemImage: "person.3")
            }
        }
    }

    /// Posts the catch to one crew. The toast says it went only when the
    /// post did; offline or failed posts say so instead.
    private func shareToCrew(code: String, name: String) {
        let posted = detail.catchRecord
        let species = speciesName
        isPostingToCrew = true
        Task {
            let shared = await CommunityService.shared.postCatch(posted, speciesName: species,
                                                                 toCrew: code, caption: "")
            isPostingToCrew = false
            if shared {
                ToastCenter.shared.show("Shared to \(name)", icon: "person.3")
            } else {
                ToastCenter.shared.show("Couldn't share. Try again when you have signal", style: .error)
            }
        }
    }

    // MARK: - Loading

    private func load() async {
        isFavorite = record.isFavorite
        if let tripId = record.tripId {
            trip = try? appState.tripRepository.fetch(tripId)
        } else {
            trip = nil
        }
        if let speciesId = record.speciesId {
            let same = (try? appState.catchRepository.fetchForSpecies(speciesId)) ?? []
            speciesCatchCount = same.count
            if let w = record.weightKg, same.count > 1 {
                isPersonalBest = same.allSatisfy { ($0.catchRecord.weightKg ?? 0) <= w }
            } else {
                isPersonalBest = false
            }
        }
        let paths = record.allPhotoPaths
        photos = await Task.detached { paths.compactMap { PhotoManager.load($0) } }.value
        if carouselIndex >= photos.count { carouselIndex = 0 }
        photosLoaded = true
        await backfillWeather()
    }

    private func toggleFavorite() {
        let saved = CatchActions.toggleFavourite(detail, appState: appState)
        withAnimation(DS.Motion.spring) {
            isFavorite = saved.isFavorite
        }
        detail.catchRecord = saved
    }

    /// Rebuild the joined detail after an edit so the open page reflects the
    /// change immediately instead of showing stale data until re-navigation.
    private func reload(with record: Catch) {
        detail = CatchActions.reloadDetail(record, appState: appState)
        isFavorite = record.isFavorite
        Task { await load() }
    }

    private func share() {
        isGeneratingShareCard = true
        Task {
            // Share the photo the angler is looking at in the carousel.
            if let image = await CatchActions.shareImage(for: detail, photoIndex: carouselIndex) {
                shareItem = CatchShareItem(image: image, filename: CatchActions.shareFilename(for: detail))
            } else {
                ToastCenter.shared.show("This catch has nothing to share yet", style: .info)
            }
            isGeneratingShareCard = false
        }
    }

    // MARK: - Regulation

    /// The size and bag rules on file for this species, one row each. A rule
    /// this fish breaks has a red icon and says so.
    @ViewBuilder
    private var regulationSection: some View {
        let result = RegulationsService.shared.verdict(species: detail.species, lengthCm: record.lengthCm)
        if let reg = result.reg,
           reg.minSizeCm != nil || reg.maxSizeCm != nil || reg.bagLimit != nil
            || !(reg.closedSeason ?? "").isEmpty {
            let verdict = result.verdict
            CardSection("Size and bag limits",
                        note: "Rules for \(reg.region). Check local rules before you keep a fish.") {
                if let mn = reg.minSizeCm {
                    CardRow("Minimum size", subtitle: sizeNote(verdict, broken: isTooSmall(verdict)),
                            systemImage: "ruler", tint: ruleTint(verdict, broken: isTooSmall(verdict)),
                            value: Units.length(cm: mn, imperial: imperial))
                }
                if let mx = reg.maxSizeCm {
                    CardRow("Maximum size", subtitle: sizeNote(verdict, broken: isTooBig(verdict)),
                            systemImage: "ruler", tint: ruleTint(verdict, broken: isTooBig(verdict)),
                            value: Units.length(cm: mx, imperial: imperial))
                }
                if let bag = reg.bagLimit {
                    CardRow("Bag limit", systemImage: "basket.fill",
                            tint: bag == 0 ? .dsScoreSlow : DS.accent,
                            value: bag == 0 ? "None kept" : "\(bag) a day")
                }
                if let closed = reg.closedSeason, !closed.isEmpty {
                    CardRow("Closed season", subtitle: closed, systemImage: "calendar", tint: .dsScoreLow)
                }
            }
            .padding(.top, DS.Space.s8)
        }
    }

    private func isTooSmall(_ verdict: KeepVerdict) -> Bool {
        if case .tooSmall = verdict { return true }
        return false
    }

    private func isTooBig(_ verdict: KeepVerdict) -> Bool {
        if case .tooBig = verdict { return true }
        return false
    }

    /// Red for the rule this fish breaks, green when it was measured and kept
    /// to the rule, accent when there is no length to check.
    private func ruleTint(_ verdict: KeepVerdict, broken: Bool) -> Color {
        if broken { return .dsScoreSlow }
        if case .unknownSize = verdict { return DS.accent }
        return .dsScoreGood
    }

    private func sizeNote(_ verdict: KeepVerdict, broken: Bool) -> String? {
        if broken { return isTooSmall(verdict) ? "This fish is under it" : "This fish is over it" }
        if case .unknownSize = verdict { return "Add a length to check this fish" }
        return nil
    }

    // MARK: - Where

    private var hasCoordinate: Bool { record.latitude != 0 || record.longitude != 0 }

    private var catchCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: record.latitude, longitude: record.longitude)
    }

    /// Where the fish came from: the catch's own fix, else its spot's.
    private var placeCoordinate: CLLocationCoordinate2D? {
        if hasCoordinate { return catchCoordinate }
        guard let spot = detail.spot else { return nil }
        return CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude)
    }

    @ViewBuilder
    private var whereSection: some View {
        if let place = placeCoordinate {
            SectionTitle("Where")
                .padding(.top, DS.Space.s8)
            Button { openOnMap(place) } label: {
                CatchMapRender(id: "catch-\(record.id)", coordinate: place, tint: tint)
            }
            .buttonStyle(.dim)
            .accessibilityLabel("Map of where it was caught")
            .accessibilityHint("Opens it on the map")
            .padding(.horizontal, DS.gutter)
            if let spot = detail.spot {
                // The spot opens on the Explore map in its sheet.
                Button { appState.pendingDeepLink = MapLink.spot(spot) } label: {
                    ArtRow(over: "Spot", title: spot.name,
                           subtitle: spot.type == .general ? nil : spot.type.label,
                           chevron: true) {
                        PlaceSnapshotThumb(spot: spot, size: 52)
                    }
                }
                .buttonStyle(.dsRow)
                .padding(.top, DS.Space.s2)
            }
            DirectionsMenu(coordinate: place, name: detail.spot?.name ?? speciesName) {
                ActionTileLabel("Directions", systemImage: "location.north.line")
            }
            .padding(.horizontal, DS.gutter)
            .padding(.top, DS.Space.s3)
        }
    }

    /// The saved spot in its sheet when there is one, otherwise the point.
    private func openOnMap(_ place: CLLocationCoordinate2D) {
        if let spot = detail.spot {
            appState.pendingDeepLink = MapLink.spot(spot)
        } else {
            appState.pendingDeepLink = MapLink.point(place, title: speciesName)
        }
    }

    // MARK: - Gear

    private var lureName: String? {
        guard let lure = detail.gearLoadout?.lure, !lure.isEmpty else { return nil }
        return lure
    }

    @ViewBuilder
    private var gearSection: some View {
        let rows = gearRows
        if lureName != nil || !rows.isEmpty {
            SectionTitle("Gear", detail: gearSetName)
                .padding(.top, DS.Space.s8)
            if let lureName {
                ArtRow(over: "Lure", title: lureName, subtitle: lureDetail) {
                    LureArtView(name: lureName, size: 56)
                }
            }
            if !rows.isEmpty {
                KeyValueList(rows: rows)
                    .padding(.top, lureName == nil ? 0 : DS.Space.s2)
            }
        }
    }

    /// The saved preset's name, when the angler picked one.
    private var gearSetName: String? {
        guard let gear = detail.gearLoadout, !gear.isAutoCreated else { return nil }
        return gear.name
    }

    /// "Chartreuse, 7 g" under the lure's name.
    private var lureDetail: String? {
        guard let g = detail.gearLoadout else { return nil }
        let parts = [g.lureColor.flatMap { $0.isEmpty ? nil : Self.sentenceCase($0) },
                     g.lureWeightG.map { Units.lureWeight(grams: $0, imperial: imperial) }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private var gearRows: [(String, String)] {
        var rows: [(String, String)] = []
        if let g = detail.gearLoadout {
            if let rod = g.rod, !rod.isEmpty { rows.append(("Rod", rod)) }
            if let reel = g.reel, !reel.isEmpty { rows.append(("Reel", reel)) }
            if let line = g.lineLb { rows.append(("Line", "\(Int(line)) lb")) }
            if let leader = g.leaderLb { rows.append(("Leader", "\(Int(leader)) lb")) }
            if let technique = g.technique, !technique.isEmpty { rows.append(("Technique", technique)) }
        }
        return rows
    }

    // MARK: - Conditions

    private var weather: WeatherSnapshot? {
        guard let json = record.weatherSnapshot, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WeatherSnapshot.self, from: data)
    }

    /// The conditions saved with the catch, plus the tide and moon predicted
    /// for its place and time. Only what is known; nothing is padded out.
    private var conditionItems: [ConditionItem] {
        let wx = weather
        var items: [ConditionItem] = []
        if let water = wx?.waterTempC {
            items.append(ConditionItem(label: "Water", systemImage: "drop.fill", iconTint: .exploreWater,
                                       value: Units.temperature(water, imperial: imperial),
                                       footnote: waterFootnote(water)))
        }
        if let air = wx?.temperatureC {
            let sky = wx?.condition.flatMap { $0.isEmpty ? nil : $0 }
            items.append(ConditionItem(label: "Air",
                                       systemImage: sky.map { WeatherIcon(condition: $0).systemName } ?? "thermometer.medium",
                                       value: Units.temperature(air, imperial: imperial),
                                       footnote: sky.map { Self.sentenceCase($0) }))
        }
        if let wind = wx?.windSpeedKmh {
            let speed = CatchStat("Wind", measured: Units.speed(kmh: wind, imperial: imperial))
            items.append(ConditionItem(label: "Wind", systemImage: "wind",
                                       value: speed.value, unit: speed.unit,
                                       footnote: wx?.windDirectionDeg.map { "From the \(Self.compassName($0))" }))
        }
        if let pressure = wx?.pressureHpa {
            let level = pressure < 1009 ? "Low" : (pressure > 1022 ? "High" : "Normal")
            let reading = Units.pressureParts(hpa: pressure, imperial: imperial)
            items.append(ConditionItem(label: "Pressure", systemImage: "gauge.with.dots.needle.33percent",
                                       value: reading.0, unit: reading.1, footnote: level))
        }
        if let rising = tideRising {
            items.append(ConditionItem(label: "Tide",
                                       systemImage: rising ? "water.waves.and.arrow.up" : "water.waves.and.arrow.down",
                                       iconTint: .exploreWater,
                                       value: rising ? "Rising" : "Falling", footnote: "Predicted"))
        }
        if let solunar {
            items.append(lightItem(solunar))
            items.append(biteItem(solunar))
        }
        if let clarity = record.clarity {
            items.append(ConditionItem(label: "Water clarity", systemImage: "eye", value: clarity.label))
        }
        return items
    }

    /// Dawn, daylight, dusk or night at the catch time, with the sun time it
    /// was nearest.
    private func lightItem(_ day: SolunarEngine.SolunarDay) -> ConditionItem {
        let at = record.caughtAt
        let clock = use24
        let time: (Date) -> String = { ForecastFormat.time($0, use24: clock) }
        if day.dawnGoldenHour.contains(at) {
            return ConditionItem(label: "Light", systemImage: "sunrise.fill", iconTint: .orange,
                                 value: "Dawn", footnote: "Sunrise \(time(day.sunrise))")
        }
        if day.duskGoldenHour.contains(at) {
            return ConditionItem(label: "Light", systemImage: "sunset.fill", iconTint: .orange,
                                 value: "Dusk", footnote: "Sunset \(time(day.sunset))")
        }
        if at > day.sunrise && at < day.sunset {
            return ConditionItem(label: "Light", systemImage: "sun.max.fill", iconTint: DS.ink(.dsScoreFair),
                                 value: "Daylight", footnote: "Sunset \(time(day.sunset))")
        }
        return ConditionItem(label: "Light", systemImage: "moon.stars.fill", iconTint: .indigo,
                             value: "Night", footnote: "Sunrise \(time(day.sunrise))")
    }

    /// Whether the catch landed in a solunar feeding period, or how far it
    /// was from the nearest one.
    private func biteItem(_ day: SolunarEngine.SolunarDay) -> ConditionItem {
        let at = record.caughtAt
        if let major = day.majorPeriods.first(where: { ($0.start...$0.end).contains(at) }) {
            return ConditionItem(label: "Bite period", systemImage: "fish.fill", iconTint: .green,
                                 value: "Major", footnote: Self.sentenceCase(major.kind.rawValue))
        }
        if let minor = day.minorPeriods.first(where: { ($0.start...$0.end).contains(at) }) {
            return ConditionItem(label: "Bite period", systemImage: "fish.fill", iconTint: .teal,
                                 value: "Minor", footnote: Self.sentenceCase(minor.kind.rawValue))
        }
        let all = day.majorPeriods + day.minorPeriods
        let gap = all.map { min(abs($0.start.timeIntervalSince(at)), abs($0.end.timeIntervalSince(at))) }.min()
        let footnote = gap.map { g -> String in
            let minutes = Int((g / 60).rounded())
            return minutes < 90 ? "\(minutes) min off a bite period" : "\(Int((g / 3600).rounded())) h off a bite period"
        }
        return ConditionItem(label: "Bite period", systemImage: "fish", iconTint: .dsText2,
                             value: "Between", footnote: footnote)
    }

    /// A catch saved without weather (logged offline, imported, or logged
    /// later) gets the hour's weather from the archive once, saved with it.
    private func backfillWeather() async {
        guard record.weatherSnapshot == nil, hasCoordinate,
              record.caughtAt < Date.now.addingTimeInterval(-600),
              let hour = await WeatherService.shared.pastHour(at: record.caughtAt, for: catchCoordinate)
        else { return }
        let snap = WeatherSnapshot(temperatureC: hour.temperatureC, waterTempC: nil,
                                   windSpeedKmh: hour.windSpeedKmh, windDirectionDeg: hour.windDirectionDeg,
                                   pressureHpa: hour.pressureHpa, condition: hour.condition)
        guard let json = (try? JSONEncoder().encode(snap)).flatMap({ String(data: $0, encoding: .utf8) }),
              detail.catchRecord.weatherSnapshot == nil else { return }
        var updated = detail.catchRecord
        updated.weatherSnapshot = json
        guard (try? appState.catchRepository.save(&updated)) != nil else { return }
        detail.catchRecord = updated
    }

    private var solunar: SolunarEngine.SolunarDay? {
        hasCoordinate ? SolunarEngine.compute(date: record.caughtAt, coordinate: catchCoordinate) : nil
    }

    /// Rising or falling at the catch time, predicted for coastal species only.
    private var tideRising: Bool? {
        let coastal = detail.species?.habitat == .marine || detail.species?.habitat == .brackish
        guard hasCoordinate, coastal else { return nil }
        let tide = TideEngine.predict(date: record.caughtAt, coordinate: catchCoordinate)
        let at = record.caughtAt
        let point = tide.points.min { abs($0.time.timeIntervalSince(at)) < abs($1.time.timeIntervalSince(at)) }
        return point?.isRising
    }

    @ViewBuilder
    private var conditionsSection: some View {
        let items = conditionItems
        if !items.isEmpty {
            SectionTitle("Conditions at the time")
                .padding(.top, DS.Space.s8)
            CatchConditionGrid(items: items)
            SectionFootnote("Weather is from the hour you caught it. Light, bite period and tide are worked out for the spot.")
        }
    }

    private func waterFootnote(_ water: Double) -> String? {
        guard let lo = detail.species?.minTempC, let hi = detail.species?.maxTempC, hi > lo else { return nil }
        if water < lo { return "\(Units.temperatureDelta(lo - water, imperial: imperial)) below their range" }
        if water > hi { return "\(Units.temperatureDelta(water - hi, imperial: imperial)) above their range" }
        return "In their range"
    }

    static func compassName(_ degrees: Double) -> String {
        let names = ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"]
        let i = Int(((degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 45).rounded()) % 8
        return names[i]
    }

    static func sentenceCase(_ text: String) -> String {
        let lower = text.lowercased()
        return lower.prefix(1).uppercased() + lower.dropFirst()
    }

    // MARK: - Notes

    @ViewBuilder
    private var notesSection: some View {
        SectionTitle("Notes")
            .padding(.top, DS.Space.s8)
        if let notes = record.notes, !notes.isEmpty {
            Text(notes)
                .font(.body)
                .foregroundStyle(.dsText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.gutter)
        } else {
            Button {
                showingEdit = true
            } label: {
                ArtRow(title: "Add a note",
                       subtitle: "What worked, what the water looked like") {
                    ThumbView(systemImage: "square.and.pencil", tint: DS.accent, size: 44)
                }
            }
            .buttonStyle(.dsRow)
        }
    }

    // MARK: - Session and Fishdex

    @ViewBuilder
    private var linksSection: some View {
        let showTrip = FeatureFlags.liveTrips && trip != nil
        if showTrip || detail.species != nil {
            VStack(spacing: 0) {
                if FeatureFlags.liveTrips, let trip {
                    NavigationLink {
                        SessionDetailView(trip: trip)
                    } label: {
                        ArtRow(over: "Session", title: trip.name,
                               subtitle: "\(LogbookFormat.shortDay(trip.startDate)), \(LogbookFormat.duration(trip.totalDurationSeconds))",
                               chevron: true) {
                            TrackThumb(points: trip.allTrackPoints, size: 52)
                        }
                    }
                    .buttonStyle(.dsRow)
                }
                if let species = detail.species {
                    NavigationLink {
                        SpeciesDetailView(species: species)
                    } label: {
                        ArtRow(over: "Fishdex", title: species.commonName,
                               subtitle: speciesCatchCount == 1 ? "1 caught" : "\(speciesCatchCount) caught",
                               chevron: true) {
                            ThumbView(species: species, size: 52)
                        }
                    }
                    .buttonStyle(.dsRow)
                }
            }
            .padding(.top, DS.Space.s8)
        }
    }

    // MARK: - Species ID

    private var predictions: [MLPrediction] {
        guard let json = record.mlTop3, let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([MLPrediction].self, from: data) else { return [] }
        return decoded
    }

    @ViewBuilder
    private var predictionsSection: some View {
        let matches = predictions
        if matches.count > 1 {
            SectionTitle("Species ID")
                .padding(.top, DS.Space.s8)
            VStack(spacing: DS.Space.s3) {
                ForEach(Array(matches.enumerated()), id: \.offset) { i, p in
                    ConfidenceBar(label: p.label, confidence: p.confidence,
                                  tint: i == 0 ? tint : Color.dsText3)
                }
            }
            .padding(.horizontal, DS.gutter)
            SectionFootnote("Identified on your phone when you logged it.")
        } else if let confidence = record.mlConfidence {
            SectionTitle("Species ID")
                .padding(.top, DS.Space.s8)
            KeyValueList(rows: [("Identified on your phone", "\(Int((confidence * 100).rounded()))%")])
        }
    }
}

// MARK: - Conditions grid

/// One condition tile's content.
private struct ConditionItem: Identifiable {
    let label: String
    let systemImage: String
    var iconTint: Color = .dsText2
    let value: String
    var unit: String? = nil
    var footnote: String? = nil
    var id: String { label }
}

/// The conditions as the app's condition tiles, two across (one at
/// accessibility sizes), as on Today and the spot pages.
private struct CatchConditionGrid: View {
    let items: [ConditionItem]
    @Environment(\.dynamicTypeSize) private var typeSize

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: DS.Space.s3),
              count: typeSize.isAccessibilitySize ? 1 : 2)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: DS.Space.s3) {
            ForEach(items) { item in
                ConditionTile(item.label, systemImage: item.systemImage, iconTint: item.iconTint,
                              value: item.value, unit: item.unit, footnote: item.footnote)
            }
        }
        .padding(.horizontal, DS.gutter)
    }
}

// MARK: - Small visuals

/// A species match with its confidence as a proportional bar.
private struct ConfidenceBar: View {
    let label: String
    let confidence: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.dsText)
                    .lineLimit(1)
                Spacer()
                Text("\(Int((confidence * 100).rounded()))%")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.dsText)
            }
            Capsule()
                .fill(Color.dsFill)
                .frame(height: 8)
                .overlay(alignment: .leading) {
                    // Sized from the track it sits in, so it never overflows.
                    GeometryReader { geo in
                        Capsule()
                            .fill(tint)
                            .frame(width: max(8, geo.size.width * CGFloat(min(1, max(0, confidence)))))
                    }
                }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Gear grid

struct GearDetailGrid: View {
    let loadout: GearLoadout

    var items: [(String, String)] {
        var result: [(String, String)] = []
        if let rod = loadout.rod { result.append(("Rod", rod)) }
        if let reel = loadout.reel { result.append(("Reel", reel)) }
        if let line = loadout.lineLb { result.append(("Line", "\(Int(line)) lb")) }
        if let leader = loadout.leaderLb { result.append(("Leader", "\(Int(leader)) lb")) }
        if let lure = loadout.lure {
            var text = lure
            if let color = loadout.lureColor { text += " (\(color))" }
            if let weight = loadout.lureWeightG { text += " \(Int(weight))g" }
            result.append(("Lure", text))
        }
        if let technique = loadout.technique { result.append(("Technique", technique)) }
        return result
    }

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
        ], spacing: 8) {
            ForEach(items, id: \.0) { label, value in
                VStack(alignment: .leading) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Weather Snapshot (for decoding weatherSnapshot JSON)

private struct WeatherSnapshot: Codable {
    var temperatureC: Double?
    var waterTempC: Double?
    var windSpeedKmh: Double?
    var windDirectionDeg: Double?
    var pressureHpa: Double?
    var condition: String?
}

// MARK: - ML Prediction (for decoding mlTop3 JSON)

private struct MLPrediction: Codable {
    var label: String
    var confidence: Double
}
