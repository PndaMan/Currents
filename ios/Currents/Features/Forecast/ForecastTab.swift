import SwiftUI
import Charts
import CoreLocation

struct ForecastTab: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    var presentedAsSheet: Bool = false
    @State private var forecast: ForecastEngine.ForecastResult?
    @State private var solunar: SolunarEngine.SolunarDay?
    @State private var tideDay: TideEngine.TideDay?
    @State private var weather: WeatherService.WeatherData?
    @State private var selectedSpecies: Species?
    @State private var allSpecies: [Species] = []
    @State private var selectedDay: Int = 0
    @State private var isLoadingWeather = true
    @State private var selectedHour: Int?
    @State private var hourDetail: ForecastEngine.ForecastResult?
    @State private var speciesSearch = ""
    @State private var showAllSpecies = false

    private var forecastDate: Date {
        Calendar.current.date(byAdding: .day, value: selectedDay, to: .now) ?? .now
    }

    private var coordinate: CLLocationCoordinate2D {
        appState.locationManager.currentLocation?.coordinate ??
        CLLocationCoordinate2D(latitude: -33.9, longitude: 18.4)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CurrentsTheme.paddingM) {
                    dayPicker

                    // Main score
                    if let forecast, let solunar {
                        scoreCard(forecast, solunar: solunar)
                    } else {
                        ProgressView()
                            .frame(height: 120)
                    }

                    // Current conditions
                    if let weather {
                        currentConditionsCard(weather)
                        windAndPressureCard(weather)
                    } else if isLoadingWeather {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Fetching weather data...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .glassCard()
                    }

                    // Hourly chart
                    if let forecast, !forecast.hourlyScores.isEmpty {
                        hourlyChart(forecast)
                    }

                    // Solunar feeding windows
                    if let solunar {
                        solunarCard(solunar)
                    }

                    // Tide chart
                    if let tideDay {
                        tideCard(tideDay)
                    }

                    // Sun times
                    if let solunar {
                        sunTimesCard(solunar)
                    }

                    // Breakdown
                    if let forecast {
                        breakdownCard(forecast)
                    }

                    // Species picker
                    speciesPicker
                }
                .padding()
            }
            .navigationTitle("Forecast")
            .toolbar {
                if presentedAsSheet {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await fetchWeatherAndCompute() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task {
                allSpecies = (try? appState.speciesRepository.fetchAll()) ?? []
                await fetchWeatherAndCompute()
            }
            .onChange(of: selectedDay) { _, _ in recompute() }
        }
    }

    // MARK: - Current Conditions Card

    private func currentConditionsCard(_ weather: WeatherService.WeatherData) -> some View {
        VStack(spacing: 16) {
            HStack {
                Text("Current Conditions")
                    .font(.headline)
                Spacer()
                Text(weather.fetchedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("ago")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Temperature row
            HStack(spacing: 20) {
                WeatherIcon(condition: weather.condition)
                    .font(.system(size: 32))

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Int(weather.temperatureC))°C")
                        .font(.system(size: 32, weight: .bold))
                        .monospacedDigit()
                    Text(weather.condition.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let waterTemp = weather.waterTempC {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "water.waves")
                                .foregroundStyle(.cyan)
                            Text("\(Int(waterTemp))°C")
                                .font(.title2.bold())
                                .monospacedDigit()
                        }
                        Text("Water Temp")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Detail grid — 2x2
            LazyVGrid(columns: [
                GridItem(.flexible()), GridItem(.flexible())
            ], spacing: 10) {
                WeatherDetailCell(icon: "drop.fill", value: "\(weather.humidity)%", label: "Humidity")
                WeatherDetailCell(icon: "cloud.fill", value: "\(weather.cloudCoverPct)%", label: "Cloud Cover")
                WeatherDetailCell(icon: "umbrella.fill", value: String(format: "%.1fmm", weather.precipMm), label: "Precipitation")
                WeatherDetailCell(icon: "sun.max.fill", value: String(format: "%.0f", weather.uvIndex), label: "UV Index")
            }
        }
        .glassCard()
    }

    // MARK: - Wind & Pressure Card

    private func windAndPressureCard(_ weather: WeatherService.WeatherData) -> some View {
        VStack(spacing: 16) {
            // Wind
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Wind")
                        .font(.headline)
                    Text("\(Int(weather.windSpeedKmh)) km/h \(windDirection(weather.windDirectionDeg))")
                        .font(.title3.bold())
                        .monospacedDigit()
                }

                Spacer()

                // Compass
                ZStack {
                    Circle()
                        .stroke(.secondary.opacity(0.2), lineWidth: 2)
                        .frame(width: 56, height: 56)
                    Text("N")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .offset(y: -30)
                    Image(systemName: "location.north.fill")
                        .font(.body)
                        .foregroundStyle(.blue)
                        .rotationEffect(.degrees(weather.windDirectionDeg))
                }
            }

            // Pressure
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pressure")
                        .font(.headline)
                    HStack(spacing: 6) {
                        Text("\(Int(weather.pressureHpa)) hPa")
                            .font(.title3.bold())
                            .monospacedDigit()

                        let trend = weather.pressureChange6h
                        HStack(spacing: 2) {
                            Image(systemName: trend < -1 ? "arrow.down" : trend > 1 ? "arrow.up" : "equal")
                                .font(.caption)
                            Text(String(format: "%+.1f", trend))
                                .font(.caption.bold())
                                .monospacedDigit()
                        }
                        .foregroundStyle(pressureTrendColor(trend))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(pressureTrendColor(trend).opacity(0.15))
                        .clipShape(Capsule())
                    }
                }
                Spacer()
                Text(pressureTrendLabel(weather.pressureChange6h))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .glassCard()
    }

    // MARK: - Day Picker

    private var dayPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(0..<7, id: \.self) { offset in
                    let date = Calendar.current.date(byAdding: .day, value: offset, to: .now) ?? .now
                    Button {
                        selectedDay = offset
                    } label: {
                        VStack(spacing: 4) {
                            Text(offset == 0 ? "Today" : dayLabel(date))
                                .font(.caption.bold())
                            Text(date, format: .dateTime.day())
                                .font(.title3.bold())
                                .monospacedDigit()
                        }
                        .frame(width: 60)
                        .padding(.vertical, 8)
                        .background(selectedDay == offset ? Color.blue : Color.clear)
                        .foregroundStyle(selectedDay == offset ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.secondary.opacity(0.3))
                        )
                    }
                }
            }
        }
    }

    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    // MARK: - Score Card

    private func scoreCard(_ forecast: ForecastEngine.ForecastResult, solunar: SolunarEngine.SolunarDay) -> some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                ScoreGauge(score: forecast.score, label: "Bite Score", size: 90)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: ratingIcon(solunar.dayRating))
                            .foregroundStyle(ratingColor(solunar.dayRating))
                        Text("\(solunar.dayRating.label) Day")
                            .font(.title3.bold())
                            .foregroundStyle(ratingColor(solunar.dayRating))
                    }

                    if !forecast.bestHours.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                            Text("Best: " + forecast.bestHours.map { formatHour($0) }.joined(separator: ", "))
                                .font(.caption.bold())
                                .foregroundStyle(.green)
                        }
                    }

                    HStack(spacing: 4) {
                        Image(systemName: solunar.moonPhase.symbolName)
                            .symbolRenderingMode(.multicolor)
                        Text(solunar.moonPhase.displayName)
                            .font(.caption)
                        Text("(\(Int(solunar.moonIllumination * 100))%)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            if !forecast.reasons.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(forecast.reasons.prefix(4), id: \.self) { reason in
                        Label(reason, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .glassCard()
    }

    // MARK: - Hourly Chart

    private func hourlyChart(_ forecast: ForecastEngine.ForecastResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Hourly Forecast")
                    .font(.headline)
                Spacer()
                if selectedHour != nil {
                    Button("Clear") { selectedHour = nil; hourDetail = nil }
                        .font(.caption)
                }
            }

            Chart(forecast.hourlyScores, id: \.hour) { point in
                BarMark(
                    x: .value("Hour", point.hour),
                    y: .value("Score", point.score)
                )
                .foregroundStyle(selectedHour == point.hour ? Color.blue : barColor(score: point.score))
                .opacity(selectedHour == nil || selectedHour == point.hour ? 1.0 : 0.4)
            }
            .chartYScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: .stride(by: 3)) { value in
                    AxisValueLabel {
                        if let hour = value.as(Int.self) {
                            Text(formatHour(hour))
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text("\(v)")
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartXSelection(value: $selectedHour)
            .frame(height: 160)

            // Hourly drill-down detail
            if let hour = selectedHour, let detail = hourDetail {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(formatHour(hour))
                            .font(.title3.bold())
                        ScoreGauge(score: detail.score, label: "", size: 36)
                        Spacer()
                        if !detail.feedingWindows.isEmpty {
                            let inWindow = detail.feedingWindows.contains { w in
                                let hourDate = Calendar.current.startOfDay(for: forecastDate)
                                    .addingTimeInterval(Double(hour) * 3600 + 1800)
                                return hourDate >= w.start && hourDate <= w.end
                            }
                            if inWindow {
                                Text("FEEDING")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.2))
                                    .foregroundStyle(.orange)
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    ForEach(detail.reasons.prefix(3), id: \.self) { reason in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(CurrentsTheme.scoreColor(detail.score))
                                .frame(width: 5, height: 5)
                            Text(reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Mini breakdown
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        MiniBreakdownCell(label: "Pressure", value: detail.breakdown.pressure)
                        MiniBreakdownCell(label: "Trend", value: detail.breakdown.pressureTrend)
                        MiniBreakdownCell(label: "Tide", value: detail.breakdown.tide)
                        MiniBreakdownCell(label: "Solunar", value: detail.breakdown.solunar)
                        MiniBreakdownCell(label: "Time", value: detail.breakdown.timeOfDay)
                        MiniBreakdownCell(label: "Wind", value: detail.breakdown.wind)
                        MiniBreakdownCell(label: "Temp", value: detail.breakdown.temperature)
                        MiniBreakdownCell(label: "Moon", value: detail.breakdown.moon)
                    }
                }
                .padding(.top, 4)
                .transition(.opacity)
            }
        }
        .glassCard()
        .onChange(of: selectedHour) { _, newHour in
            guard let hour = newHour else { hourDetail = nil; return }
            hourDetail = ForecastEngine.forecastForHour(
                hour: hour,
                date: forecastDate,
                coordinate: coordinate,
                currentPressureHpa: weather?.pressureHpa,
                pressureChange6h: weather?.pressureChange6h,
                waterTempC: weather?.waterTempC,
                windSpeedKmh: weather?.windSpeedKmh,
                species: selectedSpecies,
                isInSpawningZone: false
            )
        }
    }

    // MARK: - Solunar Card

    private func solunarCard(_ solunar: SolunarEngine.SolunarDay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Solunar Periods")
                    .font(.headline)
                Spacer()
                Image(systemName: solunar.moonPhase.symbolName)
                    .symbolRenderingMode(.multicolor)
                    .font(.title3)
            }

            ForEach(solunar.majorPeriods, id: \.peak) { window in
                feedingRow(window, isMajor: true)
            }
            ForEach(solunar.minorPeriods, id: \.peak) { window in
                feedingRow(window, isMajor: false)
            }
        }
        .glassCard()
    }

    private func feedingRow(_ window: SolunarEngine.FeedingWindow, isMajor: Bool) -> some View {
        HStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(isMajor ? Color.orange : Color.blue)
                .frame(width: 4, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(window.kind.rawValue)
                    .font(.subheadline.bold())
                Text("\(window.start, style: .time) – \(window.end, style: .time)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(isMajor ? "MAJOR" : "MINOR")
                .font(.caption2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isMajor ? Color.orange.opacity(0.2) : Color.blue.opacity(0.2))
                .foregroundStyle(isMajor ? .orange : .blue)
                .clipShape(Capsule())
        }
    }

    // MARK: - Tide Card

    private func tideCard(_ tide: TideEngine.TideDay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tides")
                .font(.headline)

            Chart(tide.points, id: \.time) { point in
                LineMark(
                    x: .value("Time", point.time),
                    y: .value("Height", point.height)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(.cyan.gradient)

                AreaMark(
                    x: .value("Time", point.time),
                    y: .value("Height", point.height)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(.cyan.opacity(0.15).gradient)
            }
            .chartYScale(domain: -1.2...1.2)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                    AxisValueLabel(format: .dateTime.hour())
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 120)

            HStack(spacing: 16) {
                ForEach(tide.highTides) { event in
                    Label("\(event.time, style: .time)", systemImage: "arrow.up")
                        .font(.caption)
                        .foregroundStyle(.cyan)
                }
                ForEach(tide.lowTides) { event in
                    Label("\(event.time, style: .time)", systemImage: "arrow.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .glassCard()
    }

    // MARK: - Sun Times Card

    private func sunTimesCard(_ solunar: SolunarEngine.SolunarDay) -> some View {
        HStack {
            VStack(spacing: 4) {
                Image(systemName: "sunrise.fill")
                    .font(.title3)
                    .symbolRenderingMode(.multicolor)
                Text(solunar.sunrise, style: .time)
                    .font(.subheadline.bold())
                    .monospacedDigit()
                Text("Sunrise")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 40)

            VStack(spacing: 4) {
                Image(systemName: "sun.max.fill")
                    .font(.title3)
                    .foregroundStyle(.yellow)
                Text("Golden Hours")
                    .font(.subheadline.bold())
                Text("\(solunar.dawnGoldenHour.lowerBound, style: .time)–\(solunar.dawnGoldenHour.upperBound, style: .time)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 40)

            VStack(spacing: 4) {
                Image(systemName: "sunset.fill")
                    .font(.title3)
                    .symbolRenderingMode(.multicolor)
                Text(solunar.sunset, style: .time)
                    .font(.subheadline.bold())
                    .monospacedDigit()
                Text("Sunset")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .glassCard()
    }

    // MARK: - Breakdown Card

    private func breakdownCard(_ forecast: ForecastEngine.ForecastResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Score Breakdown")
                .font(.headline)

            BreakdownRow(label: "Pressure", value: forecast.breakdown.pressure, weight: 10)
            BreakdownRow(label: "Pressure Trend", value: forecast.breakdown.pressureTrend, weight: 15)
            BreakdownRow(label: "Tide", value: forecast.breakdown.tide, weight: 15)
            BreakdownRow(label: "Moon Phase", value: forecast.breakdown.moon, weight: 10)
            BreakdownRow(label: "Solunar Window", value: forecast.breakdown.solunar, weight: 15)
            BreakdownRow(label: "Time of Day", value: forecast.breakdown.timeOfDay, weight: 15)
            BreakdownRow(label: "Wind", value: forecast.breakdown.wind, weight: 8)
            BreakdownRow(label: "Temperature", value: forecast.breakdown.temperature, weight: 7)
            BreakdownRow(label: "Season/Spawn", value: forecast.breakdown.season, weight: 5)
        }
        .glassCard()
    }

    // MARK: - Species Picker

    private var speciesPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Target Species")
                .font(.headline)

            Button {
                showAllSpecies = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(selectedSpecies != nil ? .blue.opacity(0.15) : .secondary.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Image(systemName: "fish.fill")
                            .foregroundStyle(selectedSpecies != nil ? .blue : .secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedSpecies?.commonName ?? "General (All Species)")
                            .font(.body.bold())
                            .foregroundStyle(.primary)
                        if let sci = selectedSpecies?.scientificName {
                            Text(sci)
                                .font(.caption)
                                .italic()
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Tap to choose a target species")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.primary)

            if let species = selectedSpecies {
                HStack(spacing: 8) {
                    if let temp = species.optimalTempC {
                        Label("\(Int(temp))°C", systemImage: "thermometer.medium")
                            .font(.caption)
                            .glassPill()
                    }
                    if let habitat = species.habitat {
                        Label(habitat.rawValue.capitalized, systemImage: "water.waves")
                            .font(.caption)
                            .glassPill()
                    }
                    Spacer()
                    Button("Clear") {
                        selectedSpecies = nil
                        recompute()
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }
            }
        }
        .glassCard()
        .sheet(isPresented: $showAllSpecies) {
            ForecastSpeciesPickerSheet(
                allSpecies: allSpecies,
                selectedSpecies: $selectedSpecies,
                onSelect: { recompute() }
            )
        }
    }

    // MARK: - Data Loading

    private func fetchWeatherAndCompute() async {
        isLoadingWeather = true
        weather = await WeatherService.shared.current(for: coordinate)
        isLoadingWeather = false
        recompute()
    }

    private func recompute() {
        let coord = coordinate
        let date = forecastDate

        solunar = SolunarEngine.compute(date: date, coordinate: coord)
        tideDay = TideEngine.predict(date: date, coordinate: coord)

        forecast = ForecastEngine.forecast(
            date: date,
            coordinate: coord,
            currentPressureHpa: weather?.pressureHpa,
            pressureChange6h: weather?.pressureChange6h,
            waterTempC: weather?.waterTempC,
            windSpeedKmh: weather?.windSpeedKmh,
            windDirection: weather?.windDirectionDeg,
            species: selectedSpecies,
            isInSpawningZone: false
        )
    }

    // MARK: - Helpers

    private func formatHour(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        let ampm = hour < 12 ? "a" : "p"
        return "\(h)\(ampm)"
    }

    private func barColor(score: Int) -> Color {
        switch score {
        case 0..<25: return .red.opacity(0.7)
        case 25..<50: return .orange.opacity(0.7)
        case 50..<75: return .yellow.opacity(0.7)
        default: return .green.opacity(0.8)
        }
    }

    private func ratingIcon(_ rating: SolunarEngine.DayRating) -> String {
        switch rating {
        case .poor: "star"
        case .fair: "star.leadinghalf.filled"
        case .good: "star.fill"
        case .best: "sparkles"
        }
    }

    private func ratingColor(_ rating: SolunarEngine.DayRating) -> Color {
        switch rating {
        case .poor: .red
        case .fair: .orange
        case .good: .green
        case .best: .yellow
        }
    }

    private func windDirection(_ degrees: Double) -> String {
        let directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                         "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int((degrees + 11.25) / 22.5) % 16
        return directions[index]
    }

    private func compassOffset(for dir: String, radius: CGFloat) -> CGSize {
        switch dir {
        case "N": return CGSize(width: 0, height: -radius)
        case "S": return CGSize(width: 0, height: radius)
        case "E": return CGSize(width: radius, height: 0)
        case "W": return CGSize(width: -radius, height: 0)
        default: return .zero
        }
    }

    private func pressureTrendColor(_ trend: Double) -> Color {
        if trend < -2 { return .green }
        if trend < -0.5 { return .green.opacity(0.7) }
        if trend > 2 { return .red }
        if trend > 0.5 { return .orange }
        return .secondary
    }

    private func pressureTrendLabel(_ trend: Double) -> String {
        if trend < -3 { return "Dropping fast" }
        if trend < -1 { return "Falling" }
        if trend > 3 { return "Rising fast" }
        if trend > 1 { return "Rising" }
        return "Stable"
    }
}

// MARK: - Weather Detail Cell

struct WeatherDetailCell: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.bold())
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Mini Breakdown Cell (hourly drill-down)

struct MiniBreakdownCell: View {
    let label: String
    let value: Double

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(value > 0.7 ? Color.green : value < 0.4 ? Color.red : Color.orange)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(Int(value * 100))%")
                .font(.caption2.bold())
                .monospacedDigit()
        }
    }
}

// MARK: - Forecast Species Picker Sheet

struct ForecastSpeciesPickerSheet: View {
    let allSpecies: [Species]
    @Binding var selectedSpecies: Species?
    let onSelect: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var habitatFilter: Species.Habitat?

    private var filtered: [Species] {
        var result = allSpecies
        if let hab = habitatFilter {
            result = result.filter { $0.habitat == hab }
        }
        if !search.isEmpty {
            let q = search.lowercased()
            result = result.filter {
                $0.commonName.lowercased().contains(q) ||
                $0.scientificName.lowercased().contains(q) ||
                ($0.family ?? "").lowercased().contains(q)
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Habitat filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(title: "All", isSelected: habitatFilter == nil) {
                            habitatFilter = nil
                        }
                        ForEach(Species.Habitat.allCases, id: \.self) { hab in
                            FilterChip(title: hab.rawValue.capitalized, isSelected: habitatFilter == hab) {
                                habitatFilter = hab
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)

                List {
                    // General option
                    Button {
                        selectedSpecies = nil
                        onSelect()
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(.secondary.opacity(0.15))
                                    .frame(width: 44, height: 44)
                                Image(systemName: "globe")
                                    .foregroundStyle(.secondary)
                            }
                            Text("General (All Species)")
                                .font(.body.bold())
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedSpecies == nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .tint(.primary)

                    Section("\(filtered.count) species") {
                        ForEach(filtered) { sp in
                            Button {
                                selectedSpecies = sp
                                onSelect()
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(habitatColor(sp.habitat).opacity(0.15))
                                            .frame(width: 44, height: 44)
                                        Image(systemName: "fish.fill")
                                            .foregroundStyle(habitatColor(sp.habitat))
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(sp.commonName)
                                            .font(.body.bold())
                                            .foregroundStyle(.primary)
                                        Text(sp.scientificName)
                                            .font(.caption)
                                            .italic()
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if let temp = sp.optimalTempC {
                                        Text("\(Int(temp))°")
                                            .font(.caption.bold())
                                            .foregroundStyle(.green)
                                    }
                                    if selectedSpecies?.id == sp.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                            .tint(.primary)
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Target Species")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Search species by name or family...")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func habitatColor(_ habitat: Species.Habitat?) -> Color {
        switch habitat {
        case .freshwater: .green
        case .marine: .blue
        case .brackish: .teal
        case nil: .gray
        }
    }
}

// MARK: - Breakdown Row

struct BreakdownRow: View {
    let label: String
    let value: Double
    let weight: Double

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                Text("\(Int(value * weight))/\(Int(weight))")
                    .font(.caption.bold())
                    .monospacedDigit()
                    .foregroundStyle(value > 0.7 ? .green : value < 0.4 ? .red : .orange)
                Spacer()
                Text("\(Int(value * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(value > 0.7 ? Color.green : value < 0.4 ? Color.red : Color.orange)
                        .frame(width: geo.size.width * min(1, max(0, value)))
                }
            }
            .frame(height: 4)
        }
    }
}
