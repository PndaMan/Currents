import SwiftUI
import MapKit
import GRDB

// MARK: - Routes

/// Pages the Explore stack pushes. Spot, Waterbody and BoatRamp are not
/// Hashable, so they travel in small wrappers keyed by their ids.
enum ExploreRoute: Hashable {
    case spot(SpotRef)
    case waterbody(WaterbodyRef)
    case species(Species)
    case catchDetail(CatchRef)
    case spots
    case waters
    case ramps
    case speciesGuide
    case regulations
    case offlineMaps
}

struct SpotRef: Hashable {
    let spot: Spot
    init(_ spot: Spot) { self.spot = spot }
    static func == (a: SpotRef, b: SpotRef) -> Bool { a.spot.id == b.spot.id }
    func hash(into hasher: inout Hasher) { hasher.combine(spot.id) }
}

struct WaterbodyRef: Hashable {
    let waterbody: Waterbody
    init(_ waterbody: Waterbody) { self.waterbody = waterbody }
    private var key: String { "\(waterbody.id ?? 0)-\(waterbody.name)-\(waterbody.latitude)" }
    static func == (a: WaterbodyRef, b: WaterbodyRef) -> Bool { a.key == b.key }
    func hash(into hasher: inout Hasher) { hasher.combine(key) }
}

struct CatchRef: Hashable {
    let detail: CatchDetail
    init(_ detail: CatchDetail) { self.detail = detail }
    static func == (a: CatchRef, b: CatchRef) -> Bool { a.detail.catchRecord.id == b.detail.catchRecord.id }
    func hash(into hasher: inout Hasher) { hasher.combine(detail.catchRecord.id) }
}

/// Resolves an `ExploreRoute` to its page. Registered once on the Explore root.
struct ExploreDestination: View {
    let route: ExploreRoute

    var body: some View {
        switch route {
        case .spot(let ref): SpotDetailView(spot: ref.spot)
        case .waterbody(let ref): WaterbodyDetailView(waterbody: ref.waterbody)
        case .species(let species): SpeciesDetailView(species: species)
        case .catchDetail(let ref): CatchDetailView(detail: ref.detail)
        case .spots: SpotsListView()
        case .waters: WaterListView()
        case .ramps: RampListView()
        case .speciesGuide: SpeciesBrowserView()
        case .regulations: RegulationsView()
        case .offlineMaps: OfflineMapsView()
        }
    }
}

// MARK: - Formatting

enum ExploreFormat {
    static func hour(_ h: Int, use24Hour: Bool) -> String {
        let hh = ((h % 24) + 24) % 24
        if use24Hour { return String(format: "%02d:00", hh) }
        let suffix = hh < 12 ? "am" : "pm"
        let display = hh % 12 == 0 ? 12 : hh % 12
        return "\(display) \(suffix)"
    }

    static func window(_ w: BiteWindows.Window?, use24Hour: Bool) -> String {
        guard let w else { return "No strong window" }
        return "\(hour(w.startHour, use24Hour: use24Hour)) to \(hour(w.endHour + 1, use24Hour: use24Hour))"
    }

    /// Luma-style verdict for a bite score, matching Today.
    static func verdict(_ score: Int) -> String {
        switch score {
        case 80...: "Excellent, go now"
        case 65..<80: "Good"
        case 50..<65: "Fair, work for them"
        default: "Slow, finesse it"
        }
    }

    static func distance(from origin: CLLocationCoordinate2D?, to target: CLLocationCoordinate2D) -> String? {
        guard let origin else { return nil }
        let m = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
            .distance(from: CLLocation(latitude: target.latitude, longitude: target.longitude))
        return Units.distance(m: m)
    }

    static func coords(_ c: CLLocationCoordinate2D) -> String {
        String(format: "%.4f, %.4f", c.latitude, c.longitude)
    }

    static func waterType(_ type: Waterbody.WaterbodyType) -> String {
        switch type {
        case .dam: "Dam"
        case .lake: "Lake"
        case .river: "River"
        case .estuary: "Estuary"
        case .coast: "Coast"
        }
    }

    static func waterIcon(_ type: Waterbody.WaterbodyType) -> String {
        switch type {
        case .lake: "water.waves"
        case .dam: "water.waves.and.arrow.down"
        case .river: "arrow.triangle.pull"
        case .estuary: "arrow.triangle.merge"
        case .coast: "sailboat.fill"
        }
    }

    static func spotType(_ spot: Spot) -> String {
        spot.type == .general ? "Spot" : spot.type.rawValue
    }

