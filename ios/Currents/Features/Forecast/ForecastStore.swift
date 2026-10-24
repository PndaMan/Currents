import SwiftUI
import CoreLocation

/// Where a forecast page goes when pushed from Today (or the forecast sheet).
enum ForecastRoute: Hashable {
    /// A day page, `offset` days from today, optionally with an hour selected.
    case day(offset: Int, hour: Int?)
    case week
    case condition(ForecastCondition, day: Int)
    /// Every lure suggestion, with the colours for the water.
    case lures
    /// Choose the species the forecast and lures are tuned for.
    case targetSpecies
    /// The target page: today's bite for the species, where to find it, the
    /// rules and your record with it. Explains targeting when none is set.
    case target
}

/// The eight condition tiles and their pages.
enum ForecastCondition: String, CaseIterable, Hashable, Identifiable {
    case water, air, wind, pressure, tide, moon, sun, sky

    var id: String { rawValue }

    var title: String {
        switch self {
        case .water: "Water temperature"
        case .air: "Air temperature"
        case .wind: "Wind"
        case .pressure: "Pressure"
        case .tide: "Tides"
        case .moon: "Moon and solunar"
        case .sun: "Sun"
        case .sky: "Sky and rain"
        }
    }

    var tint: Color {
        switch self {
        case .water: Color.dsScoreLow
        case .air: Color.dsScoreLow
        case .wind: Color(red: 0.39, green: 0.82, blue: 1.0) // ui-lint: allow, condition colours from the mockup
        case .pressure: Color(red: 0.75, green: 0.35, blue: 0.95) // ui-lint: allow, condition colours from the mockup
        case .tide: Color(red: 0.04, green: 0.52, blue: 1.0) // ui-lint: allow, condition colours from the mockup
        case .moon: Color.dsScoreFair
        case .sun: Color.dsScoreLow
        case .sky: .blue
        }
    }

    /// The tint for text and small glyphs: the same hue, darkened in light
    /// mode so yellow, orange and light blue stay readable on white.
    var ink: Color { DS.ink(tint) }
}

/// One day of the forecast with everything a page needs, all worked out on
/// the phone from the cached weather, the tide model and the moon.
struct ForecastDay {
    let offset: Int
    let date: Date
    let result: ForecastEngine.ForecastResult
    let solunar: SolunarEngine.SolunarDay
    let tide: TideEngine.TideDay
    /// Live conditions for today, the daily outlook for later days.
    let weather: WeatherService.WeatherData?
    /// That day's hourly weather. Empty when it was never fetched (offline,
    /// or further out than the hourly forecast reaches).
    let hours: [WeatherService.HourlyPoint]
    let windows: [BiteWindows.Window]

    var isToday: Bool { offset == 0 }

    /// The day's best hour. Day pages, the week and the day cards rank days
    /// by this; the Today hero shows `result.score`, the score right now.
    var peakScore: Int { result.hourlyScores.map(\.score).max() ?? result.score }

    var bestWindow: BiteWindows.Window? { windows.max { $0.peakScore < $1.peakScore } }

    var bestHour: Int {
        result.hourlyScores.max { $0.score < $1.score }?.hour ?? 6
    }

    func score(at hour: Int) -> Int? {
        result.hourlyScores.first { $0.hour == hour }?.score
    }

    func hourWeather(_ hour: Int) -> WeatherService.HourlyPoint? {
        hours.first { Calendar.current.component(.hour, from: $0.date) == hour }
    }

    /// Air temperature range across the day, when hourly data exists.
    var airRange: ClosedRange<Double>? {
        let temps = hours.map(\.temperatureC)
        guard let lo = temps.min(), let hi = temps.max() else { return nil }
        return lo...hi
    }

    /// The next high or low after now (today), or the day's first one.
    var nextTide: TideEngine.TideEvent? {
        let events = (tide.highTides + tide.lowTides).sorted { $0.time < $1.time }
        if isToday, let next = events.first(where: { $0.time > .now }) { return next }
        return events.first
    }
}

/// The forecast behind Today and the pushed forecast pages. Owns the location,
/// the target species and the cached weather; computes each day on demand.
@MainActor
@Observable
final class ForecastStore {
    /// Cape Town, used when location is off or not yet known.
    static let fallbackCoordinate = CLLocationCoordinate2D(latitude: -33.9, longitude: 18.4)

    private(set) var coordinate: CLLocationCoordinate2D = ForecastStore.fallbackCoordinate
    private(set) var placeName: String = "Cape Town"
    private(set) var species: Species?
    private(set) var current: WeatherService.WeatherData?
    private(set) var outlook: [WeatherService.WeatherData] = []
    private(set) var hourly: [WeatherService.HourlyPoint] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    /// Bumped whenever inputs change, so views can animate to new numbers.
    private(set) var revision = 0

