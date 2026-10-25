import SwiftUI
import UIKit
import CoreLocation

/// Support for capturing App Store screenshots deterministically in the iOS
/// Simulator (see `.github/workflows/screenshots.yml`), and for the manual UI
/// review run that captures every screen (`.github/workflows/ui-review.yml`).
///
/// Activated only when the app is launched with `SCREENSHOT_MODE=1` (passed by
/// CI via `SIMCTL_CHILD_SCREENSHOT_MODE`), so it can never affect a real
/// install. When active it:
///   - seeds a fictional angler's logbook, spots, sessions, gear and crew, and
///   - opens the screen named by `SCREENSHOT_SCREEN` (see `Screen`), so CI can
///     relaunch the app once per shot and grab one clean capture each.
///
/// Content rights: catch, spot, crew and avatar photos come from
/// `Documents/ScreenshotPhotos`, which CI copies from `ios/AppStore/demo-photos`
/// into the simulator's app container. They are Unsplash / Pexels licensed
/// (see docs/CONTENT_RIGHTS.md) and never ship in the app. When the folder is
/// missing, catches fall back to the app's own fish artwork. Every name is
/// fictional.
enum ScreenshotSupport {
    static var isActive: Bool {
        ProcessInfo.processInfo.environment["SCREENSHOT_MODE"] == "1"
            || CommandLine.arguments.contains("-screenshotMode")
    }

    /// A coastal spot (Kogel Bay, South Africa) the map centres on in
    /// screenshot mode, matching the seeded demo spots.
    static let demoCoordinate = CLLocationCoordinate2D(latitude: -34.235, longitude: 18.848)

    // MARK: - Screens

    /// The screens CI captures, by their `SCREENSHOT_SCREEN` value. The first
    /// group is the App Store set (`screenshots.yml`). The rest are the review
    /// set that `ui-review.yml` captures in light, dark and large text. Cases
    /// are declared in the order the review workflow runs them.
    enum Screen: String, CaseIterable {
        // App Store set.
        case today, logbook, crew
        /// Explore with the "Biting near you" sheet open over the map.
        case exploreNear = "explore-near"
        case explore
        /// The hero catch's page.
        case catchPage = "catch"
        /// Every lure suggestion for today.
        case lures
        case leaderboard
        /// My angler profile with the worn title.
        case profile

        // Review set: forecast pages, pushed on Today.
        case forecastDay = "forecast-day"
        case forecastWeek = "forecast-week"
        case conditionWater = "condition-water"
        case conditionAir = "condition-air"
        case conditionWind = "condition-wind"
        case conditionPressure = "condition-pressure"
        case conditionTide = "condition-tide"
        case conditionMoon = "condition-moon"
        case conditionSun = "condition-sun"
        case conditionSky = "condition-sky"
        case target
        case targetSpecies = "target-species"

        // Review set: Explore pages.
        case spotPage = "spot"
        case waterbodyPage = "waterbody"
        case speciesPage = "species"
        case spots, waters, ramps
        case speciesGuide = "species-guide"
        case regulations
        case offlineMaps = "offline-maps"

        // Review set: Logbook pages.
        case session, plan, streak, achievements, stats
        case sessions, gear, licences, fishdex

        // Review set: Crew pages.
        case crewDetail = "crew-detail"
        case crews, friends, requests, friend
        case tripSetup = "trip-setup"
        case groupTrip = "group-trip"

        // Review set: profile and settings, pushed on Today.
        case settings
        case settingsAppearance = "settings-appearance"
        case settingsUnits = "settings-units"
        case settingsNotifications = "settings-notifications"
        case settingsPrivacy = "settings-privacy"
        case settingsWidgets = "settings-widgets"
        case settingsStorage = "settings-storage"
        case settingsAbout = "settings-about"
        case settingsKnots = "settings-knots"
        case tips

        // Review set: the log-catch sheet, opened by a deep link.
        case logCatch = "log-catch"

        var tab: ContentView.Tab {
            switch self {
            case .today, .lures, .forecastDay, .forecastWeek,
                 .conditionWater, .conditionAir, .conditionWind, .conditionPressure,
                 .conditionTide, .conditionMoon, .conditionSun, .conditionSky,
                 .target, .targetSpecies,
                 .settings, .settingsAppearance, .settingsUnits, .settingsNotifications,
                 .settingsPrivacy, .settingsWidgets, .settingsStorage, .settingsAbout,
                 .settingsKnots, .tips:
                .today
            case .explore, .exploreNear, .spotPage, .waterbodyPage, .speciesPage,
                 .spots, .waters, .ramps, .speciesGuide, .regulations, .offlineMaps:
                .explore
            case .logbook, .catchPage, .session, .plan, .streak, .achievements, .stats,
                 .sessions, .gear, .licences, .fishdex, .logCatch:
                .logbook
            case .crew, .leaderboard, .profile, .crewDetail, .crews, .friends,
                 .requests, .friend, .tripSetup, .groupTrip:
                .crew
            }
        }

        /// The condition a `condition-*` screen opens.
        var condition: ForecastCondition? {
            switch self {
            case .conditionWater: .water
            case .conditionAir: .air
            case .conditionWind: .wind
            case .conditionPressure: .pressure
            case .conditionTide: .tide
            case .conditionMoon: .moon
            case .conditionSun: .sun
            case .conditionSky: .sky
            default: nil
            }
        }

        /// The settings page a `settings-*` screen opens under the profile
        /// page. The tips page sits under About.
        var settingsPage: SettingsRoute? {
            switch self {
            case .settingsAppearance: .appearance
            case .settingsUnits: .units
            case .settingsNotifications: .notifications
            case .settingsPrivacy: .privacy
            case .settingsWidgets: .widgets
            case .settingsStorage: .storage
            case .settingsAbout, .tips: .about
            case .settingsKnots: .knots
            default: nil
            }
        }
    }

    /// Every screen name, the App Store set first, in the order the review
    /// workflow runs them. `ui-review.yml` keeps the same list as its default,
    /// so the two must match.
    static let reviewScreens: [String] = Screen.allCases.map(\.rawValue)

