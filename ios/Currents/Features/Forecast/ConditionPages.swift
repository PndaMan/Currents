import SwiftUI
import Charts

// MARK: - Condition tiles

/// The eight Apple Weather style tiles, two to a row and one height per row.
/// Every tile reads the same way: label, big value, one small visual, and a
/// line on what it means for fishing. Each pushes its condition page.
struct ConditionGrid: View {
    let store: ForecastStore
    let day: ForecastDay
    var use24: Bool = true
    @AppStorage("units") private var units = "metric"
    @Environment(\.dynamicTypeSize) private var typeSize

    /// One tile. Rain takes the tide's place where there is no tide, and
    /// opens the sky and rain page.
    private enum Slot: Hashable, Identifiable {
        case condition(ForecastCondition)
        case rain

        var id: Self { self }

        var page: ForecastCondition {
            switch self {
            case .condition(let c): c
            case .rain: .sky
            }
        }
    }

    private var rows: [[Slot]] {
        let tideOrRain: Slot = store.showsTide ? .condition(.tide) : .rain
        return [[.condition(.water), .condition(.air)],
                [.condition(.wind), .condition(.pressure)],
                [tideOrRain, .condition(.moon)],
                [.condition(.sun), .condition(.sky)]]
    }

    var body: some View {
        // Two to a row, one to a row at accessibility sizes.
        let pair = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
        VStack(spacing: 10) {
            ForEach(rows, id: \.self) { row in
                pair {
                    ForEach(row) { slot in
                        NavigationLink(value: ForecastRoute.condition(slot.page, day: day.offset)) {
                            tile(slot)
                                .frame(maxHeight: .infinity)
                        }
                        .buttonStyle(.dim)
                        .frame(maxHeight: .infinity)
                        .accessibilityHint("Opens \(slot.page.title.lowercased())")
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, DS.gutter)
    }

    private func tile(_ slot: Slot) -> some View {
        let imperial = units == "imperial"
        let r: ConditionReading
        let tint: Color
        switch slot {
        case .condition(let c):
            r = ConditionReading.make(c, day: day, store: store, use24: use24, imperial: imperial)
            tint = c.tint
        case .rain:
            r = ConditionReading.rain(day, store: store, use24: use24)
            tint = ForecastCondition.tide.tint
        }
        return ConditionTile(r.label, systemImage: r.icon, iconTint: tint,
                             value: r.value, unit: r.unit, footnote: r.meaning) {
            TileVisual { visual(slot) }
        }
    }

    @ViewBuilder
    private func visual(_ slot: Slot) -> some View {
        // Water, air, wind and sky hide an offline estimate; the barometer
        // reading under it is real, so pressure keeps it.
        let w = ConditionReading.measured(day, store: store)
        switch slot {
        case .rain:
            if w != nil && day.hours.count > 1 {
                let rain = day.hours.map(\.precipMm)
                // A dry day is a faint baseline; a line along the bottom in
                // the rain colour reads as a full bar.
                if rain.contains(where: { $0 > 0 }) {
                    Sparkline(values: rain, tint: ForecastCondition.tide.ink, fill: true)
                } else {
                    Capsule()
                        .fill(Color.dsFill2)
                        .frame(height: 2)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        case .condition(let c):
            switch c {
            case .water:
                RangeBar(domain: 5...32, band: ConditionText.comfort(for: store.species),
                         value: w?.waterTempC, tint: c.tint)
            case .air:
                if w == nil {
                    EmptyView()
                } else if let range = day.airRange {
                    RangeBar(domain: (range.lowerBound - 4)...(range.upperBound + 4), band: range,
                             value: day.isToday ? w?.temperatureC : nil, tint: c.tint)
                } else {
                    let week = ConditionText.weekRange(store) { $0.temperatureC }
                    RangeBar(domain: (week.lowerBound - 2)...(week.upperBound + 2), band: nil,
                             value: w?.temperatureC, tint: c.tint)
                }
            case .wind:
                if let w {
                    CompassDial(degrees: w.windDirectionDeg, size: 36, tint: c.ink)
                }
            case .pressure:
                RangeBar(domain: 990...1045, band: ConditionText.pressureSweetSpot,
                         value: day.weather?.pressureHpa, tint: c.tint)
            case .tide:
                Sparkline(values: day.tide.points.map(\.height), tint: c.ink,
                          dotAt: day.isToday ? ConditionText.dayFraction(.now) : nil)
            case .moon:
                Image(systemName: day.solunar.moonPhase.symbolName)
                    .font(.title.weight(.ultraLight))
                    .moonColours()
                    .accessibilityHidden(true)
            case .sun:
                SunArc(sunrise: day.solunar.sunrise, sunset: day.solunar.sunset,
                       now: day.isToday ? .now : nil, tint: c.ink)
            case .sky:
                let hours = ConditionText.skyHours(day)
                if w == nil {
                    EmptyView()
                } else if hours.count > 1 {
                    CloudBars(hours: hours)
                } else {
                    RangeBar(domain: 0...100, band: nil, value: w.map { Double($0.cloudCoverPct) }, tint: c.tint)
                }
            }
        }
    }
}

/// The visual slot of a tile: one fixed height, sitting just above the line
/// of meaning, so every tile lines up.
private struct TileVisual<Content: View>: View {
    @ViewBuilder let content: Content
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 36

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height, alignment: .center)
            .padding(.vertical, 6)
            .frame(maxHeight: .infinity, alignment: .bottom)
    }
}

// MARK: - Readings

/// What a tile shows: label, value, unit and one line on what it means.
@MainActor
struct ConditionReading {
    let label: String
    let icon: String
    let value: String
    let unit: String?
    let meaning: String

    /// The day's weather when it is a real reading. Offline with nothing
    /// saved, today's weather is an estimate around the barometer, so the
    /// temperatures, wind and cloud in it are not shown.
    static func measured(_ day: ForecastDay, store: ForecastStore) -> WeatherService.WeatherData? {
        day.offset == 0 && store.weatherIsEstimate ? nil : day.weather
    }

    /// The line for a tile with nothing to show.
    static func noReading(_ day: ForecastDay, store: ForecastStore) -> String {
        day.offset == 0 && store.weatherIsEstimate ? "No weather offline" : "No reading yet"
    }

    static func make(_ c: ForecastCondition, day: ForecastDay, store: ForecastStore, use24: Bool,
                     imperial: Bool = Units.isImperial) -> ConditionReading {
        let w = measured(day, store: store)
        let none = noReading(day, store: store)
        switch c {
        case .water:
            let temp: Double? = w?.waterTempC
            let meaning: String = temp == nil ? none : ConditionText.waterMeaning(temp, species: store.species)
            return ConditionReading(label: "Water", icon: "thermometer.medium",
                                    value: ConditionText.temperature(temp, imperial: imperial), unit: nil,
                                    meaning: meaning)
        case .air:
            let meaning: String = w == nil ? none : ConditionText.airMeaning(day, imperial: imperial)
            return ConditionReading(label: "Air", icon: "thermometer.sun",
                                    value: ConditionText.temperature(w?.temperatureC, imperial: imperial), unit: nil,
                                    meaning: meaning)
        case .wind:
            let speed = ConditionText.speedParts(w?.windSpeedKmh, imperial: imperial)
            var unit = speed.unit
            var meaning = none
            if let w {
                unit = speed.unit + " " + ForecastFormat.compass(w.windDirectionDeg)
                meaning = ConditionText.windMeaning(w.windSpeedKmh)
            }
            return ConditionReading(label: "Wind", icon: "wind", value: speed.value, unit: unit, meaning: meaning)
        case .pressure:
            // The barometer reading is real even when the rest is estimated.
            let reading = day.weather
            var value = ConditionText.missing
            var unit = imperial ? "inHg" : "hPa"
            var meaning = "No reading yet"
            if let reading {
                (value, unit) = Units.pressureParts(hpa: reading.pressureHpa, imperial: imperial)
                meaning = ConditionText.pressureMeaning(reading)
            }
            return ConditionReading(label: "Pressure", icon: "gauge.with.dots.needle.33percent",
                                    value: value, unit: unit, meaning: meaning)
        case .tide:
            var label = "Tide"
            var value = ConditionText.missing
            if let next = day.nextTide {
                label = next.isHigh ? "High tide" : "Low tide"
                value = ForecastFormat.time(next.time, use24: use24)
            }
            let meaning: String = ConditionText.tideMeaning(day, use24: use24)
            return ConditionReading(label: label, icon: "water.waves", value: value, unit: nil, meaning: meaning)
        case .moon:
            let lit: Double = day.solunar.moonIllumination * 100
            let meaning: String = ConditionText.moonMeaning(day, use24: use24)
            return ConditionReading(label: "Moon", icon: "moon",
                                    value: ConditionText.whole(lit, suffix: "%"), unit: "lit", meaning: meaning)
        case .sun:
            let sun = ConditionText.sunEvent(day, store: store)
            // After sunset today the time is tomorrow's sunrise, so say so.
            let tomorrow = !Calendar.current.isDate(sun.time, inSameDayAs: day.date)
            let label: String = sun.isSunset ? "Sunset" : (tomorrow ? "Sunrise tomorrow" : "Sunrise")
            let icon: String = sun.isSunset ? "sunset" : "sunrise"
            let meaning: String = ConditionText.sunMeaning(day, store: store, use24: use24)
            return ConditionReading(label: label, icon: icon,
                                    value: ForecastFormat.time(sun.time, use24: use24), unit: nil, meaning: meaning)
        case .sky:
            var icon = "cloud"
            var value = ConditionText.missing
            var unit: String?
            var meaning = none
            if let w {
                icon = WeatherIcon(condition: w.condition).systemName
                value = "\(w.cloudCoverPct)%"
                unit = "cloud"
                meaning = ConditionText.skyMeaning(day, use24: use24)
            }
            return ConditionReading(label: "Sky", icon: icon, value: value, unit: unit, meaning: meaning)
        }
    }

    /// The rain tile that stands in for tides at fresh water: the day's
    /// total and when it starts.
    static func rain(_ day: ForecastDay, store: ForecastStore, use24: Bool) -> ConditionReading {
        guard let w = measured(day, store: store) else {
            return ConditionReading(label: "Rain", icon: "cloud.rain", value: ConditionText.missing,
                                    unit: "mm", meaning: noReading(day, store: store))
        }
        let total: Double = day.hours.isEmpty ? w.precipMm : day.hours.map(\.precipMm).reduce(0, +)
        var meaning = "No rain expected"
        if let first = ConditionText.firstRain(day) {
            meaning = "Rain from \(ForecastFormat.time(first.date, use24: use24)). Water may colour"
        } else if total >= 0.1 {
            meaning = "Light rain. Water stays clear"
        }
        return ConditionReading(label: "Rain", icon: "cloud.rain", value: String(format: "%.1f", total),
                                unit: "mm", meaning: meaning)
    }
}

// MARK: - Shared wording

@MainActor
enum ConditionText {
    /// The pressure range the bite score rates highest.
    static let pressureSweetSpot: ClosedRange<Double> = 1018...1028

    /// Shown where a reading is missing.
    static let missing = "–"

    /// True when a page charts the day hour by hour. Today keeps its hourly
    /// chart while the hours load rather than opening on the week and
    /// swapping; offline with no hours, the week stands in.
    static func showsHours(_ day: ForecastDay, store: ForecastStore) -> Bool {
        day.hours.count > 1 || (day.isToday && store.isLoading)
    }

    /// A rounded whole number, or the missing mark.
    static func whole(_ value: Double?, suffix: String = "") -> String {
        guard let value else { return missing }
        return "\(Int(value.rounded()))" + suffix
    }

    /// A temperature in the user's units, or the missing mark.
    static func temperature(_ celsius: Double?, imperial: Bool) -> String {
        guard let celsius else { return missing }
        return Units.temperature(celsius, imperial: imperial)
    }

    /// A wind speed split into number and unit, such as 32 and km/h. Both
    /// come from `Units.speed`, so the unit always matches the setting.
    static func speedParts(_ kmh: Double?, imperial: Bool) -> (value: String, unit: String) {
        let parts = Units.speed(kmh: kmh ?? 0, imperial: imperial).split(separator: " ", maxSplits: 1)
        let unit = parts.count > 1 ? String(parts[1]) : ""
        guard kmh != nil else { return (missing, unit) }
        return (parts.first.map(String.init) ?? missing, unit)
    }

    /// The water temperature band the target species is happiest in, or the
    /// general 15 to 25 °C range the engine uses when nothing is targeted.
    static func comfort(for species: Species?) -> ClosedRange<Double> {
        if let lo = species?.minTempC, let hi = species?.maxTempC, hi > lo {
            if let opt = species?.optimalTempC {
                // The survivable range is wide; the feeding band sits around optimal.
                let half = max(2, min(opt - lo, hi - opt) / 2)
                return (opt - half)...(opt + half)
            }
            return lo...hi
        }
        if let opt = species?.optimalTempC { return (opt - 3)...(opt + 3) }
        return 15...25
    }

    // Tile lines: short enough for two lines of a half-width tile.

    static func waterMeaning(_ temp: Double?, species: Species?) -> String {
        guard let temp else { return "No reading yet" }
        let band = comfort(for: species)
        if band.contains(temp) { return species == nil ? "Good range for most fish" : "In their comfort range" }
        if temp < band.lowerBound {
            return band.lowerBound - temp >= 4 ? "Cold. Fish slow and deep" : "Cool. Slow the retrieve"
        }
        return temp - band.upperBound >= 4 ? "Hot. Fish early, late or deep" : "Warm. Fish dawn and dusk"
    }

    static func airMeaning(_ day: ForecastDay, imperial: Bool = Units.isImperial) -> String {
        guard let w = day.weather else { return "No reading yet" }
        let ahead = day.isToday ? day.hours.filter { $0.date > .now } : day.hours
        // Today reads the hours left before midnight. Late in the evening
        // too few are left to call a trend, so it gives the day's range,
        // as later days do.
        let trend = day.isToday && ahead.count >= 4
        let span = trend || !day.isToday ? ahead : day.hours
        guard let hi = span.map(\.temperatureC).max(), let lo = span.map(\.temperatureC).min() else {
            return ForecastFormat.condition(w.condition)
        }
        let high = Units.temperature(hi, imperial: imperial)
        let low = Units.temperature(lo, imperial: imperial)
        if !trend { return "High \(high), low \(low)" }
        if hi - w.temperatureC >= 2 { return "Warming to \(high). Shallows heat up" }
        if w.temperatureC - lo >= 2 { return "Cooling to \(low). Fish drop deeper" }
        return "Steady until midnight"
    }

    static func windMeaning(_ kmh: Double) -> String {
        switch kmh {
        case ..<6: "Calm. Fish light and quiet"
        case ..<20: "A ripple helps. Fish the windward bank"
        case ..<35: "Fresh. Find a sheltered bank"
        default: "Strong. Stay off open water"
        }
    }

    static func pressureMeaning(_ w: WeatherService.WeatherData) -> String {
        if w.pressureChange6h < -1 { return "Falling. Fish feed ahead of fronts" }
        if w.pressureChange6h > 1 { return "Rising. Expect a slower bite" }
        if pressureSweetSpot.contains(w.pressureHpa) { return "Steady and in the ideal range" }
        return w.pressureHpa < pressureSweetSpot.lowerBound ? "Steady, on the low side" : "Steady, on the high side"
    }

    static func tideMeaning(_ day: ForecastDay, use24: Bool) -> String {
        if day.isToday, let rising = isRising(day) {
            return rising ? "Coming in. Fish push in to feed" : "Going out. Fish the channel mouths"
        }
        let highs = day.tide.highTides.sorted { $0.time < $1.time }.map { ForecastFormat.time($0.time, use24: use24) }
        if highs.isEmpty { return "No high tide this day" }
        return highs.count == 1 ? "High at \(highs[0])" : "Highs at \(highs.joined(separator: " and "))"
    }

    static func moonMeaning(_ day: ForecastDay, use24: Bool) -> String {
        let majors = day.solunar.majorPeriods.sorted { $0.start < $1.start }
        let next = day.isToday ? majors.first { $0.end > .now } : majors.first
        guard let next else { return ForecastFormat.moonName(day.solunar.moonPhase) }
        if day.isToday && next.start <= .now { return "Major feeding period now" }
        return "Major feeding from \(ForecastFormat.time(next.start, use24: use24))"
    }

    /// The sun time worth showing: the next sunrise or sunset today, the
    /// sunrise on later days.
    static func sunEvent(_ day: ForecastDay, store: ForecastStore) -> (time: Date, isSunset: Bool) {
        let s = day.solunar
        guard day.isToday else { return (s.sunrise, false) }
        if Date.now < s.sunrise { return (s.sunrise, false) }
        if Date.now < s.sunset { return (s.sunset, true) }
        return (store.day(1).solunar.sunrise, false)
    }

    static func sunMeaning(_ day: ForecastDay, store: ForecastStore, use24: Bool) -> String {
        let s = day.solunar
        if day.isToday {
            if s.dawnGoldenHour.contains(.now) || s.duskGoldenHour.contains(.now) { return "Golden hour now. The best light" }
            if Date.now < s.dawnGoldenHour.lowerBound {
                return "Golden hour from \(ForecastFormat.time(s.dawnGoldenHour.lowerBound, use24: use24))"
            }
            if Date.now < s.duskGoldenHour.lowerBound {
                return "Golden hour from \(ForecastFormat.time(s.duskGoldenHour.lowerBound, use24: use24))"
            }
            let tomorrow = store.day(1).solunar
            return "Dawn golden hour from \(ForecastFormat.time(tomorrow.dawnGoldenHour.lowerBound, use24: use24))"
        }
        return "Golden hours at \(ForecastFormat.time(s.dawnGoldenHour.lowerBound, use24: use24)) and \(ForecastFormat.time(s.duskGoldenHour.lowerBound, use24: use24))"
    }

    static func skyMeaning(_ day: ForecastDay, use24: Bool) -> String {
        guard let w = day.weather else { return "No reading yet" }
        if let rain = firstRain(day) {
            return "Rain from \(ForecastFormat.time(rain.date, use24: use24)). Water may colour"
        }
        if w.precipMm >= 5 { return "Heavy rain. Water will colour" }
        if w.cloudCoverPct >= 70 { return "Overcast. Fish roam and feed longer" }
        if w.cloudCoverPct <= 25 { return "Bright. Fish hold deep or in shade" }
        return "Some cloud. Good light for fishing"
    }

    // Data helpers.

    static func rainLine(_ mm: Double) -> String {
        mm >= 0.1 ? String(format: "%.1f mm", mm) : "None"
    }

    static func dayFraction(_ date: Date) -> Double {
        let start = Calendar.current.startOfDay(for: date)
        return min(1, max(0, date.timeIntervalSince(start) / 86400))
    }

    /// Whether the tide is coming in right now (today only).
    static func isRising(_ day: ForecastDay) -> Bool? {
        guard day.isToday else { return nil }
        return day.tide.points.min { abs($0.time.timeIntervalSinceNow) < abs($1.time.timeIntervalSinceNow) }?.isRising
    }

    /// The tide height now, between the two nearest hourly points.
    static func tideHeightNow(_ day: ForecastDay) -> Double? {
        guard day.isToday else { return nil }
        let pts = day.tide.points
        guard let i = pts.lastIndex(where: { $0.time <= .now }) else { return pts.first?.height }
        guard i + 1 < pts.count else { return pts[i].height }
        let a = pts[i], b = pts[i + 1]
        let span = b.time.timeIntervalSince(a.time)
        let t = span > 0 ? Date.now.timeIntervalSince(a.time) / span : 0
        return a.height + (b.height - a.height) * t
    }

    /// Twelve hours of sky: from now today, from 06:00 on later days.
    static func skyHours(_ day: ForecastDay) -> [WeatherService.HourlyPoint] {
        let from = day.isToday ? Calendar.current.component(.hour, from: .now) : 6
        return Array(day.hours.filter { Calendar.current.component(.hour, from: $0.date) >= from }.prefix(12))
    }

    static func firstRain(_ day: ForecastDay) -> WeatherService.HourlyPoint? {
        day.hours.first { $0.precipMm >= 0.2 && (!day.isToday || $0.date >= Date.now.addingTimeInterval(-3600)) }
    }

    /// The spread of a daily value across the week's outlook.
    static func weekRange(_ store: ForecastStore, _ value: (WeatherService.WeatherData) -> Double) -> ClosedRange<Double> {
        let values = (0..<7).compactMap { store.weather(for: $0).map(value) }
        guard let lo = values.min(), let hi = values.max() else { return 0...30 }
        return lo...max(hi, lo + 1)
    }

    static func nextPhase(_ target: MoonPhase, after date: Date) -> Date? {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date).addingTimeInterval(12 * 3600)
        var wasIn = MoonPhase.current(for: start) == target
        for i in 1...35 {
            guard let d = cal.date(byAdding: .day, value: i, to: start) else { continue }
            let inPhase = MoonPhase.current(for: d) == target
            if inPhase && !wasIn { return d }
            wasIn = inPhase
        }
        return nil
    }

    static func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        return f.string(from: date)
    }

    static func range(_ r: ClosedRange<Date>, use24: Bool) -> String {
        span(r.lowerBound, r.upperBound, use24: use24)
    }

    static func span(_ start: Date, _ end: Date, use24: Bool) -> String {
        "\(ForecastFormat.time(start, use24: use24)) to \(ForecastFormat.time(end, use24: use24))"
    }
}

// MARK: - Condition page

/// One page per condition, like Apple Weather's detail sheets: day strip,
/// big value, a chart over the day or week with now marked, the key numbers
/// and one line on what it means for fishing.
struct ConditionPage: View {
    let store: ForecastStore
    let condition: ForecastCondition

