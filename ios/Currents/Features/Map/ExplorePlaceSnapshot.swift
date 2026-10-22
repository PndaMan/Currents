import SwiftUI
import MapKit
import Network

/// The square thumbnail of a boat ramp or fishing access point: a small map
/// of exactly where it is, with a pin in the middle. Rendered once per place,
/// map style and appearance, then kept on disk. The glyph thumbnail shows
/// while it renders and whenever there is no connection.
struct PlaceSnapshotThumb: View {
    let place: BoatRamp
    var size: CGFloat = 64

    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale
    @AppStorage("mapStyleOption") private var mapStyleRaw = MapTab.MapStyleOption.standard.rawValue
    @State private var image: UIImage?

    private var tint: Color { ExploreFormat.placeTint(place.kind) }

    /// Satellite when the map shows imagery, the plain map otherwise.
    private var satellite: Bool {
        switch MapTab.MapStyleOption(rawValue: mapStyleRaw) ?? .standard {
        case .standard, .fishing: false
        case .offline, .imagery, .hybrid: true
        }
    }

    private var request: PlaceSnapshots.Request {
        PlaceSnapshots.Request(id: place.id, coordinate: place.coordinate, satellite: satellite,
                               dark: scheme == .dark, size: size, scale: displayScale)
    }

    var body: some View {
        ZStack {
            if let image {
                ThumbView(image: image, tint: tint, size: size)
                    .overlay { pin }
                    .transition(.opacity)
            } else {
                ThumbView(systemImage: place.kind.icon, tint: tint, size: size)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: DS.Motion.fast), value: image != nil)
        .task(id: request.key) {
            image = PlaceSnapshots.cached(request.key)
            if image == nil {
                image = await PlaceSnapshots.image(for: request)
            }
        }
        .accessibilityHidden(true)
    }

    private var pin: some View {
        Circle()
            .fill(tint)
            .frame(width: max(10, size * 0.2), height: max(10, size * 0.2))
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .mapPinShadow()
    }
}

/// Renders and caches the place thumbnails, in memory and in Caches.
@MainActor
enum PlaceSnapshots {
    struct Request {
        let id: String
        let coordinate: CLLocationCoordinate2D
        let satellite: Bool
        let dark: Bool
        let size: CGFloat
        let scale: CGFloat

        var key: String {
            let safe = id.replacingOccurrences(of: "/", with: "_")
            return "\(safe)-\(satellite ? "sat" : "map")-\(dark ? "dark" : "light")-\(Int(size))@\(Int(scale))"
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

    private static let folder: URL? = {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = caches.appendingPathComponent("PlaceSnapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func cached(_ key: String) -> UIImage? {
        if let hit = memory.object(forKey: key as NSString) { return hit }
        guard let url = folder?.appendingPathComponent("\(key).png"),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        memory.setObject(image, forKey: key as NSString)
        return image
    }

    static func image(for request: Request) async -> UIImage? {
        let key = request.key
        if let hit = cached(key) { return hit }
        if let task = running[key] { return await task.value }
        guard path.currentPath.status == .satisfied else { return nil }

        let task = Task { await render(request) }
        running[key] = task
        let image = await task.value
        running[key] = nil

        if let image {
            memory.setObject(image, forKey: key as NSString)
            if let url = folder?.appendingPathComponent("\(key).png"), let data = image.pngData() {
                try? data.write(to: url, options: .atomic)
            }
        }
        return image
    }

    private static func render(_ request: Request) async -> UIImage? {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: request.coordinate, latitudinalMeters: 450, longitudinalMeters: 450)
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
