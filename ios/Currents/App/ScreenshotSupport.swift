import UIKit
import CoreLocation

/// Support for capturing App Store screenshots deterministically in the iOS
/// Simulator (see `.github/workflows/screenshots.yml`).
///
/// Activated only when the app is launched with the `SCREENSHOT_MODE=1`
/// environment variable (passed by CI via `SIMCTL_CHILD_SCREENSHOT_MODE`), so
/// it can never affect a real install. When active it:
///   • seeds a small set of demo catches so the Catches / Collection / Profile
///     screens look populated, and
///   • opens straight to the tab named by `SCREENSHOT_TAB`, so CI can relaunch
///     the app once per tab and grab one clean, full-resolution screenshot each.
///
/// IMPORTANT — content rights: every image shown in screenshot mode is content
/// we own or that is public domain. Catch photos are rendered from the app's
/// OWN bundled fish artwork (the `fish_<id>` asset catalog), not third-party
/// photos. The map is Apple MapKit (permitted in screenshots of your own app);
/// third-party overlays (OpenSeaMap, radar, satellite) stay off by default. We
/// deliberately never navigate to the species-detail iNaturalist photo in
/// screenshot mode, so no externally-licensed imagery is captured.
enum ScreenshotSupport {
    static var isActive: Bool {
        ProcessInfo.processInfo.environment["SCREENSHOT_MODE"] == "1"
            || CommandLine.arguments.contains("-screenshotMode")
    }

    /// A scenic coastal spot (Kogel Bay, South Africa) the map centres on in
    /// screenshot mode, matching the seeded demo spots.
    static let demoCoordinate = CLLocationCoordinate2D(latitude: -34.235, longitude: 18.848)

    /// The tab CI asked us to open to, if any.
    static var initialTab: ContentView.Tab? {
        guard isActive else { return nil }
        let raw = ProcessInfo.processInfo.environment["SCREENSHOT_TAB"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return raw.flatMap(ContentView.Tab.init(rawValue:))
    }

    /// Preferred demo species, matched by common name at runtime so we never
    /// depend on brittle hard-coded IDs. Whichever are present get a catch.
    private static let preferredSpecies = [
        "Largemouth Bass", "Rainbow Trout", "Dusky Kob", "Yellowtail",
        "Dorado", "Common Carp", "Garrick", "Roman", "Elf", "Bluegill",
    ]

    @MainActor
    static func seedDemoDataIfNeeded(_ appState: AppState) {
        guard isActive else { return }
        // Idempotent: never double-seed across the per-tab relaunches.
        let existing = (try? appState.catchRepository.fetchAll()) ?? []
        guard existing.isEmpty else { return }

        let allSpecies = (try? appState.speciesRepository.fetchAll()) ?? []
        guard !allSpecies.isEmpty else { return }

        func species(_ name: String) -> Species? {
            allSpecies.first { $0.commonName.localizedCaseInsensitiveContains(name) }
        }
        let picks = preferredSpecies.compactMap(species(_:))
        guard !picks.isEmpty else { return }

        // A couple of demo spots (private, so no real location is implied).
        let spots: [Spot] = [
            Spot(name: "Kogel Bay Reef", latitude: -34.235, longitude: 18.848, spotType: .reef),
            Spot(name: "Theewaterskloof Dam", latitude: -34.05, longitude: 19.28, spotType: .dam),
            Spot(name: "Breede Estuary", latitude: -34.40, longitude: 20.84, spotType: .estuary),
        ]
        for var s in spots { try? appState.spotRepository.save(&s) }

        // Demo dam/lake bubbles clustered around the map's screenshot camera so
        // the Explore tab shows the waterbody feature populated.
        if let data = demoWaterbodiesJSON.data(using: .utf8),
           let bodies = try? JSONDecoder().decode([Waterbody].self, from: data) {
            for var wb in bodies { try? appState.waterbodyRepository.save(&wb) }
        }

        // Plausible demo measurements per species so cards/stats look real.
        let facts: [(len: Double, kg: Double, score: Int, released: Bool)] = [
            (62, 3.8, 84, false), (41, 1.1, 72, true), (108, 14.5, 91, false),
            (73, 5.2, 78, false), (96, 8.9, 88, true), (58, 3.1, 65, true),
            (81, 6.4, 80, false), (34, 0.9, 69, true), (47, 1.4, 74, true),
            (26, 0.4, 61, true),
        ]

        let calendar = Calendar.current
        for (i, sp) in picks.enumerated() {
            let fact = facts[i % facts.count]
            let spot = spots[i % spots.count]
            // Spread over recent weeks so the weekly streak + analytics populate.
            let daysAgo = i * 5 + 1
            let caughtAt = calendar.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now

            var record = Catch(
                speciesId: sp.id,
                spotId: spot.id,
                caughtAt: caughtAt,
                latitude: spot.latitude,
                longitude: spot.longitude,
                lengthCm: fact.len,
                weightKg: fact.kg,
                released: fact.released,
                forecastScoreAtCapture: fact.score,
                isFavorite: i < 2
            )
            // Use the app's OWN artwork as the catch photo (rights-clean).
            if let card = renderArtworkCard(assetName: sp.artworkAssetName),
               let filename = try? PhotoManager.save(card, id: record.id) {
                record.photoPath = filename
                record.photoPaths = Catch.encodePhotoPaths([filename])
            }
            try? appState.catchRepository.save(&record)
        }
    }

    /// A few dam/lake waterbodies near the demo map camera (Kogel Bay coast),
    /// so the Explore map shows several bite-score bubbles. Screenshot-mode
    /// only — never seeded in a real install.
    private static let demoWaterbodiesJSON = """
    [
      {"name":"Steenbras Dam","type":"dam","latitude":-34.190,"longitude":18.885,"surfaceAreaKm2":6.6,"maxDepthM":42,"isPublic":true},
      {"name":"Kogelberg Dam","type":"dam","latitude":-34.278,"longitude":18.902,"surfaceAreaKm2":2.1,"maxDepthM":18,"isPublic":true},
      {"name":"Rooiels Vlei","type":"lake","latitude":-34.302,"longitude":18.822,"surfaceAreaKm2":0.8,"maxDepthM":6,"isPublic":true},
      {"name":"Palmiet Reservoir","type":"dam","latitude":-34.334,"longitude":18.861,"surfaceAreaKm2":3.4,"maxDepthM":22,"isPublic":true},
      {"name":"Hangklip Pan","type":"lake","latitude":-34.361,"longitude":18.842,"surfaceAreaKm2":0.5,"maxDepthM":4,"isPublic":true}
    ]
    """

    /// Composite a species' transparent artwork onto a subtle ocean gradient so
    /// it reads as an intentional catch card rather than a cutout on black.
    private static func renderArtworkCard(assetName: String) -> UIImage? {
        guard let art = UIImage(named: assetName) else { return nil }
        let size = CGSize(width: 1000, height: 1000)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let colors = [
                UIColor(red: 0.07, green: 0.17, blue: 0.27, alpha: 1).cgColor,
                UIColor(red: 0.02, green: 0.08, blue: 0.15, alpha: 1).cgColor,
            ]
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors as CFArray, locations: [0, 1]
            ) {
                cg.drawLinearGradient(
                    gradient, start: .zero,
                    end: CGPoint(x: 0, y: size.height), options: []
                )
            }
            let pad: CGFloat = 90
            let maxW = size.width - pad * 2, maxH = size.height - pad * 2
            let scale = min(maxW / art.size.width, maxH / art.size.height)
            let w = art.size.width * scale, h = art.size.height * scale
            art.draw(in: CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h))
        }
    }
}