    static func habitat(_ h: Species.Habitat?) -> String {
        switch h {
        case .freshwater: "Freshwater"
        case .marine: "Saltwater"
        case .brackish: "Brackish"
        case nil: "Fish"
        }
    }

    static func area(_ km2: Double) -> String {
        if km2 >= 1000 { return String(format: "%.0f km²", km2) }
        if km2 >= 1 { return String(format: "%.1f km²", km2) }
        return String(format: "%.0f ha", km2 * 100)
    }

    /// Fishing access in the accent, ramps in teal, wherever they are drawn as thumbs.
    static func placeTint(_ kind: BoatRamp.Kind) -> Color {
        kind == .access ? DS.accent : .teal
    }

    /// Eight-point compass, "NW".
    static func compass(_ degrees: Double) -> String {
        let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let i = Int(((degrees.truncatingRemainder(dividingBy: 360) + 360 + 22.5) / 45)) % 8
        return names[i]
    }

    /// Plain sentences from engine and data copy: dashes become full stops
    /// and each part starts with a capital, as in "Yo-yo it over grass. Most
    /// bites come as it falls." Also turns "live worms" into "Live worms".
    static func sentence(_ text: String) -> String {
        let parts = text
            .replacingOccurrences(of: "\u{2014}", with: "|")
            .replacingOccurrences(of: "\u{2013} ", with: "| ")
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { part -> String in
                var p = part
                if p.hasSuffix(".") { p.removeLast() }
                return p.prefix(1).uppercased() + p.dropFirst()
            }
        guard !parts.isEmpty else { return text }
        let joined = parts.joined(separator: ". ")
        return text.hasSuffix(".") || parts.count > 1 ? joined + "." : joined
    }

    static func shortDate(_ d: Date) -> String {
        d.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

// MARK: - Bite snapshot

/// Today's bite at a coordinate: the score right now, the day's peak, the
/// hourly curve and its best windows. Worked out on the phone from cached
/// weather, so it works offline.
struct BiteSnapshot {
    let now: Int
    let day: Int
    let hourly: [(hour: Int, score: Int)]
    let windows: [BiteWindows.Window]
    let reasons: [String]

    var best: BiteWindows.Window? { windows.max { $0.peakScore < $1.peakScore } }

    init(_ f: ForecastEngine.ForecastResult) {
        now = f.score
        hourly = f.hourlyScores.sorted { $0.hour < $1.hour }
        day = max(f.score, hourly.map(\.score).max() ?? f.score)
        windows = BiteWindows.best(from: f.hourlyScores)
        reasons = f.reasons
    }

    static func load(at coord: CLLocationCoordinate2D) async -> (BiteSnapshot, WeatherService.WeatherData?) {
        let w = await WeatherService.shared.current(for: coord)
        let f = ForecastEngine.forecast(
            coordinate: coord,
            currentPressureHpa: w?.pressureHpa,
            pressureChange6h: w?.pressureChange6h,
            waterTempC: w?.waterTempC,
            windSpeedKmh: w?.windSpeedKmh,
            windDirection: w?.windDirectionDeg,
            species: nil,
            isInSpawningZone: false
        )
        return (BiteSnapshot(f), w)
    }
}

// MARK: - Small components

/// A plain label and value row, Luma's key-value list.
struct KVRow: View {
    let label: String
    let value: String
    var showsDivider = true

    init(_ label: String, _ value: String, divider: Bool = true) {
        self.label = label
        self.value = value
        self.showsDivider = divider
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
                Text(label)
                    .foregroundStyle(.dsText2)
                Spacer(minLength: DS.Space.s3)
                Text(value)
                    .foregroundStyle(.dsText)
                    .multilineTextAlignment(.trailing)
            }
            .font(.body)
            .padding(.vertical, 12)
            if showsDivider {
                Rectangle().fill(Color.dsSeparator).frame(height: 0.5)
            }
        }
        .padding(.horizontal, DS.gutter)
        .accessibilityElement(children: .combine)
    }
}

/// Footnote under a section, in the gutter.
struct ExploreFootnote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.dsText2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.gutter)
            .padding(.top, DS.Space.s2)
    }
}

/// The small grey label above a group inside a sheet ("What is biting here").
struct GroupLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.dsText2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.gutter)
            .padding(.top, DS.Space.s5)
            .padding(.bottom, DS.Space.s1)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The score in a soft disc of its own colour.
