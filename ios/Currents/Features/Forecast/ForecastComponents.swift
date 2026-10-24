import SwiftUI

// MARK: - Bite by hour

/// The day's bite as 24 bars. Height and colour carry the score; the current
/// hour gets a dot, past hours dim, and a tapped hour is outlined.
struct BiteBars: View {
    let hourly: [(hour: Int, score: Int)]
    let windows: [BiteWindows.Window]
    /// The current hour when this is today, otherwise nil.
    let currentHour: Int?
    @Binding var selected: Int?
    var height: CGFloat = 64
    var use24: Bool = true
    /// The score right now. When set, the current hour's bar is drawn from
    /// it, so the bar matches the hero ring above the chart.
    var nowScore: Int? = nil

    /// The gap between bars. `HourAxis` lays its labels out on the same grid.
    static let barSpacing: CGFloat = 3

    /// The centre of an hour's bar across a row `width` wide.
    static func barCentre(_ index: Int, count: Int, width: CGFloat) -> CGFloat {
        let n = CGFloat(max(1, count))
        let slot = max(0, (width - barSpacing * (n - 1)) / n)
        return CGFloat(index) * (slot + barSpacing) + slot / 2
    }

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func inWindow(_ h: Int) -> Bool {
        windows.contains { h >= $0.startHour && h <= $0.endHour }
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: Self.barSpacing) {
                ForEach(Array(hourly.enumerated()), id: \.element.hour) { index, point in
                    bar(point, index: index)
                }
            }
            .frame(height: height, alignment: .bottom)

