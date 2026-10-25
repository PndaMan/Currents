import SwiftUI
import MapKit
import Network

/// The square thumbnail of a place: a small map of exactly where it is, with
/// a pin in the middle. Rendered once per place, map style and appearance,
/// then kept on disk. The glyph
/// thumbnail shows while it renders and whenever there is no connection.
/// Inside `placeThumbsTogether()` the rows on screen show their maps
/// together, once all of them are ready.
/// A spot with its own picture (a photo or a collage of its catches) shows
/// that instead, and the map only when the picture cannot be found.
struct PlaceSnapshotThumb: View {
    /// Unique per place and kind, so a spot and a ramp never share a render.
    let id: String
    let coordinate: CLLocationCoordinate2D
    /// The fallback glyph while the map renders or when offline.
    let systemImage: String
    let tint: Color
    var size: CGFloat = 64
    /// Metres across the render.
    var span: CLLocationDistance = 450
    var showsPin = true
    var cover: SpotCover? = nil

    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.placeThumbGroup) private var group
    @AppStorage("mapStyleOption") private var mapStyleRaw = MapTab.MapStyleOption.standard.rawValue
    @State private var image: UIImage?
    @State private var coverImage: UIImage?
    @State private var coverMissing = false

    /// Satellite when the map shows imagery, the plain map otherwise.
    private var satellite: Bool {
        switch MapTab.MapStyleOption(rawValue: mapStyleRaw) ?? .standard {
        case .standard, .fishing: false
        case .offline, .imagery, .hybrid: true
        }
    }

    private var request: PlaceSnapshots.Request {
        PlaceSnapshots.Request(id: id, coordinate: coordinate, span: span, satellite: satellite,
                               dark: scheme == .dark, size: size, scale: displayScale)
    }

    private var coverShown: UIImage? {
        guard let cover else { return nil }
        return coverImage ?? SpotCovers.cached(cover, scale: displayScale)
    }

    /// A render already in memory shows on the first frame, so rows scrolled
    /// back into view do not flash the glyph. With a picture chosen, the map
    /// waits until that picture turns out to be missing.
    private var shown: UIImage? {
        guard cover == nil || coverMissing else { return nil }
        if let group, !group.showsMaps { return nil }
        return image ?? PlaceSnapshots.cached(request.key)
    }

    private var loadKey: String {
        guard let cover else { return request.key }
        return "\(request.key)-\(cover.id)"
    }

    var body: some View {
        ZStack {
            if let coverShown {
                ThumbView(image: coverShown, tint: tint, size: size)
                    .transition(.opacity)
            } else if let shown {
                ThumbView(image: shown, tint: tint, size: size)
                    .overlay { if showsPin { pin } }
                    .transition(.opacity)
            } else {
                ThumbView(systemImage: systemImage, tint: tint, size: size)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: DS.Motion.fast), value: coverShown != nil || shown != nil)
        .onAppear {
            group?.appeared(request.key, ready: coverShown != nil || PlaceSnapshots.cached(request.key) != nil)
        }
        .task(id: loadKey) { await load() }
        .accessibilityHidden(true)
    }

    private func load() async {
        let key = request.key
        defer { group?.finished(key) }
        if let cover {
            coverImage = nil
            coverMissing = false
            coverImage = await SpotCovers.image(for: cover, scale: displayScale)
            guard coverImage == nil else { return }
            coverMissing = true
        }
        image = PlaceSnapshots.cached(request.key)
        if image == nil {
            image = await PlaceSnapshots.image(for: request)
        }
    }

    private var pin: some View {
        Circle()
            .fill(tint)
            .frame(width: max(10, size * 0.2), height: max(10, size * 0.2))
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .mapPinShadow()
    }
}

extension PlaceSnapshotThumb {
    /// A boat ramp or fishing access point.
    init(place: BoatRamp, size: CGFloat = 64) {
        self.init(id: place.id, coordinate: place.coordinate, systemImage: place.kind.icon,
                  tint: ExploreFormat.placeTint(place.kind), size: size)
    }

    /// A saved spot, with its own picture when one was chosen.
    init(spot: Spot, size: CGFloat = 64) {
        self.init(id: "spot-\(spot.id)",
                  coordinate: CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude),
                  systemImage: spot.type.icon, tint: DS.accent, size: size, cover: SpotCover(spot))
    }

    /// A point that is not saved anywhere, such as a stop in a session.
    init(coordinate: CLLocationCoordinate2D, size: CGFloat = 64) {
        let key = String(format: "point-%.5f,%.5f", coordinate.latitude, coordinate.longitude)
        self.init(id: key, coordinate: coordinate, systemImage: "mappin.and.ellipse",
                  tint: DS.accent, size: size)
    }
}

/// Rows of water and of ramps and access show the place's glyph, never a
/// map: at row size many renders read as blank squares or bare streets, and
/// a list that mixes the two looks unfinished. The map render is kept for
/// the header of a place's own page or sheet.
extension ThumbView where Content == ThumbSymbol {
    /// A boat ramp or fishing access point.
    init(place: BoatRamp, size: CGFloat = 64) {
        self.init(systemImage: place.kind.icon, tint: ExploreFormat.placeTint(place.kind), size: size)
    }