struct ScoreDisc: View {
    let score: Int
    var size: CGFloat = 46
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text("\(score)")
            .font(.system(size > 42 ? .title3 : .headline, design: .rounded, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(DS.scoreInk(score))
            .contentTransition(.numericText())
            .frame(width: size, height: size)
            .background(DS.scoreColor(score).opacity(scheme == .dark ? 0.24 : 0.18), in: Circle())
            .accessibilityLabel("Bite score \(score) of 100")
    }
}

/// The tinted bite card in pin and location sheets: score disc, verdict and
/// one line about the day.
struct BiteBlock: View {
    let score: Int
    let title: String
    let detail: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 14) {
            ScoreDisc(score: score)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.dsText)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(DS.scoreColor(score).opacity(scheme == .dark ? 0.16 : 0.10),
                    in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .padding(.horizontal, DS.gutter)
        .accessibilityElement(children: .combine)
    }
}

/// A loading placeholder shaped like a sheet's content (the mockup's skeleton).
struct SheetSkeleton: View {
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(spacing: 14) {
                block(width: 64, height: 64, radius: DS.Radius.thumb)
                VStack(alignment: .leading, spacing: 8) {
                    block(width: 180, height: 16)
                    block(width: 120, height: 12)
                }
            }
            HStack(spacing: DS.Space.s2) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
                        .fill(Color.dsFill)
                        .frame(height: 62)
                }
            }
            block(width: 220, height: 14).padding(.top, DS.Space.s4)
            block(width: 280, height: 14)
        }
        .padding(.horizontal, DS.gutter)
        .opacity(pulse ? 0.55 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityLabel("Loading")
    }

    private func block(width: CGFloat, height: CGFloat, radius: CGFloat = 6) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.dsFill)
            .frame(width: width, height: height)
    }
}

/// Directions in Waze, Apple Maps or Google Maps, with any label (an action
/// tile, a full-width button). Same three apps as the old Drive to button.
struct DirectionsMenu<Label: View>: View {
    let coordinate: CLLocationCoordinate2D
    var name: String = ""
    @ViewBuilder var label: () -> Label
    @Environment(\.openURL) private var openURL

    var body: some View {
        Menu {
            Button { openWaze() } label: { SwiftUI.Label("Waze", systemImage: "car.fill") }
            Button { openAppleMaps() } label: { SwiftUI.Label("Apple Maps", systemImage: "map.fill") }
            Button {
                if let url = URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(coordinate.latitude),\(coordinate.longitude)&travelmode=driving") {
                    openURL(url)
                }
            } label: { SwiftUI.Label("Google Maps", systemImage: "mappin.and.ellipse") }
        } label: {
            label()
        }
        .accessibilityLabel("Directions")
    }

    private func openWaze() {
        let lat = coordinate.latitude, lon = coordinate.longitude
        let app = URL(string: "waze://?ll=\(lat),\(lon)&navigate=yes")
        let web = URL(string: "https://waze.com/ul?ll=\(lat)%2C\(lon)&navigate=yes")
        if let app {
            UIApplication.shared.open(app, options: [:]) { opened in
                if !opened, let web { UIApplication.shared.open(web) }
            }
        } else if let web {
            UIApplication.shared.open(web)
        }
    }

    private func openAppleMaps() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = name.isEmpty ? "Destination" : name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}

/// The satellite cover at the top of a spot or water page.
struct MapCover: View {
    let coordinate: CLLocationCoordinate2D
    var distance: CLLocationDistance = 2500
    var radius: CLLocationDistance? = nil

    var body: some View {
        Map(initialPosition: .camera(.init(centerCoordinate: coordinate, distance: distance))) {
            if let radius {
                MapCircle(center: coordinate, radius: radius)
                    .foregroundStyle(DS.accent.opacity(0.18))
                    .stroke(DS.accent.opacity(0.7), lineWidth: 2)
            }
            Annotation("", coordinate: coordinate) {
                Circle()
                    .fill(Color.dsScoreSlow)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(.white, lineWidth: 3))
                    .mapPinShadow()
            }
        }
        .mapStyle(.hybrid)
        .mapControls { }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .allowsHitTesting(false)
        .padding(.horizontal, DS.gutter)
        .accessibilityHidden(true)
    }
}

/// A plain icon list row for actions at the bottom of a page (Edit spot,
/// Share spot, Delete spot).
struct ExploreActionRow: View {
    let title: String
    let systemImage: String
    var isDestructive = false
    var chevron = true
    var showsDivider = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.body)
                    .foregroundStyle(isDestructive ? Color.dsScoreSlow : Color.dsText2)
                    .frame(width: 24)
                Text(title)
                    .font(.body)
                    .foregroundStyle(isDestructive ? Color.dsScoreSlow : Color.dsText)
                Spacer()
                if chevron {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.dsText3)
                }
            }
            .padding(.vertical, 14)
            if showsDivider {
                Rectangle().fill(Color.dsSeparator).frame(height: 0.5).padding(.leading, 38)
            }
        }
        .padding(.horizontal, DS.gutter)
        .contentShape(Rectangle())
    }
}