    @State private var offset: Int
    @AppStorage("use24HourTime") private var use24 = true
    @AppStorage("units") private var units = "metric"
    @AppStorage("waterClarityOverride") private var clarityOverride = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(store: ForecastStore, condition: ForecastCondition, dayOffset: Int) {
        self.store = store
        self.condition = condition
        _offset = State(initialValue: min(6, max(0, dayOffset)))
    }

    private var clarity: WaterClarity {
        let today = ConditionReading.measured(store.day(0), store: store)
        return WaterClarity(rawValue: clarityOverride) ?? WaterClarity.inferred(precipMm: today?.precipMm)
    }

    var body: some View {
        let day = store.day(offset)
        let imperial = units == "imperial"
        let page = ConditionPageModel.make(condition, day: day, store: store, use24: use24,
                                           clarity: clarity, imperial: imperial)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DetailHeader(over: store.placeName, title: condition.title)
                ForecastDayStrip(store: store, selection: $offset)
                    .padding(.top, 16)

                // Tide and sun name the time they show; the rest show the date.
                ConditionHeader(over: page.over ?? ForecastFormat.longDate(day.date), value: page.value, unit: page.unit,
                                subtitle: page.subtitle, tint: condition.ink) {
                    accessory(day)
                }
                .padding(.top, 20)
                if let note = store.staleNote { SectionFootnote(note) }

                ConditionChartCard(title: page.chartTitle, caption: page.chartCaption) {
                    ConditionPageChart(condition: condition, day: day, store: store, imperial: imperial)
                }
                .padding(.top, 24)

                if !page.figures.isEmpty {
                    CardSection("Key numbers", note: page.footnote) {
                        ForEach(Array(page.figures.enumerated()), id: \.offset) { _, figure in
                            CardRow(figure.label, subtitle: figure.detail, systemImage: figure.icon,
                                    tint: condition.tint, value: figure.value)
                        }
                    }
                    .padding(.top, 28)
                } else if let footnote = page.footnote {
                    SectionFootnote(footnote)
                        .padding(.top, DS.Space.s2)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 40)
            .animation(reduceMotion ? nil : DS.Motion.softSpring, value: offset)
            .pageWidth()
        }
        // The wash fades out over the title and day strip, so the chart card
        // sits on the plain page; a blue wash hides the grey card in light mode.
        .detailTint(condition.tint, height: 300)
        .pageTitleFade(condition.title)
        .refreshable {
            let live = await store.load(force: true)
            ForecastStore.refreshFeedback(live)
        }
    }