    /// The screen CI asked for. Falls back to the older `SCREENSHOT_TAB`,
    /// whose values (today, map, catches, fish, community) still map to tabs.
    static var screen: Screen? {
        guard isActive else { return nil }
        let env = ProcessInfo.processInfo.environment
        let raw = (env["SCREENSHOT_SCREEN"] ?? env["SCREENSHOT_TAB"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let raw else { return nil }
        if let screen = Screen(rawValue: raw) { return screen }
        return ContentView.Tab(rawValue: raw).map { tab -> Screen in
            switch tab {
            case .today: .today
            case .explore: .explore
            case .logbook: .logbook
            case .crew: .crew
            }
        }
    }

    /// The tab CI asked us to open to, if any.
    static var initialTab: ContentView.Tab? { screen?.tab }

    /// What to push on that tab's stack once it is on screen, if anything.
    /// Screens that open a saved record look it up from the seeded data when
    /// this is read, so it runs after seeding. When the record is missing the
    /// screen returns nil and CI captures its tab's root instead.
    @MainActor
    static var initialPath: NavigationPath? {
        guard let screen = Self.screen, let appState = AppState.shared else { return nil }
        var path = NavigationPath()
        switch screen {
        // Tab roots, and the log-catch sheet, which `launchURL` opens.
        case .today, .logbook, .crew, .exploreNear, .explore, .logCatch:
            return nil

        // App Store set.
        case .catchPage: path.append(LogbookRoute.catchDetail(heroCatchId))
        case .lures: path.append(ForecastRoute.lures)
        case .leaderboard: path.append(CrewRoute.leaderboard(crewCode))
        case .profile: path.append(CrewRoute.myProfile)

        // Forecast pages, on Today's stack.
        case .forecastDay: path.append(ForecastRoute.day(offset: 0, hour: nil))
        case .forecastWeek: path.append(ForecastRoute.week)
        case .conditionWater, .conditionAir, .conditionWind, .conditionPressure,
             .conditionTide, .conditionMoon, .conditionSun, .conditionSky:
            guard let condition = screen.condition else { return nil }
            path.append(ForecastRoute.condition(condition, day: 0))
        case .target: path.append(ForecastRoute.target)
        case .targetSpecies: path.append(ForecastRoute.targetSpecies)

        // Explore pages, on Explore's stack.
        case .spotPage:
            guard let spot = firstDemoSpot(appState) else { return nil }
            path.append(ExploreRoute.spot(SpotRef(spot)))
        case .waterbodyPage:
            guard let waterbody = demoWaterbody(appState) else { return nil }
            path.append(ExploreRoute.waterbody(WaterbodyRef(waterbody)))
        case .speciesPage:
            guard let fish = heroSpecies(appState) else { return nil }
            path.append(ExploreRoute.species(fish))
        case .spots: path.append(ExploreRoute.spots)
        case .waters: path.append(ExploreRoute.waters)
        case .ramps: path.append(ExploreRoute.ramps)
        case .speciesGuide: path.append(ExploreRoute.speciesGuide)
        case .regulations: path.append(ExploreRoute.regulations)
        case .offlineMaps: path.append(ExploreRoute.offlineMaps)

        // Logbook pages, on Logbook's stack.
        case .session:
            guard let id = latestSessionId(appState) else { return nil }
            path.append(LogbookRoute.session(id))
        case .plan:
            guard let id = plannedSessionId(appState) else { return nil }
            path.append(LogbookRoute.plan(id))
        case .streak: path.append(LogbookRoute.streak)
        case .achievements: path.append(LogbookRoute.achievements)
        case .stats: path.append(LogbookRoute.stats)
        case .sessions: path.append(AppRoute.sessions)
        case .gear: path.append(AppRoute.gear)
        case .licences: path.append(AppRoute.licenses)
        case .fishdex: path.append(AppRoute.fishdex)

        // Crew pages, on Crew's stack.
        case .crewDetail: path.append(CrewRoute.crew(crewCode))
        case .crews: path.append(CrewRoute.crews)
        case .friends: path.append(CrewRoute.friends)
        case .requests: path.append(CrewRoute.requests)
        case .friend: path.append(CrewRoute.friend(mates[0].code))
        case .tripSetup: path.append(CrewRoute.tripSetup(crewCode: crewCode))
        case .groupTrip:
            guard let trip = demoLiveTrips(crewCode: crewCode).first else { return nil }
            path.append(CrewRoute.trip(code: trip.id, name: trip.name))

        // Profile and settings, on Today's stack. Settings pages register
        // their own routes, so the profile page goes first.
        case .settings, .settingsAppearance, .settingsUnits, .settingsNotifications,
             .settingsPrivacy, .settingsWidgets, .settingsStorage, .settingsAbout,
             .settingsKnots, .tips:
            path.append(AppRoute.profile)
            if let page = screen.settingsPage { path.append(page) }
            if screen == .tips { path.append(AboutRoute.tips) }
        }
        return path
    }

    /// A deep link to open once the tab is up, for a screen that is a sheet
    /// rather than a pushed page. Only the log-catch sheet needs one.
    static var launchURL: URL? {
        screen == .logCatch ? URL(string: "currents://log") : nil
    }

    /// Where a scrolling page opens for the review run's scrolled shots:
    /// `-uiReviewScroll center` opens it at the middle and
    /// `-uiReviewScroll bottom` at the end. Nil, the usual top, without the
    /// argument or outside screenshot mode. The design system's page
    /// modifiers read it (`reviewScrollAnchor`). x stays 0 so rows that
    /// scroll sideways still open at their leading edge.
    static let scrollAnchor: UnitPoint? = {
        guard isActive else { return nil }
        switch UserDefaults.standard.string(forKey: "uiReviewScroll") {
        case "center": return UnitPoint(x: 0, y: 0.5)
        case "bottom": return UnitPoint(x: 0, y: 1)
        default: return nil
        }
    }()

    // MARK: - Records the review screens open

    /// The first spot the demo seed saved (Kogel Bay Reef). Spots list newest
    /// first, so it is matched by name.
    @MainActor
    private static func firstDemoSpot(_ appState: AppState) -> Spot? {
        let spots = (try? appState.spotRepository.fetchAll()) ?? []
        return spots.first { $0.name == demoSpots[0].name }
    }

    /// The seeded Steenbras Dam, found by name so every run opens the same
    /// place: the bundled map rows load in the background and can outrank it
    /// by size. Else a waterbody near the demo coordinate, else any.
    @MainActor
    private static func demoWaterbody(_ appState: AppState) -> Waterbody? {
        let repository = appState.waterbodyRepository
        let named = ((try? repository.fetchAll()) ?? []).filter { $0.name == "Steenbras Dam" }
        if let seeded = named.first(where: { $0.osmId == nil }) ?? named.first { return seeded }
        let near = (try? repository.fetchNearby(latitude: demoCoordinate.latitude,
                                                longitude: demoCoordinate.longitude,
                                                radiusKm: 30)) ?? []
        return near.first ?? (try? repository.fetchAll())?.first
    }

    /// The species of the hero catch (Largemouth Bass).
    @MainActor
    private static func heroSpecies(_ appState: AppState) -> Species? {
        let catches = (try? appState.catchRepository.fetchAll(limit: 500)) ?? []
        return catches.first { $0.catchRecord.id == heroCatchId }?.species
    }

    /// The most recent finished session.
    @MainActor
    private static func latestSessionId(_ appState: AppState) -> String? {
        let trips = (try? appState.tripRepository.fetchAll()) ?? []
        return trips.first { $0.endDate != nil && $0.plannedDate == nil }?.id
    }

    /// The planned session ("Bass at first light").
    @MainActor
    private static func plannedSessionId(_ appState: AppState) -> String? {
        (try? appState.tripRepository.fetchPlanned())?.first?.id
    }

    /// The catch the catch-page shot opens. Fixed so CI can deep link to it.
    static let heroCatchId = "demo-catch-hero"

    // MARK: - Photos

    /// Licensed demo photos CI copied into the app container, by filename.
    /// Each name starts with what it shows: "bass-01.jpg", "scene-dam-01.jpg".
    private static var photoFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ScreenshotPhotos", isDirectory: true)
    }

    /// The demo photo Log catch's camera shows as its live picture, and then
    /// takes by itself, when the app is launched with
    /// `SCREENSHOT_PHOTO=<file name>`, so a screen recording shows the real
    /// capture and species ID (`.github/workflows/preview-footage.yml`).
    static var capturePhoto: UIImage? {
        guard isActive,
              let name = ProcessInfo.processInfo.environment["SCREENSHOT_PHOTO"], !name.isEmpty
        else { return nil }
        return UIImage(contentsOfFile: photoFolder.appendingPathComponent(name).path)
    }

    private static func photoNames() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: photoFolder.path)) ?? []
        return names.filter { $0.lowercased().hasSuffix(".jpg") }.sorted()
    }

    /// Hands out the demo photos for a subject in turn, so repeated catches
    /// of one species use different pictures where there are several.
    private final class PhotoPicker {
        let names: [String]
        var used: [String: Int] = [:]

        init(names: [String]) { self.names = names }

        /// The next photo whose name starts with one of `keys`, tried in order.
        func next(_ keys: [String]) -> UIImage? {
            for key in keys {
                let matches = names.filter { $0.lowercased().hasPrefix(key + "-") }
                guard !matches.isEmpty else { continue }
                let i = used[key, default: 0]
                used[key] = i + 1
                return load(matches[i % matches.count])
            }
            return nil
        }

        private func load(_ name: String) -> UIImage? {
            UIImage(contentsOfFile: ScreenshotSupport.photoFolder.appendingPathComponent(name).path)
        }
    }

    /// A square crop, scaled down, for avatars and crew icons.
    private static func square(_ image: UIImage, side: CGFloat) -> UIImage {
        let crop = min(image.size.width, image.size.height)
        let scale = side / crop
        let size = CGSize(width: side, height: side)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let w = image.size.width * scale, h = image.size.height * scale
            image.draw(in: CGRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
        }
    }

    // MARK: - Demo people

    struct DemoAngler {
        let code: String
        let name: String
        let title: String
        let bio: String
        let homeWater: String
        /// Photo subjects for the avatar: a fish or the water, never a face.
        let avatar: [String]
    }

    static let me = DemoAngler(code: "KOGEL1", name: "Jordan", title: "Unstoppable",
                               bio: "Bass on the dams, kob in the estuary.",
                               homeWater: "Steenbras Dam", avatar: ["bass"])

    static let crewCode = "DAWN01"
    static let tournamentCode = "SPRING"

    static let mates: [DemoAngler] = [
        .init(code: "REEF07", name: "Sipho", title: "Heavy Hitter",
              bio: "Estuary kob and the odd garrick.", homeWater: "Breede Estuary",
              avatar: ["drum", "scene"]),
        .init(code: "TIDE22", name: "Megan", title: "Early Riser",
              bio: "First light on the rocks.", homeWater: "Kogel Bay",
              avatar: ["scene-coast", "scene"]),
        .init(code: "KLIP31", name: "Thabo", title: "Rod Bender",
              bio: "Carp, patience and a flask of coffee.", homeWater: "Theewaterskloof Dam",
              avatar: ["carp", "scene"]),
        .init(code: "VLEI18", name: "Lauren", title: "Naturalist",
              bio: "Mountain streams and small flies.", homeWater: "Palmiet River",
              avatar: ["trout", "scene"]),
        .init(code: "BREE09", name: "Ruan", title: "Night Owl",
              bio: "Catfish after dark.", homeWater: "Hartbeespoort Dam",
              avatar: ["catfish", "scene"]),
    ]

    private static func angler(_ code: String) -> DemoAngler {
        mates.first { $0.code == code } ?? me
    }

    // MARK: - Demo species

    private struct DemoSpecies {
        let name: String
        /// Photo name prefixes, best match first.
        let photos: [String]
        let lengthCm: ClosedRange<Double>
        /// Weight in kg is about `k * length^3` for a fish in fair condition.
        let k: Double
        let spots: [Int]
        let loadout: Int
    }

    /// Indexes into `demoSpots` and `loadouts` below.
    private static let species: [DemoSpecies] = [
        .init(name: "Largemouth Bass", photos: ["bass"], lengthCm: 32...54, k: 1.76e-5, spots: [1, 2], loadout: 0),
        .init(name: "Common Carp", photos: ["carp"], lengthCm: 48...82, k: 1.75e-5, spots: [2, 5], loadout: 2),
        .init(name: "Brown Trout", photos: ["trout"], lengthCm: 30...52, k: 1.2e-5, spots: [4], loadout: 3),
        // No photo of a Dusky Kob, Leervis or Galjoen is bundled, and another
        // fish would be wrong data, so these show the species artwork instead.
        .init(name: "Dusky Kob", photos: ["kob"], lengthCm: 62...112, k: 9.0e-6, spots: [3, 0], loadout: 1),
        .init(name: "Yellowtail Kingfish", photos: ["yellowtail"], lengthCm: 70...98, k: 1.1e-5, spots: [0], loadout: 1),
        .init(name: "Nile Tilapia", photos: ["tilapia"], lengthCm: 26...40, k: 1.87e-5, spots: [5], loadout: 0),
        .init(name: "African Sharptooth Catfish", photos: ["catfish"], lengthCm: 60...104, k: 9.6e-6, spots: [5, 2], loadout: 2),
        .init(name: "Leervis (Garrick)", photos: ["garrick"], lengthCm: 72...104, k: 1.1e-5, spots: [3], loadout: 1),
        .init(name: "Galjoen", photos: ["galjoen"], lengthCm: 30...48, k: 2.3e-5, spots: [0], loadout: 1),
    ]

    private static func speciesNamed(_ name: String) -> DemoSpecies? {
        species.first { $0.name == name }
    }

    /// Photo subjects for a species shown in the crew screens.
    private static func photoKeys(_ speciesName: String) -> [String] {
        speciesNamed(speciesName)?.photos ?? ["fish"]
    }

    // MARK: - Seeding

    @MainActor
    static func seedDemoDataIfNeeded(_ appState: AppState) {
        guard isActive else { return }
        // Every launch, before the early return below: see the function.
        seedJoinedGroupTrip()
        // Idempotent: the per-shot relaunches reuse the first launch's data.
        let existing = (try? appState.catchRepository.fetchAll(limit: 1)) ?? []
        guard existing.isEmpty else { return }

        let allSpecies = (try? appState.speciesRepository.fetchAll()) ?? []
        guard !allSpecies.isEmpty else { return }

        let picker = PhotoPicker(names: photoNames())
        seedMap(appState)
        let spots = seedSpots(appState, picker: picker)
        let loadouts = seedGear(appState)
        seedCatches(appState, allSpecies: allSpecies, spots: spots, loadouts: loadouts, picker: picker)
        seedSharedCatchIds(appState)
        seedLicences(appState)
        if let bass = allSpecies.first(where: { $0.commonName == "Largemouth Bass" }) {
            UserDefaults.standard.set(Int(bass.id), forKey: "targetSpeciesId")
        }
        seedCommunity(picker: picker)
    }

    /// Dam and lake bubbles around the map's screenshot camera, so Explore
    /// shows several bite scores.
    @MainActor
    private static func seedMap(_ appState: AppState) {
        guard let data = demoWaterbodiesJSON.data(using: .utf8),
              let bodies = try? JSONDecoder().decode([Waterbody].self, from: data) else { return }
        for var wb in bodies { try? appState.waterbodyRepository.save(&wb) }
    }

    private static let demoSpots: [(name: String, lat: Double, lon: Double, type: Spot.SpotType, cover: String?)] = [
        ("Kogel Bay Reef", -34.235, 18.848, .reef, "scene-coast"),
        ("Steenbras Dam north bank", -34.186, 18.879, .dam, "scene-lake"),
        ("Theewaterskloof weed beds", -34.050, 19.280, .dam, nil),
        ("Breede Estuary channel", -34.400, 20.840, .estuary, "scene-river"),
        ("Palmiet River pools", -34.290, 18.990, .river, nil),
        ("Hartbeespoort Dam wall", -25.745, 27.858, .dam, "scene-dam"),
    ]

    @MainActor
    private static func seedSpots(_ appState: AppState, picker: PhotoPicker) -> [Spot] {
        demoSpots.enumerated().map { i, s -> Spot in
            var spot = Spot(name: s.name, latitude: s.lat, longitude: s.lon,
                            createdAt: Date(timeIntervalSinceNow: -Double(120 - i * 10) * 86_400),
                            spotType: s.type)
            if let key = s.cover, let image = picker.next([key, "scene"]),
               let file = try? PhotoManager.save(image, id: "demo-spot-\(i)") {
                spot.cover = .photo
                spot.coverPhotoPath = file
            }
            try? appState.spotRepository.save(&spot)
            return spot
        }
    }

    @MainActor
    private static func seedGear(_ appState: AppState) -> [GearLoadout] {
        var loadouts = [
            GearLoadout(name: "Dam finesse", rod: "7 ft medium spinning", reel: "2500 spinning",
                        lineLb: 10, leaderLb: 8, lure: "Ned rig", lureColor: "Green pumpkin",
                        lureWeightG: 5, technique: "Slow drag along the weed edge"),
            GearLoadout(name: "Estuary and surf", rod: "10 ft surf spinning", reel: "5000 spinning",
                        lineLb: 30, leaderLb: 40, lure: "Paddle tail swimbait", lureColor: "Pearl white",
                        lureWeightG: 28, technique: "Slow roll on the push of the tide"),
            GearLoadout(name: "Carp and catfish", rod: "12 ft carp rod", reel: "Baitrunner 6000",
                        lineLb: 15, leaderLb: 25, lure: "Corn and bread mielie meal", technique: "Hair rig on the bottom"),
            GearLoadout(name: "Stream trout", rod: "8 ft 4 wt fly", reel: "Fly reel",
                        lineLb: 4, leaderLb: 4, lure: "Bead head nymph", lureColor: "Olive",
                        technique: "Dead drift through the riffles"),
        ]
        for i in loadouts.indices { try? appState.gearRepository.save(&loadouts[i]) }

        let owned: [OwnedGear] = [
            .init(category: .rod, name: "7 ft medium spinning rod"),
            .init(category: .reel, name: "2500 spinning reel"),
            .init(category: .lure, name: "Spinnerbait, white and chartreuse", stock: 3, lowStockThreshold: 1),
            .init(category: .lure, name: "Squarebill crankbait, craw", stock: 2, lowStockThreshold: 1),
            .init(category: .lure, name: "Paddle tail swimbait, pearl", stock: 6, lowStockThreshold: 2),
            .init(category: .lure, name: "Soft plastic worm, green pumpkin", stock: 12, lowStockThreshold: 4),
            .init(category: .lure, name: "Topwater walking bait, bone", stock: 1, lowStockThreshold: 1),
            .init(category: .lure, name: "Ned rig mushroom head", stock: 8, lowStockThreshold: 3),
            .init(category: .line, name: "10 lb braid", stock: 1),
        ]
        for var g in owned { try? appState.ownedGearRepository.save(&g) }
        return loadouts
    }

    /// A small deterministic generator, so every CI run seeds the same log.
    private struct SeededRandom {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 53)
        }
        mutating func pick(_ range: ClosedRange<Double>) -> Double {
            range.lowerBound + next() * (range.upperBound - range.lowerBound)
        }
        mutating func int(_ range: ClosedRange<Int>) -> Int {
            range.lowerBound + Int(next() * Double(range.upperBound - range.lowerBound + 1))
        }
    }

    /// About three catches a week over the last 13 weeks, every week fished,
    /// so the weekly streak reaches 13 and "Unstoppable" is earned for real.
    @MainActor
    private static func seedCatches(_ appState: AppState, allSpecies: [Species], spots: [Spot],
                                     loadouts: [GearLoadout], picker: PhotoPicker) {
        let calendar = Calendar.current
        var rng = SeededRandom(state: 20_261_023)
        // Species per outing, cycled, weighted toward the dams.
        let rotation = [0, 3, 1, 0, 4, 2, 0, 6, 3, 5, 0, 7, 1, 8, 0, 2, 3, 4]
        var outing = 0
        let notes = [
            "Came up on the second cast along the weed edge.",
            "Slow roll on the push of the tide.",
            "Bit just as the wind dropped.",
            "Released after a quick photo.",
            "Hard fight in the current.",
        ]

        for week in stride(from: 12, through: 0, by: -1) {
            let outings = week == 0 ? 1 : (week % 3 == 0 ? 2 : 1)
            for o in 0..<outings {
                let dayOffset = week * 7 + (week == 0 ? 0 : 1 + o * 3)
                guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: .now) else { continue }
                // This week's outing is the hero bass session.
                let sp = week == 0 ? species[0] : species[rotation[outing % rotation.count]]
                outing += 1
                let spotIndex = week == 0 ? 1 : sp.spots[outing % sp.spots.count]
                let spot = spots[spotIndex]
                // Other fish on the outing are ones that live at that spot.
                let locals = species.filter { $0.spots.contains(spotIndex) }
                let evening = outing % 3 == 0
                var start = calendar.date(bySettingHour: evening ? 16 : 5, minute: 20, second: 0, of: day) ?? day
                if week == 0 { start = Date.now.addingTimeInterval(-4 * 3600) }
                let fishCount = week == 0 ? 2 : rng.int(1...4)

                // This week's session starts four hours before the run, so
                // its name comes from that hour, not from the rotation.
                let partName = week == 0 ? partOfDay(start) : (evening ? "evening" : "morning")
                var trip = Trip(name: "\(spot.name), \(partName)",
                                startDate: start, endDate: start.addingTimeInterval(3.5 * 3600),
                                spotId: spot.id, weatherConditions: evening ? "clear" : "cloudy")
                if week == 0 { trip.endDate = Date.now.addingTimeInterval(-1200) }
                try? appState.tripRepository.save(&trip)

                for f in 0..<fishCount {
                    let isHero = week == 0 && f == 0
                    let s = f == 0 || rng.next() < 0.5 ? sp : locals[rng.int(0...(locals.count - 1))]
                    guard let speciesRow = allSpecies.first(where: { $0.commonName == s.name }) else { continue }
                    let length = isHero ? 52 : (rng.pick(s.lengthCm) * 2).rounded() / 2
                    let weight = isHero ? 2.9 : (s.k * pow(length, 3) * rng.pick(0.9...1.1) * 10).rounded() / 10
                    let caughtAt = start.addingTimeInterval(Double(25 + f * 50) * 60 + rng.pick(0...900))
                    var record = Catch(
                        id: isHero ? heroCatchId : UUID().uuidString,
                        speciesId: speciesRow.id,
                        spotId: spot.id,
                        caughtAt: min(caughtAt, Date.now.addingTimeInterval(-1800)),
                        latitude: spot.latitude + rng.pick(-0.004...0.004),
                        longitude: spot.longitude + rng.pick(-0.004...0.004),
                        lengthCm: length,
                        weightKg: weight,
                        released: s.loadout != 1 || rng.next() < 0.6,
                        // Replaced below by the engine's score; the draw stays
                        // so the rest of the demo data comes out the same.
                        forecastScoreAtCapture: isHero ? nil : rng.int(58...93),
                        gearLoadoutId: loadouts[s.loadout].id,
                        tripId: trip.id,
                        notes: isHero ? notes[0] : (rng.next() < 0.4 ? notes[rng.int(1...4)] : nil),
                        isFavorite: isHero || rng.next() < 0.12,
                        waterClarity: s.loadout == 1 ? .stained : .clear,
                        depthM: (rng.pick(0.8...6) * 10).rounded() / 10
                    )
                    // The score the app stores when a fish is logged, without
                    // the weather the demo has none of, so the session chart
                    // and the catch page agree.
                    record.forecastScoreAtCapture = ForecastEngine.forecast(
                        date: record.caughtAt,
                        coordinate: CLLocationCoordinate2D(latitude: record.latitude, longitude: record.longitude),
                        currentPressureHpa: nil, pressureChange6h: nil,
                        waterTempC: nil, windSpeedKmh: nil, windDirection: nil,
                        species: speciesRow, isInSpawningZone: false
                    ).score
                    // Photos: the hero gets three so the pager shows, a few
                    // others get two, and the app's artwork stands in when
                    // the demo photos are missing.
                    let photoCount = isHero ? 3 : (rng.next() < 0.25 ? 2 : 1)
                    var images: [UIImage] = []
                    for _ in 0..<photoCount {
                        if let image = picker.next(s.photos) { images.append(image) }
                    }
                    if images.isEmpty, let card = renderArtworkCard(assetName: speciesRow.artworkAssetName) {
                        images = [card]
                    }
                    if let files = try? PhotoManager.saveMultiple(images, catchId: record.id), !files.isEmpty {
                        record.photoPath = files[0]
                        record.photoPaths = Catch.encodePhotoPaths(files)
                    }
                    try? appState.catchRepository.save(&record)
                }
            }
        }

        // A planned session for tomorrow morning, for the "Up next" row.
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now),
           let at = calendar.date(bySettingHour: 5, minute: 30, second: 0, of: tomorrow) {
            let spot = spots[1]
            var plan = Trip(name: "Bass at first light", startDate: at, spotId: spot.id,
                            plannedDate: at, plannedLatitude: spot.latitude, plannedLongitude: spot.longitude)
            try? appState.tripRepository.save(&plan)
        }
    }

    /// The catches the sync has sent to the shared board, as it records them
    /// once a catch is up. Your own Crew profile lists these, and friends see
    /// the same set.
    @MainActor
    private static func seedSharedCatchIds(_ appState: AppState) {
        let all = (try? appState.catchRepository.fetchAll(limit: 100_000)) ?? []
        UserDefaults.standard.set(all.map { $0.catchRecord.id }, forKey: "publishedCatchIds")
    }

    /// Two licences for the wallet: one valid for months, one that runs out
    /// within 30 days, so the expiry warning shows. Details only, no
    /// document, as if typed in by hand.
    @MainActor
    private static func seedLicences(_ appState: AppState) {
        let calendar = Calendar.current
        func day(_ offset: Int) -> Date? { calendar.date(byAdding: .day, value: offset, to: .now) }
        var licences = [
            FishingLicense(title: "Freshwater angling licence", licenseType: "Freshwater",
                           holderName: me.name, licenseNumber: "WC-FW-204318", region: "Western Cape",
                           issueDate: day(-245), expiryDate: day(120)),
            FishingLicense(title: "Recreational fishing permit", licenseType: "Marine",
                           holderName: me.name, licenseNumber: "RF-5531907", region: "South Africa",
                           issueDate: day(-347), expiryDate: day(18)),
        ]
        for i in licences.indices {
            try? appState.licenseRepository.save(&licences[i])
        }
    }

    // MARK: - Community

    /// A joined crew with members, a feed with photos, reactions and
    /// comments, a live tournament, a live trip, a leaderboard and profiles.
    /// Local storage only: CloudKit is off in screenshot mode, and
    /// CommunityService reads the demo members, standings and live trip from
    /// here (see `demoCrewMembers` and friends).
    @MainActor
    private static func seedCommunity(picker: PhotoPicker) {
        let d = UserDefaults.standard
        // These must be set before CommunityService.shared is first built.
        d.set(true, forKey: "communityJoined")
        d.set(me.name, forKey: "communityName")
        d.set(me.code, forKey: "communityFriendCode")
        d.set(true, forKey: "friendCodeClaimed")
        d.set(me.bio, forKey: "communityBio")
        d.set(me.homeWater, forKey: "communityHomeWater")
        d.set("Western Cape", forKey: "communityRegion")
        d.set(Calendar.current.date(byAdding: .month, value: -14, to: .now), forKey: "communityMemberSince")
        d.set(me.title, forKey: "communityTitle")
        d.set(false, forKey: "communityDemoAdded")
        d.set(mates.map(\.code), forKey: "communityFriends")
        for mate in mates { d.set(true, forKey: "catchaccess-\(mate.code)") }

        let crew = CommunityService.Crew(
            code: crewCode, name: "Dawn Patrol", emoji: CommunityService.crewReactionEmojis[1],
            createdByCode: me.code, createdByName: me.name,
            joinedAt: Date(timeIntervalSinceNow: -200 * 86_400),
            mates: [mates[0].code], admins: [mates[1].code])
        if let data = try? JSONEncoder().encode([crew]) {
            d.set(data, forKey: "myCrews")
        }
        if let banner = picker.next(["scene-coast", "scene"]) {
            CommunityDiskCache.saveImage(banner, key: "crewbanner-\(crewCode)")
        }
        if let icon = picker.next(["scene-lake", "scene"]) {
            CommunityDiskCache.saveImage(square(icon, side: 256), key: "crewicon-\(crewCode)")
        }

        let svc = CommunityService.shared
        if let mine = picker.next(me.avatar) { svc.saveAvatar(square(mine, side: 512)) }
        for (i, mate) in mates.enumerated() {
            let avatar = picker.next(mate.avatar).map { square($0, side: 256) }
            let profile = CommunityService.Profile(
                id: mate.code, name: mate.name, bio: mate.bio, region: "Western Cape",
                homeWater: mate.homeWater, avatar: avatar,
                memberSince: Date(timeIntervalSinceNow: -Double(300 + i * 40) * 86_400),
                totalCatches: [148, 96, 212, 61, 87][i], speciesCount: [14, 9, 11, 7, 6][i],
                bestWeightKg: [14.2, 9.8, 12.6, 2.4, 11.1][i], bestLengthCm: [118, 101, 86, 56, 108][i],
                favoriteSpecies: ["Dusky Kob", "Yellowtail Kingfish", "Common Carp",
                                  "Brown Trout", "African Sharptooth Catfish"][i],
                title: mate.title)
            svc.seedScreenshotProfile(profile, avatarData: avatar?.jpegData(compressionQuality: 0.8))
        }

        seedFeed(picker: picker)
        seedLeaderboard(picker: picker)
        seedTournament()
        seedGroupTrip(picker: picker)
    }

    /// The live trip in your own list of group trips, as joining it on the
    /// phone records it. The trip page reads the members (you are one) and
    /// the crew rows read this list, so both say you're in. Rewritten on
    /// every launch so the saved name keeps step with the trip's part-of-day
    /// name through a long capture run; any other saved trip is kept.
    private static func seedJoinedGroupTrip() {
        guard let trip = demoLiveTrips(crewCode: crewCode).first else { return }
        let joinedAt = demoGroupMembers(code: trip.id).first { $0.id == me.code }?.joinedAt ?? trip.createdAt
        let ref = CommunityService.GroupRef(code: trip.id, name: trip.name, hostName: trip.hostName,
                                            isHost: false, joinedAt: joinedAt, crewCode: crewCode)
        let d = UserDefaults.standard
        var groups = d.data(forKey: "myGroupTrips")
            .flatMap { try? JSONDecoder().decode([CommunityService.GroupRef].self, from: $0) } ?? []
        groups.removeAll { $0.code == ref.code }
        groups.append(ref)
        if let data = try? JSONEncoder().encode(groups) {
            d.set(data, forKey: "myGroupTrips")
        }
    }

    /// Photos for the live trip's catches, and a link from the trip to a
    /// session id that is never saved. The trip page links a member's
    /// session on open and would otherwise save a new open session, which
    /// would then show in every later Logbook capture.
    @MainActor
    private static func seedGroupTrip(picker: PhotoPicker) {
        for c in demoTripCatches {
            if let photo = picker.next(["bass"]) {
                CommunityDiskCache.saveImage(photo, key: "catchphoto-\(c.id)")
            }
        }
        if let trip = demoLiveTrips(crewCode: crewCode).first {
            CommunityService.shared.setGroupCode(trip.id, forTripId: "demo-group-trip-session")
        }
    }

    private static let demoPosts: [(author: String, species: String, kg: Double, cm: Double,
                                    hoursAgo: Double, caption: String)] = [
        ("KOGEL1", "Largemouth Bass", 2.9, 52, 1.5, "Topwater at first light, weed edge on the north bank"),
        ("REEF07", "Dusky Kob", 11.2, 108, 5, "Estuary on the push of the tide. Finally."),
        ("TIDE22", "Yellowtail Kingfish", 7.4, 86, 9, "Birds working off the point all morning"),
        ("KLIP31", "Common Carp", 8.6, 74, 22, "Sunset session at the dam"),
        ("VLEI18", "Brown Trout", 1.6, 48, 30, "Cold start, worth it"),
        ("BREE09", "African Sharptooth Catfish", 9.8, 96, 46, "Night shift on the river"),
        ("KOGEL1", "Leervis (Garrick)", 9.1, 94, 60, "Released after a quick photo"),
        ("TIDE22", "Largemouth Bass", 2.2, 47, 75, ""),
        ("REEF07", "Galjoen", 1.8, 42, 98, "White water and red bait"),
        ("KLIP31", "Nile Tilapia", 1.1, 38, 120, ""),
    ]

    private static let demoComments: [Int: [(String, String, Double)]] = [
        0: [("REEF07", "That is a proper dam bass", 1.2), ("TIDE22", "Which bait?", 1.0),
            ("KOGEL1", "Walking bait in bone, right at sunrise", 0.8)],
        1: [("KOGEL1", "Huge. What was the tide doing?", 4.5), ("BREE09", "Respect", 4.0)],
        3: [("VLEI18", "Beautiful fish", 20)],
        5: [("KLIP31", "How late were you out?", 40), ("BREE09", "Until the coffee ran out", 39)],
    ]

    @MainActor
    private static func seedFeed(picker: PhotoPicker) {
        let emojis = CommunityService.crewReactionEmojis
        let everyone = [me] + mates
        var feed: [CommunityService.CrewPost] = []
        for (i, p) in demoPosts.enumerated() {
            let id = "crewpost-\(crewCode)-demo\(i + 1)"
            let author = angler(p.author)
            let photo = picker.next(photoKeys(p.species))
            if let photo { CommunityDiskCache.saveImage(photo, key: "post-\(id)") }
            let reactors = everyone.filter { $0.code != p.author }.prefix(max(1, 5 - i / 2))
            let reactions = reactors.enumerated().map { j, r in
                CommunityService.CrewReaction(id: "crewreact-\(id)-\(r.code)", reactorCode: r.code,
                                              reactorName: r.name, emoji: emojis[(i + j) % emojis.count])
            }
            let comments = (demoComments[i] ?? []).enumerated().map { j, c in
                CommunityService.CrewComment(
                    id: "crewcomment-demo\(i + 1)-\(j)", postId: id, crewCode: crewCode,
                    authorCode: c.0, authorName: angler(c.0).name, text: c.1,
                    createdAt: Date(timeIntervalSinceNow: -c.2 * 3600))
            }
            if !comments.isEmpty { CommunityDiskCache.save(comments, key: "comments-\(id)") }
            feed.append(CommunityService.CrewPost(
                id: id, crewCode: crewCode, authorCode: author.code, authorName: author.name,
                species: p.species, weightKg: p.kg, lengthCm: p.cm,
                caughtAt: Date(timeIntervalSinceNow: -p.hoursAgo * 3600),
                caption: p.caption, hasPhoto: photo != nil, tripName: "",
                reactions: reactions, commentCount: comments.count))
        }
        CommunityDiskCache.saveFeed(feed, for: crewCode)
    }

    /// The crew's catches for the leaderboard (mine come from the logbook).
    private static let demoLeaderCatches: [(code: String, species: String, kg: Double, cm: Double, daysAgo: Double)] = [
        ("REEF07", "Dusky Kob", 11.2, 108, 0.2), ("REEF07", "Dusky Kob", 14.2, 118, 19),
        ("REEF07", "Galjoen", 1.8, 42, 4), ("REEF07", "Leervis (Garrick)", 8.4, 92, 27),
        ("TIDE22", "Yellowtail Kingfish", 7.4, 86, 0.4), ("TIDE22", "Yellowtail Kingfish", 9.8, 97, 33),
        ("TIDE22", "Largemouth Bass", 2.2, 47, 3),
        ("KLIP31", "Common Carp", 8.6, 74, 1), ("KLIP31", "Common Carp", 12.6, 86, 24),
        ("KLIP31", "Nile Tilapia", 1.1, 38, 5),
        ("VLEI18", "Brown Trout", 1.6, 48, 1.3), ("VLEI18", "Brown Trout", 2.4, 56, 15),
        ("BREE09", "African Sharptooth Catfish", 9.8, 96, 2), ("BREE09", "African Sharptooth Catfish", 11.1, 108, 41),
    ]

    @MainActor
    private static func seedLeaderboard(picker: PhotoPicker) {
        let rows: [CommunityService.LeaderRowDTO] = demoLeaderCatches.enumerated().map { i, c -> CommunityService.LeaderRowDTO in
            let id = "leader-demo-\(i)"
            let photo = picker.next(photoKeys(c.species))
            if let photo { CommunityDiskCache.saveImage(photo, key: "catchphoto-\(id)") }
            let row = CommunityService.LeaderRow(
                id: id, anglerName: angler(c.code).name, friendCode: c.code, species: c.species,
                weightKg: c.kg, lengthCm: c.cm, catchCount: nil, region: "Western Cape",
                date: Date(timeIntervalSinceNow: -c.daysAgo * 86_400),
                localPhotoPath: nil, hasRemotePhoto: photo != nil, coordinate: nil)
            return CommunityService.LeaderRowDTO(row)
        }
        // Smaller fish without photos, so the most fish board is a close race
        // (the logbook has about 40) while the photo grids keep the big ones.
        let totals = ["REEF07": 37, "TIDE22": 33, "KLIP31": 28, "VLEI18": 23, "BREE09": 19]
        var filler: [CommunityService.LeaderRowDTO] = []
        for (code, total) in totals.sorted(by: { $0.key < $1.key }) {
            let mine = demoLeaderCatches.filter { $0.code == code }
            guard let first = mine.first else { continue }
            for n in 0..<max(0, total - mine.count) {
                let row = CommunityService.LeaderRow(
                    id: "leader-demo-\(code)-\(n)", anglerName: angler(code).name, friendCode: code,
                    species: first.species, weightKg: 0.6 + Double(n % 5) * 0.12, lengthCm: 30 + Double(n % 7),
                    catchCount: nil, region: "Western Cape",
                    date: Date(timeIntervalSinceNow: -Double(2 + n * 2) * 86_400),
                    localPhotoPath: nil, hasRemotePhoto: false, coordinate: nil)
                filler.append(CommunityService.LeaderRowDTO(row))
            }
        }
        let all = rows + filler
        CommunityDiskCache.save(all, key: "leadercatches")
        // A crew board caches under its own key: "leadercatches-" and the
        // sorted member codes, mine included, joined by "-", exactly as
        // CommunityService.fetchAllLeaderCatches builds it.
        let boardCodes = Set(demoCrewMembers(code: crewCode).map(\.id)).union([me.code]).sorted()
        CommunityDiskCache.save(all, key: "leadercatches-\(boardCodes.joined(separator: "-"))")

        // A friend's page lists their catches from "angler-catches-<code>"
        // (CommunityService.cachedAnglerCatches), newest first: the photo
        // rows above, which hold every catch the crew feed shows.
        for mate in mates {
            let theirs = rows.filter { $0.friendCode == mate.code }.sorted { $0.date > $1.date }
            CommunityDiskCache.save(theirs, key: "angler-catches-\(mate.code)")
        }
    }

    private static var demoTournament: CommunityService.Tournament {
        CommunityService.Tournament(
            id: tournamentCode, name: "Spring bass open", crewCode: crewCode,
            hostCode: me.code, hostName: me.name,
            createdAt: Date(timeIntervalSinceNow: -30 * 3600),
            endsAt: Date(timeIntervalSinceNow: 18 * 3600),
            endedAt: nil, winnerTeam: nil,
            pointsPerFish: 10, pointsPerKg: 1, speciesBonus: 5)
    }

    @MainActor
    private static func seedTournament() {
        let current = demoTournament
        let past = CommunityService.Tournament(
            id: "WINTER", name: "Winter kob classic", crewCode: crewCode,
            hostCode: mates[0].code, hostName: mates[0].name,
            createdAt: Date(timeIntervalSinceNow: -62 * 86_400),
            endsAt: Date(timeIntervalSinceNow: -60 * 86_400),
            endedAt: Date(timeIntervalSinceNow: -60 * 86_400), winnerTeam: "Estuary rats",
            pointsPerFish: 10, pointsPerKg: 1, speciesBonus: 5)
        CommunityDiskCache.save(current, key: "tournament-\(crewCode)")
        CommunityDiskCache.save([current, past], key: "tournaments-\(crewCode)")
    }

    // MARK: - Demo answers for CommunityService

    /// Crew members, for `CommunityService.crewMembers` in screenshot mode.
    static func demoCrewMembers(code: String) -> [CommunityService.GroupMember] {
        guard code == crewCode else { return [] }
        return ([me] + mates).enumerated().map { i, a in
            CommunityService.GroupMember(id: a.code, name: a.name,
                                         joinedAt: Date(timeIntervalSinceNow: -Double(200 - i * 12) * 86_400))
        }
    }

    /// Live team standings, for `CommunityService.teamStandings`.
    static func demoStandings(tournament: CommunityService.Tournament) -> [CommunityService.TeamStanding] {
        guard tournament.id == tournamentCode else { return [] }
        let teams: [(code: String, name: String, members: [String],
                     fish: [(String, String, Double, Double, Double)])] = [
            ("TEAMA1", "Weed edge", ["KOGEL1", "VLEI18"], [
                ("KOGEL1", "Largemouth Bass", 2.9, 52, 1.5), ("KOGEL1", "Largemouth Bass", 1.4, 41, 20),
                ("VLEI18", "Brown Trout", 1.6, 48, 6), ("KOGEL1", "Common Carp", 6.2, 68, 26),
            ]),
            ("TEAMB2", "Estuary rats", ["REEF07", "BREE09"], [
                ("REEF07", "Dusky Kob", 11.2, 108, 5), ("BREE09", "African Sharptooth Catfish", 9.8, 96, 22),
            ]),
            ("TEAMC3", "Point break", ["TIDE22", "KLIP31"], [
                ("TIDE22", "Yellowtail Kingfish", 7.4, 86, 9), ("KLIP31", "Common Carp", 8.6, 74, 22),
                ("TIDE22", "Largemouth Bass", 2.2, 47, 12),
            ]),
        ]
        return teams.map { team -> CommunityService.TeamStanding in
            let catches = team.fish.enumerated().map { i, f in
                CommunityService.GroupCatch(id: "\(team.code)-\(i)", anglerName: angler(f.0).name,
                                            friendCode: f.0, species: f.1, weightKg: f.2, lengthCm: f.3,
                                            date: Date(timeIntervalSinceNow: -f.4 * 3600))
            }
            let score = TournamentPoints.score(catches.map { (species: $0.species, weightKg: $0.weightKg) },
                                               rates: tournament.rates)
            return CommunityService.TeamStanding(
                id: team.code, teamName: team.name, points: score.points, fishCount: score.fish,
                totalWeightKg: score.weightKg, speciesCount: score.species, memberCodes: team.members,
                isEnded: false, hostCode: team.members[0], hostName: angler(team.members[0]).name,
                catches: catches)
        }
        .sorted { $0.points > $1.points }
    }

    /// A crewmate's session in progress, for `CommunityService.liveCrewTrips`.
    /// Named for the part of the day it started in, so the name agrees with
    /// the times shown beside it whenever CI runs.
    static func demoLiveTrips(crewCode code: String) -> [CommunityService.GroupTrip] {
        guard code == crewCode else { return [] }
        let started = Date(timeIntervalSinceNow: -5400)
        return [CommunityService.GroupTrip(
            id: "EVEN42", name: "Steenbras \(partOfDay(started))", hostCode: mates[1].code,
            hostName: mates[1].name, createdAt: started, isHost: false, endedAt: nil, crewCode: code)]
    }

    /// The live trip by its join code, for `CommunityService.groupTrip`.
    static func demoGroupTrip(code: String) -> CommunityService.GroupTrip? {
        demoLiveTrips(crewCode: crewCode).first { $0.id == code }
    }

    /// Who is on the live trip, for `CommunityService.groupMembers`: the host,
    /// two crewmates and me, so the trip page opens as a member sees it.
    static func demoGroupMembers(code: String) -> [CommunityService.GroupMember] {
        guard let trip = demoGroupTrip(code: code) else { return [] }
        let joined: [(code: String, minutesIn: Double)] = [
            (mates[1].code, 0), (mates[0].code, 10), (me.code, 25), (mates[2].code, 40),
        ]
        return joined.map { j in
            CommunityService.GroupMember(id: j.code, name: angler(j.code).name,
                                         joinedAt: trip.createdAt.addingTimeInterval(j.minutesIn * 60))
        }
    }

    /// Catches shared into the live trip, newest first. Bass, the fish the
    /// demo log has at Steenbras. `seedCommunity` caches a photo for each id.
    private static let demoTripCatches: [(id: String, code: String, kg: Double, cm: Double, minutesAgo: Double)] = [
        ("grouptrip-demo-1", "TIDE22", 0.9, 37, 12),
        ("grouptrip-demo-2", "REEF07", 1.2, 40, 34),
        ("grouptrip-demo-3", "KLIP31", 1.7, 45, 51),
        ("grouptrip-demo-4", "TIDE22", 2.2, 49, 70),
    ]

    /// The live trip's catch feed, for `CommunityService.groupCatches`.
    static func demoGroupCatches(code: String) -> [CommunityService.GroupCatch] {
        guard demoGroupTrip(code: code) != nil else { return [] }
        return demoTripCatches.map { c in
            CommunityService.GroupCatch(id: c.id, anglerName: angler(c.code).name, friendCode: c.code,
                                        species: "Largemouth Bass", weightKg: c.kg, lengthCm: c.cm,
                                        date: Date(timeIntervalSinceNow: -c.minutesAgo * 60))
        }
    }

    /// "morning", "afternoon", "evening" or "night" for the hour a demo
    /// session started, so its name matches its start time.
    private static func partOfDay(_ date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 4..<12: "morning"
        case 12..<17: "afternoon"
        case 17..<21: "evening"
        default: "night"
        }
    }

    // MARK: - Fallback artwork

    /// Dam and lake waterbodies near the demo map camera.
    private static let demoWaterbodiesJSON = """
    [
      {"name":"Steenbras Dam","type":"dam","latitude":-34.185,"longitude":18.864,"surfaceAreaKm2":6.6,"maxDepthM":42,"isPublic":true},
      {"name":"Kogelberg Dam","type":"dam","latitude":-34.278,"longitude":18.902,"surfaceAreaKm2":2.1,"maxDepthM":18,"isPublic":true},
      {"name":"Rooiels Vlei","type":"lake","latitude":-34.302,"longitude":18.822,"surfaceAreaKm2":0.8,"maxDepthM":6,"isPublic":true},
      {"name":"Palmiet Reservoir","type":"dam","latitude":-34.334,"longitude":18.861,"surfaceAreaKm2":3.4,"maxDepthM":22,"isPublic":true},
      {"name":"Hangklip Pan","type":"lake","latitude":-34.361,"longitude":18.842,"surfaceAreaKm2":0.5,"maxDepthM":4,"isPublic":true}
    ]
    """

    /// A species' own artwork on a flat dark card, used when the demo photos
    /// are missing.
    private static func renderArtworkCard(assetName: String) -> UIImage? {
        guard let art = UIImage(named: assetName) else { return nil }
        let size = CGSize(width: 1000, height: 1000)
        let background = UIColor.secondarySystemBackground
            .resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        return UIGraphicsImageRenderer(size: size).image { ctx in
            background.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let pad: CGFloat = 90
            let scale = min((size.width - pad * 2) / art.size.width, (size.height - pad * 2) / art.size.height)
            let w = art.size.width * scale, h = art.size.height * scale
            art.draw(in: CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h))
        }
    }
}
