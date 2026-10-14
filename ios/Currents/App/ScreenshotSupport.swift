import UIKit
import CoreLocation

/// Support for capturing App Store screenshots deterministically in the iOS
/// Simulator (see `.github/workflows/screenshots.yml`).
///
/// Activated only when the app is launched with the `SCREENSHOT_MODE=1`
/// environment variable (passed by CI via `SIMCTL_CHILD_SCREENSHOT_MODE`), so
/// it can never affect a real install. When active it:
///   • seeds fourteen months of a believable angler's life — catches across
///     two dozen species, spots, gear setups, GPS-tracked trips, three crews
///     with a photo feed and a friends leaderboard — so every screen
///     photographs populated, and
///   • opens straight to the tab named by `SCREENSHOT_TAB` (and optionally a
///     pushed screen named by `SCREENSHOT_SCREEN`), so CI can relaunch the app
///     once per screen and grab one clean, full-resolution screenshot each.
///
/// IMPORTANT — content rights: every image shown in screenshot mode is content
/// we own or that is public domain. Catch photos are rendered from the app's
/// OWN bundled fish artwork (the `fish_<id>` asset catalog), not third-party
/// photos. The map is Apple MapKit (permitted in screenshots of your own app);
/// third-party overlays (OpenSeaMap, radar, satellite) stay off by default. We
/// deliberately never navigate to the species-detail iNaturalist photo in
/// screenshot mode, so no externally-licensed imagery is captured. Every
/// person named here is fictional.
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

    /// A screen to push on top of the initial tab: `catch` (the hero catch's
    /// detail), `analytics`, `profile` or `leaderboard`.
    static var screen: String? {
        guard isActive else { return nil }
        return ProcessInfo.processInfo.environment["SCREENSHOT_SCREEN"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    /// The catch the `catch` screen opens — the trip-of-the-year kob.
    static let heroCatchId = "demo-hero-kob"

    // MARK: - Seed tables

    private struct DemoSpot {
        let name: String, lat: Double, lon: Double, type: Spot.SpotType, notes: String?
    }

    private static let demoSpots: [DemoSpot] = [
        .init(name: "Kogel Bay Reef", lat: -34.235, lon: 18.848, type: .reef,
              notes: "Fish the gully left of the third car park. Dead on a south-easter."),
        .init(name: "Theewaterskloof — Drowned Forest", lat: -34.052, lon: 19.282, type: .dam,
              notes: "Bass hold on the stumps in 2–4 m. Launch at Villiersdorp side."),
        .init(name: "Breede Mouth", lat: -34.402, lon: 20.842, type: .estuary,
              notes: "Push tide only. The drop-off by the green buoy."),
        .init(name: "Gordon's Bay Harbour Wall", lat: -34.163, lon: 18.866, type: .harbour, notes: nil),
        .init(name: "Struisbaai Bank", lat: -34.851, lon: 20.104, type: .offshore,
              notes: "38 nm out. Birds working = tuna under them."),
        .init(name: "Elandspad, Pool 7", lat: -33.731, lon: 19.141, type: .river,
              notes: "Upstream of the weir. Wade wet, rods 4–5 wt."),
        .init(name: "Clanwilliam Dam — Rondegat Arm", lat: -32.183, lon: 18.872, type: .dam, notes: nil),
        .init(name: "Strand Pavilion Gully", lat: -34.115, lon: 18.826, type: .beach,
              notes: "Low tide reveals the gully. Elf on sardine at last light."),
        .init(name: "Steenbras Mouth", lat: -34.196, lon: 18.818, type: .rocks, notes: nil),
    ]

    private struct DemoGear {
        let name: String, rod: String, reel: String, line: Double, leader: Double
        let lure: String, color: String?, grams: Double?, technique: String
    }

    private static let demoGear: [DemoGear] = [
        .init(name: "Dawn topwater", rod: "Zodias 7'0\" M", reel: "Stradic FL 2500",
              line: 15, leader: 12, lure: "Whopper Plopper 110", color: "Bone", grams: 22,
              technique: "Topwater"),
        .init(name: "Estuary paddle", rod: "Saltist 8'", reel: "Daiwa BG 3000",
              line: 20, leader: 25, lure: "Z-Man 5\" DieZel", color: "Pearl", grams: 14,
              technique: "Slow hop off the drop"),
        .init(name: "Rock & surf", rod: "Assassin Kinetic 12'", reel: "Penn Spinfisher 6500",
              line: 30, leader: 60, lure: "Sardine & chokka", color: nil, grams: 113,
              technique: "Running sinker"),
        .init(name: "Fly — 5 wt", rod: "Sage Foundation 9' 5wt", reel: "Redington Behemoth",
              line: 6, leader: 5, lure: "Woolly Bugger #10", color: "Olive", grams: nil,
              technique: "Dead drift, strip on the swing"),
        .init(name: "Speed jig", rod: "Grappler 5'8\" PE5", reel: "Saragosa 10000",
              line: 65, leader: 80, lure: "Vortex Jig", color: "Mackerel", grams: 200,
              technique: "Speed jigging"),
        .init(name: "Carp bottom", rod: "Fox Horizon 12' 3lb", reel: "Shimano Baitrunner",
              line: 15, leader: 25, lure: "Mielie pip & boilie", color: "Strawberry", grams: 85,
              technique: "Hair rig"),
    ]

    private struct DemoTrip {
        let name: String, spot: Int, daysAgo: Int, startHour: Double, hours: Double
        let weather: String, notes: String?
    }

    private static let demoTrips: [DemoTrip] = [
        .init(name: "Breede mouth, spring tide", spot: 2, daysAgo: 4, startHour: 4.5, hours: 7.5,
              weather: "fog", notes: "Fog till 8. Kob on the push, nothing after the turn."),
        .init(name: "Struisbaai tuna run", spot: 4, daysAgo: 23, startHour: 5, hours: 9,
              weather: "clear", notes: "Two yellowfin, one dorado on the way home."),
        .init(name: "Drowned forest bass", spot: 1, daysAgo: 11, startHour: 5.5, hours: 5,
              weather: "cloudy", notes: nil),
        .init(name: "Elandspad fly day", spot: 5, daysAgo: 38, startHour: 7, hours: 6.5,
              weather: "clear", notes: "Low clear water. 6x tippet or nothing."),
        .init(name: "Kogel Bay before work", spot: 0, daysAgo: 1, startHour: 5.25, hours: 2.25,
              weather: "clear", notes: nil),
        .init(name: "Clanwilliam long weekend", spot: 6, daysAgo: 96, startHour: 6, hours: 8,
              weather: "clear", notes: "Water down 30%. Smallies on the rocky points."),
    ]

    /// One seeded catch. `trip` indexes `demoTrips`, `gear` indexes `demoGear`.
    private struct DemoCatch {
        let species: String, spot: Int, daysAgo: Int, hour: Double
        let cm: Double, kg: Double, released: Bool, score: Int
        var fav = false, gear: Int? = nil, trip: Int? = nil
        var clarity: WaterClarity? = nil, depth: Double? = nil, note: String? = nil
        var id: String? = nil
    }

    private static let demoCatches: [DemoCatch] = [
        // This week
        .init(species: "Leervis (Garrick)", spot: 0, daysAgo: 1, hour: 6.1, cm: 88, kg: 7.4,
              released: true, score: 86, fav: true, gear: 0, trip: 4, clarity: .clear, depth: 2.5,
              note: "Came up behind the plopper three times before it ate. Shaking after."),
        .init(species: "Bluefish", spot: 0, daysAgo: 1, hour: 6.6, cm: 46, kg: 1.3,
              released: true, score: 84, gear: 0, trip: 4),
        .init(species: "Dusky Kob", spot: 2, daysAgo: 4, hour: 5.66, cm: 112, kg: 15.2,
              released: true, score: 93, fav: true, gear: 1, trip: 0, clarity: .stained, depth: 3.4,
              note: "Push tide, 40 min after the turn. Took the pearl paddle on a slow hop off the drop. Swam her ten minutes before she kicked off.",
              id: heroCatchId),
        .init(species: "Dusky Kob", spot: 2, daysAgo: 4, hour: 6.9, cm: 74, kg: 4.1,
              released: true, score: 88, gear: 1, trip: 0, clarity: .stained, depth: 2.8),
        .init(species: "Cape Stumpnose", spot: 2, daysAgo: 4, hour: 8.2, cm: 31, kg: 0.7,
              released: true, score: 71, gear: 1, trip: 0),
        .init(species: "Flathead Mullet", spot: 2, daysAgo: 4, hour: 10.5, cm: 38, kg: 0.9,
              released: true, score: 62, trip: 0),
        // Last fortnight
        .init(species: "Largemouth Bass", spot: 1, daysAgo: 11, hour: 6.2, cm: 54, kg: 2.9,
              released: true, score: 81, fav: true, gear: 0, trip: 2, clarity: .stained, depth: 1.8,
              note: "Blow-up right on a stump. Fog still sitting on the water."),
        .init(species: "Largemouth Bass", spot: 1, daysAgo: 11, hour: 7.0, cm: 41, kg: 1.4,
              released: true, score: 79, gear: 0, trip: 2),
        .init(species: "Largemouth Bass", spot: 1, daysAgo: 11, hour: 8.4, cm: 37, kg: 0.9,
              released: true, score: 74, trip: 2),
        .init(species: "Bluegill", spot: 1, daysAgo: 11, hour: 9.3, cm: 19, kg: 0.2,
              released: true, score: 70, trip: 2),
        .init(species: "Galjoen", spot: 8, daysAgo: 15, hour: 16.8, cm: 44, kg: 2.2,
              released: true, score: 76, gear: 2, clarity: .stained, depth: 1.5,
              note: "White water, red bait. Finally."),
        .init(species: "Blacktail", spot: 8, daysAgo: 15, hour: 17.4, cm: 29, kg: 0.6,
              released: true, score: 73, gear: 2),
        .init(species: "Bluefish", spot: 7, daysAgo: 18, hour: 18.9, cm: 52, kg: 1.8,
              released: false, score: 82, gear: 2, note: "Sardine on a sliding trace. Dinner."),
        // Tuna trip
        .init(species: "Yellowfin Tuna", spot: 4, daysAgo: 23, hour: 9.1, cm: 131, kg: 38.5,
              released: false, score: 90, fav: true, gear: 4, trip: 1, clarity: .clear, depth: 60,
              note: "Forty-minute fight on the jig. Birds working the whole morning."),
        .init(species: "Yellowfin Tuna", spot: 4, daysAgo: 23, hour: 10.4, cm: 104, kg: 21.0,
              released: false, score: 88, gear: 4, trip: 1, clarity: .clear, depth: 45),
        .init(species: "Dorado", spot: 4, daysAgo: 23, hour: 12.7, cm: 96, kg: 8.9,
              released: true, score: 83, fav: true, gear: 4, trip: 1,
              note: "Lit up green and gold right at the boat."),
        .init(species: "Snoek", spot: 4, daysAgo: 23, hour: 13.2, cm: 82, kg: 3.6,
              released: false, score: 80, trip: 1),
        // Harbour + reef
        .init(species: "Red Roman", spot: 0, daysAgo: 27, hour: 8.0, cm: 33, kg: 0.9,
              released: true, score: 69, gear: 2),
        .init(species: "Hottentot Seabream", spot: 3, daysAgo: 29, hour: 7.2, cm: 28, kg: 0.5,
              released: true, score: 64),
        .init(species: "Yellowtail Kingfish", spot: 3, daysAgo: 31, hour: 6.4, cm: 86, kg: 7.9,
              released: false, score: 87, fav: true, gear: 0, clarity: .clear,
              note: "Shoal pushed bait right up against the wall."),
        // Elandspad
        .init(species: "Rainbow Trout", spot: 5, daysAgo: 38, hour: 9.2, cm: 42, kg: 0.9,
              released: true, score: 75, fav: true, gear: 3, trip: 3, clarity: .clear, depth: 0.8,
              note: "Sighted in the tail of the pool. Third drift."),
        .init(species: "Rainbow Trout", spot: 5, daysAgo: 38, hour: 11.0, cm: 31, kg: 0.4,
              released: true, score: 72, gear: 3, trip: 3),
        .init(species: "Brown Trout", spot: 5, daysAgo: 38, hour: 12.4, cm: 47, kg: 1.2,
              released: true, score: 77, gear: 3, trip: 3, clarity: .clear),
        // Earlier spring / winter
        .init(species: "White Steenbras", spot: 2, daysAgo: 45, hour: 15.5, cm: 71, kg: 4.8,
              released: true, score: 78, gear: 2, note: "Pencil bait on the sandbank."),
        .init(species: "Common Carp", spot: 1, daysAgo: 52, hour: 19.5, cm: 74, kg: 9.6,
              released: true, score: 72, fav: true, gear: 5,
              note: "Third run of the night. Bobbin to the rod."),
        .init(species: "Common Carp", spot: 1, daysAgo: 52, hour: 22.1, cm: 61, kg: 5.4,
              released: true, score: 70, gear: 5),
        .init(species: "Grass Carp", spot: 1, daysAgo: 59, hour: 14.0, cm: 88, kg: 11.2,
              released: true, score: 66, gear: 5),
        .init(species: "Dusky Kob", spot: 2, daysAgo: 66, hour: 21.0, cm: 86, kg: 6.8,
              released: true, score: 85, gear: 1, clarity: .muddy),
        .init(species: "Leervis (Garrick)", spot: 2, daysAgo: 66, hour: 8.0, cm: 79, kg: 5.5,
              released: true, score: 82, gear: 1),
        .init(species: "Largemouth Bass", spot: 1, daysAgo: 73, hour: 17.5, cm: 48, kg: 2.1,
              released: true, score: 77, gear: 0),
        .init(species: "Mozambique Tilapia", spot: 1, daysAgo: 80, hour: 11.0, cm: 30, kg: 0.6,
              released: true, score: 60),
        .init(species: "African Sharptooth Catfish", spot: 1, daysAgo: 87, hour: 22.5, cm: 102, kg: 9.1,
              released: true, score: 68, gear: 5, note: "Took a carp bait at 22:30. Not what I came for."),
        // Clanwilliam
        .init(species: "Smallmouth Bass", spot: 6, daysAgo: 96, hour: 7.1, cm: 44, kg: 1.6,
              released: true, score: 80, fav: true, gear: 0, trip: 5, clarity: .clear,
              note: "Rocky point, first cast of the trip."),
        .init(species: "Smallmouth Bass", spot: 6, daysAgo: 96, hour: 8.3, cm: 38, kg: 1.0,
              released: true, score: 78, gear: 0, trip: 5),
        .init(species: "Largemouth Bass", spot: 6, daysAgo: 95, hour: 18.0, cm: 51, kg: 2.4,
              released: true, score: 74, trip: 5),
        .init(species: "Bluegill", spot: 6, daysAgo: 95, hour: 12.0, cm: 17, kg: 0.15,
              released: true, score: 61, trip: 5),
        // Winter + last summer
        .init(species: "Galjoen", spot: 0, daysAgo: 118, hour: 15.0, cm: 51, kg: 3.1,
              released: true, score: 79, gear: 2),
        .init(species: "Red Steenbras", spot: 0, daysAgo: 140, hour: 9.2, cm: 68, kg: 5.2,
              released: true, score: 74, fav: true, gear: 2, note: "Out of the deep gully. Released — slow growers."),
        .init(species: "Cape Stumpnose", spot: 2, daysAgo: 162, hour: 10.0, cm: 34, kg: 0.8,
              released: true, score: 66),
        .init(species: "Snoek", spot: 3, daysAgo: 190, hour: 7.0, cm: 88, kg: 4.2,
              released: false, score: 81, note: "Winter run. Whole harbour was on them."),
        .init(species: "Bluefish", spot: 7, daysAgo: 230, hour: 18.5, cm: 49, kg: 1.6,
              released: true, score: 77),
        .init(species: "Yellowtail Kingfish", spot: 0, daysAgo: 260, hour: 6.0, cm: 92, kg: 9.4,
              released: true, score: 86),
        .init(species: "Largemouth Bass", spot: 1, daysAgo: 300, hour: 6.4, cm: 57, kg: 3.4,
              released: true, score: 83, fav: true, gear: 0,
              note: "Personal best. Still the one to beat."),
        .init(species: "Rainbow Trout", spot: 5, daysAgo: 340, hour: 10.0, cm: 39, kg: 0.7,
              released: true, score: 70, gear: 3),
        .init(species: "Dorado", spot: 4, daysAgo: 380, hour: 11.0, cm: 104, kg: 11.6,
              released: false, score: 84, gear: 4),
        .init(species: "Giant Trevally", spot: 4, daysAgo: 410, hour: 9.0, cm: 92, kg: 12.4,
              released: true, score: 82, gear: 4, note: "Sodwana trip. Different planet."),
    ]

    // MARK: - Seeding

    @MainActor
    static func seedDemoDataIfNeeded(_ appState: AppState) {
        guard isActive else { return }
        // Idempotent: never double-seed across the per-tab relaunches.
        let existing = (try? appState.catchRepository.fetchAll()) ?? []
        guard existing.isEmpty else { return }

        let allSpecies = (try? appState.speciesRepository.fetchAll()) ?? []
        guard !allSpecies.isEmpty else { return }

        func species(_ name: String) -> Species? {
            allSpecies.first { $0.commonName.caseInsensitiveCompare(name) == .orderedSame }
                ?? allSpecies.first { $0.commonName.localizedCaseInsensitiveContains(name) }
        }

        // Spots (private, so no real location is implied).
        var spots: [Spot] = []
        for s in demoSpots {
            var spot = Spot(name: s.name, latitude: s.lat, longitude: s.lon,
                            notes: s.notes, spotType: s.type)
            try? appState.spotRepository.save(&spot)
            spots.append(spot)
        }

        // Demo dam/lake bubbles clustered around the map's screenshot camera so
        // the Explore tab shows the waterbody feature populated.
        if let data = demoWaterbodiesJSON.data(using: .utf8),
           let bodies = try? JSONDecoder().decode([Waterbody].self, from: data) {
            for var wb in bodies { try? appState.waterbodyRepository.save(&wb) }
        }

        // Gear setups.
        var gear: [GearLoadout] = []
        for g in demoGear {
            var loadout = GearLoadout(name: g.name, rod: g.rod, reel: g.reel,
                                      lineLb: g.line, leaderLb: g.leader, lure: g.lure,
                                      lureColor: g.color, lureWeightG: g.grams, technique: g.technique)
            try? appState.gearRepository.save(&loadout)
            gear.append(loadout)
        }
        seedOwnedGear(appState)

        // Completed trips with a wandering GPS track around their spot.
        var rng = SeededRandom(seed: 0xC0FFEE)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        func date(daysAgo: Int, hour: Double) -> Date {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
            return day.addingTimeInterval(hour * 3600)
        }
        var trips: [Trip] = []
        for t in demoTrips {
            let spot = spots[t.spot]
            let start = date(daysAgo: t.daysAgo, hour: t.startHour)
            let end = start.addingTimeInterval(t.hours * 3600)
            var lat = spot.latitude, lon = spot.longitude
            var heading = rng.next() * .pi * 2
            let steps = 60
            let points: [Trip.TrackPoint] = (0..<steps).map { i in
                heading += (rng.next() - 0.5) * 0.9
                let stride = t.spot == 4 ? 0.0028 : 0.00045
                lat += cos(heading) * stride
                lon += sin(heading) * stride
                return .init(lat: lat, lon: lon,
                             t: start.addingTimeInterval(Double(i) / Double(steps) * t.hours * 3600))
            }
            var trip = Trip(name: t.name, startDate: start, endDate: end, spotId: spot.id,
                            notes: t.notes, weatherConditions: t.weather,
                            trackPoints: Trip.encodeTrack(points))
            try? appState.tripRepository.save(&trip)
            trips.append(trip)
        }

        // Catches.
        let conditions = ["clear", "partly cloudy", "cloudy", "fog", "clear"]
        for c in demoCatches {
            guard let sp = species(c.species) else { continue }
            let spot = spots[c.spot]
            // Jitter each fix off the spot pin so the map clusters look real.
            let lat = spot.latitude + (rng.next() - 0.5) * 0.004
            let lon = spot.longitude + (rng.next() - 0.5) * 0.004
            let salt = [Spot.SpotType.reef, .offshore, .harbour, .beach, .rocks, .estuary]
                .contains(demoSpots[c.spot].type)
            let weather = WeatherSnapshotSeed(
                temperatureC: (salt ? 17 : 19) + (rng.next() * 8).rounded(),
                waterTempC: (salt ? 15 : 18) + (rng.next() * 6).rounded(),
                windSpeedKmh: (4 + rng.next() * 22).rounded(),
                windDirectionDeg: (rng.next() * 360).rounded(),
                pressureHpa: (1012 + rng.next() * 14).rounded(),
                condition: conditions[Int(rng.next() * Double(conditions.count)) % conditions.count])
            let confidence = 0.86 + rng.next() * 0.12
            let mlTop3 = (try? JSONEncoder().encode([MLPredictionSeed(label: sp.commonName,
                                                                      confidence: confidence)]))
                .flatMap { String(data: $0, encoding: .utf8) }

            var record = Catch(
                id: c.id ?? UUID().uuidString,
                speciesId: sp.id,
                spotId: spot.id,
                caughtAt: date(daysAgo: c.daysAgo, hour: c.hour),
                latitude: lat,
                longitude: lon,
                lengthCm: c.cm,
                weightKg: c.kg,
                released: c.released,
                mlConfidence: confidence,
                mlTop3: mlTop3,
                forecastScoreAtCapture: c.score,
                weatherSnapshot: (try? JSONEncoder().encode(weather)).flatMap { String(data: $0, encoding: .utf8) },
                gearLoadoutId: c.gear.map { gear[$0].id },
                tripId: c.trip.map { trips[$0].id },
                notes: c.note,
                isFavorite: c.fav,
                waterClarity: c.clarity,
                depthM: c.depth
            )
            // Use the app's OWN artwork as the catch photo (rights-clean).
            if let card = renderArtworkCard(assetName: sp.artworkAssetName,
                                            palette: salt ? .salt : .fresh,
                                            seed: rng.next()),
               let filename = try? PhotoManager.save(card, id: record.id) {
                record.photoPath = filename
                record.photoPaths = Catch.encodePhotoPaths([filename])
            }
            try? appState.catchRepository.save(&record)
        }

        seedDemoCommunity(species: species)
    }

    private struct WeatherSnapshotSeed: Codable {
        var temperatureC, waterTempC, windSpeedKmh, windDirectionDeg, pressureHpa: Double
        var condition: String
    }

    private struct MLPredictionSeed: Codable {
        var label: String
        var confidence: Double
    }

    @MainActor
    private static func seedOwnedGear(_ appState: AppState) {
        let items: [OwnedGear] = [
            OwnedGear(category: .rod, name: "Zodias 7'0\" M", brand: "Shimano"),
            OwnedGear(category: .rod, name: "Saltist 8'", brand: "Daiwa"),
            OwnedGear(category: .rod, name: "Foundation 9' 5wt", brand: "Sage"),
            OwnedGear(category: .reel, name: "Stradic FL 2500", brand: "Shimano"),
            OwnedGear(category: .reel, name: "BG 3000", brand: "Daiwa"),
            OwnedGear(category: .lure, name: "Whopper Plopper 110", brand: "River2Sea",
                      specs: "Bone", stock: 2, lowStockThreshold: 1),
            OwnedGear(category: .lure, name: "5\" DieZel MinnowZ", brand: "Z-Man",
                      specs: "Pearl", stock: 3, lowStockThreshold: 4),
            OwnedGear(category: .lure, name: "Senko 5\"", brand: "Yamamoto",
                      specs: "Green pumpkin", stock: 14, lowStockThreshold: 5),
            OwnedGear(category: .lure, name: "Vortex Jig 200g", brand: "Williamson",
                      specs: "Mackerel", stock: 2, lowStockThreshold: 1),
            OwnedGear(category: .line, name: "Kairiki 8 — 20 lb", brand: "Shimano", stock: 1),
            OwnedGear(category: .hook, name: "Owner SSW 2/0", brand: "Owner", stock: 9, lowStockThreshold: 10),
            OwnedGear(category: .bait, name: "Chokka strips", stock: 2, lowStockThreshold: 2),
        ]
        for var g in items { try? appState.ownedGearRepository.save(&g) }
    }

    // MARK: - Community

    /// Seed a joined Community with three crews, a lively photo feed, friends
    /// and a leaderboard — entirely from local storage (UserDefaults + the
    /// disk caches), so the Community screens photograph populated without any
    /// CloudKit round trip. All names are fictional and every fish is the
    /// app's own artwork.
    @MainActor
    private static func seedDemoCommunity(species: @escaping (String) -> Species?) {
        let d = UserDefaults.standard
        let me = (code: "KOGEL1", name: "Aidan")
        d.set(true, forKey: "communityJoined")
        d.set(me.name, forKey: "communityName")
        d.set(me.code, forKey: "communityFriendCode")
        d.set("Western Cape", forKey: "communityRegion")
        d.set(Calendar.current.date(byAdding: .month, value: -14, to: .now), forKey: "communityMemberSince")
        d.set(true, forKey: "communityDemoAdded")

        let sipho = (code: "REEF07", name: "Sipho Dlamini")
        let megan = (code: "TIDE22", name: "Megan Fourie")
        let ruan = (code: "DAMS44", name: "Ruan Botha")
        let thandi = (code: "FLY909", name: "Thandi Mokoena")
        let jess = (code: "BANK12", name: "Jess van Wyk")
        let friends = [sipho, megan, ruan, thandi, jess]
        d.set(friends.map(\.code) + [CommunityService.demoCode], forKey: "communityFriends")

        let crews = [
            CommunityService.Crew(code: "DAWN01", name: "Dawn Patrol", emoji: "🌊",
                                  createdByCode: me.code, createdByName: me.name,
                                  joinedAt: .now.addingTimeInterval(-86400 * 200),
                                  mates: [sipho.code], admins: [megan.code]),
            CommunityService.Crew(code: "BREDE5", name: "Breede Bandits", emoji: "🎣",
                                  createdByCode: sipho.code, createdByName: sipho.name,
                                  joinedAt: .now.addingTimeInterval(-86400 * 120)),
            CommunityService.Crew(code: "FLYELN", name: "Elandspad Fly Club", emoji: "🪶",
                                  createdByCode: thandi.code, createdByName: thandi.name,
                                  joinedAt: .now.addingTimeInterval(-86400 * 60)),
        ]
        if let data = try? JSONEncoder().encode(crews) { d.set(data, forKey: "myCrews") }

        var rng = SeededRandom(seed: 0xB17E)
        func post(_ crew: String, _ id: Int, _ author: (code: String, name: String),
                  _ speciesName: String, kg: Double?, cm: Double?, hoursAgo: Double,
                  caption: String, trip: String = "", comments: Int = 0, photo: Bool = true,
                  reactions: [((code: String, name: String), String)]) -> CommunityService.CrewPost {
            let postId = "crewpost-\(crew)-demo\(id)"
            var hasPhoto = false
            if photo, let sp = species(speciesName),
               let card = renderArtworkCard(assetName: sp.artworkAssetName,
                                            palette: crew == "FLYELN" ? .fresh : .salt,
                                            seed: rng.next()) {
                CommunityDiskCache.saveImage(card, key: "post-\(postId)")
                hasPhoto = true
            }
            return CommunityService.CrewPost(
                id: postId, crewCode: crew,
                authorCode: author.code, authorName: author.name,
                species: species(speciesName)?.commonName ?? speciesName,
                weightKg: kg, lengthCm: cm,
                caughtAt: Date().addingTimeInterval(-hoursAgo * 3600),
                caption: caption, hasPhoto: hasPhoto, tripName: trip,
                reactions: reactions.map {
                    CommunityService.CrewReaction(
                        id: "crewreact-\(postId)-\($0.0.code)",
                        reactorCode: $0.0.code, reactorName: $0.0.name, emoji: $0.1)
                },
                commentCount: comments)
        }

        let dawn = [
            post("DAWN01", 1, me, "Leervis (Garrick)", kg: 7.4, cm: 88, hoursAgo: 27,
                 caption: "Three swipes at the plopper before it committed. Still shaking.",
                 trip: "Kogel Bay before work", comments: 6,
                 reactions: [(sipho, "🔥"), (megan, "😮"), (ruan, "🔥"), (jess, "👏")]),
            post("DAWN01", 2, megan, "Yellowtail Kingfish", kg: 6.1, cm: 81, hoursAgo: 9,
                 caption: "Wall was alive at 6. Get here.", comments: 3,
                 reactions: [(me, "🔥"), (sipho, "🎣")]),
            post("DAWN01", 3, sipho, "Galjoen", kg: 2.6, cm: 47, hoursAgo: 52,
                 caption: "National fish, national treasure. Back she goes.", comments: 2,
                 reactions: [(me, "👏"), (megan, "🐟")]),
            post("DAWN01", 4, jess, "Bluefish", kg: 1.9, cm: 53, hoursAgo: 74,
                 caption: "Elf on the last light. Sardine fillet, no sinker.",
                 reactions: [(me, "🎣")]),
            post("DAWN01", 5, ruan, "Red Roman", kg: 1.1, cm: 35, hoursAgo: 101,
                 caption: "", photo: false, reactions: []),
        ]
        let breede = [
            post("BREDE5", 1, me, "Dusky Kob", kg: 15.2, cm: 112, hoursAgo: 4 * 24 - 5,
                 caption: "Fish of the year. 112 on the mat, swum and released.",
                 trip: "Breede mouth, spring tide", comments: 14,
                 reactions: [(sipho, "😮"), (megan, "🔥"), (ruan, "🔥"), (thandi, "👏"), (jess, "😮")]),
            post("BREDE5", 2, sipho, "Leervis (Garrick)", kg: 6.0, cm: 82, hoursAgo: 16,
                 caption: "Live mullet on the drop-off. Jumped four times.", comments: 4,
                 reactions: [(me, "🔥"), (ruan, "😮")]),
            post("BREDE5", 3, ruan, "Spotted Grunter", kg: 1.4, cm: 44, hoursAgo: 40,
                 caption: "Prawn on the flats. Tailing in 30 cm of water.", photo: false,
                 reactions: [(sipho, "🎣")]),
            post("BREDE5", 4, sipho, "White Steenbras", kg: 4.3, cm: 69, hoursAgo: 130,
                 caption: "Pencil bait on the bank, right where Aidan said.", comments: 1,
                 reactions: [(me, "👏")]),
        ]
        let fly = [
            post("FLYELN", 1, thandi, "Rainbow Trout", kg: 1.1, cm: 46, hoursAgo: 20,
                 caption: "Pool 7 fished like a dream. #16 parachute Adams.", comments: 5,
                 reactions: [(me, "🔥"), (jess, "🐟")]),
            post("FLYELN", 2, jess, "Brown Trout", kg: 0.8, cm: 39, hoursAgo: 63,
                 caption: "First wild brown. Hands shaking too much for a decent photo.",
                 comments: 8, reactions: [(thandi, "👏"), (me, "🔥"), (megan, "😮")]),
            post("FLYELN", 3, me, "Rainbow Trout", kg: 0.9, cm: 42, hoursAgo: 38 * 24 - 9,
                 caption: "Sighted in the tail of the pool. Third drift.",
                 trip: "Elandspad fly day", comments: 2, reactions: [(thandi, "🎣")]),
        ]
        CommunityDiskCache.saveFeed(dawn, for: "DAWN01")
        CommunityDiskCache.saveFeed(breede, for: "BREDE5")
        CommunityDiskCache.saveFeed(fly, for: "FLYELN")

        // Friends leaderboard: the rows a CloudKit fetch would have cached.
        func row(_ i: Int, _ who: (code: String, name: String), _ sp: String,
                 _ kg: Double, _ cm: Double, daysAgo: Double) -> CommunityService.LeaderRowDTO {
            CommunityService.LeaderRowDTO(CommunityService.LeaderRow(
                id: "demo-leader-\(i)", anglerName: who.name, friendCode: who.code,
                species: species(sp)?.commonName ?? sp, weightKg: kg, lengthCm: cm,
                catchCount: nil, region: "Western Cape",
                date: .now.addingTimeInterval(-daysAgo * 86400)))
        }
        let board: [(code: String, name: String, sp: String, kg: Double, cm: Double, days: Double)] = [
            (sipho.code, sipho.name, "Dusky Kob", 13.8, 106, 9),
            (sipho.code, sipho.name, "Leervis (Garrick)", 6.0, 82, 1),
            (sipho.code, sipho.name, "White Steenbras", 4.3, 69, 5),
            (sipho.code, sipho.name, "Galjoen", 2.6, 47, 2),
            (sipho.code, sipho.name, "Red Roman", 1.2, 36, 20),
            (sipho.code, sipho.name, "Snoek", 3.9, 85, 40),
            (megan.code, megan.name, "Yellowtail Kingfish", 6.1, 81, 0.4),
            (megan.code, megan.name, "Yellowfin Tuna", 24.5, 112, 23),
            (megan.code, megan.name, "Dorado", 7.2, 90, 23),
            (megan.code, megan.name, "Snoek", 3.1, 79, 50),
            (ruan.code, ruan.name, "Largemouth Bass", 3.1, 55, 6),
            (ruan.code, ruan.name, "Common Carp", 14.2, 86, 12),
            (ruan.code, ruan.name, "Largemouth Bass", 2.2, 49, 30),
            (ruan.code, ruan.name, "Smallmouth Bass", 1.3, 41, 33),
            (ruan.code, ruan.name, "Grass Carp", 16.0, 98, 60),
            (ruan.code, ruan.name, "Red Roman", 1.1, 35, 4),
            (ruan.code, ruan.name, "Spotted Grunter", 1.4, 44, 2),
            (thandi.code, thandi.name, "Rainbow Trout", 1.1, 46, 1),
            (thandi.code, thandi.name, "Brown Trout", 1.6, 52, 15),
            (thandi.code, thandi.name, "Rainbow Trout", 0.7, 37, 38),
            (jess.code, jess.name, "Brown Trout", 0.8, 39, 3),
            (jess.code, jess.name, "Bluefish", 1.9, 53, 3),
            (jess.code, jess.name, "Blacktail", 0.5, 27, 8),
        ]
        let rows = board.enumerated().map { i, b in
            row(i, (code: b.code, name: b.name), b.sp, b.kg, b.cm, daysAgo: b.days)
        }
        CommunityDiskCache.save(rows, key: "leadercatches")
        CommunityDiskCache.touch(key: "leadercatches")
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

    // MARK: - Artwork cards

    private enum CardPalette {
        case salt, fresh

        /// Top/bottom gradient stops; `t` (0…1) nudges the hue so a gallery of
        /// cards doesn't read as one image repeated.
        func colors(_ t: Double) -> (UIColor, UIColor) {
            switch self {
            case .salt:
                (UIColor(red: 0.05 + 0.04 * t, green: 0.17 + 0.05 * t, blue: 0.30 - 0.04 * t, alpha: 1),
                 UIColor(red: 0.01, green: 0.06, blue: 0.13, alpha: 1))
            case .fresh:
                (UIColor(red: 0.09 + 0.05 * t, green: 0.22 + 0.04 * t, blue: 0.20 + 0.03 * t, alpha: 1),
                 UIColor(red: 0.03, green: 0.08, blue: 0.08, alpha: 1))
            }
        }
    }

    /// Composite a species' transparent artwork onto a subtle water gradient so
    /// it reads as an intentional catch card rather than a cutout on black.
    private static func renderArtworkCard(assetName: String, palette: CardPalette = .salt,
                                          seed: Double = 0.5) -> UIImage? {
        guard let art = UIImage(named: assetName) else { return nil }
        let size = CGSize(width: 1000, height: 1000)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let (top, bottom) = palette.colors(seed)
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1]
            ) {
                cg.drawLinearGradient(
                    gradient, start: CGPoint(x: size.width * seed, y: 0),
                    end: CGPoint(x: size.width * (1 - seed), y: size.height), options: []
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

/// Tiny deterministic PRNG (SplitMix64) so every screenshot run seeds the
/// exact same jitter, weather and gradients.
private struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    /// Uniform in 0..<1.
    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}