    @ViewBuilder
    private func accessory(_ day: ForecastDay) -> some View {
        switch condition {
        case .wind:
            if let w = ConditionReading.measured(day, store: store) {
                CompassDial(degrees: w.windDirectionDeg, size: 88, showsLabels: true, tint: condition.ink)
            }
        case .moon:
            MoonGlyph(phase: day.solunar.moonPhase)
        default:
            EmptyView()
        }
    }
}

private struct MoonGlyph: View {
    let phase: MoonPhase
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 72

    var body: some View {
        Image(systemName: phase.symbolName)
            .font(.system(size: size, weight: .ultraLight)) // ui-lint: allow, @ScaledMetric symbol
            .moonColours()
            .accessibilityLabel(ForecastFormat.moonName(phase))
    }
}

private extension View {
    /// The moon's lit face in the moon colour. The outline layer is the same
    /// colour at full strength in dark mode, where it also fills a full
    /// moon's face, and at half strength in light mode, where full strength
    /// drew a heavy ring. Following the text colour drew a grey disc in a
    /// black ring in light mode. Callers set an ultra light weight, which
    /// thins the outline.
    func moonColours() -> some View {
        let moon = UIColor(ForecastCondition.moon.tint)
        let outline = Color(uiColor: UIColor { traits in
            let resolved = moon.resolvedColor(with: traits)
            return traits.userInterfaceStyle == .dark ? resolved : resolved.withAlphaComponent(0.5)
        })
        return symbolRenderingMode(.palette)
            .foregroundStyle(outline, ForecastCondition.moon.tint)
    }
}

