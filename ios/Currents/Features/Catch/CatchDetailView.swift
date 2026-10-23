import SwiftUI
import MapKit

/// A catch's page: cover, title block, Share / Edit / Favourite, then grouped
/// rows for the catch itself, the conditions at the time and the gear, the
/// size and bag rules, notes, the map and spot, and links to its session and
/// Fishdex entry. Tinted with the species' art colour.
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
            content
                .padding(.bottom, DS.Space.s8)
                .pageWidth()
        }
        .detailTint(detail.species?.artTint)
        .navigationTitle(speciesName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { moreMenu }
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

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            cover
                .padding(.horizontal, DS.gutter)
                .padding(.top, DS.Space.s2)

            DetailHeader(over: "\(LogbookFormat.longDay(record.caughtAt)), \(LogbookFormat.time(record.caughtAt))",
                         title: speciesName,
                         subtitle: detail.species?.scientificName)
                .padding(.top, DS.Space.s4)

            if isPersonalBest {
                Label("Personal best", systemImage: "trophy.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.dsText)
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, DS.Space.s2)
            }

            actions
                .padding(.top, DS.Space.s5)

            catchSection
            regulationNote
            conditionsSection
            gearSection
            notesSection
            spotSection
            linksSection
            predictionsSection

            DangerButton(title: "Delete catch", systemImage: "trash") {
                showingDeleteConfirm = true
            }
            .padding(.top, DS.Space.s8)
        }
    }

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
        } else if let image = photos.first {
            coverPhoto(image)
                .frame(height: 340)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
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

    // MARK: - The catch

    private var catchRows: [KeyValueList.Row] {
        var rows: [KeyValueList.Row] = []
        if let cm = record.lengthCm {
            rows.append(.init(label: "Length", value: Units.length(cm: cm, imperial: imperial)))
        }
        if let kg = record.weightKg {
            rows.append(.init(label: "Weight", value: Units.weight(kg: kg, imperial: imperial)))
        }
        rows.append(.init(label: "Caught", value: "\(LogbookFormat.shortDay(record.caughtAt)), \(LogbookFormat.time(record.caughtAt))"))
        rows.append(.init(label: "Kept or released", value: record.released ? "Released" : "Kept"))
        if let score = record.forecastScoreAtCapture {
            rows.append(.init(label: "Bite score", value: "\(score) of 100"))
        }
        if let confidence = record.mlConfidence {
            rows.append(.init(label: "Identified on your phone", value: "\(Int((confidence * 100).rounded()))%"))
        }
        return rows
    }

    private var catchSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("The catch")
            KeyValueList(rows: catchRows)
        }
        .padding(.top, DS.Space.s8)
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
            SectionTitle("Where")
                .padding(.top, DS.Space.s8)
            if hasCoordinate {
                catchMap
                    .padding(.horizontal, DS.gutter)
            }
            if let spot = detail.spot {
                // The spot opens on the Explore map in its sheet.
                Button { appState.pendingDeepLink = MapLink.spot(spot) } label: {
                    ArtRow(over: "Spot", title: spot.name,
                           subtitle: spot.type == .general ? nil : spot.type.rawValue,
                           chevron: true) {
                        PlaceSnapshotThumb(spot: spot, size: 52)
                    }
                }
                .buttonStyle(.dsRow)
                .padding(.top, DS.Space.s2)
            }
            if hasCoordinate {
                DirectionsButton(coordinate: catchCoordinate,
                                 name: detail.spot?.name ?? speciesName)
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, DS.Space.s3)
            }
        }
    }

    private var catchMap: some View {
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

    private var conditionRows: [KeyValueList.Row] {
        let wx = weather
        var rows: [KeyValueList.Row] = []
        if let water = wx?.waterTempC {
            let note = waterFootnote(water).map { ", \($0.lowercased())" } ?? ""
            rows.append(.init(label: "Water", value: degrees(water) + note))
        }
        if let air = wx?.temperatureC {
            let sky = wx?.condition.map { ", \($0.lowercased())" } ?? ""
            rows.append(.init(label: "Air", value: degrees(air) + sky))
        }
        if let wind = wx?.windSpeedKmh {
            let speed = "\(Int((imperial ? wind * 0.621371 : wind).rounded())) \(Units.speedSymbol)"
            let from = wx?.windDirectionDeg.map { ", from the \(Self.compassName($0))" } ?? ""
            rows.append(.init(label: "Wind", value: speed + from))
        }
        if let pressure = wx?.pressureHpa {
            let level = pressure < 1009 ? "low" : (pressure > 1022 ? "high" : "normal")
            rows.append(.init(label: "Pressure", value: "\(Int(pressure.rounded())) hPa, \(level)"))
        }
        if let clarity = record.clarity {
            rows.append(.init(label: "Water clarity", value: clarity.label))
        }
        if let tide = tideState {
            rows.append(.init(label: "Tide", value: tide))
        }
        if let solunar = solunar {
            let lit = Int((solunar.moonIllumination * 100).rounded())
            rows.append(.init(label: "Moon", value: "\(Self.sentenceCase(solunar.moonPhase.displayName)), \(lit)%"))
        }
        return rows
    }

    private var solunar: SolunarEngine.SolunarDay? {
        hasCoordinate ? SolunarEngine.compute(date: record.caughtAt, coordinate: catchCoordinate) : nil
    }

    /// Rising or falling at the catch time, predicted for coastal species only.
    private var tideState: String? {
        let coastal = detail.species?.habitat == .marine || detail.species?.habitat == .brackish
        guard hasCoordinate, coastal else { return nil }
        let tide = TideEngine.predict(date: record.caughtAt, coordinate: catchCoordinate)
        let at = record.caughtAt
        let point = tide.points.min { abs($0.time.timeIntervalSince(at)) < abs($1.time.timeIntervalSince(at)) }
        return point.map { $0.isRising ? "Rising" : "Falling" }
    }

    @ViewBuilder
    private var conditionsSection: some View {
        let rows = conditionRows
        if !rows.isEmpty {
            SectionTitle("Conditions at the time")
                .padding(.top, DS.Space.s8)
            KeyValueList(rows: rows)
            SectionFootnote("Saved when you logged it. Tide and moon are predicted for the spot.")
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
            SectionFootnote("Identified on your phone when you logged it.")
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