            if let currentHour {
                // The now dot sits under its bar.
                GeometryReader { geo in
                    let index = hourly.firstIndex { $0.hour == currentHour } ?? currentHour
                    Circle()
                        .fill(Color.dsText)
                        .frame(width: 5, height: 5)
                        .position(x: Self.barCentre(index, count: hourly.count, width: geo.size.width), y: 2.5)
                }
                .frame(height: 5)
                .accessibilityHidden(true)
            }
        }
        .onAppear {
            if reduceMotion { appeared = true } else {
                withAnimation(DS.Motion.softSpring) { appeared = true }
            }
        }
    }

    private func bar(_ point: (hour: Int, score: Int), index: Int) -> some View {
        let isSelected = selected == point.hour
        let isNow = currentHour == point.hour
        let isPast = currentHour.map { point.hour < $0 } ?? false
        let score = isNow ? (nowScore ?? point.score) : point.score
        let lit = inWindow(point.hour) || isNow || isSelected || score >= 50
        let fraction = max(0.08, CGFloat(score) / 100)
        // Only coloured bars dim, for a past hour or while another hour is
        // picked. A grey bar stays full strength: dimmed, it vanishes on white.
        let barOpacity: Double = (!lit || isSelected) ? 1 : (isPast ? 0.35 : (selected != nil ? 0.45 : 1))

        return Button {
            // Ticks here, not on change: the plan sheet also moves the
            // outlined hour from its window tiles.
            Haptics.selection()
            withAnimation(DS.Motion.softSpring) {
                selected = isSelected ? nil : point.hour
            }
        } label: {
            RoundedRectangle(cornerRadius: 4, style: .continuous) // ui-lint: allow, chart bar, not a card
                .fill(lit ? DS.scoreColor(score) : Color.dsFill2)
                .opacity(barOpacity)
                .frame(height: appeared ? height * fraction : 4)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 4, style: .continuous) // ui-lint: allow, chart bar, not a card
                            .strokeBorder(Color.dsText, lineWidth: 1.5)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .contentShape(Rectangle())
                .animation(reduceMotion ? nil : DS.Motion.softSpring.delay(Double(index) * 0.015),
                           value: appeared)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(ForecastFormat.hour(point.hour, use24: use24)), score \(score)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Hour labels under `BiteBars`, each centred on its own bar, with the
/// first and last kept inside the edges. Uses the bars' spacing, so it lines
/// up when it is as wide as the bars.
struct HourAxis: View {
    var labels: [String] = ["12 am", "6 am", "Noon", "6 pm", "11 pm"]
    /// The hour each label names, in order.
    var hours: [Int] = [0, 6, 12, 18, 23]
    /// Bars in the chart above.
    var count: Int = 24

    var body: some View {
        // A hidden label gives the row its height; the real labels sit over
        // it, each at its bar.
        Text(labels.first ?? " ")
            .hidden()
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topLeading) {
                GeometryReader { geo in
                    let width = geo.size.width
                    ZStack(alignment: .topLeading) {
                        Color.clear.frame(width: width, height: 0)
                        ForEach(Array(zip(hours, labels).enumerated()), id: \.offset) { _, item in
                            let centre = BiteBars.barCentre(item.0, count: count, width: width)
                            Text(item.1)
                                .fixedSize()
                                .alignmentGuide(HorizontalAlignment.leading) { d in
                                    -min(max(0, centre - d.width / 2), max(0, width - d.width))
                                }
                        }
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.dsText2)
            .accessibilityHidden(true)
    }
}

// MARK: - Best windows

/// Up to three best windows as equal tiles: time of day, peak score, time range.
struct WindowTiles: View {
    let day: ForecastDay
    var use24: Bool = true
    var onSelect: (Int) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private var nowHour: Int { Calendar.current.component(.hour, from: .now) }

    var body: some View {
        if day.windows.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "moon.zzz")
                    .foregroundStyle(.dsText2)
                Text("No standout window. Fish the best hour, \(ForecastFormat.hour(day.bestHour, use24: use24)).")
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        } else {
            // Side by side, stacked at accessibility sizes, as ActionTriple does.
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 10))
                : AnyLayout(HStackLayout(spacing: 10))
            layout {
                ForEach(day.windows) { w in tile(w) }
            }
        }
    }

    private func tile(_ w: BiteWindows.Window) -> some View {
        let isNow = day.isToday && nowHour >= w.startHour && nowHour <= w.endHour
        let passed = day.isToday && nowHour > w.endHour
        let end = ForecastFormat.hour(w.endHour + 1, use24: use24)
        let time = isNow ? "Until \(end)" : passed ? "Passed" : ForecastFormat.range(w, use24: use24)

        // The window's name and its best hour's score. The score this hour is
        // the hero's; the outline marks the window you are in.
        return Button {
            onSelect(isNow ? nowHour : w.startHour)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Label(ForecastFormat.windowName(w.startHour),
                      systemImage: ForecastFormat.windowIcon(w.startHour))
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                    .labelStyle(TintedIconLabelStyle(tint: DS.scoreInk(w.peakScore)))
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("Peak")
                        .font(.footnote)
                        .foregroundStyle(.dsText2)
                    Text("\(w.peakScore)")
                        .font(.title.bold())
                        .monospacedDigit()
                        .foregroundStyle(DS.scoreInk(w.peakScore))
                }
                Text(time)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.dsText2)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                    .minimumScaleFactor(0.75)
            }
            // A passed window dims its content; the card keeps its fill, so
            // it still reads as a tile on a white page.
            .opacity(passed ? 0.5 : 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .overlay {
                if isNow {
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .strokeBorder(DS.scoreColor(w.peakScore), lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.dim)
        .accessibilityElement(children: .combine)
    }
}

/// A label whose icon takes a tint while the title keeps the label's style.
struct TintedIconLabelStyle: LabelStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.foregroundStyle(tint)
            configuration.title
        }
    }
}

// MARK: - Hour info (day page)

/// What a tapped hour looks like: score, the hour and its grade, the
/// weather for that hour and the engine's main reason. The factors are in
/// "Why this score" further down the page.
struct HourInfoBox: View {
    let store: ForecastStore
    let day: ForecastDay
    let hour: Int?
    var use24: Bool = true
    /// Clears the hour. When set, the card shows a close button and a tap
    /// anywhere on it goes back to the day view.
    var onClose: (() -> Void)? = nil
    @AppStorage("units") private var units = "metric"
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The weather the card shows for an hour.
    private struct HourWeather {
        let temperatureC: Double
        let windSpeedKmh: Double
        let cloudCoverPct: Int
        let precipMm: Double
    }