/// One key number on a condition page: a label with its symbol, the value
/// on the right and, where it helps, a second line under the label.
struct ConditionFigure {
    let label: String
    let icon: String
    var value: String? = nil
    var detail: String? = nil
}

/// The words and numbers for one condition page: the header, the chart's
/// title, the key numbers and at most one sentence under them.
@MainActor
struct ConditionPageModel {
    var value: String
    var unit: String?
    var subtitle: String
    var chartTitle: String
    var chartCaption: String? = nil
    var figures: [ConditionFigure]
    var footnote: String? = nil
    /// The line over the big value when it names a time rather than the
    /// day: "Low tide", "Sunset", "Sunrise tomorrow".
    var over: String? = nil

    static func make(_ c: ForecastCondition, day: ForecastDay, store: ForecastStore,
                     use24: Bool, clarity: WaterClarity, imperial: Bool = Units.isImperial) -> ConditionPageModel {
        let reading = ConditionReading.make(c, day: day, store: store, use24: use24, imperial: imperial)
        switch c {
        case .water: return water(day, store: store, reading: reading, clarity: clarity, imperial: imperial)
        case .air: return air(day, store: store, reading: reading, use24: use24, imperial: imperial)
        case .wind: return wind(day, store: store, reading: reading, use24: use24, imperial: imperial)
        case .pressure: return pressure(day, store: store, reading: reading, imperial: imperial)
        case .tide: return tide(day, reading: reading, use24: use24)
        case .moon: return moon(day, reading: reading, use24: use24)
        case .sun: return sun(day, reading: reading, use24: use24)
        case .sky: return sky(day, store: store, reading: reading, use24: use24, clarity: clarity)
        }
    }

    private static func hourlyTitle(_ day: ForecastDay, store: ForecastStore) -> String {
        ConditionText.showsHours(day, store: store) ? "Through the day" : "Next 7 days"
    }

    private static func speed(_ kmh: Double, imperial: Bool) -> String {
        Units.speed(kmh: kmh, imperial: imperial)
    }

    /// "At 14:00", the hour a high or low falls.
    private static func at(_ date: Date, use24: Bool) -> String {
        "At \(ForecastFormat.time(date, use24: use24))"
    }

    // Water

    private static func water(_ day: ForecastDay, store: ForecastStore, reading: ConditionReading,
                              clarity: WaterClarity, imperial: Bool) -> ConditionPageModel {
        let band = ConditionText.comfort(for: store.species)
        let temp: Double? = ConditionReading.measured(day, store: store)?.waterTempC
        var week: [(day: Int, temp: Double)] = []
        for d in 0..<7 {
            // Today's offline estimate is not a reading.
            if d == 0 && store.weatherIsEstimate { continue }
            if let t = store.weather(for: d)?.waterTempC { week.append((d, t)) }
        }
        let low = Units.temperature(band.lowerBound, imperial: imperial)
        let high = Units.temperature(band.upperBound, imperial: imperial)
        let bandText = "\(low) to \(high)"

        var figures: [ConditionFigure] = []
        figures.append(ConditionFigure(label: day.isToday ? "Now" : "That day", icon: "thermometer.medium",
                                       value: ConditionText.temperature(temp, imperial: imperial)))
        figures.append(ConditionFigure(label: "Comfort range", icon: "scope", value: bandText))
        if week.count > 2, let first = week.first, let last = week.last {
            let change: Double = last.temp - first.temp
            let lastDay: String = ForecastFormat.dayName(last.day, date: store.day(last.day).date)
            if abs(change) < 1.5 {
                figures.append(ConditionFigure(label: "This week", icon: "chart.line.flattrend.xyaxis", value: "Steady"))
            } else {
                let warming = change > 0
                figures.append(ConditionFigure(label: "This week",
                                               icon: warming ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis",
                                               value: warming ? "Warming" : "Cooling",
                                               detail: "\(Units.temperature(last.temp, imperial: imperial)) by \(lastDay)"))
            }
        }
        if let warm = week.max(by: { $0.temp < $1.temp }) {
            figures.append(ConditionFigure(label: "Warmest", icon: "thermometer.high",
                                           value: Units.temperature(warm.temp, imperial: imperial),
                                           detail: ForecastFormat.dayName(warm.day, date: store.day(warm.day).date)))
        }
        if let cool = week.min(by: { $0.temp < $1.temp }) {
            figures.append(ConditionFigure(label: "Coolest", icon: "thermometer.low",
                                           value: Units.temperature(cool.temp, imperial: imperial),
                                           detail: ForecastFormat.dayName(cool.day, date: store.day(cool.day).date)))
        }
        figures.append(ConditionFigure(label: "Clarity", icon: clarity.icon, value: clarity.label))

        // The name as stored, mid-sentence; "most fish" when nothing is targeted.
        let whom: String = store.species?.commonName ?? "most fish"
        return ConditionPageModel(
            value: ConditionText.temperature(temp, imperial: imperial), unit: nil, subtitle: reading.meaning,
            chartTitle: "Next 7 days", chartCaption: "The shaded band is the comfort range for \(whom), \(bandText).",
            figures: figures,
            footnote: "Estimated from the air temperature, so treat it as a guide."
        )
    }

    // Air

    private static func air(_ day: ForecastDay, store: ForecastStore, reading: ConditionReading,
                            use24: Bool, imperial: Bool) -> ConditionPageModel {
        let w = ConditionReading.measured(day, store: store)
        let hours = w == nil ? [] : day.hours
        let hi = hours.max { $0.temperatureC < $1.temperatureC }
        let lo = hours.min { $0.temperatureC < $1.temperatureC }

        var figures: [ConditionFigure] = []
        figures.append(ConditionFigure(label: day.isToday ? "Now" : "Midday", icon: "thermometer.medium",
                                       value: ConditionText.temperature(w?.temperatureC, imperial: imperial)))
        if let hi {
            figures.append(ConditionFigure(label: "High", icon: "thermometer.high",
                                           value: Units.temperature(hi.temperatureC, imperial: imperial),
                                           detail: at(hi.date, use24: use24)))
        }
        if let lo {
            figures.append(ConditionFigure(label: "Low", icon: "thermometer.low",
                                           value: Units.temperature(lo.temperatureC, imperial: imperial),
                                           detail: at(lo.date, use24: use24)))
        }
        if let w {
            figures.append(ConditionFigure(label: "Humidity", icon: "humidity", value: "\(w.humidity)%"))
            figures.append(ConditionFigure(label: "Sky", icon: WeatherIcon(condition: w.condition).systemName,
                                           value: ForecastFormat.condition(w.condition)))
        }

        return ConditionPageModel(
            value: ConditionText.temperature(w?.temperatureC, imperial: imperial), unit: nil, subtitle: reading.meaning,
            chartTitle: hourlyTitle(day, store: store), figures: figures,
            footnote: w == nil ? nil : "Air moves the water temperature slowly, so a warm spell warms the sunny bank first."
        )
    }

    // Wind

