import SwiftUI
import Charts

// MARK: - Condition tiles

/// The eight Apple Weather style tiles. Each pushes its condition page.
struct ConditionGrid: View {
    let store: ForecastStore
    let day: ForecastDay
    var use24: Bool = true

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
            ForEach(ForecastCondition.allCases) { c in
                NavigationLink(value: ForecastRoute.condition(c, day: day.offset)) {
                    tile(c)
                }
                .buttonStyle(.dim)
            }
        }
        .padding(.horizontal, DS.gutter)
    }

    @ViewBuilder
    private func tile(_ c: ForecastCondition) -> some View {
        let w = day.weather
        switch c {
        case .water:
            let comfort = ConditionText.comfort(for: store.species)
            let temp = w?.waterTempC
            ConditionTile("Water", systemImage: "thermometer.medium", iconTint: c.tint,
                          value: temp.map { "\(Int($0.rounded()))°" } ?? "–",
                          footnote: temp.map { ConditionText.waterFootnote($0, comfort: comfort, species: store.species) } ?? "No reading yet") {
                RangeBar(domain: 5...32, band: comfort, value: temp, tint: .dsScoreGood)
            }
        case .air:
            let range = day.airRange
            ConditionTile("Air", systemImage: "thermometer.sun", iconTint: c.tint,
                          value: w.map { "\(Int($0.temperatureC.rounded()))°" } ?? "–",
                          footnote: range.map { "High \(Int($0.upperBound.rounded()))°, low \(Int($0.lowerBound.rounded()))°" }
                            ?? w.map { ForecastFormat.condition($0.condition) } ?? "No reading yet") {
                if let range {
                    RangeBar(domain: (range.lowerBound - 4)...(range.upperBound + 4), band: range,
                             value: day.isToday ? w?.temperatureC : nil, tint: .dsScoreLow)
                }
            }
        case .wind:
            ConditionTile("Wind", systemImage: "wind", iconTint: c.tint,
                          value: w.map { "\(Int($0.windSpeedKmh.rounded()))" } ?? "–", unit: "km/h",
                          footnote: w.map { "From the \(ForecastFormat.compassWord($0.windDirectionDeg))" } ?? "No reading yet") {
                if let w {
                    CompassDial(degrees: w.windDirectionDeg, size: 46, tint: c.tint)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        case .pressure:
            let values = day.hours.map(\.pressureHpa)
            ConditionTile("Pressure", systemImage: "gauge.with.dots.needle.33percent", iconTint: c.tint,
                          value: w.map { "\(Int($0.pressureHpa.rounded()))" } ?? "–", unit: "hPa",
                          footnote: w.map { ForecastFormat.pressureTrend($0.pressureChange6h) } ?? "No reading yet") {
                if values.count > 1 {
                    Sparkline(values: values, tint: c.tint).frame(height: 28)
                }
            }
        case .tide:
            let next = day.nextTide
            ConditionTile("Tide", systemImage: "water.waves", iconTint: c.tint,
                          value: next.map { ForecastFormat.time($0.time, use24: use24) } ?? "–",
                          footnote: next.map { $0.isHigh ? "High tide" : "Low tide" } ?? "No tide today") {
                Sparkline(values: day.tide.points.map(\.height), tint: c.tint,
                          dotAt: day.isToday ? ConditionText.dayFraction(.now) : nil)
                    .frame(height: 30)
            }
        case .moon:
            let major = ConditionText.nextMajor(day)
            ConditionTile("Moon", systemImage: "moon", iconTint: c.tint,
                          value: "\(Int((day.solunar.moonIllumination * 100).rounded()))", unit: "%",
                          footnote: major.map { "Major from \(ForecastFormat.time($0.start, use24: use24))" }
                            ?? ForecastFormat.moonName(day.solunar.moonPhase)) {
                Image(systemName: day.solunar.moonPhase.symbolName)
                    .font(.largeTitle)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.dsText)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        case .sun:
            let s = day.solunar
            let up = day.isToday && Date.now > s.sunrise && Date.now < s.sunset
            ConditionTile("Sun", systemImage: up ? "sunset" : "sunrise", iconTint: c.tint,
                          value: ForecastFormat.time(up ? s.sunset : s.sunrise, use24: use24),
                          footnote: up ? "Sunset. Rose at \(ForecastFormat.time(s.sunrise, use24: use24))"
                                       : "Sunrise. Sets \(ForecastFormat.time(s.sunset, use24: use24))") {
                SunArc(sunrise: s.sunrise, sunset: s.sunset, now: day.isToday ? .now : nil, tint: c.tint)
                    .frame(height: 36)
            }
        case .sky:
            let next = ConditionText.skyHours(day)
            ConditionTile("Sky", systemImage: w.map { WeatherIcon(condition: $0.condition).systemName } ?? "cloud",
                          iconTint: c.tint,
                          value: w.map { "\($0.cloudCoverPct)" } ?? "–", unit: "% cloud",
                          footnote: w.map { ConditionText.rainLine($0.precipMm) } ?? "No reading yet") {
                if !next.isEmpty { CloudBars(hours: next) }
            }
        }
    }
}

// MARK: - Shared wording

enum ConditionText {
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

    static func waterFootnote(_ temp: Double, comfort: ClosedRange<Double>, species: Species?) -> String {
        let who = species?.commonName.lowercased() ?? "most fish"
        if comfort.contains(temp) { return "In range for \(who)" }
        if temp < comfort.lowerBound { return "\(Int((comfort.lowerBound - temp).rounded()))° below their range" }
        return "\(Int((temp - comfort.upperBound).rounded()))° above their range"
    }

    static func rainLine(_ mm: Double) -> String {
        mm >= 0.1 ? String(format: "%.1f mm rain", mm) : "No rain"
    }

    static func dayFraction(_ date: Date) -> Double {
        let start = Calendar.current.startOfDay(for: date)
        return min(1, max(0, date.timeIntervalSince(start) / 86400))
    }

    /// The next major period (today), or the day's first one.
    static func nextMajor(_ day: ForecastDay) -> SolunarEngine.FeedingWindow? {
        let majors = day.solunar.majorPeriods.sorted { $0.start < $1.start }
        if day.isToday, let next = majors.first(where: { $0.end > .now }) { return next }
        return majors.first
    }

    /// Twelve hours of sky: from now today, from 06:00 on later days.
    static func skyHours(_ day: ForecastDay) -> [WeatherService.HourlyPoint] {
        let from = day.isToday ? Calendar.current.component(.hour, from: .now) : 6
        return Array(day.hours.filter { Calendar.current.component(.hour, from: $0.date) >= from }.prefix(12))
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
        f.dateFormat = "EEEE d MMM"
        return f.string(from: date)
    }
}

// MARK: - Condition page

/// One page per condition, pushed from a tile. Large tinted value, a chart,
/// the numbers as a list, then what it means for the bite.
struct ConditionPage: View {
    let store: ForecastStore
    let condition: ForecastCondition
    let dayOffset: Int

    @AppStorage("use24HourTime") private var use24 = true
    @AppStorage("waterClarityOverride") private var clarityOverride = ""
    @ScaledMetric(relativeTo: .largeTitle) private var moonSize: CGFloat = 120

    private var day: ForecastDay { store.day(dayOffset) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                content
            }
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .detailTint(condition.tint)
        .navigationTitle(condition.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func header(_ value: String, unit: String?, subtitle: String) -> some View {
        ConditionHeader(over: ForecastFormat.longDate(day.date), value: value, unit: unit,
                        subtitle: subtitle, tint: condition.tint)
    }

    @ViewBuilder
    private var content: some View {
        switch condition {
        case .water: water
        case .air: air
        case .wind: wind
        case .pressure: pressure
        case .tide: tide
        case .moon: moon
        case .sun: sun
        case .sky: sky
        }
    }

    // MARK: Water

    @ViewBuilder
    private var water: some View {
        let comfort = ConditionText.comfort(for: store.species)
        let temp = day.weather?.waterTempC
        let who = store.species?.commonName ?? "Most fish"
        header(temp.map { "\(Int($0.rounded()))" } ?? "–", unit: "°C",
               subtitle: temp.map { comfort.contains($0) ? "In the comfort range for \(who.lowercased())"
                                   : "Outside the \(Int(comfort.lowerBound)) to \(Int(comfort.upperBound)) °C range for \(who.lowercased())" }
                   ?? "No reading yet. Pull down on Today to refresh.")

        let points = (0..<7).compactMap { d -> ChartPoint? in
            guard let t = store.weather(for: d)?.waterTempC else { return nil }
            return ChartPoint(x: store.day(d).date, y: t)
        }
        if points.count > 1 {
            let lowest: Double = min(comfort.lowerBound, points.map(\.y).min() ?? 10) - 3
            let highest: Double = max(comfort.upperBound, points.map(\.y).max() ?? 25) + 3
            VStack(alignment: .leading, spacing: 0) {
                SectionTitle("Next 7 days")
                ConditionLineChart(points: points, tint: condition.tint, yDomain: lowest...highest,
                                   band: comfort, xStride: .day, xFormat: .dateTime.weekday(.abbreviated))
                    .padding(.horizontal, DS.gutter)
                BandLegend(text: "\(who), \(Int(comfort.lowerBound)) to \(Int(comfort.upperBound)) °C")
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, 10)
            }
        }
        ExplainText(paragraphs: [
            store.species.map { "\($0.commonName) feed hardest between \(Int(comfort.lowerBound)) and \(Int(comfort.upperBound)) °C. Fish are cold-blooded, so water temperature sets how hard they chase." }
                ?? "Most gamefish are happiest between 15 and 25 °C. Below that they slow down; above it they go deep for oxygen.",
            "Estimated from the air temperature, so treat it as a guide. Shallow water warms first on a sunny afternoon.",
        ])
    }

    // MARK: Air

    @ViewBuilder
    private var air: some View {
        let w = day.weather
        let range = day.airRange
        header(w.map { "\(Int($0.temperatureC.rounded()))" } ?? "–", unit: "°C",
               subtitle: [range.map { "High \(Int($0.upperBound.rounded()))°, low \(Int($0.lowerBound.rounded()))°" },
                          w.map { ForecastFormat.condition($0.condition) }]
                   .compactMap { $0 }.joined(separator: ". "))
        hourChart(title: "Through the day", values: day.hours.map { ($0.date, $0.temperatureC) })
        if let range {
            let hi = day.hours.max { $0.temperatureC < $1.temperatureC }
            let lo = day.hours.min { $0.temperatureC < $1.temperatureC }
            KeyValueList(rows: [
                ("High", "\(Int(range.upperBound.rounded()))°" + (hi.map { " at \(ForecastFormat.time($0.date, use24: use24))" } ?? "")),
                ("Low", "\(Int(range.lowerBound.rounded()))°" + (lo.map { " at \(ForecastFormat.time($0.date, use24: use24))" } ?? "")),
            ])
        }
        ExplainText(paragraphs: [
            "Air temperature moves water temperature slowly. A warm spell after a cold week pushes fish shallow on the sunny bank first.",
        ])
    }

    // MARK: Wind

    @ViewBuilder
    private var wind: some View {
        let w = day.weather
        header(w.map { "\(Int($0.windSpeedKmh.rounded()))" } ?? "–",
               unit: w.map { "km/h \(ForecastFormat.compass($0.windDirectionDeg))" } ?? "km/h",
               subtitle: w.map { "From the \(ForecastFormat.compassWord($0.windDirectionDeg))" } ?? "No reading yet")
        if let w {
            HStack(spacing: 20) {
                CompassDial(degrees: w.windDirectionDeg, size: 150, showsLabels: true, tint: condition.tint)
                VStack(alignment: .leading, spacing: 6) {
                    Text("From the \(ForecastFormat.compassWord(w.windDirectionDeg))")
                        .font(.headline)
                        .foregroundStyle(.dsText)
                    Text("Fish the bank it blows into. Bait gets pushed there and predators follow.")
                        .font(.subheadline)
                        .foregroundStyle(.dsText2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, DS.gutter)
        }
        hourChart(title: "Speed through the day", values: day.hours.map { ($0.date, $0.windSpeedKmh) }, minZero: true)
        ExplainText(paragraphs: [
            "A light chop breaks up the surface so fish are less line-shy. Dead calm makes them spooky; a gale makes them unfishable.",
        ])
    }

    // MARK: Pressure

    @ViewBuilder
    private var pressure: some View {
        let w = day.weather
        let change = w?.pressureChange6h ?? 0
        header(w.map { "\(Int($0.pressureHpa.rounded()))" } ?? "–", unit: "hPa",
               subtitle: w == nil ? "No reading yet"
                   : abs(change) < 0.5 ? "Steady over the last 6 hours"
                   : "\(change < 0 ? "Falling" : "Rising") \(String(format: "%.1f", abs(change))) hPa in 6 hours")
        hourChart(title: ForecastFormat.dayName(day.offset, date: day.date), values: day.hours.map { ($0.date, $0.pressureHpa) })
        KeyValueList(rows: [
            ("Falling fast", "Best bite"),
            ("Steady", "Normal"),
            ("Rising after a front", "Slow"),
        ])
        ExplainText(paragraphs: [
            "Falling pressure ahead of a front is one of the best signals for an active bite. The bright, high-pressure day behind it is the toughest.",
        ] + (w?.pressureIsEstimated == true
             ? ["From the phone's barometer while offline. The trend is accurate, the absolute value is approximate."]
             : []))
    }

    // MARK: Tide

    @ViewBuilder
    private var tide: some View {
        let next = day.nextTide
        let events = (day.tide.highTides + day.tide.lowTides).sorted { $0.time < $1.time }
        header(next.map { ForecastFormat.time($0.time, use24: use24) } ?? "–",
               unit: next.map { $0.isHigh ? "high" : "low" },
               subtitle: "\(store.placeName). Worked out from the moon and sun.")
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle(ForecastFormat.dayName(day.offset, date: day.date))
            ConditionLineChart(points: day.tide.points.map { ChartPoint(x: $0.time, y: $0.height) },
                               tint: condition.tint, yDomain: -1.4...1.4,
                               now: day.isToday ? .now : nil,
                               marks: events.map { ChartPoint(x: $0.time, y: $0.height) },
                               showsYAxis: false)
                .padding(.horizontal, DS.gutter)
        }
        if !events.isEmpty {
            KeyValueList(rows: events.map { ($0.isHigh ? "High" : "Low", ForecastFormat.time($0.time, use24: use24)) })
        }
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("This week")
            KeyValueList(rows: (0..<7).map { d -> (String, String) in
                let date = store.day(d).date
                let highs = TideEngine.predict(date: date, coordinate: store.coordinate).highTides
                    .map { ForecastFormat.time($0.time, use24: use24) }
                return (ForecastFormat.dayName(d, date: date),
                        highs.isEmpty ? "No high" : "High \(highs.joined(separator: " and "))")
            })
        }
        ExplainText(paragraphs: [
            "Moving water around a tide change is a peak feeding period. Slack water is usually dead.",
            "Heights are relative. Check local tide tables before launching a boat.",
        ])
    }

    // MARK: Moon

    @ViewBuilder
    private var moon: some View {
        let s = day.solunar
        let periods = (s.majorPeriods + s.minorPeriods).sorted { $0.start < $1.start }
        header("\(Int((s.moonIllumination * 100).rounded()))", unit: "% lit",
               subtitle: ForecastFormat.moonName(s.moonPhase))
        Image(systemName: s.moonPhase.symbolName)
            .font(.system(size: moonSize)) // ui-lint: allow, @ScaledMetric symbol
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.dsText)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(ForecastFormat.moonName(s.moonPhase))
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Feeding periods")
            VStack(spacing: 6) {
                SolunarBar(day: day, tint: condition.tint)
                HourAxis()
                HStack(spacing: 16) {
                    BandLegend(text: "Major, 2 hours", color: condition.tint)
                    BandLegend(text: "Minor, 1 hour", color: condition.tint.opacity(0.45))
                    Spacer(minLength: 0)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, DS.gutter)
        }
        KeyValueList(rows: periods.map { p -> (String, String) in
            let major = p.kind == .majorOverhead || p.kind == .majorUnderfoot
            return ("\(major ? "Major" : "Minor"), \(p.kind.rawValue.lowercased())",
                    "\(ForecastFormat.time(p.start, use24: use24)) to \(ForecastFormat.time(p.end, use24: use24))")
        })
        KeyValueList(rows: [
            ("Moonrise", s.moonrise.map { ForecastFormat.time($0, use24: use24) } ?? "None"),
            ("Moonset", s.moonset.map { ForecastFormat.time($0, use24: use24) } ?? "None"),
            ("Solunar day", s.dayRating.label),
            ("Next full moon", ConditionText.nextPhase(.full, after: day.date).map(ConditionText.shortDate) ?? "–"),
            ("Next new moon", ConditionText.nextPhase(.new, after: day.date).map(ConditionText.shortDate) ?? "–"),
        ])
        ExplainText(paragraphs: [
            "Major periods are when the moon is overhead or underfoot, minor periods when it rises and sets. Fish switch on most reliably in them.",
            "Full and new moons give the strongest solunar pull; quarter moons the weakest.",
        ])
    }

    // MARK: Sun

    @ViewBuilder
    private var sun: some View {
        let s = day.solunar
        let light = Int(s.sunset.timeIntervalSince(s.sunrise) / 60)
        header(ForecastFormat.time(s.sunrise, use24: use24), unit: "sunrise",
               subtitle: "Sunset \(ForecastFormat.time(s.sunset, use24: use24)), \(light / 60) h \(light % 60) min of light")
        VStack(spacing: 6) {
            SunArc(sunrise: s.sunrise, sunset: s.sunset, now: day.isToday ? .now : nil, tint: condition.tint)
                .frame(height: 120)
            HStack {
                Text(ForecastFormat.time(s.sunrise, use24: use24))
                Spacer()
                Text(ForecastFormat.time(s.sunset, use24: use24))
            }
            .font(.footnote.monospacedDigit())
            .foregroundStyle(.dsText2)
        }
        .padding(.horizontal, DS.gutter + 10)
        KeyValueList(rows: [
            ("Sunrise", ForecastFormat.time(s.sunrise, use24: use24)),
            ("Morning golden hour", "\(ForecastFormat.time(s.dawnGoldenHour.lowerBound, use24: use24)) to \(ForecastFormat.time(s.dawnGoldenHour.upperBound, use24: use24))"),
            ("Evening golden hour", "\(ForecastFormat.time(s.duskGoldenHour.lowerBound, use24: use24)) to \(ForecastFormat.time(s.duskGoldenHour.upperBound, use24: use24))"),
            ("Sunset", ForecastFormat.time(s.sunset, use24: use24)),
        ])
        ExplainText(paragraphs: [
            "Low light is when predators have the advantage, so dawn and dusk usually top the day.",
        ])
    }

    // MARK: Sky

    @ViewBuilder
    private var sky: some View {
        let w = day.weather
        let clarity = WaterClarity(rawValue: clarityOverride) ?? WaterClarity.inferred(precipMm: store.weather(for: 0)?.precipMm)
        let rainHours = day.hours.filter { $0.precipMm >= 0.1 }
        header(w.map { "\($0.cloudCoverPct)" } ?? "–", unit: "% cloud",
               subtitle: w.map { "\(ForecastFormat.condition($0.condition)). \(ConditionText.rainLine($0.precipMm))." } ?? "No reading yet")
        hourChart(title: "Cloud cover", values: day.hours.map { ($0.date, Double($0.cloudCoverPct)) }, yDomain: 0...100)
        if !day.hours.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionTitle("Rain")
                if rainHours.isEmpty {
                    Label("No rain expected \(day.isToday ? "today" : "this day")", systemImage: "sun.max")
                        .font(.subheadline)
                        .foregroundStyle(.dsText2)
                        .padding(.horizontal, DS.gutter)
                } else {
                    Chart(day.hours, id: \.date) { p in
                        BarMark(x: .value("Hour", p.date, unit: .hour), y: .value("Rain", p.precipMm))
                            .foregroundStyle(ForecastCondition.tide.tint)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                            AxisValueLabel(format: .dateTime.hour())
                        }
                    }
                    .frame(height: 120)
                    .padding(.horizontal, DS.gutter)
                }
            }
        }
        if let w {
            KeyValueList(rows: [
                ("Humidity", "\(w.humidity)%"),
                ("UV index", String(format: "%.0f", w.uvIndex)),
                ("Rain", ConditionText.rainLine(w.precipMm)),
                ("Water clarity", clarity.label),
            ])
        }
        ExplainText(paragraphs: [
            "Cloud takes away the ambush advantage bright sun gives prey, so an overcast day spreads the bite out instead of bunching it at dawn and dusk.",
            "Light rain dims the surface and adds oxygen, often a trigger. Heavy rain colours the water and usually shuts it down for a while.",
            "High humidity usually travels with low pressure and cloud. Hard UV drives fish deep or under cover, so fish shade and structure.",
        ])
    }

    // MARK: Helpers

    @ViewBuilder
    private func hourChart(title: String, values: [(Date, Double)], yDomain: ClosedRange<Double>? = nil,
                           minZero: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle(title)
            if values.count > 1 {
                let ys = values.map { $0.1 }
                let lo = minZero ? 0 : (ys.min() ?? 0) - 2
                let hi = (ys.max() ?? 1) + 2
                ConditionLineChart(points: values.map { ChartPoint(x: $0.0, y: $0.1) }, tint: condition.tint,
                                   yDomain: yDomain ?? lo...hi,
                                   now: day.isToday ? .now : nil)
                    .padding(.horizontal, DS.gutter)
            } else {
                Label("Hour by hour needs a connection. These are the last saved numbers.", systemImage: "wifi.slash")
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                    .padding(.horizontal, DS.gutter)
            }
        }
    }
}