    /// The score shown for an hour: this moment's for the current hour of
    /// today, so it matches the hero ring and the bar, otherwise the hour's own.
    private func shownScore(_ hour: Int) -> Int? {
        isNow(hour) ? day.result.score : day.score(at: hour)
    }

    private func isNow(_ hour: Int) -> Bool {
        day.isToday && hour == Calendar.current.component(.hour, from: .now)
    }

    /// This moment's reading for the current hour of today, as the tiles
    /// show; the hourly forecast for every other hour.
    private func weather(_ hour: Int) -> HourWeather? {
        if isNow(hour), let w = ConditionReading.measured(day, store: store) {
            return HourWeather(temperatureC: w.temperatureC, windSpeedKmh: w.windSpeedKmh,
                               cloudCoverPct: w.cloudCoverPct, precipMm: w.precipMm)
        }
        guard let p = day.hourWeather(hour) else { return nil }
        return HourWeather(temperatureC: p.temperatureC, windSpeedKmh: p.windSpeedKmh,
                           cloudCoverPct: p.cloudCoverPct, precipMm: p.precipMm)
    }

    var body: some View {
        Group {
            if let hour, let score = shownScore(hour) {
                filled(hour: hour, score: score)
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
                    .overlay(alignment: .topTrailing) {
                        if onClose != nil { closeButton }
                    }
            } else {
                Text("Tap an hour for the score and weather")
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }

    private func filled(hour: Int, score: Int) -> some View {
        // This moment's reading for the current hour, as the hero shows.
        let detail = isNow(hour) ? day.result : store.hourDetail(day: day.offset, hour: hour)
        let hourDate = Calendar.current.startOfDay(for: day.date).addingTimeInterval(Double(hour) * 3600 + 1800)
        let feeding = detail.feedingWindows.contains { hourDate >= $0.start && hourDate <= $0.end }
        let wx = weather(hour)
        // The hour and its grade side by side, stacked at accessibility sizes.
        let title = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                ScoreRing(score: score, size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    title {
                        Text(ForecastFormat.hour(hour, use24: use24))
                            .font(.headline)
                            .monospacedDigit()
                            .foregroundStyle(.dsText)
                        Text(ForecastFormat.grade(score))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(DS.scoreInk(score))
                    }
                    if let wx {
                        weatherLabels(wx, hour: hour)
                    }
                    if feeding {
                        Label("In a solunar feeding period", systemImage: "moon.stars.fill")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.tint)
                    }
                }
                Spacer(minLength: 0)
            }
            // Room for the close button in the corner.
            .padding(.trailing, onClose == nil ? 0 : 24)
            if let reason = detail.reasons.first {
                Text(ForecastFormat.clean(reason))
                    .font(.footnote)
                    .foregroundStyle(.dsText2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .transition(.opacity)
    }

    /// The sky and temperature, the wind and any rain as short labels side
    /// by side, stacked when they do not fit, as the week rows show a day.
    private func weatherLabels(_ w: HourWeather, hour: Int) -> some View {
        let imperial = units == "imperial"
        let temperature = Units.temperature(w.temperatureC, imperial: imperial)
        let wind = Units.speed(kmh: w.windSpeedKmh, imperial: imperial)
        let rainText = ConditionText.rainLine(w.precipMm)
        let wet = w.precipMm >= 0.1
        let sky = Label(temperature, systemImage: ForecastFormat.weatherSymbol(cloud: w.cloudCoverPct,
                                                                                precipMm: w.precipMm, hour: hour))
            .accessibilityLabel("\(temperature), \(w.cloudCoverPct)% cloud")
        let breeze = Label(wind, systemImage: "wind")
            .accessibilityLabel("Wind \(wind)")
        let rain = Label(rainText, systemImage: "drop")
            .accessibilityLabel("Rain \(rainText)")
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                sky
                breeze
                if wet { rain }
            }
            VStack(alignment: .leading, spacing: 2) {
                sky
                breeze
                if wet { rain }
            }
        }
        .font(.footnote)
        .foregroundStyle(.dsText2)
        .symbolRenderingMode(.hierarchical)
        .monospacedDigit()
    }