    private static func wind(_ day: ForecastDay, store: ForecastStore, reading: ConditionReading,
                             use24: Bool, imperial: Bool) -> ConditionPageModel {
        guard let w = ConditionReading.measured(day, store: store) else {
            return empty(reading, day: day, store: store)
        }
        let from: String = ForecastFormat.compassWord(w.windDirectionDeg)
        let toward: String = ForecastFormat.compassWord(w.windDirectionDeg + 180)
        let strongest = day.hours.max { $0.windSpeedKmh < $1.windSpeedKmh }
        let calmest = day.hours.min { $0.windSpeedKmh < $1.windSpeedKmh }

        var figures: [ConditionFigure] = []
        figures.append(ConditionFigure(label: "Speed", icon: "wind", value: speed(w.windSpeedKmh, imperial: imperial)))
        figures.append(ConditionFigure(label: "From", icon: "location.north.line",
                                       value: "\(ForecastFormat.compass(w.windDirectionDeg)) \(ConditionText.whole(w.windDirectionDeg, suffix: "°"))"))
        if let strongest {
            figures.append(ConditionFigure(label: "Strongest", icon: "gauge.with.dots.needle.67percent",
                                           value: speed(strongest.windSpeedKmh, imperial: imperial),
                                           detail: at(strongest.date, use24: use24)))
        }
        if let calmest {
            figures.append(ConditionFigure(label: "Calmest", icon: "leaf",
                                           value: speed(calmest.windSpeedKmh, imperial: imperial),
                                           detail: at(calmest.date, use24: use24)))
        }

        return ConditionPageModel(
            value: reading.value, unit: ConditionText.speedParts(nil, imperial: imperial).unit,
            subtitle: "From the \(from). \(reading.meaning)",
            chartTitle: hourlyTitle(day, store: store), figures: figures,
            footnote: "A \(from) wind pushes food onto the \(toward) bank, so fish the bank it blows into."
        )
    }

    // Pressure

    private static func pressure(_ day: ForecastDay, store: ForecastStore, reading: ConditionReading,
                                 imperial: Bool) -> ConditionPageModel {
        // The barometer reading is real even offline, so this page keeps it.
        guard let w = day.weather else { return emptyPressure(reading, day: day, store: store) }
        let change: Double = w.pressureChange6h
        let inside: Bool = ConditionText.pressureSweetSpot.contains(w.pressureHpa)
        let high = Units.pressure(hpa: ConditionText.pressureSweetSpot.upperBound, imperial: imperial)
        let likes = "\(Units.pressureParts(hpa: ConditionText.pressureSweetSpot.lowerBound, imperial: imperial).0) to \(high)"

        var footnote: String
        if change < -1 {
            footnote = "Falling pressure ahead of a front is one of the best signs of an active bite."
        } else if change > 1 {
            footnote = "Rising pressure after a front usually slows the bite, so fish slower and smaller."
        } else if inside {
            footnote = "Steady pressure in this range is what the score likes most."
        } else {
            footnote = "Steady pressure outside the range the score likes makes for an average day."
        }
        if w.pressureIsEstimated == true {
            footnote = "From the phone's barometer while offline, so the trend is right and the number is approximate."
        }

        let values: [Double] = day.hours.map(\.pressureHpa)
        let trendIcon: String = change < -1 ? "arrow.down.right" : (change > 1 ? "arrow.up.right" : "arrow.right")
        var figures: [ConditionFigure] = []
        figures.append(ConditionFigure(label: "Pressure", icon: "gauge.with.dots.needle.33percent",
                                       value: Units.pressure(hpa: w.pressureHpa, imperial: imperial)))
        // Today's trend is the live reading's last six hours; later days
        // carry their own midday to evening change.
        figures.append(ConditionFigure(label: day.isToday ? "Last 6 hours" : "Midday to evening", icon: trendIcon,
                                       value: ForecastFormat.pressureTrend(change, imperial: imperial)))
        if let lo = values.min(), let hi = values.max() {
            let loText = Units.pressureParts(hpa: lo, imperial: imperial).0
            figures.append(ConditionFigure(label: "Day range", icon: "arrow.up.arrow.down",
                                           value: "\(loText) to \(Units.pressure(hpa: hi, imperial: imperial))"))
        }
        figures.append(ConditionFigure(label: "Score likes", icon: "scope", value: likes))

        // The chart's range follows the day's pressure, so the band can sit
        // off the top or bottom of it.
        let band = ConditionText.pressureSweetSpot
        let meetsBand = values.isEmpty
            || ((values.max() ?? 0) >= band.lowerBound && (values.min() ?? 0) <= band.upperBound)
        let caption = meetsBand
            ? "The shaded band is the range the score likes, \(likes)."
            : "All day the pressure sits outside the range the score likes, \(likes)."
        return ConditionPageModel(
            value: reading.value, unit: reading.unit, subtitle: reading.meaning,
            chartTitle: hourlyTitle(day, store: store), chartCaption: caption,
            figures: figures, footnote: footnote
        )
    }

    // Tide

    private static func tide(_ day: ForecastDay, reading: ConditionReading, use24: Bool) -> ConditionPageModel {
        let events = (day.tide.highTides + day.tide.lowTides).sorted { $0.time < $1.time }
        let rising: Bool? = ConditionText.isRising(day)

        // The day's highs and lows in order, like a tide table.
        var figures: [ConditionFigure] = []
        if let rising {
            figures.append(ConditionFigure(label: "Now", icon: rising ? "arrow.up.right" : "arrow.down.right",
                                           value: rising ? "Coming in" : "Going out"))
        }
        for event in events {
            figures.append(ConditionFigure(label: event.isHigh ? "High tide" : "Low tide",
                                           icon: event.isHigh ? "arrow.up.to.line" : "arrow.down.to.line",
                                           value: ForecastFormat.time(event.time, use24: use24)))
        }
        if events.isEmpty {
            figures.append(ConditionFigure(label: "Tides", icon: "water.waves", value: "None"))
        }

        return ConditionPageModel(
            value: reading.value, unit: nil, subtitle: reading.meaning,
            chartTitle: "Through the day", figures: figures,
            footnote: "Worked out from the moon and sun with relative heights, so check local tables before launching a boat.",
            over: day.nextTide == nil ? nil : reading.label
        )
    }

    // Moon

    private static func moon(_ day: ForecastDay, reading: ConditionReading, use24: Bool) -> ConditionPageModel {
        let s = day.solunar
        let majors: [String] = s.majorPeriods.sorted { $0.start < $1.start }.map { ConditionText.span($0.start, $0.end, use24: use24) }
        let minors: [String] = s.minorPeriods.sorted { $0.start < $1.start }.map { ConditionText.span($0.start, $0.end, use24: use24) }
        let name: String = ForecastFormat.moonName(s.moonPhase)

        // Periods go one to a line under their label; there are at most two.
        func periods(_ label: String, _ icon: String, _ spans: [String]) -> ConditionFigure {
            spans.isEmpty
                ? ConditionFigure(label: label, icon: icon, value: "None")
                : ConditionFigure(label: label, icon: icon, detail: spans.joined(separator: "\n"))
        }
        var figures: [ConditionFigure] = []
        figures.append(ConditionFigure(label: "Solunar day", icon: "star.leadinghalf.filled", value: s.dayRating.label))
        figures.append(periods("Major periods", "moon.stars.fill", majors))
        figures.append(periods("Minor periods", "moon.stars", minors))
        figures.append(ConditionFigure(label: "Moonrise", icon: "moonrise",
                                       value: s.moonrise.map { ForecastFormat.time($0, use24: use24) } ?? "None"))
        figures.append(ConditionFigure(label: "Moonset", icon: "moonset",
                                       value: s.moonset.map { ForecastFormat.time($0, use24: use24) } ?? "None"))
        if let full = ConditionText.nextPhase(.full, after: day.date) {
            figures.append(ConditionFigure(label: "Next full moon", icon: "moonphase.full.moon",
                                           value: ConditionText.shortDate(full)))
        }
        if let newMoon = ConditionText.nextPhase(.new, after: day.date) {
            figures.append(ConditionFigure(label: "Next new moon", icon: "moonphase.new.moon",
                                           value: ConditionText.shortDate(newMoon)))
        }

        var footnote = "Fish switch on most reliably inside the major and minor periods."
        if s.moonPhase == .full || s.moonPhase == .new {
            footnote = "Around the full and new moon the pull is strongest, so the periods matter more than usual."
        } else if s.moonPhase == .firstQuarter || s.moonPhase == .lastQuarter {
            footnote = "Quarter moons give the weakest pull, so lean on dawn and dusk as well."
        }

        // The tile line falls back to the phase name; say it once.
        let subtitle = reading.meaning == name ? name : "\(name). \(reading.meaning)"
        return ConditionPageModel(
            value: reading.value, unit: reading.unit, subtitle: subtitle,
            chartTitle: "Solunar pull through the day",
            chartCaption: "Stronger shading marks the major periods, fainter shading the minor ones.",
            figures: figures, footnote: footnote
        )
    }

