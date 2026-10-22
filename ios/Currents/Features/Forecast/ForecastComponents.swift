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

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func inWindow(_ h: Int) -> Bool {
        windows.contains { h >= $0.startHour && h <= $0.endHour }
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(hourly.enumerated()), id: \.element.hour) { index, point in
                    bar(point, index: index)
                }
            }
            .frame(height: height, alignment: .bottom)

            if let currentHour {
                // The now dot sits under its bar.
                GeometryReader { geo in
                    let w = geo.size.width / CGFloat(max(1, hourly.count))
                    Circle()
                        .fill(Color.dsText)
                        .frame(width: 5, height: 5)
                        .position(x: w * (CGFloat(currentHour) + 0.5), y: 2.5)
                }
                .frame(height: 5)
                .accessibilityHidden(true)
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
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
        let lit = inWindow(point.hour) || isNow || isSelected || point.score >= 50
        let fraction = max(0.08, CGFloat(point.score) / 100)

        return Button {
            withAnimation(DS.Motion.softSpring) {
                selected = isSelected ? nil : point.hour
            }
        } label: {
            RoundedRectangle(cornerRadius: 4, style: .continuous) // ui-lint: allow, chart bar, not a card
                .fill(lit ? DS.scoreColor(point.score) : Color.dsFill2)
                .opacity(isPast && !isSelected ? 0.35 : (selected != nil && !isSelected ? 0.45 : 1))
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
        .accessibilityLabel("\(ForecastFormat.hour(point.hour, use24: use24)), score \(point.score)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Evenly spaced axis labels under a 24-hour chart.
struct HourAxis: View {
    var labels: [String] = ["12 am", "6 am", "Noon", "6 pm", "11 pm"]

    var body: some View {
        HStack {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                Text(label)
                if index < labels.count - 1 { Spacer(minLength: 0) }
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

    private var nowHour: Int { Calendar.current.component(.hour, from: .now) }

    var body: some View {
        if day.windows.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "moon.zzz")
                    .foregroundStyle(.dsText2)
                Text("No strong windows. Fish the best hour, \(ForecastFormat.hour(day.bestHour, use24: use24)).")
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        } else {
            HStack(spacing: 10) {
                ForEach(day.windows) { w in tile(w) }
            }
        }
    }

    private func tile(_ w: BiteWindows.Window) -> some View {
        let isNow = day.isToday && nowHour >= w.startHour && nowHour <= w.endHour
        let passed = day.isToday && nowHour > w.endHour
        let end = ForecastFormat.hour(w.endHour + 1, use24: use24)
        let time = isNow ? "Until \(end)" : passed ? "Passed" : ForecastFormat.range(w, use24: use24)

        return Button {
            onSelect(isNow ? nowHour : w.startHour)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Label(isNow ? "Now" : ForecastFormat.windowName(w.startHour),
                      systemImage: ForecastFormat.windowIcon(w.startHour))
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                    .labelStyle(TintedIconLabelStyle(tint: DS.scoreInk(w.peakScore)))
                Text("\(w.peakScore)")
                    .font(.title.bold())
                    .monospacedDigit()
                    .foregroundStyle(DS.scoreInk(w.peakScore))
                Text(time)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.dsText2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
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
            .opacity(passed ? 0.5 : 1)
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

/// What a tapped hour looks like: score, verdict, the weather for that hour
/// and the engine's factor cells.
struct HourInfoBox: View {
    let store: ForecastStore
    let day: ForecastDay
    let hour: Int?
    var use24: Bool = true

    var body: some View {
        Group {
            if let hour, let score = day.score(at: hour) {
                filled(hour: hour, score: score)
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
        let detail = store.hourDetail(day: day.offset, hour: hour)
        let hourDate = Calendar.current.startOfDay(for: day.date).addingTimeInterval(Double(hour) * 3600 + 1800)
        let feeding = detail.feedingWindows.contains { hourDate >= $0.start && hourDate <= $0.end }
        let wx = day.hourWeather(hour)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                ScoreRing(score: score, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(ForecastFormat.hour(hour, use24: use24)), \(ForecastFormat.verdict(score).lowercased())")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.dsText)
                    if let wx {
                        Text(weatherLine(wx))
                            .font(.footnote)
                            .foregroundStyle(.dsText2)
                    }
                    if feeding {
                        Label("In a solunar feeding period", systemImage: "moon.stars.fill")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.tint)
                    }
                }
                Spacer(minLength: 0)
            }
            if let reason = detail.reasons.first {
                Text(ForecastFormat.clean(reason))
                    .font(.footnote)
                    .foregroundStyle(.dsText2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())], spacing: 6) {
                MiniFactor(label: "Pressure", value: detail.breakdown.pressure)
                MiniFactor(label: "Trend", value: detail.breakdown.pressureTrend)
                if detail.breakdown.weights.tide > 0 {
                    MiniFactor(label: "Tide", value: detail.breakdown.tide)
                }
                MiniFactor(label: "Solunar", value: detail.breakdown.solunar)
                MiniFactor(label: "Time of day", value: detail.breakdown.timeOfDay)
                MiniFactor(label: "Wind", value: detail.breakdown.wind)
                MiniFactor(label: "Temperature", value: detail.breakdown.temperature)
                MiniFactor(label: "Moon", value: detail.breakdown.moon)
            }
        }
        .transition(.opacity)
    }

    private func weatherLine(_ w: WeatherService.HourlyPoint) -> String {
        var parts = ["\(Int(w.temperatureC.rounded()))°", "wind \(Int(w.windSpeedKmh.rounded())) km/h",
                     "\(w.cloudCoverPct)% cloud"]
        if w.precipMm >= 0.1 { parts.append(String(format: "%.1f mm rain", w.precipMm)) }
        return parts.joined(separator: ", ")
    }
}

private struct MiniFactor: View {
    let label: String
    let value: Double

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(DS.scoreColor(Int(value * 100)))
                .frame(width: 7, height: 7)
            Text(label)
                .font(.footnote)
                .foregroundStyle(.dsText2)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text("\(Int((value * 100).rounded()))%")
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.dsText)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Hour by hour weather

struct HourStrip: View {
    let day: ForecastDay
    var use24: Bool = true

    private var nowHour: Int { Calendar.current.component(.hour, from: .now) }

    private var points: [WeatherService.HourlyPoint] {
        guard day.isToday else { return day.hours }
        return day.hours.filter { Calendar.current.component(.hour, from: $0.date) >= nowHour }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(points, id: \.date) { p in
                    let h = Calendar.current.component(.hour, from: p.date)
                    let isNow = day.isToday && h == nowHour
                    VStack(spacing: 8) {
                        Text(isNow ? "Now" : String(ForecastFormat.hour(h, use24: use24).prefix(use24 ? 2 : 5)))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.dsText)
                        Image(systemName: ForecastFormat.weatherSymbol(cloud: p.cloudCoverPct, precipMm: p.precipMm, hour: h))
                            .symbolRenderingMode(.hierarchical)
                            .font(.title3)
                            .foregroundStyle(.dsText2)
                            .frame(height: 24)
                        Text("\(Int(p.temperatureC.rounded()))°")
                            .font(.headline)
                            .monospacedDigit()
                            .foregroundStyle(.dsText)
                        HStack(spacing: 2) {
                            Image(systemName: "location.north.fill")
                                .font(.caption2)
                                .rotationEffect(.degrees(p.windDirectionDeg + 180))
                            Text("\(Int(p.windSpeedKmh.rounded()))")
                                .monospacedDigit()
                        }
                        .font(.footnote)
                        .foregroundStyle(.dsText2)
                        Text(p.precipMm >= 0.1 ? String(format: "%.1f", p.precipMm) : " ")
                            .font(.caption)
                            .foregroundStyle(ForecastCondition.tide.tint)
                    }
                    .frame(width: 54)
                    .padding(.vertical, 14)
                    .background {
                        if isNow {
                            RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous).fill(Color.dsFill2)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(isNow ? "Now" : ForecastFormat.hour(h, use24: use24)), \(Int(p.temperatureC.rounded())) degrees, wind \(Int(p.windSpeedKmh.rounded())) kilometres an hour")
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

    private var weights: ForecastEngine.FactorWeights { breakdown.weights }

    private var rows: [(String, String, Double, Double, String)] {
        [
            ("Pressure", "gauge.with.dots.needle.50percent", breakdown.pressure, weights.pressure,
             "Steady, moderate pressure keeps fish comfortable at their normal depth. Extremes push them down and make them sluggish."),
            ("Pressure trend", "chart.line.downtrend.xyaxis", breakdown.pressureTrend, weights.pressureTrend,
             "A falling glass ahead of a front is the classic feeding trigger. The bright high-pressure day behind it is the toughest bite there is."),
            ("Tide", "water.waves", breakdown.tide, weights.tide, tideExplanation),
            ("Moon phase", "moon", breakdown.moon, weights.moon,
             "Full and new moons give the biggest tidal movement, and a bright night can shift feeding into darkness and flatten the dawn bite."),
            ("Solunar window", "clock", breakdown.solunar, weights.solunar,
             "Major and minor periods track when the moon is overhead or underfoot, the windows fish most reliably switch on."),
            ("Time of day", "sun.max", breakdown.timeOfDay, weights.timeOfDay, timeExplanation),
            ("Wind", "wind", breakdown.wind, weights.wind,
             "A ripple breaks up the surface and stacks bait on the windward bank. Dead calm makes fish spooky; a gale makes them unfishable."),
            ("Temperature", "thermometer.medium", breakdown.temperature, weights.temperature,
             species.map { "Scored against the range \($0.commonName) prefer. Fish are cold-blooded, so water temperature sets how hard they will chase." }
                ?? "Scored against the 15 to 25 °C band most game fish like. Target a species to score it against that fish's own range."),
            ("Season and spawn", "calendar", breakdown.season, weights.season,
             "Pre-spawn fish feed hard, spawning fish guard rather than eat, and post-spawn fish recover before switching back on."),
        ]
    }

    private var tideExplanation: String {
        let base = "Moving water concentrates bait against structure. Slack water at the top or bottom of the tide is usually the quietest part of the cycle."
        switch ForecastEngine.SpeciesTraits(species).tide {
        case .ignored: return "\(species?.commonName ?? "This fish") live in fresh water, where there is no tide, so it is left out and its share goes to the rest."
        case .heavier: return base + " It counts for more because \(species?.commonName ?? "this fish") feed on the tide."
        case .general: return base
        }
    }

    private var timeExplanation: String {
        let base = "Low light at dawn and dusk hands predators the advantage, which is why those hours out-fish the middle of the day."
        guard ForecastEngine.SpeciesTraits(species).feedsAtNight, let name = species?.commonName else { return base }
        return base + " \(name) also feed through the night, so dark hours score well too."
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                FactorRow(name: row.0, icon: row.1, value: row.2, weight: row.3,
                          explanation: row.3 > 0 || row.0 == "Tide"
                              ? row.4 : row.4 + " There is no reading for it yet, so its share goes to the rest.")
                if index < rows.count - 1 {
                    Divider().overlay(Color.dsSeparator).padding(.leading, 48)
                }
            }
        }
        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .padding(.horizontal, DS.gutter)
    }
}

private struct FactorRow: View {
    let name: String
    let icon: String
    let value: Double
    let weight: Double
    let explanation: String
    @State private var expanded = false

    private var points: Int { Int((min(1, max(0, value)) * weight).rounded()) }
    private var counted: Bool { weight > 0 }

    var body: some View {
        Button {
            withAnimation(DS.Motion.softSpring) { expanded.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundStyle(.dsText2)
                        .frame(width: 22)
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(.dsText)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Spacer(minLength: 8)
                    if counted {
                        meter.frame(width: 64, height: 6)
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("\(points)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.dsText)
                            Text("of \(Int(weight.rounded()))")
                                .font(.caption)
                                .foregroundStyle(.dsText2)
                        }
                        .monospacedDigit()
                        .frame(minWidth: 44, alignment: .trailing)
                    } else {
                        Text("Not counted")
                            .font(.footnote)
                            .foregroundStyle(.dsText2)
                    }
                }
                if expanded {
                    Text(explanation)
                        .font(.footnote)
                        .foregroundStyle(.dsText2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 34)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.dim)
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
    var tint: Color = ForecastCondition.wind.tint

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
                ForEach(Array(["N", "E", "S", "W"].enumerated()), id: \.offset) { i, t in
                    Text(t)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.dsText2)
                        .offset(y: -size * 0.3)
                        .rotationEffect(.degrees(Double(i) * 90))
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

// MARK: - Explanations

/// Plain explanatory paragraphs under a condition page.
struct ExplainText: View {
    let paragraphs: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(paragraphs, id: \.self) { p in
                Text(p)
                    .font(.body)
                    .foregroundStyle(.dsText2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.gutter)
    }
}