    /// A dam, lake, river or stretch of coast.
    init(water: Waterbody, size: CGFloat = 64) {
        self.init(systemImage: ExploreFormat.waterIcon(water.type), tint: Color.exploreWater, size: size)
    }
}

/// Lets a list show its place maps together. The rows on screen when the
/// list opens keep their glyphs until every one of them has its map (or a
/// few seconds have passed), then all change at once. Rows scrolled in
/// after that load on their own, like anywhere else.
@MainActor
@Observable
final class PlaceThumbGroup {
    /// Rows on screen at the start whose map is still loading.
    private var waiting = Set<String>()
    private(set) var settled = false
    @ObservationIgnored private var started: Date?

    var showsMaps: Bool { settled || waiting.isEmpty }

    /// A row came on screen. `ready` when its map is already in memory.
    func appeared(_ key: String, ready: Bool) {
        if started == nil {
            started = .now
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                self?.settled = true
            }
        }
        guard !settled, !ready, let start = started, Date.now.timeIntervalSince(start) < 0.5 else { return }
        waiting.insert(key)
    }

    /// A row's map loaded, or turned out not to be available.
    func finished(_ key: String) {
        guard waiting.remove(key) != nil, waiting.isEmpty else { return }
        settled = true
    }
}

private struct PlaceThumbGroupKey: EnvironmentKey {
    static let defaultValue: PlaceThumbGroup? = nil
}

extension EnvironmentValues {
    /// The list that shows its place maps together, if any.
    var placeThumbGroup: PlaceThumbGroup? {
        get { self[PlaceThumbGroupKey.self] }
        set { self[PlaceThumbGroupKey.self] = newValue }
    }
}

private struct PlaceThumbsTogether: ViewModifier {
    @State private var group = PlaceThumbGroup()

    func body(content: Content) -> some View {
        content.environment(\.placeThumbGroup, group)
    }
}

extension View {
    /// The place thumbnails inside show their maps together instead of one
    /// by one as each render lands. For lists of places.
    func placeThumbsTogether() -> some View {
        modifier(PlaceThumbsTogether())
    }
}

/// Renders and caches the place thumbnails, in memory and in Caches. The
/// snapshotter draws off the main thread; reading, decoding and writing the
/// files happen off it too.
@MainActor
enum PlaceSnapshots {
    struct Request {
        let id: String
        let coordinate: CLLocationCoordinate2D
        var span: CLLocationDistance = 450
        let satellite: Bool
        let dark: Bool
        let size: CGFloat
        let scale: CGFloat

        var key: String {
            let safe = id.replacingOccurrences(of: "/", with: "_")
            // The default span keeps the key ramps were first cached under.
            let framing = span == 450 ? "" : "-\(Int(span))m"
            return "\(safe)\(framing)-\(satellite ? "sat" : "map")-\(dark ? "dark" : "light")-\(Int(size))@\(Int(scale))"
        }
    }

    private static let memory = NSCache<NSString, UIImage>()
    private static var running: [String: Task<UIImage?, Never>] = [:]

    /// Watches the connection so nothing renders blank tiles offline.
    private static let path: NWPathMonitor = {
        let monitor = NWPathMonitor()
        monitor.start(queue: DispatchQueue(label: "PlaceSnapshots.path"))
        return monitor
    }()

    nonisolated private static let folder: URL? = {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = caches.appendingPathComponent("PlaceSnapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// A render already in memory. Files on disk load through `image(for:)`.
    static func cached(_ key: String) -> UIImage? {
        memory.object(forKey: key as NSString)
    }

    static func image(for request: Request) async -> UIImage? {
        let key = request.key
        if let hit = cached(key) { return hit }
        if let task = running[key] { return await task.value }

        let task = Task { await load(request) }
        running[key] = task
        let image = await task.value
        running[key] = nil

        if let image { memory.setObject(image, forKey: key as NSString) }
        return image
    }

    /// From disk when it was rendered before, otherwise a fresh render while
    /// online, saved for next time.
    private static func load(_ request: Request) async -> UIImage? {
        let key = request.key
        let stored = await Task.detached(priority: .utility) { readFile(key) }.value
        if let stored { return stored }
        guard path.currentPath.status == .satisfied, let image = await render(request) else { return nil }
        Task.detached(priority: .utility) { writeFile(image, key: key) }
        return image
    }

    nonisolated private static func readFile(_ key: String) -> UIImage? {
        guard let url = folder?.appendingPathComponent("\(key).png"),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        return image.preparingForDisplay() ?? image
    }

    nonisolated private static func writeFile(_ image: UIImage, key: String) {
        guard let url = folder?.appendingPathComponent("\(key).png"), let data = image.pngData() else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func render(_ request: Request) async -> UIImage? {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: request.coordinate,
                                            latitudinalMeters: request.span, longitudinalMeters: request.span)
        options.size = CGSize(width: request.size, height: request.size)
        options.preferredConfiguration = request.satellite
            ? MKImageryMapConfiguration()
            : MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        options.traitCollection = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: request.dark ? .dark : .light),
            UITraitCollection(displayScale: request.scale),
        ])
        do {
            return try await MKMapSnapshotter(options: options).start().image
        } catch {
            return nil
        }
    }
}