    // Sun

    private static func sun(_ day: ForecastDay, reading: ConditionReading, use24: Bool) -> ConditionPageModel {
        let s = day.solunar
        let light: String = ForecastFormat.elapsed(s.sunset.timeIntervalSince(s.sunrise))
        let dawn: String = ConditionText.range(s.dawnGoldenHour, use24: use24)
        let dusk: String = ConditionText.range(s.duskGoldenHour, use24: use24)

        // After sunset the hero shows tomorrow's sunrise, so these rows say
        // they are today's.
        let today = day.isToday && Date.now >= s.sunset ? " today" : ""
        var figures: [ConditionFigure] = []
        figures.append(ConditionFigure(label: "Sunrise" + today, icon: "sunrise",
                                       value: ForecastFormat.time(s.sunrise, use24: use24)))
        figures.append(ConditionFigure(label: "Sunset" + today, icon: "sunset",
                                       value: ForecastFormat.time(s.sunset, use24: use24)))
        figures.append(ConditionFigure(label: "Daylight", icon: "sun.max", value: light))
        figures.append(ConditionFigure(label: "Morning golden hour", icon: "sunrise.fill", detail: dawn))
        figures.append(ConditionFigure(label: "Evening golden hour", icon: "sunset.fill", detail: dusk))

        return ConditionPageModel(
            value: reading.value, unit: nil, subtitle: reading.meaning,
            chartTitle: "Daylight", chartCaption: "Shading marks the golden hours.",
            figures: figures,
            footnote: "Low light gives predators the edge, so dawn and dusk usually fish best.",
            over: reading.label
        )
    }

    // Sky

    private static func sky(_ day: ForecastDay, store: ForecastStore, reading: ConditionReading, use24: Bool,
                            clarity: WaterClarity) -> ConditionPageModel {
        guard let w = ConditionReading.measured(day, store: store) else {
            return empty(reading, day: day, store: store)
        }
        let total: Double = day.hours.isEmpty ? w.precipMm : day.hours.map(\.precipMm).reduce(0, +)
        let rain: String = ConditionText.rainLine(total)

        var figures: [ConditionFigure] = []
        figures.append(ConditionFigure(label: "Cloud", icon: "cloud", value: "\(w.cloudCoverPct)%"))
        figures.append(ConditionFigure(label: "Rain", icon: "cloud.rain", value: rain))
        if let first = ConditionText.firstRain(day) {
            figures.append(ConditionFigure(label: "Rain from", icon: "clock",
                                           value: ForecastFormat.time(first.date, use24: use24)))
        }
        figures.append(ConditionFigure(label: "Humidity", icon: "humidity", value: "\(w.humidity)%"))
        figures.append(ConditionFigure(label: "UV index", icon: "sun.max.fill", value: ConditionText.whole(w.uvIndex)))
        figures.append(ConditionFigure(label: "Water clarity", icon: clarity.icon, value: clarity.label))

        let footnote: String
        if total >= 0.2 {
            footnote = "Light rain dims the surface and often starts a bite, while heavy rain colours the water."
        } else if w.cloudCoverPct >= 70 {
            footnote = "Cloud takes away the bright light prey hide in, so fish roam and the bite spreads through the day."
        } else if w.cloudCoverPct <= 25 {
            footnote = "Bright sun pushes fish deep or under cover, so fish shade, weed edges and structure."
        } else {
            footnote = "Broken cloud gives good light, so fish the shade lines when the sun is out."
        }

        let hourly = ConditionText.showsHours(day, store: store)
        let chartTitle: String = hourly ? "Cloud through the day" : "Cloud, next 7 days"
        // The legend only when the chart has a wet bar to point at; the same
        // test as the chart's.
        let wet: Bool = hourly
            ? day.hours.contains { $0.precipMm >= 0.2 }
            : (0..<7).contains { d in
                !(d == 0 && store.weatherIsEstimate) && (store.weather(for: d)?.precipMm ?? 0) >= 0.2
            }
        let caption: String? = wet ? (hourly ? "Solid bars are hours with rain." : "Solid bars are days with rain.") : nil
        return ConditionPageModel(
            value: reading.value, unit: reading.unit, subtitle: reading.meaning,
            chartTitle: chartTitle, chartCaption: caption,
            figures: figures, footnote: footnote
        )
    }

    /// No weather for the day: offline with nothing saved, or beyond the
    /// outlook.
    private static func empty(_ reading: ConditionReading, day: ForecastDay, store: ForecastStore) -> ConditionPageModel {
        let offline = day.offset == 0 && store.weatherIsEstimate
        return ConditionPageModel(
            value: ConditionText.missing, unit: reading.unit, subtitle: reading.meaning,
            chartTitle: hourlyTitle(day, store: store), figures: [],
            footnote: offline
                ? "The bite score uses pressure, tide, moon and season until there is signal."
                : "The bite score uses the tide, moon and season until the weather loads."
        )
    }

    private static func emptyPressure(_ reading: ConditionReading, day: ForecastDay,
                                      store: ForecastStore) -> ConditionPageModel {
        ConditionPageModel(
            value: ConditionText.missing, unit: reading.unit, subtitle: reading.meaning,
            chartTitle: hourlyTitle(day, store: store), figures: [],
            footnote: "The bite score uses the tide, moon and season until the weather loads."
        )
    }
}

// MARK: - Page parts

/// The big tinted value block at the top of a condition page, with room for
/// a visual on the right (the wind compass, the moon).
struct ConditionHeader<Accessory: View>: View {
    let over: String
    let value: String
    let unit: String?
    let subtitle: String
    let tint: Color
    private let accessory: Accessory
    @ScaledMetric(relativeTo: .largeTitle) private var valueSize: CGFloat = 52
    @Environment(\.dynamicTypeSize) private var typeSize

    init(over: String, value: String, unit: String?, subtitle: String, tint: Color,
         @ViewBuilder accessory: () -> Accessory) {
        self.over = over
        self.value = value
        self.unit = unit
        self.subtitle = subtitle
        self.tint = tint
        self.accessory = accessory()
    }

    var body: some View {
        // The visual sits beside the value, under it at accessibility sizes.
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(over)
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value)
                        .font(.system(size: valueSize, weight: .bold)) // ui-lint: allow, @ScaledMetric numeral
                        .monospacedDigit()
                        .foregroundStyle(tint)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let unit {
                        Text(unit)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.dsText2)
                    }
                }
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.dsText2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !stacked { Spacer(minLength: 0) }
            accessory
        }
        .padding(.horizontal, DS.gutter)
        .accessibilityElement(children: .combine)
    }
}

extension ConditionHeader where Accessory == EmptyView {
    init(over: String, value: String, unit: String?, subtitle: String, tint: Color) {
        self.init(over: over, value: value, unit: unit, subtitle: subtitle, tint: tint) { EmptyView() }
    }
}

/// A chart on a fill card with its title and an optional legend line.
struct ConditionChartCard<Content: View>: View {
    let title: String
    var caption: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.dsText)
            content
            if let caption {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.dsText2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .padding(.horizontal, DS.gutter)
    }
}

/// Key numbers as labelled values, two to a row.
struct ConditionFigures: View {
    let items: [(String, String)]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10, alignment: .top),
                            GridItem(.flexible(), alignment: .top)],
                  alignment: .leading, spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.0)
                        .font(.footnote)
                        .foregroundStyle(.dsText2)
                    Text(item.1)
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(.dsText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
                .padding(14)
                .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, DS.gutter)
    }
}

// MARK: - Charts

struct ChartPoint: Identifiable {
    let x: Date
    let y: Double
    var id: Date { x }
}

/// A shaded stretch of the day (golden hours, solunar periods).
struct ChartShade: Identifiable {
    let start: Date
    let end: Date
    var strong: Bool = true
    var id: Date { start }
}

/// The chart for one condition page, built from the day's data. Uses the
/// hourly weather when it was fetched, otherwise the seven-day outlook.
struct ConditionPageChart: View {
    let condition: ForecastCondition
    let day: ForecastDay
    let store: ForecastStore
    var imperial: Bool = Units.isImperial

