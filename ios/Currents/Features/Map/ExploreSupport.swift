import SwiftUI
import MapKit
import GRDB
import Network

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
        spot.type.label
    }

    static func habitat(_ h: Species.Habitat?) -> String {
        switch h {
        case .freshwater: "Freshwater"
        case .marine: "Saltwater"
        case .brackish: "Estuary"
        case nil: "Fish"
        }
    }

    /// Small waters read in hectares (acres in imperial).
    static func area(_ km2: Double) -> String {
        Units.area(km2: km2, smallInHectares: true)
    }

    /// A ramp's kind and distance, leaving the kind out when the name
    /// already says it (an unnamed ramp is called by its kind, or by its
    /// kind and its water or town, "Ramp at Theewaterskloof Dam", "Ramp
    /// near Hout Bay"). Pass the side from `BoatRampService.side(of:)` to
    /// tell apart places that share a name: "Southeast shore, 22 km away".
    static func rampLine(_ ramp: BoatRamp, distance: String?, side: String? = nil) -> String {
        let saysKind = ramp.name == ramp.kind.label || ramp.name.hasPrefix(ramp.kind.waterNamePrefix)
            || ramp.name.hasPrefix(ramp.kind.placeNamePrefix)
        let kind = saysKind ? nil : ramp.kind.label
        return [side, kind, distance].compactMap { $0 }.joined(separator: ", ")
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

    /// "Saturday 24 October"
    static func shortDate(_ d: Date) -> String {
        ForecastFormat.longDate(d)
    }
}

// MARK: - Bite snapshot

/// Today's bite at a coordinate: the score for this hour, the day's peak,
/// the hourly curve and its best windows. Worked out on the phone from
/// cached weather, so it works offline.
struct BiteSnapshot {
    let now: Int
    let day: Int
    let hourly: [(hour: Int, score: Int)]
    let windows: [BiteWindows.Window]
    let reasons: [String]
    /// Tomorrow's best window, for when every window today is over. Filled
    /// in by `load(at:)`.
    var tomorrow: BiteWindows.Window? = nil
    /// The date of `tomorrow`, for its day name.
    var tomorrowDate: Date? = nil

    /// The best window that has not passed yet. On a tie the earlier one
    /// wins, so a window under way beats an equal one later.
    var best: BiteWindows.Window? {
        windows.filter { !$0.hasPassed() }.max { $0.peakScore < $1.peakScore }
    }

    /// True when today had windows and every one of them is over.
    var allPassed: Bool { !windows.isEmpty && best == nil }

    /// "Best 06:00 to 09:00, peaking at 81", or "No more windows today.
    /// Tomorrow 05:00 to 08:00, peaking at 74" once today's are over.
    func bestLine(use24: Bool) -> String? {
        if let best {
            let when = best.isNow() ? "Now until \(ForecastFormat.hour(best.endHour + 1, use24: use24))"
                                     : "Best \(ForecastFormat.range(best, use24: use24))"
            return "\(when), peaking at \(best.peakScore)"
        }
        guard allPassed else { return nil }
        guard let tomorrow else { return "No more windows today" }
        let day = ForecastFormat.dayName(1, date: tomorrowDate ?? .now)
        return "No more windows today. \(day) \(ForecastFormat.range(tomorrow, use24: use24)), peaking at \(tomorrow.peakScore)"
    }

    init(_ f: ForecastEngine.ForecastResult) {
        now = f.score
        hourly = f.hourlyScores.sorted { $0.hour < $1.hour }
        // The day's hourly peak, as the forecast pages show it, so the ring,
        // the pins and the windows agree.
        day = hourly.map(\.score).max() ?? f.score
        windows = BiteWindows.best(from: f.hourlyScores)
        reasons = f.reasons
    }

    static func load(at coord: CLLocationCoordinate2D) async -> (BiteSnapshot, WeatherService.WeatherData?) {
        let w = await WeatherService.shared.current(for: coord)
        let f = ForecastEngine.forecast(
            coordinate: coord,
            currentPressureHpa: w?.pressureHpa,
            pressureChange6h: w?.pressureChange6h,
            waterTempC: w?.measured?.waterTempC,
            windSpeedKmh: w?.measured?.windSpeedKmh,
            windDirection: w?.measured?.windDirectionDeg,
            species: nil,
            isInSpawningZone: false
        )
        var snapshot = BiteSnapshot(f)
        if snapshot.allPassed {
            // The same day forecast Today shows for tomorrow, from the cached
            // outlook when there is one.
            let outlook = await WeatherService.shared.forecastDays(for: coord)
            let next = ForecastEngine.day(1, coordinate: coord, current: w, outlook: outlook, species: nil)
            snapshot.tomorrow = BiteWindows.best(from: next.result.hourlyScores).max { $0.peakScore < $1.peakScore }
            snapshot.tomorrowDate = next.date
        }
        return (snapshot, w)
    }
}

// MARK: - Species filter

/// The Explore map narrowed to one species: your spots where you caught it
/// or that sit on a water known to hold it, and waters whose species list
/// includes it. Only confirmed records count, never nearby sightings.
struct SpeciesMapFilter {
    let species: Species
    /// Where the filter was asked for; waters are looked for around it.
    let origin: CLLocationCoordinate2D
    let spotIds: Set<String>
    /// Waters that hold it and are not saved as one of the spots.
    let waters: [Waterbody]
    /// Your catches of it, for the catch pins.
    let catchIds: Set<String>

    var placeCount: Int { spotIds.count + waters.count }

    /// Whether a place opened through a map link stays on the filtered map.
    func keeps(_ target: ExploreFocus.Target) -> Bool {
        switch target {
        case .spot(let id): return spotIds.contains(id)
        case .water(let id): return waters.contains { $0.id == id }
        case .ramp, .point: return false
        }
    }