    /// A small close mark in the top corner, like the close button on a sheet.
    private var closeButton: some View {
        Button { close() } label: {
            Image(systemName: "xmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(.dsText2)
                .frame(width: 28, height: 28)
                .background(Color.dsFill2, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.dim)
        // The mark sits 6 points in from the card's corner; the card pads 14.
        .offset(x: 16, y: -16)
        .accessibilityLabel("Close hour")
    }

    private func close() {
        guard let onClose else { return }
        Haptics.selection()
        onClose()
    }
}

// MARK: - Hour by hour weather

/// The weather hour by hour. Today starts at the current hour and runs on
/// into tomorrow, so it always shows the next day's worth of hours.
struct HourStrip: View {
    let day: ForecastDay
    /// The next day's hours, which today's strip continues into.
    var following: [WeatherService.HourlyPoint] = []
    var use24: Bool = true
    @AppStorage("units") private var units = "metric"
    @ScaledMetric(relativeTo: .headline) private var columnWidth: CGFloat = 54

    private var nowHour: Int { Calendar.current.component(.hour, from: .now) }
    private var imperial: Bool { units == "imperial" }

    /// The wind speed's number alone, in the user's unit, for the narrow column.
    private func windNumber(_ kmh: Double) -> String {
        let text = Units.speed(kmh: kmh, imperial: imperial)
        return text.split(separator: " ").first.map(String.init) ?? text
    }

    private var points: [WeatherService.HourlyPoint] {
        guard day.isToday else { return day.hours }
        let ahead = day.hours.filter { Calendar.current.component(.hour, from: $0.date) >= nowHour }
        return Array((ahead + following).prefix(24))
    }

    var body: some View {
        let shown = points
        // The rain line only when an hour has rain to show.
        let wet = shown.contains { $0.precipMm >= 0.1 }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(shown, id: \.date) { p in
                    let h = Calendar.current.component(.hour, from: p.date)
                    let isNow = day.isToday && Calendar.current.isDate(p.date, equalTo: .now, toGranularity: .hour)
                    VStack(spacing: 8) {
                        Text(isNow ? "Now" : String(ForecastFormat.hour(h, use24: use24).prefix(use24 ? 2 : 5)))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.dsText)
                        Image(systemName: ForecastFormat.weatherSymbol(cloud: p.cloudCoverPct, precipMm: p.precipMm, hour: h))
                            .symbolRenderingMode(.hierarchical)
                            .font(.title3)
                            .foregroundStyle(.dsText2)
                            .frame(height: 24)
                        Text(Units.temperature(p.temperatureC, imperial: imperial))
                            .font(.headline)
                            .monospacedDigit()
                            .foregroundStyle(.dsText)
                        HStack(spacing: 2) {
                            Image(systemName: "location.north.fill")
                                .font(.caption2)
                                .rotationEffect(.degrees(p.windDirectionDeg + 180))
                            Text(windNumber(p.windSpeedKmh))
                                .monospacedDigit()
                        }
                        .font(.footnote)
                        .foregroundStyle(.dsText2)
                        if wet {
                            Text(p.precipMm >= 0.1 ? String(format: "%.1f", p.precipMm) : " ")
                                .font(.caption)
                                .foregroundStyle(ForecastCondition.tide.ink)
                        }
                    }
                    .frame(minWidth: columnWidth)
                    .padding(.vertical, 10)
                    // Inset inside the card, so the highlight's corners clear
                    // its top and bottom edges.
                    .background {
                        if isNow {
                            RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous).fill(Color.dsFill2)
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(isNow ? "Now" : ForecastFormat.hour(h, use24: use24)), \(Units.temperature(p.temperatureC, imperial: imperial)), wind \(Units.speed(kmh: p.windSpeedKmh, imperial: imperial))")
                }
            }
            .padding(.horizontal, 8)
        }
        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .padding(.horizontal, DS.gutter)
    }
}

// MARK: - Score breakdown