    var body: some View {
        switch condition {
        case .water: waterChart
        case .air: weatherChart(hourly: { shown($0.temperatureC) }, daily: { shown($0.temperatureC) }, band: nil)
        case .wind: weatherChart(hourly: { shown($0.windSpeedKmh) }, daily: { shown($0.windSpeedKmh) },
                                 band: nil, fromZero: true)
        case .pressure: weatherChart(hourly: { shown($0.pressureHpa) }, daily: { shown($0.pressureHpa) },
                                     band: shownRange(ConditionText.pressureSweetSpot))
        case .tide: tideChart
        case .moon: moonChart
        case .sun: sunChart
        case .sky: skyChart
        }
    }

    /// The darker ink of the condition's hue, so yellow and light blue lines
    /// read on white.
    private var tint: Color { condition.ink }

    /// The plain hue for washes under the line (area, bands, shading): ink
    /// at low opacity turns orange brown and yellow olive in light mode.
    private var fillTint: Color { condition.tint }

    /// A stored metric value in the user's units.
    private func shown(_ value: Double) -> Double {
        guard imperial else { return value }
        switch condition {
        case .water, .air: return value * 9 / 5 + 32
        case .wind: return value * 0.62137119
        case .pressure: return value * 0.0295300
        default: return value
        }
    }

    private func shownRange(_ range: ClosedRange<Double>) -> ClosedRange<Double> {
        shown(range.lowerBound)...shown(range.upperBound)
    }

    /// Today's hours are still loading, so the chart waits for them rather
    /// than showing the week first.
    private var awaitsHours: Bool {
        day.hours.count <= 1 && ConditionText.showsHours(day, store: store)
    }

    /// Today's offline estimate is left out of the week, except for the
    /// barometer, which is a real reading.
    private func skipsToday(_ d: Int) -> Bool {
        d == 0 && store.weatherIsEstimate && condition != .pressure
    }

    /// Noon of each of the seven days, so week points are evenly spaced.
    private func noon(_ offset: Int) -> Date {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: .now)) ?? .now
        return start.addingTimeInterval(12 * 3600)
    }

    private func weekPoints(_ value: (WeatherService.WeatherData) -> Double?) -> [ChartPoint] {
        (0..<7).compactMap { d -> ChartPoint? in
            guard !skipsToday(d), let w = store.weather(for: d), let v = value(w) else { return nil }
            return ChartPoint(x: noon(d), y: v)
        }
    }

    private func padded(_ values: [Double], including extra: ClosedRange<Double>?, fromZero: Bool) -> ClosedRange<Double> {
        var lo = values.min() ?? 0
        var hi = values.max() ?? 1
        if let extra {
            lo = min(lo, extra.lowerBound)
            hi = max(hi, extra.upperBound)
        }
        // Inches of mercury move in hundredths, so they need a finer floor.
        let floor: Double = imperial && condition == .pressure ? 0.03 : 1
        let pad = max(floor, (hi - lo) * 0.15)
        return (fromZero ? 0 : lo - pad)...(hi + pad)
    }

    private var waterChart: some View {
        let points = weekPoints { w -> Double? in w.waterTempC.map { shown($0) } }
        let band = shownRange(ConditionText.comfort(for: store.species))
        let current = points.first { Calendar.current.isDate($0.x, inSameDayAs: day.date) }
        return chartOrEmpty(points.count > 1) {
            ConditionChart(points: points, tint: tint, fillTint: fillTint,
                           yDomain: padded(points.map(\.y), including: band, fromZero: false),
                           band: band, current: current, daily: true)
        }
    }

    private func weatherChart(hourly: (WeatherService.HourlyPoint) -> Double,
                              daily: (WeatherService.WeatherData) -> Double,
                              band: ClosedRange<Double>?, fromZero: Bool = false) -> some View {
        let useHours = day.hours.count > 1
        var points: [ChartPoint] = []
        if useHours {
            points = day.hours.map { ChartPoint(x: $0.date, y: hourly($0)) }
        } else if !awaitsHours {
            points = weekPoints { w -> Double? in daily(w) }
        }
        let current: ChartPoint?
        if useHours {
            current = day.isToday ? nowPoint(points, reading: daily) : nil
        } else {
            current = points.first { Calendar.current.isDate($0.x, inSameDayAs: day.date) }
        }
        // The range follows the data; a band outside it is cut off rather
        // than squashing the line.
        let values = points.map(\.y) + (current.map { [$0.y] } ?? [])
        return chartOrEmpty(points.count > 1, loading: awaitsHours) {
            ConditionChart(points: points, tint: tint, fillTint: fillTint,
                           yDomain: padded(values, including: nil, fromZero: fromZero),
                           band: band, current: current, daily: !useHours)
        }
    }

    /// Today's point on an hourly chart: at this minute with the hero's
    /// reading, so the two agree. Falls back to the nearest hour when there
    /// is no reading.
    private func nowPoint(_ points: [ChartPoint], reading: (WeatherService.WeatherData) -> Double) -> ChartPoint? {
        // The barometer is real even offline; the rest hide an estimate.
        let w = condition == .pressure ? day.weather : ConditionReading.measured(day, store: store)
        if let w { return ChartPoint(x: .now, y: reading(w)) }
        return points.min { abs($0.x.timeIntervalSinceNow) < abs($1.x.timeIntervalSinceNow) }
    }

    private var tideChart: some View {
        let points = day.tide.points.map { ChartPoint(x: $0.time, y: $0.height) }
        let events = (day.tide.highTides + day.tide.lowTides).map { ChartPoint(x: $0.time, y: $0.height) }
        let current = ConditionText.tideHeightNow(day).map { ChartPoint(x: .now, y: $0) }
        return chartOrEmpty(points.count > 1) {
            ConditionChart(points: points, tint: tint, fillTint: fillTint, yDomain: -1.3...1.3,
                           marks: events, current: current, showsYAxis: false)
        }
    }

    private var moonChart: some View {
        let start = Calendar.current.startOfDay(for: day.date)
        let points = SolunarEngine.hourlyScores(date: day.date, coordinate: store.coordinate).map {
            ChartPoint(x: start.addingTimeInterval(Double($0.hour) * 3600 + 1800), y: $0.score * 100)
        }
        let majors = day.solunar.majorPeriods.map { ChartShade(start: $0.start, end: $0.end, strong: true) }
        let minors = day.solunar.minorPeriods.map { ChartShade(start: $0.start, end: $0.end, strong: false) }
        let current = day.isToday ? points.min { abs($0.x.timeIntervalSinceNow) < abs($1.x.timeIntervalSinceNow) } : nil
        return ConditionChart(points: points, tint: tint, fillTint: fillTint, yDomain: 0...100,
                              shades: majors + minors,
                              current: current, showsYAxis: false)
    }

    /// The sun's height as a smooth day curve, above the line in daylight and
    /// below it at night, with the golden hours shaded.
    private var sunChart: some View {
        let s = day.solunar
        let start = Calendar.current.startOfDay(for: day.date)
        let dayLength = max(1, s.sunset.timeIntervalSince(s.sunrise))
        let nightLength = max(1, 86400 - dayLength)
        let points: [ChartPoint] = stride(from: 0.0, through: 86400.0, by: 900.0).map { t in
            let time = start.addingTimeInterval(t)
            return ChartPoint(x: time, y: sunHeight(time, sunrise: s.sunrise, sunset: s.sunset,
                                                    dayLength: dayLength, nightLength: nightLength))
        }
        let shades = [ChartShade(start: s.dawnGoldenHour.lowerBound, end: s.dawnGoldenHour.upperBound),
                      ChartShade(start: s.duskGoldenHour.lowerBound, end: s.duskGoldenHour.upperBound)]
        let current: ChartPoint? = day.isToday
            ? ChartPoint(x: .now, y: sunHeight(.now, sunrise: s.sunrise, sunset: s.sunset,
                                               dayLength: dayLength, nightLength: nightLength))
            : nil
        return ConditionChart(points: points, tint: tint, fillTint: fillTint, yDomain: -1.1...1.2,
                              shades: shades,
                              current: current, baseline: 0, showsYAxis: false)
    }

    private func sunHeight(_ time: Date, sunrise: Date, sunset: Date,
                           dayLength: TimeInterval, nightLength: TimeInterval) -> Double {
        if time >= sunrise && time <= sunset {
            return sin(.pi * time.timeIntervalSince(sunrise) / dayLength)
        }
        let sinceSunset = time > sunset ? time.timeIntervalSince(sunset) : time.timeIntervalSince(sunset) + 86400
        return -0.6 * sin(.pi * min(1, sinceSunset / nightLength))
    }

    private var skyChart: some View {
        let useHours = day.hours.count > 1
        var points: [ChartPoint] = []
        var rainy = Set<Date>()
        if useHours {
            for h in day.hours {
                points.append(ChartPoint(x: h.date, y: Double(h.cloudCoverPct)))
                if h.precipMm >= 0.2 { rainy.insert(h.date) }
            }
        } else if !awaitsHours {
            for d in 0..<7 {
                guard !skipsToday(d), let w = store.weather(for: d) else { continue }
                points.append(ChartPoint(x: noon(d), y: Double(w.cloudCoverPct)))
                if w.precipMm >= 0.2 { rainy.insert(noon(d)) }
            }
        }
        let current: ChartPoint?
        if useHours {
            current = day.isToday ? nowPoint(points, reading: { Double($0.cloudCoverPct) }) : nil
        } else {
            current = points.first { Calendar.current.isDate($0.x, inSameDayAs: day.date) }
        }
        // In the page colour; with rain about, dry bars go pale and wet ones
        // stay solid, as the caption says.
        let dry: Color = rainy.isEmpty ? tint : tint.opacity(0.35)
        return chartOrEmpty(points.count > 1, loading: awaitsHours) {
            ConditionChart(points: points, bars: true, tint: dry, yDomain: 0...100,
                           current: current, highlighted: rainy, highlightTint: tint,
                           daily: !useHours)
        }
    }

    @ViewBuilder
    private func chartOrEmpty<C: View>(_ hasData: Bool, loading: Bool = false,
                                       @ViewBuilder chart: () -> C) -> some View {
        if hasData {
            chart()
        } else if loading {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 180)
                .accessibilityLabel("Loading the hours")
        } else {
            Label("No weather saved for this day yet. Pull down to refresh when you have signal.",
                  systemImage: "wifi.slash")
                .font(.subheadline)
                .foregroundStyle(.dsText2)
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
        }
    }
}