// MARK: - Saved spots

/// Saving places as spots and removing them again, shared by every Explore
/// page so a water is only ever saved once and nothing logged is lost.
@MainActor
enum ExploreSpots {
    /// What removing a spot unlinked, so saving it again can link it back.
    struct Detached: Equatable {
        var catchIds: [String] = []
        var tripIds: [String] = []
        var isEmpty: Bool { catchIds.isEmpty && tripIds.isEmpty }
    }

    /// The saved spot that stands for this water, if there is one.
    static func savedSpot(for waterbody: Waterbody, in appState: AppState) -> Spot? {
        guard let id = waterbody.id else { return nil }
        return ((try? appState.spotRepository.fetchAll()) ?? []).first { $0.waterbodyId == id }
    }

    /// Saves a water as a spot, or hands back the spot already saved for it.
    static func save(_ waterbody: Waterbody, in appState: AppState) throws -> Spot {
        if let existing = savedSpot(for: waterbody, in: appState) { return existing }
        var spot = Spot(name: waterbody.name, latitude: waterbody.latitude, longitude: waterbody.longitude,
                        waterbodyId: waterbody.id, spotType: SpotFormat.spotType(for: waterbody.type))
        try appState.spotRepository.save(&spot)
        return spot
    }

    /// Removes a spot and keeps everything logged there. `catch.spotId` and
    /// `trip.spotId` reference the spot with no ON DELETE action and foreign
    /// keys are on, so a plain delete fails for any spot with catches or
    /// plans. They are unlinked first, in the same transaction.
    @discardableResult
    static func remove(_ spot: Spot, in appState: AppState) throws -> Detached {
        let detached = try appState.db.db.write { db -> Detached in
            let catchIds = try String.fetchAll(db, sql: "SELECT id FROM \"catch\" WHERE spotId = ?", arguments: [spot.id])
            let tripIds = try String.fetchAll(db, sql: "SELECT id FROM trip WHERE spotId = ?", arguments: [spot.id])
            try db.execute(sql: "UPDATE \"catch\" SET spotId = NULL WHERE spotId = ?", arguments: [spot.id])
            try db.execute(sql: "UPDATE trip SET spotId = NULL WHERE spotId = ?", arguments: [spot.id])
            _ = try spot.delete(db)
            return Detached(catchIds: catchIds, tripIds: tripIds)
        }
        for id in detached.catchIds { CloudSyncEngine.shared.catchChanged(id) }
        CloudSyncEngine.shared.spotDeleted(spot.id)
        return detached
    }

    /// Links what an earlier removal unlinked back to the spot, unless it
    /// has been given another spot since.
    static func reattach(_ detached: Detached, to spot: Spot, in appState: AppState) {
        guard !detached.isEmpty else { return }
        do {
            try appState.db.db.write { db in
                for id in detached.catchIds {
                    try db.execute(sql: "UPDATE \"catch\" SET spotId = ? WHERE id = ? AND spotId IS NULL",
                                   arguments: [spot.id, id])
                }
                for id in detached.tripIds {
                    try db.execute(sql: "UPDATE trip SET spotId = ? WHERE id = ? AND spotId IS NULL",
                                   arguments: [spot.id, id])
                }
            }
            for id in detached.catchIds { CloudSyncEngine.shared.catchChanged(id) }
        } catch {
            print("[Currents] Could not link catches back to \(spot.name): \(error)")
        }
    }
}

// MARK: - Focus from other tabs

/// A place another tab asked Explore to show, from a
/// `currents://map/spot/<id>` or `currents://map/water/<id>` link. The map
/// opens it as its place sheet and clears it.
@MainActor
@Observable
final class ExploreFocus {
    static let shared = ExploreFocus()

    enum Target: Equatable {
        case spot(String)
        case water(Int64)
    }

    var target: Target?

    /// Reads a map link. Returns false when it names no place.
    @discardableResult
    func open(_ url: URL) -> Bool {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else { return false }
        switch parts[0] {
        case "spot":
            target = .spot(parts[1])
        case "water":
            guard let id = Int64(parts[1]) else { return false }
            target = .water(id)
        default:
            return false
        }
        return true
    }
}