/// The engine's nine factors with the points each can add, as the engine
/// weighed them for this forecast (a factor with no reading, or tide for a
/// freshwater target, is not counted and its share goes to the others). Tap
/// a row to see why it matters.
struct FactorBreakdown: View {
    let breakdown: ForecastEngine.ScoreBreakdown
    var species: Species? = nil
    /// One line under the card, such as when the score is for.
    var note: String? = nil
    @AppStorage("units") private var units = "metric"

    private var weights: ForecastEngine.FactorWeights { breakdown.weights }

    private struct Factor {
        let name: String
        let icon: String
        let tint: Color
        let value: Double
        let weight: Double
        let why: String
    }

    private var factors: [Factor] {
        let imperial = units == "imperial"
        let band = "\(Units.temperature(15, imperial: imperial)) to \(Units.temperature(25, imperial: imperial))"
        return [
            Factor(name: "Pressure", icon: "gauge.with.dots.needle.50percent", tint: ForecastCondition.pressure.tint,
                   value: breakdown.pressure, weight: weights.pressure,
                   why: "Steady, moderate pressure keeps fish at their normal depth."),
            Factor(name: "Pressure trend", icon: "chart.line.downtrend.xyaxis", tint: .indigo,
                   value: breakdown.pressureTrend, weight: weights.pressureTrend,
                   why: "A falling glass before a front is the classic feeding trigger."),
            Factor(name: "Tide", icon: "water.waves", tint: ForecastCondition.tide.tint,
                   value: breakdown.tide, weight: weights.tide, why: tideExplanation),
            Factor(name: "Moon phase", icon: "moon", tint: ForecastCondition.moon.tint,
                   value: breakdown.moon, weight: weights.moon,
                   why: "Full and new moons bring the biggest tides and the strongest pull."),
            Factor(name: "Solunar window", icon: "clock", tint: .purple,
                   value: breakdown.solunar, weight: weights.solunar,
                   why: "Major and minor periods are when fish most reliably switch on."),
            Factor(name: "Time of day", icon: "sun.max", tint: ForecastCondition.sun.tint,
                   value: breakdown.timeOfDay, weight: weights.timeOfDay, why: timeExplanation),
            Factor(name: "Wind", icon: "wind", tint: ForecastCondition.wind.tint,
                   value: breakdown.wind, weight: weights.wind,
                   why: "A ripple breaks up the surface and pushes bait to the windward bank."),
            Factor(name: "Temperature", icon: "thermometer.medium", tint: ForecastCondition.water.tint,
                   value: breakdown.temperature, weight: weights.temperature,
                   why: species.map { "Scored against the range \($0.commonName) prefer." }
                       ?? "Scored against the \(band) most game fish like."),
            Factor(name: "Season and spawn", icon: "calendar", tint: .green,
                   value: breakdown.season, weight: weights.season,
                   why: "Pre-spawn fish feed hard, and spawning fish guard rather than eat."),
        ]
    }

    private var tideExplanation: String {
        switch ForecastEngine.SpeciesTraits(species).tide {
        case .ignored: return "\(species?.commonName ?? "This fish") live in fresh water, so tide is left out."
        case .heavier: return "Counts for more because \(species?.commonName ?? "this fish") feed on the tide."
        case .general: return "Moving water stacks bait against structure."
        }
    }

    private var timeExplanation: String {
        guard ForecastEngine.SpeciesTraits(species).feedsAtNight, let name = species?.commonName else {
            return "Low light at dawn and dusk out-fishes the middle of the day."
        }
        return "\(name) also feed through the night, so dark hours score well."
    }

    var body: some View {
        CardSection("Why this score", note: note) {
            ForEach(Array(factors.enumerated()), id: \.offset) { _, f in
                FactorRow(name: f.name, icon: f.icon, tint: f.tint, value: f.value, weight: f.weight,
                          explanation: f.weight > 0 || f.name == "Tide"
                              ? f.why : "No reading yet, so its share goes to the rest.")
            }
        }
    }
}

private struct FactorRow: View {
    let name: String
    let icon: String
    let tint: Color
    let value: Double
    let weight: Double
    let explanation: String
    @State private var expanded = false
    @ScaledMetric(relativeTo: .body) private var meterWidth: CGFloat = 48
    @Environment(\.dynamicTypeSize) private var typeSize