    @MainActor
    static func load(_ species: Species, near origin: CLLocationCoordinate2D, appState: AppState) -> SpeciesMapFilter {
        let caught = (try? appState.catchRepository.fetchForSpecies(species.id)) ?? []
        let saved = (try? appState.spotRepository.fetchAll()) ?? []
        let holding = TargetData.waters(holding: species.id, near: origin, appState: appState)
        let spots = TargetData.spots(catches: caught, saved: saved,
                                     holdingWaterIds: Set(holding.compactMap(\.id)), from: origin)
        let savedWaters = Set(spots.compactMap { $0.spot.waterbodyId })
        let waters = holding.filter { wb in wb.id.map { !savedWaters.contains($0) } ?? true }
        return SpeciesMapFilter(species: species, origin: origin,
                                spotIds: Set(spots.map(\.spot.id)), waters: waters,
                                catchIds: Set(caught.map(\.catchRecord.id)))
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

/// The satellite cover at the top of a spot or water page: the place's pin
/// on the satellite map. A water is drawn by the map itself; the bundle has
/// no outline for it, and a circle of its area would cover the land too.
struct MapCover: View {
    let coordinate: CLLocationCoordinate2D
    var distance: CLLocationDistance = 2500

    var body: some View {
        Map(initialPosition: .camera(.init(centerCoordinate: coordinate, distance: distance))) {
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

// MARK: - Inline title

extension View {
    /// The inline title of a scrolling Explore page or sheet, faded in once
    /// its `DetailHeader` has scrolled away, as on TodayPage. A page whose
    /// header sits below a cover passes a `threshold`. Apply to the
    /// ScrollView, after `detailTint` or `detailScrollEdge`.
    func exploreInlineTitle(_ title: String, threshold: CGFloat? = nil) -> some View {
        pageTitleFade(title, threshold: threshold)
    }
}

// MARK: - Connection

/// Whether the phone has a connection, so the map badge only says
/// "Offline" when it is. It starts assuming online, so nothing flashes
/// "Offline" before the first answer arrives.
@MainActor
final class ExploreConnection: ObservableObject {
    static let shared = ExploreConnection()
    @Published private(set) var isOffline = false
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { path in
            let offline = path.status != .satisfied
            Task { @MainActor in
                if ExploreConnection.shared.isOffline != offline { ExploreConnection.shared.isOffline = offline }
            }
        }
        monitor.start(queue: DispatchQueue(label: "ExploreConnection"))
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

/// A place a list or another tab asked Explore to show. The map centres on
/// it, opens its sheet at half height and clears it. The links:
///   currents://map/spot/<id>
///   currents://map/water/<id>
///   currents://map/ramp/<osm type>/<osm id>?lat=<lat>&lon=<lon>
///   currents://map/point?lat=<lat>&lon=<lon>&name=<title>
@MainActor
@Observable
final class ExploreFocus {
    static let shared = ExploreFocus()

    enum Target: Equatable {
        case spot(String)
        case water(Int64)
        /// A boat ramp or fishing access point, with where it is in case it
        /// has not been loaded yet.
        case ramp(id: String, latitude: Double?, longitude: Double?)
        /// A point saved nowhere, which opens as a dropped pin.
        case point(latitude: Double, longitude: Double, title: String?)
    }

    var target: Target?

    /// Reads a map link. Returns false when it names no place.
    @discardableResult
    func open(_ url: URL) -> Bool {
        let parts = url.pathComponents.filter { $0 != "/" }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { query.first { $0.name == name }?.value }
        let lat = value("lat").flatMap(Double.init)
        let lon = value("lon").flatMap(Double.init)
        guard let kind = parts.first else { return false }
        switch kind {
        case "spot" where parts.count >= 2:
            target = .spot(parts[1])
        case "water" where parts.count >= 2:
            guard let id = Int64(parts[1]) else { return false }
            target = .water(id)
        case "ramp" where parts.count >= 2:
            // OpenStreetMap ids carry a slash, such as node/123.
            target = .ramp(id: parts.dropFirst().joined(separator: "/"), latitude: lat, longitude: lon)
        case "point":
            guard let lat, let lon else { return false }
            target = .point(latitude: lat, longitude: lon, title: value("name"))
        default:
            return false
        }
        return true
    }
}

/// The links that show a place on the Explore map. A list sets one as
/// `appState.pendingDeepLink`; the app goes back to the map from any tab or
/// page, centres it on the place and opens the place's half-height sheet.
enum MapLink {
    static func spot(_ spot: Spot) -> URL? {
        link("/spot/\(spot.id)")
    }

    /// Nil for a water that was never stored, which has no id to look up.
    static func water(_ water: Waterbody) -> URL? {
        water.id.flatMap { link("/water/\($0)") }
    }

    static func ramp(_ ramp: BoatRamp) -> URL? {
        link("/ramp/\(ramp.id)", query: coordinateItems(ramp.coordinate))
    }

    static func point(_ coordinate: CLLocationCoordinate2D, title: String? = nil) -> URL? {
        var items = coordinateItems(coordinate)
        if let title { items.append(URLQueryItem(name: "name", value: title)) }
        return link("/point", query: items)
    }

    private static func coordinateItems(_ c: CLLocationCoordinate2D) -> [URLQueryItem] {
        [URLQueryItem(name: "lat", value: String(c.latitude)), URLQueryItem(name: "lon", value: String(c.longitude))]
    }

    private static func link(_ path: String, query: [URLQueryItem] = []) -> URL? {
        var parts = URLComponents()
        parts.scheme = "currents"
        parts.host = "map"
        parts.path = path
        parts.queryItems = query.isEmpty ? nil : query
        return parts.url
    }
}