/// The big tinted value block at the top of a condition page.
struct ConditionHeader: View {
    let over: String
    let value: String
    let unit: String?
    let subtitle: String
    let tint: Color
    @ScaledMetric(relativeTo: .largeTitle) private var valueSize: CGFloat = 52

    var body: some View {
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
                if let unit {
                    Text(unit)
                        .font(.title2.weight(.semibold))
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.gutter)
        .accessibilityElement(children: .combine)
    }
}

struct ChartPoint: Identifiable {
    let x: Date
    let y: Double
    var id: Date { x }
}

/// A smooth filled line over a day (or a week) with an optional comfort band,
/// a now rule and marked points.
struct ConditionLineChart: View {
    let points: [ChartPoint]
    var tint: Color
    var yDomain: ClosedRange<Double>
    var band: ClosedRange<Double>? = nil
    var now: Date? = nil
    var marks: [ChartPoint] = []
    var showsYAxis: Bool = true
    var xStride: Calendar.Component = .hour
    var xFormat: Date.FormatStyle = .dateTime.hour()

    var body: some View {
        Chart {
            if let band, let first = points.first, let last = points.last {
                RectangleMark(xStart: .value("Start", first.x), xEnd: .value("End", last.x),
                              yStart: .value("Low", band.lowerBound), yEnd: .value("High", band.upperBound))
                    .foregroundStyle(Color.dsScoreGood.opacity(0.16))
            }
            ForEach(points) { p in
                AreaMark(x: .value("Time", p.x),
                         yStart: .value("Base", yDomain.lowerBound),
                         yEnd: .value("Value", p.y))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(LinearGradient(colors: [tint.opacity(0.3), tint.opacity(0.02)], // ui-lint: allow, chart area fill
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Time", p.x), y: .value("Value", p.y))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
            ForEach(marks) { m in
                PointMark(x: .value("Time", m.x), y: .value("Value", m.y))
                    .foregroundStyle(tint)
                    .symbolSize(40)
            }
            if let now {
                RuleMark(x: .value("Now", now))
                    .foregroundStyle(Color.dsText3)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .stride(by: xStride, count: xStride == .hour ? 6 : 1)) { _ in
                AxisValueLabel(format: xFormat)
            }
        }
        .chartYAxis(showsYAxis ? .automatic : .hidden)
        .frame(height: 170)
    }
}

/// Major and minor solunar periods laid along the day, with now marked.
struct SolunarBar: View {
    let day: ForecastDay
    var tint: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let start = Calendar.current.startOfDay(for: day.date)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.dsFill2)
                ForEach(Array((day.solunar.majorPeriods + day.solunar.minorPeriods).enumerated()), id: \.offset) { _, p in
                    let a = max(0, min(1, p.start.timeIntervalSince(start) / 86400))
                    let b = max(0, min(1, p.end.timeIntervalSince(start) / 86400))
                    let major = p.kind == .majorOverhead || p.kind == .majorUnderfoot
                    Capsule()
                        .fill(major ? tint : tint.opacity(0.45))
                        .frame(width: max(4, w * CGFloat(b - a)))
                        .offset(x: w * CGFloat(a))
                }
                if day.isToday {
                    Rectangle()
                        .fill(Color.dsText)
                        .frame(width: 2, height: 30)
                        .offset(x: w * CGFloat(ConditionText.dayFraction(.now)) - 1)
                }
            }
        }
        .frame(height: 22)
        .accessibilityHidden(true)
    }
}

/// A small coloured swatch and its label, for chart legends.
struct BandLegend: View {
    let text: String
    var color: Color = Color.dsScoreGood.opacity(0.5)

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3, style: .continuous) // ui-lint: allow, legend swatch, not a card
                .fill(color)
                .frame(width: 14, height: 10)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.dsText2)
        }
    }
}