    private var points: Int { Int((min(1, max(0, value)) * weight).rounded()) }
    private var counted: Bool { weight > 0 }

    var body: some View {
        Button {
            withAnimation(DS.Motion.softSpring) { expanded.toggle() }
        } label: {
            CardRow(name, subtitle: expanded ? explanation : nil, systemImage: icon, tint: tint,
                    value: counted ? "\(points) of \(Int(weight.rounded()))" : "Not counted") {
                if counted && !typeSize.isAccessibilitySize {
                    meter.frame(width: meterWidth, height: 6)
                }
            }
        }
        .buttonStyle(.dsCardRow)
        .accessibilityLabel(counted ? "\(name), \(points) of \(Int(weight.rounded())) points" : "\(name), not counted")
        .accessibilityHint(expanded ? "" : "Shows why it matters")
    }

    private var meter: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.dsFill2)
                Capsule()
                    .fill(DS.scoreColor(Int(value * 100)))
                    .frame(width: geo.size.width * min(1, max(0, value)))
            }
        }
    }
}

// MARK: - Small visuals for condition tiles and pages

/// A horizontal track with a highlighted band and a dot for the value.
struct RangeBar: View {
    let domain: ClosedRange<Double>
    var band: ClosedRange<Double>?
    var value: Double?
    var tint: Color

    private func x(_ v: Double, _ w: CGFloat) -> CGFloat {
        let span = domain.upperBound - domain.lowerBound
        guard span > 0 else { return 0 }
        return w * CGFloat(min(1, max(0, (v - domain.lowerBound) / span)))
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.dsFill2).frame(height: 6)
                if let band {
                    Capsule()
                        .fill(tint)
                        .frame(width: max(6, x(band.upperBound, w) - x(band.lowerBound, w)), height: 6)
                        .offset(x: x(band.lowerBound, w))
                }
                if let value {
                    Circle()
                        .fill(tint)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Color.dsBackground, lineWidth: 3))
                        .offset(x: x(value, w) - 7)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 16)
        .accessibilityHidden(true)
    }
}

/// A smooth line through values, optionally with a dot at a fraction along it.
struct Sparkline: View {
    let values: [Double]
    var tint: Color
    var lineWidth: CGFloat = 2.5
    var dotAt: Double? = nil
    var fill: Bool = false

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack {
                if fill, pts.count > 1 {
                    Path { p in
                        p.addPath(curve(pts))
                        p.addLine(to: CGPoint(x: pts.last!.x, y: geo.size.height))
                        p.addLine(to: CGPoint(x: pts.first!.x, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.02)], // ui-lint: allow, chart area fill
                                         startPoint: .top, endPoint: .bottom))
                }
                curve(pts)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                if let dotAt, let dot = point(atFraction: dotAt, in: geo.size) {
                    Circle()
                        .fill(tint)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color.dsBackground, lineWidth: 2.5))
                        .position(dot)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1, let lo = values.min(), let hi = values.max() else { return [] }
        let span = hi - lo == 0 ? 1 : hi - lo
        let pad: CGFloat = lineWidth + 2
        return values.enumerated().map { i, v in
            CGPoint(x: CGFloat(i) / CGFloat(values.count - 1) * size.width,
                    y: pad + (1 - CGFloat((v - lo) / span)) * (size.height - pad * 2))
        }
    }

    private func point(atFraction f: Double, in size: CGSize) -> CGPoint? {
        let pts = points(in: size)
        guard pts.count > 1 else { return nil }
        let pos = min(1, max(0, f)) * Double(pts.count - 1)
        let i = min(pts.count - 2, Int(pos))
        let t = CGFloat(pos - Double(i))
        let a = pts[i], b = pts[i + 1]
        return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    private func curve(_ pts: [CGPoint]) -> Path {
        Path { p in
            guard let first = pts.first else { return }
            p.move(to: first)
            for i in 1..<max(1, pts.count) where i < pts.count {
                let a = pts[i - 1], b = pts[i]
                let mid = (a.x + b.x) / 2
                p.addCurve(to: b, control1: CGPoint(x: mid, y: a.y), control2: CGPoint(x: mid, y: b.y))
            }
        }
    }
}

