import SwiftUI
import MapKit

/// A catch's page: cover, title block, Share / Edit / Favourite, size, the
/// size and bag rules, the spot, gear, conditions at the time, notes, and
/// links to its session and Fishdex entry.
struct CatchDetailView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("units") private var units = "metric"
    private var imperial: Bool { units == "imperial" }
    @Environment(\.dismiss) private var dismiss
    @State private var detail: CatchDetail
    @State private var showingDeleteConfirm = false
    @State private var showingEdit = false
    @State private var isGeneratingShareCard = false
    @State private var shareItem: CatchShareItem?
    @State private var trip: Trip?
    @State private var showingPhotoViewer = false
    @State private var carouselIndex = 0
    @State private var isFavorite = false
    @State private var photos: [UIImage] = []
    @State private var speciesCatchCount = 0
    @State private var isPersonalBest = false

    init(detail: CatchDetail) {
        _detail = State(initialValue: detail)
    }

    private var record: Catch { detail.catchRecord }
    private var speciesName: String { detail.species?.commonName ?? "Unknown species" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                cover
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, DS.Space.s2)

                DetailHeader(over: "\(LogbookFormat.longDay(record.caughtAt)), \(LogbookFormat.time(record.caughtAt))",
                             title: speciesName,
                             subtitle: detail.species?.scientificName)
                    .padding(.top, DS.Space.s4)

                tags
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, DS.Space.s3)

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
                .padding(.top, DS.Space.s5)

                measureTiles
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, DS.Space.s6)

                regulationNote

                spotSection

                gearSection

                conditionsSection

                notesSection

                linksSection

                predictionsSection

                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete catch", systemImage: "trash")
                        .foregroundStyle(Color.dsScoreSlow)
                }
                .buttonStyle(.dsTonal)
                .padding(.horizontal, DS.gutter)
                .padding(.top, DS.Space.s8)
            }
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
        }
        .detailTint(detail.species?.artTint ?? DS.accent)
        .navigationTitle(speciesName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
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
                    let svc = CommunityService.shared
                    if svc.joined, !svc.myCrews.isEmpty {
                        Menu {
                            ForEach(svc.myCrews) { crew in
                                Button(crew.name) {
                                    let posted = detail.catchRecord
                                    let name = speciesName
                                    Task {
                                        await svc.postCatch(posted, speciesName: name,
                                                            toCrew: crew.code, caption: "")
                                        ToastCenter.shared.show("Shared to \(crew.name)")
                                    }
                                }
                            }
                        } label: {
                            Label("Share to crew", systemImage: "person.3")
                        }
                    }
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
        }
        .confirmationDialog("Delete this catch?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Delete catch", role: .destructive) {
                Haptics.warning()
                CatchActions.delete(detail, appState: appState)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(speciesName), \(LogbookFormat.shortDay(record.caughtAt)). Its photos go too, including from shared feeds. This can't be undone.")
        }
        .fullScreenCover(isPresented: $showingEdit) {
            LogCatchView(editing: detail) { updated in
                let saved = CatchActions.saveEdit(updated, appState: appState)
                reload(with: saved)
            }
        }
        .sheet(item: $shareItem) { item in
            ImageShareSheet(image: item.image, filename: item.filename)
        }
        .fullScreenCover(isPresented: $showingPhotoViewer) {
            FullscreenPhotoViewer(
                photoPaths: detail.catchRecord.allPhotoPaths,
                currentIndex: carouselIndex
            )
        }
        .task(id: detail.catchRecord.id) {
            await load()
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

    // MARK: - Cover

    @ViewBuilder
    private var cover: some View {
        if photos.count > 1 {
            TabView(selection: $carouselIndex) {
                ForEach(Array(photos.enumerated()), id: \.offset) { index, image in
                    coverPhoto(image)
                        .tag(index)
                }
            }
            .tabViewStyle(.page)
            .frame(height: 340)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .overlay(alignment: .topTrailing) { expandButton }
        } else if let image = photos.first {
            coverPhoto(image)
                .frame(height: 340)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                .overlay(alignment: .topTrailing) { expandButton }
        } else if let species = detail.species {
            // No photo: the species art on its colour, so the catch still
            // reads visually.
            SpeciesArtworkView(species: species, caught: true, size: 200)
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .background(species.artTint.opacity(0.18),
                            in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        }
    }

    private func coverPhoto(_ image: UIImage) -> some View {
        Color.clear
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { showingPhotoViewer = true }
            .accessibilityElement()
            .accessibilityLabel("Photo of the catch")
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens the photo full screen")
    }

    private var expandButton: some View {
        Button {
            showingPhotoViewer = true
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .glassEffect(.regular.interactive(), in: Circle())
        }
        .buttonStyle(.plain)
        .padding(10)
        .accessibilityLabel("Show photo full screen")
    }

    // MARK: - Title tags

    private var tags: some View {
        FlowTags(spacing: 6) {
            tag(record.released ? "Released" : "Kept", systemImage: nil)
            if let confidence = record.mlConfidence {
                tag("Identified on your phone, \(Int(confidence * 100))%", systemImage: nil)
            }
            if isPersonalBest {
                tag("Personal best", systemImage: "trophy.fill")
            }
        }
    }

    private func tag(_ text: String, systemImage: String?) -> some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.dsScoreFair)
            }
            Text(text)
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(.dsText)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.dsFill, in: Capsule())
    }

    // MARK: - Size

    @ViewBuilder
    private var measureTiles: some View {
        let length = record.lengthCm.map { Units.lengthParts(cm: $0, imperial: imperial) }
        let weight = record.weightKg.map { Units.weightParts(kg: $0, imperial: imperial) }
        let score = record.forecastScoreAtCapture
        if length != nil || weight != nil || score != nil {
            HStack(spacing: 10) {
                StatTile("Length", systemImage: "ruler", tint: .dsText2,
                         value: length?.0 ?? "None", unit: length?.1, width: nil)
                StatTile("Weight", systemImage: "scalemass", tint: .dsText2,
                         value: weight?.0 ?? "None", unit: weight?.1, width: nil)
                if let score {
                    StatTile("Bite score", systemImage: "gauge.medium", tint: DS.scoreColor(score),
                             value: "\(score)", width: nil)
                }
            }
        }
    }

    // MARK: - Regulation

    @ViewBuilder
    private var regulationNote: some View {
        let result = RegulationsService.shared.verdict(
            species: detail.species,
            lengthCm: record.lengthCm
        )
        if let reg = result.reg {
            let warn: Bool = {
                switch result.verdict {
                case .tooSmall, .tooBig: return true
                default: return false
                }
            }()
            let text: String = {
                var parts: [String] = []
                switch result.verdict {
                case .legal:
                    if let mn = reg.minSizeCm {
                        parts.append("Legal size to keep in \(reg.region), minimum \(Units.length(cm: mn, imperial: imperial)).")
                    } else {
                        parts.append("Legal size to keep in \(reg.region).")
                    }
                case .tooSmall(let mn):
                    parts.append("Undersized. The minimum to keep in \(reg.region) is \(Units.length(cm: mn, imperial: imperial)).")
                case .tooBig(let mx):
                    parts.append("Over the slot. The maximum to keep in \(reg.region) is \(Units.length(cm: mx, imperial: imperial)).")
                case .unknownSize:
                    parts.append("Add a length to check it against the \(reg.region) limit.")
                case .noRegulation:
                    break
                }
                if let bag = reg.bagLimit { parts.append("Bag limit \(bag) per person per day.") }
                if let closed = reg.closedSeason, !closed.isEmpty { parts.append("Closed season: \(closed).") }
                return parts.joined(separator: " ")
            }()
            if !text.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: warn ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                        .foregroundStyle(warn ? Color.dsScoreSlow : Color.dsScoreGood)
                        .font(.body)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(text)
                            .font(.subheadline)
                            .foregroundStyle(.dsText)
                        Text("Check local rules before you keep a fish.")
                            .font(.footnote)
                            .foregroundStyle(.dsText2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(14)
                .background((warn ? Color.dsScoreSlow.opacity(0.12) : Color.dsFill),
                            in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
                .padding(.horizontal, DS.gutter)
                .padding(.top, DS.Space.s4)
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - Spot

    private var hasCoordinate: Bool { record.latitude != 0 || record.longitude != 0 }

    private var catchCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: record.latitude, longitude: record.longitude)
    }

    @ViewBuilder
    private var spotSection: some View {
        if hasCoordinate || detail.spot != nil {
            SectionTitle("Spot")
                .padding(.top, DS.Space.s8)
            if let spot = detail.spot {
                // The spot opens on the Explore map in its sheet.
                Button { appState.pendingDeepLink = MapLink.spot(spot) } label: {
                    ArtRow(title: spot.name,
                           subtitle: spot.type == .general ? nil : spot.type.rawValue,
                           chevron: true) {
                        PlaceSnapshotThumb(spot: spot, size: 52)
                    }
                }
                .buttonStyle(.dsRow)
            }
            if hasCoordinate {
                Map(initialPosition: .camera(.init(centerCoordinate: catchCoordinate, distance: 2000))) {
                    Annotation("", coordinate: catchCoordinate) {
                        Image(systemName: "fish.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white, detail.species?.artTint ?? DS.accent)
                    }
                }
                .mapStyle(.hybrid)
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                .allowsHitTesting(false)
                .accessibilityLabel("Map of where it was caught")
                .padding(.horizontal, DS.gutter)
                .padding(.top, DS.Space.s2)

                DirectionsButton(coordinate: catchCoordinate,
                                 name: detail.spot?.name ?? speciesName)
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, DS.Space.s3)
            }
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
            SectionTitle("Gear")
                .padding(.top, DS.Space.s8)
            if let gear = detail.gearLoadout, !gear.isAutoCreated {
                Text(gear.name)
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                    .padding(.horizontal, DS.gutter)
                    .padding(.bottom, DS.Space.s1)
            }
            if let lureName {
                ArtRow(over: "Lure", title: lureName, subtitle: lureDetail) {
                    LureArtView(name: lureName, size: 56)
                }
            }
            if !rows.isEmpty {
                LogbookKeyValueList(rows: rows)
            }
        }
    }

    /// "Chartreuse, 7 g" under the lure's name.
    private var lureDetail: String? {
        guard let g = detail.gearLoadout else { return nil }
        let parts = [g.lureColor.flatMap { $0.isEmpty ? nil : Self.sentenceCase($0) },
                     g.lureWeightG.map { "\(Int($0)) g" }].compactMap { $0 }
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
        if let depth = record.depthM { rows.append(("Depth", Units.depth(m: depth, imperial: imperial))) }
        return rows
    }

    // MARK: - Conditions

    private var weather: WeatherSnapshot? {
        guard let json = record.weatherSnapshot, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WeatherSnapshot.self, from: data)
    }

    private func degrees(_ celsius: Double) -> String {
        "\(Int((imperial ? celsius * 9 / 5 + 32 : celsius).rounded()))°"
    }

    @ViewBuilder
    private var conditionsSection: some View {
        let wx = weather
        let solunar = hasCoordinate ? SolunarEngine.compute(date: record.caughtAt, coordinate: catchCoordinate) : nil
        let coastal = detail.species?.habitat == .marine || detail.species?.habitat == .brackish
        let tide = (hasCoordinate && coastal) ? TideEngine.predict(date: record.caughtAt, coordinate: catchCoordinate) : nil
        let tidePoint = tide?.points.min { abs($0.time.timeIntervalSince(record.caughtAt)) < abs($1.time.timeIntervalSince(record.caughtAt)) }
        if wx != nil || solunar != nil || record.clarity != nil {
            SectionTitle("Conditions at the time")
                .padding(.top, DS.Space.s8)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                if let water = wx?.waterTempC {
                    ConditionTile("Water", systemImage: "thermometer.medium", iconTint: .dsScoreLow,
                                  value: degrees(water), footnote: waterFootnote(water)) {
                        if let lo = detail.species?.minTempC, let hi = detail.species?.maxTempC, hi > lo {
                            TempRangeBar(low: lo, high: hi, value: water)
                        }
                    }
                }
                if let wind = wx?.windSpeedKmh {
                    ConditionTile("Wind", systemImage: "wind", iconTint: .cyan,
                                  value: "\(Int((imperial ? wind * 0.621371 : wind).rounded()))",
                                  unit: Units.speedSymbol,
                                  footnote: wx?.windDirectionDeg.map { "From the \(Self.compassName($0))" }) {
                        if let dir = wx?.windDirectionDeg {
                            Image(systemName: "location.north.fill")
                                .font(.title2)
                                .foregroundStyle(.dsText2)
                                .rotationEffect(.degrees(dir + 180))
                                .accessibilityHidden(true)
                        }
                    }
                }
                if let pressure = wx?.pressureHpa {
                    ConditionTile("Pressure", systemImage: "gauge.with.dots.needle.33percent",
                                  iconTint: .purple,
                                  value: "\(Int(pressure.rounded()))", unit: "hPa",
                                  footnote: pressure < 1009 ? "Low" : (pressure > 1022 ? "High" : "Normal"))
                }
                if let clarity = record.clarity {
                    ConditionTile("Water clarity", systemImage: "drop.fill", iconTint: DS.accent,
                                  value: clarity.label, footnote: "Set when you logged it")
                } else if let tidePoint {
                    ConditionTile("Tide", systemImage: "water.waves", iconTint: .blue,
                                  value: tidePoint.isRising ? "Rising" : "Falling",
                                  footnote: "Predicted for the spot") {
                        if let tide {
                            TideSpark(points: tide.points, at: record.caughtAt)
                        }
                    }
                }
                if let solunar {
                    ConditionTile("Moon", systemImage: "moon.fill", iconTint: .dsScoreFair,
                                  value: "\(Int((solunar.moonIllumination * 100).rounded()))", unit: "%",
                                  footnote: Self.sentenceCase(solunar.moonPhase.displayName)) {
                        Image(systemName: solunar.moonPhase.symbolName)
                            .font(.title)
                            .foregroundStyle(.dsText2)
                            .accessibilityHidden(true)
                    }
                }
                if let air = wx?.temperatureC {
                    ConditionTile("Air", systemImage: "cloud.sun.fill", iconTint: .dsScoreLow,
                                  value: degrees(air), footnote: wx?.condition.map(Self.sentenceCase))
                }
            }
            .padding(.horizontal, DS.gutter)
            SectionFoot("Saved when you logged it.")
        }
    }

    private func waterFootnote(_ water: Double) -> String? {
        guard let lo = detail.species?.minTempC, let hi = detail.species?.maxTempC, hi > lo else { return nil }
        if water < lo { return "\(Int((lo - water).rounded()))° below their range" }
        if water > hi { return "\(Int((water - hi).rounded()))° above their range" }
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
                               subtitle: "\(speciesCatchCount) caught", chevron: true) {
                            ThumbView(species: species, size: 52)
                        }
                    }
                    .buttonStyle(.dsRow)
                }
            }
            .padding(.top, DS.Space.s6)
        }
    }

    // MARK: - Species ID

    @ViewBuilder
    private var predictionsSection: some View {
        if let json = record.mlTop3,
           let data = json.data(using: .utf8),
           let predictions = try? JSONDecoder().decode([MLPrediction].self, from: data),
           predictions.count > 1 {
            SectionTitle("Species ID")
                .padding(.top, DS.Space.s8)
            VStack(spacing: 12) {
                ForEach(Array(predictions.enumerated()), id: \.offset) { i, p in
                    ConfidenceBar(label: p.label, confidence: p.confidence,
                                  tint: i == 0 ? (detail.species?.artTint ?? DS.accent) : Color.dsText3)
                }
            }
            .padding(.horizontal, DS.gutter)
            SectionFoot("Identified on your phone when you logged it.")
        }
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

/// A species' comfortable temperature band with the reading as a dot.
private struct TempRangeBar: View {
    let low: Double
    let high: Double
    let value: Double

    var body: some View {
        GeometryReader { geo in
            let minT = min(low, value) - 4, maxT = max(high, value) + 4
            let span = max(maxT - minT, 1)
            let x: (Double) -> CGFloat = { CGFloat(($0 - minT) / span) * geo.size.width }
            ZStack(alignment: .leading) {
                Capsule().fill(Color.dsFill2).frame(height: 6)
                Capsule().fill(Color.dsScoreGood.opacity(0.7))
                    .frame(width: max(4, x(high) - x(low)), height: 6)
                    .offset(x: x(low))
                Circle().fill(Color.dsText)
                    .frame(width: 12, height: 12)
                    .offset(x: x(value) - 6)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 34)
        .accessibilityHidden(true)
    }
}

/// The day's tide curve with the catch time marked.
private struct TideSpark: View {
    let points: [TideEngine.TidePoint]
    let at: Date

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let n = max(points.count - 1, 1)
            Path { p in
                for (i, pt) in points.enumerated() {
                    let pos = CGPoint(x: CGFloat(i) / CGFloat(n) * w,
                                      y: h / 2 - CGFloat(pt.height) * (h / 2 - 3))
                    if i == 0 { p.move(to: pos) } else { p.addLine(to: pos) }
                }
            }
            .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            if let i = points.firstIndex(where: { $0.time >= at }) {
                Circle().fill(Color.dsText)
                    .frame(width: 8, height: 8)
                    .position(x: CGFloat(i) / CGFloat(n) * w,
                              y: h / 2 - CGFloat(points[i].height) * (h / 2 - 3))
            }
        }
        .frame(height: 34)
        .accessibilityHidden(true)
    }
}

/// Tags that wrap onto a new line when they run out of room.
private struct FlowTags: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = fitted(s, width)
            if x > 0 && x + size.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += size.width + spacing
            rowH = max(rowH, size.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: maxX, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let size = fitted(s, bounds.width)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }

    /// A tag's natural size, or wrapped to the row when it is wider.
    private func fitted(_ s: LayoutSubview, _ width: CGFloat) -> CGSize {
        let natural = s.sizeThatFits(.unspecified)
        guard natural.width > width, width.isFinite else { return natural }
        return s.sizeThatFits(ProposedViewSize(width: width, height: nil))
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
