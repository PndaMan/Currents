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

    private let rows: [[ForecastCondition]] = [[.water, .air], [.wind, .pressure], [.tide, .moon], [.sun, .sky]]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(rows, id: \.self) { row in
                HStack(alignment: .top, spacing: 10) {
                    ForEach(row) { c in
                        NavigationLink(value: ForecastRoute.condition(c, day: day.offset)) {
                            tile(c)
                                .frame(maxHeight: .infinity)
                        }
                        .buttonStyle(.dim)
                        .frame(maxHeight: .infinity)
                        .accessibilityHint("Opens \(c.title.lowercased())")
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, DS.gutter)
    }

    private func tile(_ c: ForecastCondition) -> some View {
        let r = ConditionReading.make(c, day: day, store: store, use24: use24)
        return ConditionTile(r.label, systemImage: r.icon, iconTint: c.tint,
                             value: r.value, unit: r.unit, footnote: r.meaning) {
            TileVisual { visual(c) }
        }
    }

    @ViewBuilder
    private func visual(_ c: ForecastCondition) -> some View {
        let w = day.weather
        switch c {
        case .water:
            RangeBar(domain: 5...32, band: ConditionText.comfort(for: store.species),
                     value: w?.waterTempC, tint: c.tint)
        case .air:
            if let range = day.airRange {
                RangeBar(domain: (range.lowerBound - 4)...(range.upperBound + 4), band: range,
                         value: day.isToday ? w?.temperatureC : nil, tint: c.tint)
            } else {
                let week = ConditionText.weekRange(store) { $0.temperatureC }
                RangeBar(domain: (week.lowerBound - 2)...(week.upperBound + 2), band: nil,
                         value: w?.temperatureC, tint: c.tint)
            }
        case .wind:
            if let w {
                CompassDial(degrees: w.windDirectionDeg, size: 36, tint: c.tint)
            }
        case .pressure:
            RangeBar(domain: 990...1045, band: ConditionText.pressureSweetSpot,
                     value: w?.pressureHpa, tint: c.tint)
        case .tide:
            Sparkline(values: day.tide.points.map(\.height), tint: c.tint,
                      dotAt: day.isToday ? ConditionText.dayFraction(.now) : nil)
        case .moon:
            Image(systemName: day.solunar.moonPhase.symbolName)
                .font(.title)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.dsText)
                .accessibilityHidden(true)
        case .sun:
            SunArc(sunrise: day.solunar.sunrise, sunset: day.solunar.sunset,
                   now: day.isToday ? .now : nil, tint: c.tint)
        case .sky:
            let hours = ConditionText.skyHours(day)
            if hours.count > 1 {
                CloudBars(hours: hours)
            } else {
                RangeBar(domain: 0...100, band: nil, value: w.map { Double($0.cloudCoverPct) }, tint: c.tint)
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

    static func make(_ c: ForecastCondition, day: ForecastDay, store: ForecastStore, use24: Bool) -> ConditionReading {
        let w = day.weather
        switch c {
        case .water:
            let temp: Double? = w?.waterTempC
            let meaning: String = ConditionText.waterMeaning(temp, species: store.species)
            return ConditionReading(label: "Water", icon: "thermometer.medium",
                                    value: ConditionText.whole(temp, suffix: "°"), unit: nil, meaning: meaning)
        case .air:
            let meaning: String = ConditionText.airMeaning(day)
            return ConditionReading(label: "Air", icon: "thermometer.sun",
                                    value: ConditionText.whole(w?.temperatureC, suffix: "°"), unit: nil, meaning: meaning)
        case .wind:
            var unit = "km/h"
            var meaning = "No reading yet"
            if let w {
                unit = "km/h " + ForecastFormat.compass(w.windDirectionDeg)
                meaning = ConditionText.windMeaning(w.windSpeedKmh)
            }
            return ConditionReading(label: "Wind", icon: "wind",
                                    value: ConditionText.whole(w?.windSpeedKmh), unit: unit, meaning: meaning)
        case .pressure:
            var meaning = "No reading yet"
            if let w { meaning = ConditionText.pressureMeaning(w) }
            return ConditionReading(label: "Pressure", icon: "gauge.with.dots.needle.33percent",
                                    value: ConditionText.whole(w?.pressureHpa), unit: "hPa", meaning: meaning)
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
                                    value: ConditionText.whole(lit), unit: "% lit", meaning: meaning)
        case .sun:
            let sun = ConditionText.sunEvent(day, store: store)
            let label: String = sun.isSunset ? "Sunset" : "Sunrise"
            let icon: String = sun.isSunset ? "sunset" : "sunrise"
            let meaning: String = ConditionText.sunMeaning(day, store: store, use24: use24)
            return ConditionReading(label: label, icon: icon,
                                    value: ForecastFormat.time(sun.time, use24: use24), unit: nil, meaning: meaning)
        case .sky:
            var icon = "cloud"
            var value = ConditionText.missing
            if let w {
                icon = WeatherIcon(condition: w.condition).systemName
                value = "\(w.cloudCoverPct)"
            }
            let meaning: String = ConditionText.skyMeaning(day, use24: use24)
            return ConditionReading(label: "Sky", icon: icon, value: value, unit: "% cloud", meaning: meaning)
        }
    }
}

// MARK: - Shared wording

@MainActor
enum ConditionText {
    /// The pressure range the bite score rates highest.
    static let pressureSweetSpot: ClosedRange<Double> = 1018...1028

    /// Shown where a reading is missing.
    static let missing = "–"

    /// A rounded whole number, or the missing mark.
    static func whole(_ value: Double?, suffix: String = "") -> String {
        guard let value else { return missing }
        return "\(Int(value.rounded()))" + suffix
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

    static func who(_ species: Species?) -> String {
        species?.commonName ?? "Most fish"
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

    static func airMeaning(_ day: ForecastDay) -> String {
        guard let w = day.weather else { return "No reading yet" }
        let ahead = day.isToday ? day.hours.filter { $0.date > .now } : day.hours
        guard let hi = ahead.map(\.temperatureC).max(), let lo = ahead.map(\.temperatureC).min() else {
            return ForecastFormat.condition(w.condition)
        }
        if !day.isToday { return "High \(Int(hi.rounded()))°, low \(Int(lo.rounded()))°" }
        if hi - w.temperatureC >= 2 { return "Warming to \(Int(hi.rounded()))°. Shallows heat up" }
        if w.temperatureC - lo >= 2 { return "Cooling to \(Int(lo.rounded()))°. Fish drop deeper" }
        return "Steady. Little change today"
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
            if s.dawnGoldenHour.contains(.now) || s.duskGoldenHour.contains(.now) { return "Golden hour now. Prime light" }
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

    static func duration(_ seconds: TimeInterval) -> String {
        let m = max(0, Int(seconds / 60))
        return "\(m / 60) h \(m % 60) min"
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
/// big value, a chart over the day or week with now marked, a summary, the
/// key numbers and what it means for fishing.
struct ConditionPage: View {
    let store: ForecastStore
    let condition: ForecastCondition

    @State private var offset: Int
    @AppStorage("use24HourTime") private var use24 = true
    @AppStorage("waterClarityOverride") private var clarityOverride = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(store: ForecastStore, condition: ForecastCondition, dayOffset: Int) {
        self.store = store
        self.condition = condition
        _offset = State(initialValue: min(6, max(0, dayOffset)))
    }

    private var clarity: WaterClarity {
        WaterClarity(rawValue: clarityOverride) ?? WaterClarity.inferred(precipMm: store.weather(for: 0)?.precipMm)
    }

    var body: some View {
        let day = store.day(offset)
        let page = ConditionPageModel.make(condition, day: day, store: store, use24: use24, clarity: clarity)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForecastDayStrip(store: store, selection: $offset)

                ConditionHeader(over: ForecastFormat.longDate(day.date), value: page.value, unit: page.unit,
                                subtitle: page.subtitle, tint: condition.tint) {
                    accessory(day)
                }
                .padding(.top, 20)

                ConditionChartCard(title: page.chartTitle, caption: page.chartCaption) {
                    ConditionPageChart(condition: condition, day: day, store: store)
                }
                .padding(.top, 24)

                SectionTitle("Summary")
                    .padding(.top, 28)
                Text(page.summary)
                    .font(.body)
                    .foregroundStyle(.dsText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DS.gutter)

                if !page.figures.isEmpty {
                    SectionTitle("Key numbers")
                        .padding(.top, 28)
                    ConditionFigures(items: page.figures)
                }

                SectionTitle("What it means for fishing")
                    .padding(.top, 28)
                ExplainText(paragraphs: page.advice)

                if let note = page.note {
                    Label(note, systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.dsText2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, DS.gutter)
                        .padding(.top, 16)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 40)
            .animation(reduceMotion ? nil : DS.Motion.softSpring, value: offset)
            .pageWidth()
        }
        .detailTint(condition.tint)
        .navigationTitle(condition.title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.load(force: true) }
    }

    @ViewBuilder
    private func accessory(_ day: ForecastDay) -> some View {
        switch condition {
        case .wind:
            if let w = day.weather {
                CompassDial(degrees: w.windDirectionDeg, size: 88, showsLabels: true, tint: condition.tint)
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
            .font(.system(size: size)) // ui-lint: allow, @ScaledMetric symbol
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.dsText)
            .accessibilityLabel(ForecastFormat.moonName(phase))
    }
}

/// The words and numbers for one condition page.
@MainActor
struct ConditionPageModel {
    var value: String
    var unit: String?
    var subtitle: String
    var chartTitle: String
    var chartCaption: String? = nil
    var summary: String
    var figures: [(String, String)]
    var advice: [String]
    var note: String? = nil

    static func make(_ c: ForecastCondition, day: ForecastDay, store: ForecastStore,
                     use24: Bool, clarity: WaterClarity) -> ConditionPageModel {
        let reading = ConditionReading.make(c, day: day, store: store, use24: use24)
        switch c {
        case .water: return water(day, store: store, reading: reading, clarity: clarity)
        case .air: return air(day, store: store, reading: reading, use24: use24)
        case .wind: return wind(day, store: store, reading: reading, use24: use24)
        case .pressure: return pressure(day, store: store, reading: reading)
        case .tide: return tide(day, store: store, reading: reading, use24: use24)
        case .moon: return moon(day, reading: reading, use24: use24)
        case .sun: return sun(day, reading: reading, use24: use24)
        case .sky: return sky(day, reading: reading, use24: use24, clarity: clarity)
        }
    }

    private static func hourlyTitle(_ day: ForecastDay) -> String {
        day.hours.count > 1 ? "Through the day" : "Next 7 days"
    }

    private static func degrees(_ value: Double?) -> String {
        ConditionText.whole(value, suffix: "°")
    }

    private static func kmh(_ value: Double) -> String {
        ConditionText.whole(value) + " km/h"
    }

    private static func listOrNone(_ items: [String], separator: String = ", ") -> String {
        items.isEmpty ? "None" : items.joined(separator: separator)
    }

    // Water

    private static func water(_ day: ForecastDay, store: ForecastStore, reading: ConditionReading,
                              clarity: WaterClarity) -> ConditionPageModel {
        let band = ConditionText.comfort(for: store.species)
        let who: String = ConditionText.who(store.species)
        let temp: Double? = day.weather?.waterTempC
        var week: [(day: Int, temp: Double)] = []
        for d in 0..<7 {
            if let t = store.weather(for: d)?.waterTempC { week.append((d, t)) }
        }
        let bandText = "\(Int(band.lowerBound)) to \(Int(band.upperBound))°"

        var summary = "No reading yet."
        if let temp {
            let when: String = day.isToday ? "today" : "that day"
            summary = "About \(degrees(temp)) \(when)."
        }
        if week.count > 2, let first = week.first, let last = week.last {
            let change: Double = last.temp - first.temp
            let lastDay: String = ForecastFormat.dayName(last.day, date: store.day(last.day).date)
            if abs(change) < 1.5 {
                summary += " Steady through the week."
            } else {
                let way: String = change > 0 ? "Warming" : "Cooling"
                summary += " \(way) to \(degrees(last.temp)) by \(lastDay)."
            }
        }

        var advice: [String] = []
        if let temp {
            if band.contains(temp) {
                advice.append("\(who) are in their comfort range, so expect normal feeding. Cover water and keep moving.")
            } else if temp < band.lowerBound {
                advice.append("The water is colder than \(who.lowercased()) like. They feed less and hold deeper, so slow down, fish smaller lures and look for the warmest water.")
            } else {
                advice.append("The water is warmer than \(who.lowercased()) like. They go deep for oxygen in the heat of the day, so fish early, late or deeper.")
            }
        }
        advice.append("Shallow water warms first on a sunny afternoon, so the bite there often picks up after lunch.")

        var figures: [(String, String)] = []
        figures.append((day.isToday ? "Now" : "That day", degrees(temp)))
        figures.append(("Comfort range", bandText))
        if let warm = week.max(by: { $0.temp < $1.temp }) {
            figures.append(("Warmest", degrees(warm.temp) + " " + ForecastFormat.shortDay(store.day(warm.day).date)))
        }
        if let cool = week.min(by: { $0.temp < $1.temp }) {
            figures.append(("Coolest", degrees(cool.temp) + " " + ForecastFormat.shortDay(store.day(cool.day).date)))
        }
        figures.append(("Clarity", clarity.label))

        return ConditionPageModel(
            value: ConditionText.whole(temp), unit: "°C", subtitle: reading.meaning,
            chartTitle: "Next 7 days", chartCaption: "Shaded band: \(who.lowercased()), \(bandText)",
            summary: summary, figures: figures, advice: advice,
            note: "Estimated from the air temperature, so treat it as a guide."
        )
    }

    // Air

    private static func air(_ day: ForecastDay, store: ForecastStore, reading: ConditionReading,
                            use24: Bool) -> ConditionPageModel {
        let w = day.weather
        let hi = day.hours.max { $0.temperatureC < $1.temperatureC }
        let lo = day.hours.min { $0.temperatureC < $1.temperatureC }
        var summary = "No reading yet."
        if let hi, let lo {
            let hiAt: String = ForecastFormat.time(hi.date, use24: use24)
            let loAt: String = ForecastFormat.time(lo.date, use24: use24)
            summary = "High \(degrees(hi.temperatureC)) at \(hiAt), low \(degrees(lo.temperatureC)) at \(loAt)."
        } else if let w {
            summary = "Around \(degrees(w.temperatureC)) and \(w.condition.lowercased())."
        }
        if let w { summary += " Humidity \(w.humidity)%." }

        var figures: [(String, String)] = []
        figures.append((day.isToday ? "Now" : "Midday", degrees(w?.temperatureC)))
        figures.append(("High", degrees(hi?.temperatureC)))
        figures.append(("Low", degrees(lo?.temperatureC)))
        if let w { figures.append(("Sky", ForecastFormat.condition(w.condition))) }

        return ConditionPageModel(
            value: ConditionText.whole(w?.temperatureC), unit: "°C", subtitle: reading.meaning,
            chartTitle: hourlyTitle(day), summary: summary, figures: figures,
            advice: ["Air temperature moves water temperature slowly. A warm spell after a cold week pushes fish onto the sunny bank first; a cold night pushes them deeper."]
        )
    }

    // Wind

    private static func wind(_ day: ForecastDay, store: ForecastStore, reading: ConditionReading,
                             use24: Bool) -> ConditionPageModel {
        guard let w = day.weather else { return empty(reading, chartTitle: hourlyTitle(day)) }
        let from: String = ForecastFormat.compassWord(w.windDirectionDeg)
        let toward: String = ForecastFormat.compassWord(w.windDirectionDeg + 180)
        let strongest = day.hours.max { $0.windSpeedKmh < $1.windSpeedKmh }
        let calmest = day.hours.min { $0.windSpeedKmh < $1.windSpeedKmh }

        var summary = "From the \(from) at \(kmh(w.windSpeedKmh))."
        if let strongest {
            summary += " Strongest \(kmh(strongest.windSpeedKmh)) at \(ForecastFormat.time(strongest.date, use24: use24))."
        }

        let speedAdvice: String
        switch w.windSpeedKmh {
        case ..<6: speedAdvice = "Calm water makes fish wary, so use light line and long casts."
        case ..<20: speedAdvice = "A ripple breaks up the surface, so fish are less line-shy."
        case ..<35: speedAdvice = "Use heavier lures to stay in touch, and find shelter if casting gets hard."
        default: speedAdvice = "Stay safe and off open water. Sheltered bays fish best."
        }

        var figures: [(String, String)] = []
        figures.append(("Speed", kmh(w.windSpeedKmh)))
        figures.append(("From", ForecastFormat.compass(w.windDirectionDeg) + ", " + ConditionText.whole(w.windDirectionDeg, suffix: "°")))
        if let strongest {
            figures.append(("Strongest", kmh(strongest.windSpeedKmh) + ", " + ForecastFormat.time(strongest.date, use24: use24)))
        }
        if let calmest {
            figures.append(("Calmest", kmh(calmest.windSpeedKmh) + ", " + ForecastFormat.time(calmest.date, use24: use24)))
        }

        return ConditionPageModel(
            value: ConditionText.whole(w.windSpeedKmh), unit: "km/h",
            subtitle: "From the \(from). \(reading.meaning)",
            chartTitle: hourlyTitle(day), summary: summary, figures: figures,
            advice: ["A \(from) wind pushes food onto the \(toward) bank, and predators follow it. Fish the bank it blows into.",
                     speedAdvice]
        )
    }

    // Pressure

    private static func pressure(_ day: ForecastDay, store: ForecastStore,
                                 reading: ConditionReading) -> ConditionPageModel {
        guard let w = day.weather else { return empty(reading, chartTitle: hourlyTitle(day)) }
        let change: Double = w.pressureChange6h
        let inside: Bool = ConditionText.pressureSweetSpot.contains(w.pressureHpa)
        let hpa: String = ConditionText.whole(w.pressureHpa)

        var trend = "steady over the last 6 hours"
        if abs(change) >= 0.5 {
            let way: String = change < 0 ? "falling" : "rising"
            trend = "\(way) \(String(format: "%.1f", abs(change))) hPa in 6 hours"
        }
        let side: String = inside ? "Inside" : "Outside"
        let summary = "\(hpa) hPa and \(trend). \(side) the range the score likes."

        let advice: String
        if change < -1 {
            advice = "Falling pressure ahead of a front is one of the best signs of an active bite. Get out before it arrives."
        } else if change > 1 {
            advice = "Rising pressure after a front usually slows the bite. Fish slower and smaller, tight to cover."
        } else if inside {
            advice = "Steady pressure in the 1018 to 1028 hPa range is what the score likes most. Expect a normal day."
        } else {
            advice = "Steady, but outside the 1018 to 1028 hPa range the score likes, so expect an average day."
        }

        let values: [Double] = day.hours.map(\.pressureHpa)
        var figures: [(String, String)] = []
        figures.append(("Pressure", hpa + " hPa"))
        figures.append(("Last 6 hours", ForecastFormat.pressureTrend(change)))
        if let lo = values.min(), let hi = values.max() {
            figures.append(("Day range", ConditionText.whole(lo) + " to " + ConditionText.whole(hi)))
        }
        figures.append(("Score likes", "1018 to 1028"))

        var note: String? = nil
        if w.pressureIsEstimated == true {
            note = "From the phone's barometer while offline. The trend is right; the exact number is approximate."
        }

        return ConditionPageModel(
            value: hpa, unit: "hPa", subtitle: reading.meaning,
            chartTitle: hourlyTitle(day), chartCaption: "Shaded band: the 1018 to 1028 hPa range the score likes",
            summary: summary, figures: figures, advice: [advice], note: note
        )
    }

    // Tide

    private static func tide(_ day: ForecastDay, store: ForecastStore, reading: ConditionReading,
                             use24: Bool) -> ConditionPageModel {
        let highs: [String] = day.tide.highTides.sorted { $0.time < $1.time }.map { ForecastFormat.time($0.time, use24: use24) }
        let lows: [String] = day.tide.lowTides.sorted { $0.time < $1.time }.map { ForecastFormat.time($0.time, use24: use24) }
        var parts: [String] = []
        if !highs.isEmpty { parts.append("High at " + highs.joined(separator: " and ")) }
        if !lows.isEmpty { parts.append("low at " + lows.joined(separator: " and ")) }
        let summary: String = parts.isEmpty ? "No turns of the tide this day." : parts.joined(separator: ", ") + "."

        let rising: Bool? = ConditionText.isRising(day)
        var advice = ["Moving water around a tide change is a peak feeding time. Slack water is usually quiet."]
        if rising == true { advice.append("On the push, fish follow the water onto the flats and into estuaries.") }
        if rising == false { advice.append("On the drop, fish wait at channel mouths and drop-offs for food washing out.") }

        var figures: [(String, String)] = []
        if let rising { figures.append(("Now", rising ? "Coming in" : "Going out")) }
        if let next = day.nextTide {
            let kind: String = next.isHigh ? "High" : "Low"
            figures.append(("Next", kind + ", " + ForecastFormat.time(next.time, use24: use24)))
        }
        figures.append(("High tides", listOrNone(highs)))
        figures.append(("Low tides", listOrNone(lows)))

        return ConditionPageModel(
            value: reading.value, unit: nil, subtitle: reading.meaning,
            chartTitle: "Through the day",
            summary: summary, figures: figures, advice: advice,
            note: "Worked out from the moon and sun for \(store.placeName). Heights are relative, so check local tables before launching a boat."
        )
    }

    // Moon

    private static func moon(_ day: ForecastDay, reading: ConditionReading, use24: Bool) -> ConditionPageModel {
        let s = day.solunar
        let majors: [String] = s.majorPeriods.sorted { $0.start < $1.start }.map { ConditionText.span($0.start, $0.end, use24: use24) }
        let minors: [String] = s.minorPeriods.sorted { $0.start < $1.start }.map { ConditionText.span($0.start, $0.end, use24: use24) }
        let name: String = ForecastFormat.moonName(s.moonPhase)

        var advice = ["Major periods, with the moon overhead or underfoot, last about two hours. Minor periods, at moonrise and moonset, about one. Fish switch on most reliably inside them."]
        if s.moonPhase == .full || s.moonPhase == .new {
            advice.append("Around the full and new moon the pull is strongest, so the periods matter more than usual.")
        }
        if s.moonPhase == .firstQuarter || s.moonPhase == .lastQuarter {
            advice.append("Quarter moons give the weakest pull, so lean on dawn and dusk as well.")
        }

        var figures: [(String, String)] = []
        figures.append(("Major periods", listOrNone(majors, separator: "\n")))
        figures.append(("Minor periods", listOrNone(minors, separator: "\n")))
        figures.append(("Moonrise", s.moonrise.map { ForecastFormat.time($0, use24: use24) } ?? "None"))
        figures.append(("Moonset", s.moonset.map { ForecastFormat.time($0, use24: use24) } ?? "None"))
        if let full = ConditionText.nextPhase(.full, after: day.date) {
            figures.append(("Next full moon", ConditionText.shortDate(full)))
        }
        if let newMoon = ConditionText.nextPhase(.new, after: day.date) {
            figures.append(("Next new moon", ConditionText.shortDate(newMoon)))
        }

        let rating: String = s.dayRating.label.lowercased()
        return ConditionPageModel(
            value: reading.value, unit: "% lit", subtitle: "\(name). \(reading.meaning)",
            chartTitle: "Solunar pull through the day",
            chartCaption: "Shaded: major periods (darker) and minor periods (lighter)",
            summary: "\(name), \(reading.value)% lit. Solunar day: \(rating).",
            figures: figures, advice: advice
        )
    }

    // Sun

    private static func sun(_ day: ForecastDay, reading: ConditionReading, use24: Bool) -> ConditionPageModel {
        let s = day.solunar
        let light: String = ConditionText.duration(s.sunset.timeIntervalSince(s.sunrise))
        let dawn: String = ConditionText.range(s.dawnGoldenHour, use24: use24)
        let dusk: String = ConditionText.range(s.duskGoldenHour, use24: use24)

        var advice = ["Low light gives predators the edge, so dawn and dusk usually top the day. In bright midday sun fish hold deeper or in shade."]
        if day.isToday && (s.dawnGoldenHour.contains(Date.now) || s.duskGoldenHour.contains(Date.now)) {
            advice.insert("Golden hour is on now. This is the light to be on the water for.", at: 0)
        }

        var figures: [(String, String)] = []
        figures.append(("Sunrise", ForecastFormat.time(s.sunrise, use24: use24)))
        figures.append(("Sunset", ForecastFormat.time(s.sunset, use24: use24)))
        figures.append(("Daylight", light))
        figures.append(("Morning golden hour", dawn))
        figures.append(("Evening golden hour", dusk))

        return ConditionPageModel(
            value: reading.value, unit: nil, subtitle: reading.meaning,
            chartTitle: "Daylight", chartCaption: "Shaded: golden hours",
            summary: "\(light) of daylight. Golden hours \(dawn) and \(dusk).",
            figures: figures, advice: advice
        )
    }

    // Sky

    private static func sky(_ day: ForecastDay, reading: ConditionReading, use24: Bool,
                            clarity: WaterClarity) -> ConditionPageModel {
        guard let w = day.weather else { return empty(reading, chartTitle: hourlyTitle(day)) }
        let rainHours = day.hours.filter { $0.precipMm >= 0.2 }
        let total: Double = day.hours.isEmpty ? w.precipMm : day.hours.map(\.precipMm).reduce(0, +)
        let rain: String = ConditionText.rainLine(total)

        var summary = "\(w.cloudCoverPct)% cloud, \(w.condition.lowercased())."
        if let first = rainHours.first {
            summary += " Rain from \(ForecastFormat.time(first.date, use24: use24)), \(rain) in all."
        } else if total >= 0.1 {
            summary += " \(rain) of rain."
        } else {
            summary += " No rain expected."
        }

        var advice: [String] = []
        if w.cloudCoverPct >= 70 {
            advice.append("Cloud takes away the bright-sun advantage prey have, so fish roam and the bite spreads through the day.")
        } else if w.cloudCoverPct <= 25 {
            advice.append("Bright sun pushes fish deep or under cover. Fish shade, weed edges and structure.")
        } else {
            advice.append("Broken cloud gives good light. Fish shade lines when the sun is out.")
        }
        if total >= 0.2 {
            advice.append("Light rain dims the surface and adds oxygen, often a trigger. Heavy rain colours the water and can shut the bite down for a while.")
        }

        var figures: [(String, String)] = []
        figures.append(("Cloud", "\(w.cloudCoverPct)%"))
        figures.append(("Rain", rain))
        figures.append(("Humidity", "\(w.humidity)%"))
        figures.append(("UV index", ConditionText.whole(w.uvIndex)))
        figures.append(("Water clarity", clarity.label))

        let chartTitle: String = day.hours.count > 1 ? "Cloud through the day" : "Cloud, next 7 days"
        return ConditionPageModel(
            value: "\(w.cloudCoverPct)", unit: "% cloud", subtitle: reading.meaning,
            chartTitle: chartTitle, chartCaption: "Blue bars: hours with rain",
            summary: summary, figures: figures, advice: advice
        )
    }

    private static func empty(_ reading: ConditionReading, chartTitle: String) -> ConditionPageModel {
        ConditionPageModel(
            value: ConditionText.missing, unit: reading.unit, subtitle: "No reading yet",
            chartTitle: chartTitle,
            summary: "There is no saved weather for this day yet. Pull down to refresh when you have signal.",
            figures: [],
            advice: ["The bite score still uses the tide, moon and season until the weather loads."]
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
        HStack(alignment: .center, spacing: 12) {
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
            Spacer(minLength: 0)
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

    var body: some View {
        switch condition {
        case .water: waterChart
        case .air: weatherChart(hourly: { $0.temperatureC }, daily: { $0.temperatureC }, band: nil)
        case .wind: weatherChart(hourly: { $0.windSpeedKmh }, daily: { $0.windSpeedKmh }, band: nil, fromZero: true)
        case .pressure: weatherChart(hourly: { $0.pressureHpa }, daily: { $0.pressureHpa },
                                     band: ConditionText.pressureSweetSpot)
        case .tide: tideChart
        case .moon: moonChart
        case .sun: sunChart
        case .sky: skyChart
        }
    }

    private var tint: Color { condition.tint }

    /// Noon of each of the seven days, so week points are evenly spaced.
    private func noon(_ offset: Int) -> Date {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: .now)) ?? .now
        return start.addingTimeInterval(12 * 3600)
    }

    private func weekPoints(_ value: (WeatherService.WeatherData) -> Double?) -> [ChartPoint] {
        (0..<7).compactMap { d -> ChartPoint? in
            guard let w = store.weather(for: d), let v = value(w) else { return nil }
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
        let pad = max(1, (hi - lo) * 0.15)
        return (fromZero ? 0 : lo - pad)...(hi + pad)
    }

    private var waterChart: some View {
        let points = weekPoints { $0.waterTempC }
        let band = ConditionText.comfort(for: store.species)
        let current = points.first { Calendar.current.isDate($0.x, inSameDayAs: day.date) }
        return chartOrEmpty(points.count > 1) {
            ConditionChart(points: points, tint: tint,
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
        } else {
            points = weekPoints { w -> Double? in daily(w) }
        }
        let current: ChartPoint?
        if useHours {
            current = day.isToday ? points.min { abs($0.x.timeIntervalSinceNow) < abs($1.x.timeIntervalSinceNow) } : nil
        } else {
            current = points.first { Calendar.current.isDate($0.x, inSameDayAs: day.date) }
        }
        return chartOrEmpty(points.count > 1) {
            ConditionChart(points: points, tint: tint,
                           yDomain: padded(points.map(\.y), including: band, fromZero: fromZero),
                           band: band, current: current, daily: !useHours)
        }
    }

    private var tideChart: some View {
        let points = day.tide.points.map { ChartPoint(x: $0.time, y: $0.height) }
        let events = (day.tide.highTides + day.tide.lowTides).map { ChartPoint(x: $0.time, y: $0.height) }
        let current = ConditionText.tideHeightNow(day).map { ChartPoint(x: .now, y: $0) }
        return chartOrEmpty(points.count > 1) {
            ConditionChart(points: points, tint: tint, yDomain: -1.3...1.3,
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
        return ConditionChart(points: points, tint: tint, yDomain: 0...100, shades: majors + minors,
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
        return ConditionChart(points: points, tint: tint, yDomain: -1.1...1.2, shades: shades,
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
        } else {
            for d in 0..<7 {
                guard let w = store.weather(for: d) else { continue }
                points.append(ChartPoint(x: noon(d), y: Double(w.cloudCoverPct)))
                if w.precipMm >= 0.2 { rainy.insert(noon(d)) }
            }
        }
        let current: ChartPoint?
        if useHours {
            current = day.isToday ? points.min { abs($0.x.timeIntervalSinceNow) < abs($1.x.timeIntervalSinceNow) } : nil
        } else {
            current = points.first { Calendar.current.isDate($0.x, inSameDayAs: day.date) }
        }
        return chartOrEmpty(points.count > 1) {
            ConditionChart(points: points, bars: true, tint: Color.dsText3, yDomain: 0...100,
                           current: current, highlighted: rainy, highlightTint: ForecastCondition.tide.tint,
                           daily: !useHours)
        }
    }

    @ViewBuilder
    private func chartOrEmpty<C: View>(_ hasData: Bool, @ViewBuilder chart: () -> C) -> some View {
        if hasData {
            chart()
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
/// stretches, marked points and the current point with a rule through it.
struct ConditionChart: View {
    let points: [ChartPoint]
    var bars: Bool = false
    var tint: Color
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

    /// One tick under each day, or every six hours.
    private var ticks: [Date] {
        if daily { return points.map(\.x) }
        let start = xDomain.lowerBound
        return [0, 6, 12, 18].map { start.addingTimeInterval(Double($0) * 3600) }
    }
    private var labelFormat: Date.FormatStyle {
        daily ? .dateTime.weekday(.abbreviated) : .dateTime.hour()
    }

    /// Hourly bars span their hour, so the marker sits in the middle of one.
    private func currentX(_ point: ChartPoint) -> Date {
        bars && !daily ? point.x.addingTimeInterval(1800) : point.x
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
            AxisMarks(values: ticks) { _ in
                AxisGridLine()
                AxisValueLabel(format: labelFormat)
            }
        }
        .chartYAxis(showsYAxis ? .automatic : .hidden)
        .frame(height: 180)
    }

    @ChartContentBuilder
    private var bandLayer: some ChartContent {
        if let band {
            RectangleMark(xStart: .value("Start", xDomain.lowerBound), xEnd: .value("End", xDomain.upperBound),
                          yStart: .value("Low", band.lowerBound), yEnd: .value("High", band.upperBound))
                .foregroundStyle(tint.opacity(0.16))
        }
    }

    @ChartContentBuilder
    private var shadeLayer: some ChartContent {
        ForEach(shades) { s in
            RectangleMark(xStart: .value("Start", s.start), xEnd: .value("End", s.end),
                          yStart: .value("Low", yDomain.lowerBound), yEnd: .value("High", yDomain.upperBound))
                .foregroundStyle(tint.opacity(s.strong ? 0.24 : 0.12))
        }
    }

    @ChartContentBuilder
    private var lineLayer: some ChartContent {
        ForEach(points) { p in
            AreaMark(x: .value("Time", p.x),
                     yStart: .value("Base", baseline ?? yDomain.lowerBound),
                     yEnd: .value("Value", p.y))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(tint.opacity(0.18))
            LineMark(x: .value("Time", p.x), y: .value("Value", p.y))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
    }

    @ChartContentBuilder
    private var barLayer: some ChartContent {
        ForEach(points) { p in
            BarMark(x: .value("Time", p.x, unit: xUnit), y: .value("Value", p.y))
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
        if let current {
            RuleMark(x: .value("Now", currentX(current)))
                .foregroundStyle(Color.dsText3)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            PointMark(x: .value("Now", currentX(current)), y: .value("Value", current.y))
                .symbol {
                    Circle()
                        .fill(bars ? Color.dsText : tint)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color.dsBackground, lineWidth: 3))
                }
        }
    }
}