    @ObservationIgnored private var cache: [Int: ForecastDay] = [:]

    /// True at a saved freshwater spot, false at a saltwater one, nil when
    /// the place does not say (the phone's location, an estuary).
    private(set) var freshwater: Bool?

    /// Tides matter here: not at a freshwater spot, and not for a target
    /// that lives in fresh water.
    var showsTide: Bool {
        if freshwater == true { return false }
        return ForecastEngine.SpeciesTraits(species).tide != .ignored
    }

    func setLocation(_ coordinate: CLLocationCoordinate2D, name: String, freshwater: Bool? = nil) {
        let moved = abs(coordinate.latitude - self.coordinate.latitude) > 0.0001
            || abs(coordinate.longitude - self.coordinate.longitude) > 0.0001
        self.placeName = name
        self.freshwater = freshwater
        guard moved else { return }
        self.coordinate = coordinate
        invalidate()
    }

    func setSpecies(_ species: Species?) {
        guard species?.id != self.species?.id else { return }
        self.species = species
        invalidate()
    }

    /// Cached weather first, live when there is signal. The weather saved on
    /// the phone is shown before any request goes out, so a weak signal never
    /// holds the page up. `force` skips the freshness cache (pull to refresh,
    /// the refresh button). Returns false when the weather service could not
    /// be reached and saved or estimated weather is showing instead.
    @discardableResult
    func load(force: Bool = false) async -> Bool {
        isLoading = true
        let coord = coordinate
        let saved = await WeatherService.shared.saved(for: coord)
        if saved.current != nil || !saved.days.isEmpty {
            if let c = saved.current { current = c }
            if !saved.days.isEmpty { outlook = saved.days }
            hasLoaded = true
            invalidate()
        }
        // The three requests run side by side; each waits at most 10 s.
        async let reading = WeatherService.shared.currentReading(for: coord, force: force)
        async let days = WeatherService.shared.forecastDays(for: coord, force: force)
        async let hours = WeatherService.shared.hourlyForecast(for: coord)
        let latest = await reading
        current = latest.data
        invalidate()
        let outlookDays = await days
        if !outlookDays.isEmpty || outlook.isEmpty {
            outlook = outlookDays
            invalidate()
        }
        if let h = await hours {
            hourly = h.hours
            invalidate()
        }
        isLoading = false
        hasLoaded = true
        return latest.isLive
    }

    /// After a pull to refresh: a soft tap when fresh weather came back, a
    /// note when the weather service could not be reached.
    static func refreshFeedback(_ live: Bool) {
        if live {
            Haptics.softPress()
        } else {
            ToastCenter.shared.show("No signal, showing saved weather", style: .info, haptic: false, icon: "wifi.slash")
        }
    }

    /// Weather for a day: live for today, the daily outlook for later days.
    func weather(for offset: Int) -> WeatherService.WeatherData? {
        if offset == 0 { return current ?? outlook.first }
        return outlook.indices.contains(offset) ? outlook[offset] : nil
    }

    /// When the weather was last really fetched (today's reading). An
    /// offline estimate has no fetch time, so it never reads as updated.
    var updatedAt: Date? {
        if let c = current { return c.isEstimated ? nil : c.fetchedAt }
        return outlook.first?.fetchedAt
    }

    /// True when nothing was ever fetched for this place and only the
    /// barometer's pressure is real. Temperature, wind and sky are unknown.
    var weatherIsEstimate: Bool { current?.isEstimated == true }

    /// "Updated 3 h ago" once the weather is more than an hour old, for the
    /// note under each forecast page's hero. Nil while it is fresh.
    var staleNote: String? {
        if weatherIsEstimate { return "No weather offline. Pull to refresh when you have signal." }
        guard let updated = updatedAt, Date.now.timeIntervalSince(updated) > 3600 else { return nil }
        return ForecastFormat.updated(updated) + ". Pull to refresh when you have signal."
    }