/// A compass dial with the wind arrow pointing where the wind blows to.
struct CompassDial: View {
    let degrees: Double
    var size: CGFloat = 48
    var showsLabels: Bool = false
    var tint: Color = ForecastCondition.wind.ink

    var body: some View {
        ZStack {
            ForEach(0..<36, id: \.self) { i in
                Capsule()
                    .fill(Color.dsText3)
                    .frame(width: i % 9 == 0 ? 2 : 1, height: size * (i % 9 == 0 ? 0.12 : 0.06))
                    .offset(y: -size * 0.44)
                    .rotationEffect(.degrees(Double(i) * 10))
            }
            if showsLabels {
                // Placed round the dial rather than rotated, so E and W stay
                // upright.
                ForEach(Array(["N", "E", "S", "W"].enumerated()), id: \.offset) { i, t in
                    let angle = Double(i) * .pi / 2
                    Text(t)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.dsText2)
                        .offset(x: size * 0.3 * CGFloat(sin(angle)), y: -size * 0.3 * CGFloat(cos(angle)))
                }
            }
            Image(systemName: "location.north.fill")
                .font(.system(size: size * 0.32, weight: .semibold)) // ui-lint: allow, scales with the dial
                .foregroundStyle(tint)
                .rotationEffect(.degrees(degrees + 180))
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Wind from the \(ForecastFormat.compassWord(degrees))")
    }
}

/// The sun's path from sunrise to sunset, with the sun on it during the day.
struct SunArc: View {
    let sunrise: Date
    let sunset: Date
    /// Pass a time to draw progress and the sun (today only).
    var now: Date?
    var tint: Color = ForecastCondition.sun.tint

    private var fraction: Double? {
        guard let now, now > sunrise, now < sunset else { return nil }
        return now.timeIntervalSince(sunrise) / sunset.timeIntervalSince(sunrise)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let center = CGPoint(x: w / 2, y: h - 2)
            let r = min(w / 2 - 6, h - 6)
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h - 2))
                    p.addLine(to: CGPoint(x: w, y: h - 2))
                }
                .stroke(Color.dsSeparator, lineWidth: 1)
                Path { p in
                    p.addArc(center: center, radius: r, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
                }
                .stroke(Color.dsText3, style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
                if let f = fraction {
                    let end = 180 + 180 * f
                    Path { p in
                        p.addArc(center: center, radius: r, startAngle: .degrees(180), endAngle: .degrees(end), clockwise: false)
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    Circle()
                        .fill(tint)
                        .frame(width: 11, height: 11)
                        .position(x: center.x + r * CGFloat(cos(end * .pi / 180)),
                                  y: center.y + r * CGFloat(sin(end * .pi / 180)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Short bars for cloud cover through the coming hours; rainy hours tinted.
struct CloudBars: View {
    let hours: [WeatherService.HourlyPoint]

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(hours, id: \.date) { p in
                RoundedRectangle(cornerRadius: 2, style: .continuous) // ui-lint: allow, chart bar, not a card
                    .fill(p.precipMm >= 0.2 ? ForecastCondition.tide.tint : Color.dsText3)
                    .frame(maxWidth: .infinity)
                    .frame(height: max(4, 24 * CGFloat(p.cloudCoverPct) / 100))
            }
        }
        .frame(height: 26, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

// MARK: - Page title

extension View {
    /// Sets `shown` once a page with its own large title has scrolled past
    /// it. Apply to the page's ScrollView.
    func forecastTracksTitle(_ shown: Binding<Bool>) -> some View {
        onScrollGeometryChange(for: Bool.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top > 60
        } action: { _, past in
            shown.wrappedValue = past
        }
    }

    /// The inline title of a page that shows its own large title: hidden at
    /// rest and faded in once `shown`, as on `TodayPage`.
    func forecastInlineTitle(_ title: String, shown: Bool) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                        .opacity(shown ? 1 : 0)
                        .animation(.easeOut(duration: DS.Motion.fast), value: shown)
                        .accessibilityHidden(!shown)
                }
            }
    }
}