/// A line (or bar) chart over a day or a week: optional comfort band, shaded
/// stretches, marked points and the current point.
struct ConditionChart: View {
    let points: [ChartPoint]
    var bars: Bool = false
    /// The line, bars, marks and current point.
    var tint: Color
    /// The area under the line, the band and the shading. Defaults to `tint`.
    var fillTint: Color? = nil
    var yDomain: ClosedRange<Double>
    var band: ClosedRange<Double>? = nil
    var shades: [ChartShade] = []
    var marks: [ChartPoint] = []
    var current: ChartPoint? = nil
    var highlighted: Set<Date> = []
    var highlightTint: Color = .clear
    var baseline: Double? = nil
    var daily: Bool = false
    var showsYAxis: Bool = true
    @AppStorage("use24HourTime") private var use24 = true

    private var xDomain: ClosedRange<Date> {
        let first = points.first?.x ?? .now
        let last = points.last?.x ?? .now
        if daily {
            return first.addingTimeInterval(-12 * 3600)...last.addingTimeInterval(12 * 3600)
        }
        let start = Calendar.current.startOfDay(for: first)
        return start...start.addingTimeInterval(86400)
    }

    private var xUnit: Calendar.Component { daily ? .day : .hour }

    private var fill: Color { fillTint ?? tint }

    /// One tick under each day, or every six hours.
    private var ticks: [Date] {
        if daily { return points.map(\.x) }
        let start = xDomain.lowerBound
        return [0, 6, 12, 18].map { start.addingTimeInterval(Double($0) * 3600) }
    }
    /// Weekdays under a week; hours under a day, in the app's 12 or 24-hour
    /// setting rather than the phone's.
    private func axisLabel(_ date: Date) -> String {
        if daily { return date.formatted(.dateTime.weekday(.abbreviated)) }
        return ForecastFormat.hour(Calendar.current.component(.hour, from: date), use24: use24)
    }

    var body: some View {
        Chart {
            bandLayer
            shadeLayer
            if bars {
                barLayer
            } else {
                lineLayer
            }
            baselineLayer
            markLayer
            currentLayer
        }
        .chartYScale(domain: yDomain)
        .chartXScale(domain: xDomain)
        .chartXAxis {
            AxisMarks(values: ticks) { value in
                AxisGridLine()
                // Day names sit centred under their day; hour labels start
                // at their line so 00:00 stays inside the chart.
                AxisValueLabel(anchor: daily ? UnitPoint.top : nil) {
                    if let date = value.as(Date.self) {
                        Text(axisLabel(date))
                    }
                }
            }
        }
        .chartYAxis {
            if showsYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            // 1028, not 1,028.
                            Text(number.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)))
                        }
                    }
                }
            }
        }
        .frame(height: 180)
    }

    @ChartContentBuilder
    private var bandLayer: some ChartContent {
        // Cut to the chart's range, so a band beyond the data does not
        // spill past the plot.
        if let band, band.lowerBound < yDomain.upperBound, band.upperBound > yDomain.lowerBound {
            RectangleMark(xStart: .value("Start", xDomain.lowerBound), xEnd: .value("End", xDomain.upperBound),
                          yStart: .value("Low", max(band.lowerBound, yDomain.lowerBound)),
                          yEnd: .value("High", min(band.upperBound, yDomain.upperBound)))
                .foregroundStyle(fill.opacity(0.16))
        }
    }

    /// The shades cut to the chart's range, so a period that runs past
    /// midnight stops at the plot's edge, as the band does.
    private var shownShades: [ChartShade] {
        shades.compactMap { s in
            let start = max(s.start, xDomain.lowerBound)
            let end = min(s.end, xDomain.upperBound)
            return start < end ? ChartShade(start: start, end: end, strong: s.strong) : nil
        }
    }

    @ChartContentBuilder
    private var shadeLayer: some ChartContent {
        ForEach(shownShades) { s in
            RectangleMark(xStart: .value("Start", s.start), xEnd: .value("End", s.end),
                          yStart: .value("Low", yDomain.lowerBound), yEnd: .value("High", yDomain.upperBound))
                .foregroundStyle(fill.opacity(s.strong ? 0.24 : 0.12))
        }
    }

    @ChartContentBuilder
    private var lineLayer: some ChartContent {
        ForEach(points) { p in
            // With a baseline (the sun's horizon) the wash fills only above
            // it, so night is not a filled band.
            AreaMark(x: .value("Time", p.x),
                     yStart: .value("Base", baseline ?? yDomain.lowerBound),
                     yEnd: .value("Value", baseline.map { max($0, p.y) } ?? p.y))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(fill.opacity(0.18))
            LineMark(x: .value("Time", p.x), y: .value("Value", p.y))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
    }

    /// The least a bar shows, about 2 pt, so a zero reads as a value
    /// rather than a missing day.
    private var barStub: Double { (yDomain.upperBound - yDomain.lowerBound) * 0.012 }

    @ChartContentBuilder
    private var barLayer: some ChartContent {
        ForEach(points) { p in
            BarMark(x: .value("Time", p.x, unit: xUnit), y: .value("Value", max(p.y, yDomain.lowerBound + barStub)))
                .foregroundStyle(highlighted.contains(p.x) ? highlightTint : tint)
                .cornerRadius(3) // ui-lint: allow, chart bar, not a card
        }
    }

    @ChartContentBuilder
    private var baselineLayer: some ChartContent {
        if let baseline {
            RuleMark(y: .value("Horizon", baseline))
                .foregroundStyle(Color.dsSeparator)
                .lineStyle(StrokeStyle(lineWidth: 1))
        }
    }

    @ChartContentBuilder
    private var markLayer: some ChartContent {
        ForEach(marks) { m in
            PointMark(x: .value("Time", m.x), y: .value("Value", m.y))
                .foregroundStyle(tint)
                .symbolSize(36)
        }
    }

    @ChartContentBuilder
    private var currentLayer: some ChartContent {
        // A point, not a rule: a dashed rule beside the dashed grid lines
        // reads as one more grid line.
        if let current {
            PointMark(x: .value("Now", current.x), y: .value("Value", current.y))
                .symbol {
                    Circle()
                        .fill(bars ? Color.dsText : tint)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color.dsBackground, lineWidth: 3))
                }
        }
    }
}