    func day(_ offset: Int) -> ForecastDay {
        if let cached = cache[offset] { return cached }
        let cal = Calendar.current
        let computed = ForecastEngine.day(offset, coordinate: coordinate, current: current,
                                          outlook: outlook, species: species)
        let date = computed.date
        let w = computed.weather
        var result = computed.result
        if offset == 0, weatherIsEstimate, let reading = w {
            // Offline with nothing saved: only the barometer is real, so
            // score without the placeholder wind and water.
            result = ForecastEngine.forecast(
                date: date, coordinate: coordinate,
                currentPressureHpa: reading.pressureHpa, pressureChange6h: reading.pressureChange6h,
                waterTempC: nil, windSpeedKmh: nil, windDirection: nil,
                species: species, isInSpawningZone: false)
        }
        let day = ForecastDay(
            offset: offset,
            date: date,
            result: result,
            solunar: SolunarEngine.compute(date: date, coordinate: coordinate),
            tide: TideEngine.predict(date: date, coordinate: coordinate),
            weather: w,
            hours: hourly.filter { cal.isDate($0.date, inSameDayAs: date) },
            windows: BiteWindows.best(from: result.hourlyScores)
        )
        cache[offset] = day
        return day
    }

    /// The engine's drill-down for one hour of a day (the eight factor cells).
    func hourDetail(day offset: Int, hour: Int) -> ForecastEngine.ForecastResult {
        let d = day(offset)
        let w = d.weather
        let estimate = offset == 0 && weatherIsEstimate
        return ForecastEngine.forecastForHour(
            hour: hour,
            date: d.date,
            coordinate: coordinate,
            currentPressureHpa: w?.pressureHpa,
            pressureChange6h: w?.pressureChange6h,
            waterTempC: estimate ? nil : w?.waterTempC,
            windSpeedKmh: estimate ? nil : w?.windSpeedKmh,
            species: species,
            isInSpawningZone: false
        )
    }

    private func invalidate() {
        cache.removeAll()
        revision += 1
    }
}

/// Words and times for the forecast pages.
enum ForecastFormat {
    /// The verdict line for the current hour, used only on Today's hero. For
    /// any other score use `grade(_:)`.
    static func verdict(_ score: Int) -> String {
        switch score {
        case 80...: "Excellent, go now"
        case 65..<80: "Good conditions"
        case 50..<65: "Fair, work for them"
        default: "Slow, finesse it"
        }
    }

    /// A bite score as one word, for any score that is not about the current
    /// hour: "Excellent", "Good", "Fair", "Slow". Same thresholds as `verdict`.
    static func grade(_ score: Int) -> String {
        switch score {
        case 80...: "Excellent"
        case 65..<80: "Good"
        case 50..<65: "Fair"
        default: "Slow"
        }
    }

    /// A duration, "45 min", "2 h 15 min", "3 h". Under a minute is "1 min".
    static func elapsed(_ seconds: TimeInterval) -> String {
        let whole = seconds.isFinite ? Int(max(0, seconds)) : 0
        let minutes = max(1, whole / 60)
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    /// The user's 24-hour setting, for code that is not a view. Views read
    /// @AppStorage("use24HourTime") so they redraw when it changes.
    static var use24: Bool { UserDefaults.standard.object(forKey: "use24HourTime") as? Bool ?? true }

    /// "Updated 20 min ago", "Updated 3 h ago", "Updated 2 days ago".
    static func updated(_ date: Date, now: Date = .now) -> String {
        let age = max(0, now.timeIntervalSince(date))
        if age < 60 { return "Updated just now" }
        if age < 3600 { return "Updated \(elapsed(age)) ago" }
        if age < 86_400 { return "Updated \(elapsed((age / 3600).rounded(.down) * 3600)) ago" }
        let days = Int(age / 86_400)
        return "Updated \(days) \(days == 1 ? "day" : "days") ago"
    }

    /// Engine reasons used to join clauses with dashes; any that still do
    /// read better with commas.
    static func clean(_ reason: String) -> String {
        reason.replacingOccurrences(of: " — ", with: ", ")
            .replacingOccurrences(of: " - ", with: ", ")
    }

    static func guidance(_ score: Int) -> String {
        clean(BiteWindows.guidance(forScore: score))
    }

    static func hour(_ h: Int, use24: Bool) -> String {
        let hh = ((h % 24) + 24) % 24
        if use24 { return String(format: "%02d:00", hh) }
        let display = hh % 12 == 0 ? 12 : hh % 12
        return "\(display) \(hh < 12 ? "am" : "pm")"
    }

    static func time(_ date: Date, use24: Bool) -> String {
        let f = DateFormatter()
        f.dateFormat = use24 ? "HH:mm" : "h:mm a"
        f.amSymbol = "am"
        f.pmSymbol = "pm"
        return f.string(from: date)
    }

    /// A time in the user's setting, "06:40" or "6:40 am".
    static func time(_ date: Date) -> String { time(date, use24: use24) }

    static func range(_ w: BiteWindows.Window, use24: Bool) -> String {
        "\(hour(w.startHour, use24: use24)) to \(hour(w.endHour + 1, use24: use24))"
    }

    static func longDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE d MMMM"
        return f.string(from: date)
    }

    static func shortDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date)
    }

    static func dayName(_ offset: Int, date: Date) -> String {
        if offset == 0 { return "Today" }
        if offset == 1 { return "Tomorrow" }
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f.string(from: date)
    }

    static func dayNumber(_ date: Date) -> String {
        "\(Calendar.current.component(.day, from: date))"
    }

    /// Eight-point compass, "SW".
    static func compass(_ degrees: Double) -> String {
        let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let i = Int(((degrees.truncatingRemainder(dividingBy: 360) + 360 + 22.5) / 45)) % 8
        return names[i]
    }

    /// "south-west", for sentences.
    static func compassWord(_ degrees: Double) -> String {
        let names = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
        let i = Int(((degrees.truncatingRemainder(dividingBy: 360) + 360 + 22.5) / 45)) % 8
        return names[i]
    }

    /// "Waxing gibbous", in sentence case whatever the engine's name.
    static func moonName(_ phase: MoonPhase) -> String {
        let name = phase.displayName
        guard let first = name.first else { return name }
        return String(first) + name.dropFirst().lowercased()
    }

    /// Falling 1.2 hPa, Rising 0.04 inHg or Steady. The time span is the
    /// caller's label.
    static func pressureTrend(_ change: Double, imperial: Bool = Units.isImperial) -> String {
        if abs(change) < 0.5 { return "Steady" }
        let word = change < 0 ? "Falling" : "Rising"
        return "\(word) \(Units.pressureChange(hpa: change, imperial: imperial))"
    }

    static func condition(_ raw: String) -> String {
        guard let first = raw.first else { return raw }
        return String(first).uppercased() + raw.dropFirst()
    }

    /// Icon for a time of day, used on window tiles.
    static func windowIcon(_ hour: Int) -> String {
        switch hour {
        case 4..<8: "sunrise"
        case 8..<17: "sun.max"
        case 17..<20: "sunset"
        default: "moon.stars"
        }
    }

    static func windowName(_ hour: Int) -> String {
        switch hour {
        case 4..<8: "Dawn"
        case 8..<11: "Morning"
        case 11..<15: "Midday"
        case 15..<17: "Afternoon"
        case 17..<20: "Dusk"
        default: "Night"
        }
    }

    /// SF Symbol for an hour of weather.
    static func weatherSymbol(cloud: Int, precipMm: Double, hour: Int) -> String {
        let night = hour < 6 || hour >= 19
        if precipMm >= 1 { return "cloud.rain" }
        if precipMm >= 0.2 { return "cloud.drizzle" }
        if cloud >= 70 { return "cloud" }
        if cloud >= 30 { return night ? "cloud.moon" : "cloud.sun" }
        return night ? "moon.stars" : "sun.max"
    }
}

/// Keeps a store's target species in step with the shared `targetSpeciesId`
/// setting (0 means any species). The species page's Target button and the
/// forecast species pickers all write that key.
private struct TargetSpeciesSync: ViewModifier {
    let store: ForecastStore
    @Environment(AppState.self) private var appState
    @AppStorage("targetSpeciesId") private var targetSpeciesId: Int = 0
    @AppStorage(RecentTargets.key) private var recentTargets = ""

    func body(content: Content) -> some View {
        content.task(id: targetSpeciesId) {
            let id = Int64(targetSpeciesId)
            // Every writer of the target passes through here (species page,
            // onboarding, the pickers), so recents are kept in one place.
            let recents = RecentTargets.adding(id, to: recentTargets)
            if recents != recentTargets { recentTargets = recents }
            guard id != (store.species?.id ?? 0) else { return }
            let species: Species? = id == 0 ? nil : (try? appState.speciesRepository.fetch(id: id)) ?? nil
            store.setSpecies(species)
        }
    }
}

extension View {
    /// Reads the shared target species into `store` now and whenever it changes.
    func syncsTargetSpecies(_ store: ForecastStore) -> some View {
        modifier(TargetSpeciesSync(store: store))
    }
}

/// The last few species targeted, newest first, so switching back is one
/// tap. Stored as comma-separated ids under `recentTargetSpeciesIds`.
enum RecentTargets {
    static let key = "recentTargetSpeciesIds"
    static let limit = 6

    static func ids(_ raw: String) -> [Int64] {
        raw.split(separator: ",").compactMap { Int64($0) }.filter { $0 != 0 }
    }

    static func adding(_ id: Int64, to raw: String) -> String {
        guard id != 0 else { return raw }
        let list = [id] + ids(raw).filter { $0 != id }
        return list.prefix(limit).map { String($0) }.joined(separator: ",")
    }
}
