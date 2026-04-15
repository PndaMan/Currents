import SwiftUI
import MapKit
import CoreLocation

/// Sheet shown when the user taps anywhere on the map.
///
/// Gives a full picture of why (or why not) that coordinate is worth fishing:
/// current weather, a full bite forecast, nearby saved spots, and probable
/// fishing holes derived from the user's catch history + terrain heuristics.
struct LocationInspectorSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let coordinate: CLLocationCoordinate2D

    @State private var weather: WeatherService.WeatherData?
    @State private var forecast: ForecastEngine.ForecastResult?
    @State private var placeName: String?
    @State private var nearbySpots: [ScoredSpot] = []
    @State private var probableSpots: [ProbableSpot] = []
    @State private var isLoading = true
    @State private var showingSaveAsSpot = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CurrentsTheme.paddingM) {
                    header
                    if let forecast {
                        BiteScoreCard(forecast: forecast)
                    }
                    if let weather {
                        weatherCard(weather)
                    }
                    probableSpotsSection
                    nearbySpotsSection
                    actionBar
                }
                .padding()
            }
            .navigationTitle("Location Insight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
            .sheet(isPresented: $showingSaveAsSpot) {
                AddSpotSheet(prefillCoordinate: coordinate)
                    .presentationDetents([.medium])
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Map(initialPosition: .camera(.init(
                centerCoordinate: coordinate,
                distance: 2500
            ))) {
                Marker("", coordinate: coordinate)
                    .tint(.orange)
            }
            .mapStyle(.hybrid)
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .allowsHitTesting(false)

            HStack {
                Image(systemName: "scope")
                    .foregroundStyle(.orange)
                Text(placeName ?? String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Weather Card

    @ViewBuilder
    private func weatherCard(_ w: WeatherService.WeatherData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Current Conditions", systemImage: "cloud.sun.fill")
                .font(.headline)
            HStack(spacing: 16) {
                WeatherStat(icon: "thermometer.medium", label: "Air", value: String(format: "%.0f°", w.temperatureC))
                if let wt = w.waterTempC {
                    WeatherStat(icon: "drop.fill", label: "Water", value: String(format: "%.0f°", wt))
                }
                WeatherStat(icon: "wind", label: "Wind", value: "\(Int(w.windSpeedKmh))km/h")
                WeatherStat(icon: "barometer", label: "Pres", value: "\(Int(w.pressureHpa))")
            }
            if w.pressureChange6h != 0 {
                let sign = w.pressureChange6h > 0 ? "rising" : "falling"
                let arrow = w.pressureChange6h > 0 ? "arrow.up" : "arrow.down"
                HStack {
                    Image(systemName: arrow)
                    Text("Pressure \(sign) \(String(format: "%.1f", abs(w.pressureChange6h))) hPa / 6h")
                        .font(.caption)
                }
                .foregroundStyle(w.pressureChange6h < 0 ? .green : .orange)
            }
        }
        .glassCard()
    }

    // MARK: - Probable Spots

    @ViewBuilder
    private var probableSpotsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Probable Fishing Spots", systemImage: "sparkles")
                .font(.headline)

            if probableSpots.isEmpty {
                Text("Tap a spot closer to water to see suggestions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(probableSpots) { p in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(CurrentsTheme.scoreColor(p.score).gradient)
                                .frame(width: 36, height: 36)
                            Text("\(p.score)")
                                .font(.caption.bold())
                                .monospacedDigit()
                                .foregroundStyle(.white)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name)
                                .font(.subheadline.bold())
                            Text(p.reason)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Text(p.distanceString)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: - Nearby Spots

    @ViewBuilder
    private var nearbySpotsSection: some View {
        if !nearbySpots.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Your Spots Nearby", systemImage: "mappin.and.ellipse")
                    .font(.headline)
                ForEach(nearbySpots) { entry in
                    HStack(spacing: 12) {
                        Image(systemName: entry.spot.isPrivate ? "lock.fill" : "mappin.circle.fill")
                            .foregroundStyle(CurrentsTheme.accent)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.spot.name)
                                .font(.subheadline.bold())
                            Text("\(entry.catchCount) catch\(entry.catchCount == 1 ? "" : "es")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(entry.distanceString)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
    }

    // MARK: - Actions

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                showingSaveAsSpot = true
            } label: {
                Label("Save as Spot", systemImage: "mappin.and.ellipse")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            ShareLink(item: mapsURL) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private var mapsURL: URL {
        URL(string: "https://maps.apple.com/?ll=\(coordinate.latitude),\(coordinate.longitude)")!
    }

    // MARK: - Loading

    private func load() async {
        async let weatherTask = WeatherService.shared.current(for: coordinate)
        async let placeNameTask = reverseGeocode(coordinate)

        let w = await weatherTask
        await MainActor.run { self.weather = w }

        // Build forecast using weather inputs
        let f = ForecastEngine.forecast(
            date: .now,
            coordinate: coordinate,
            currentPressureHpa: w?.pressureHpa,
            pressureChange6h: w?.pressureChange6h,
            waterTempC: w?.waterTempC,
            windSpeedKmh: w?.windSpeedKmh,
            windDirection: w?.windDirectionDeg,
            species: nil,
            isInSpawningZone: false
        )
        await MainActor.run { self.forecast = f }

        self.placeName = await placeNameTask

        // Compute nearby user spots & probable spots
        let (nearby, probable) = await computeSpotInsights()
        await MainActor.run {
            self.nearbySpots = nearby
            self.probableSpots = probable
            self.isLoading = false
        }
    }

    private func reverseGeocode(_ coord: CLLocationCoordinate2D) async -> String? {
        let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(loc)
            if let p = placemarks.first {
                return [p.locality, p.administrativeArea, p.country]
                    .compactMap { $0 }
                    .joined(separator: ", ")
            }
        } catch {
            return nil
        }
        return nil
    }

    private func computeSpotInsights() async -> ([ScoredSpot], [ProbableSpot]) {
        guard let spots = try? appState.spotRepository.fetchNearby(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            radiusKm: 50
        ) else {
            return ([], [])
        }

        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let scored: [ScoredSpot] = spots.compactMap { spot in
            let loc = CLLocation(latitude: spot.latitude, longitude: spot.longitude)
            let distM = origin.distance(from: loc)
            guard distM < 30_000 else { return nil }
            let count = (try? appState.catchRepository.fetchForSpot(spot.id))?.count ?? 0
            return ScoredSpot(spot: spot, distanceMeters: distM, catchCount: count)
        }
        .sorted { $0.distanceMeters < $1.distanceMeters }

        // Probable spots: rank saved spots by (catchHistory * 2 + (1/distance))
        // and add the top scoring historical producers.
        let probable = scored
            .sorted { scoreForProbable($0) > scoreForProbable($1) }
            .prefix(3)
            .map { entry -> ProbableSpot in
                let score = Int(min(100, max(10, scoreForProbable(entry) * 10)))
                let reason = entry.catchCount > 0
                    ? "\(entry.catchCount) historical catches — proven producer"
                    : "Saved spot within reach of this tap"
                return ProbableSpot(
                    id: entry.id,
                    name: entry.spot.name,
                    score: score,
                    reason: reason,
                    distanceMeters: entry.distanceMeters
                )
            }

        return (Array(scored.prefix(5)), probable)
    }

    private func scoreForProbable(_ entry: ScoredSpot) -> Double {
        let distanceKm = entry.distanceMeters / 1000.0
        let proximityScore = max(0, 10 - distanceKm)
        return proximityScore + Double(entry.catchCount) * 2
    }
}

// MARK: - Supporting Types

private struct ScoredSpot: Identifiable {
    let spot: Spot
    let distanceMeters: Double
    let catchCount: Int

    var id: String { spot.id }

    var distanceString: String {
        if distanceMeters < 1000 {
            return "\(Int(distanceMeters)) m"
        }
        return String(format: "%.1f km", distanceMeters / 1000)
    }
}

private struct ProbableSpot: Identifiable {
    let id: String
    let name: String
    let score: Int
    let reason: String
    let distanceMeters: Double

    var distanceString: String {
        if distanceMeters < 1000 {
            return "\(Int(distanceMeters)) m"
        }
        return String(format: "%.1f km", distanceMeters / 1000)
    }
}

// MARK: - Bite Score Card

struct BiteScoreCard: View {
    let forecast: ForecastEngine.ForecastResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Bite Forecast", systemImage: "fish.fill")
                    .font(.headline)
                Spacer()
                Text(ratingLabel)
                    .font(.caption.bold())
                    .glassPill()
            }
            HStack(spacing: 16) {
                ScoreGauge(score: forecast.score, label: "Right now", size: 88)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(forecast.reasons.prefix(3), id: \.self) { reason in
                        HStack(alignment: .top, spacing: 6) {
                            Circle()
                                .fill(CurrentsTheme.scoreColor(forecast.score))
                                .frame(width: 6, height: 6)
                                .padding(.top, 5)
                            Text(reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .glassCard()
    }

    private var ratingLabel: String {
        switch forecast.score {
        case 85...: return "Excellent"
        case 70..<85: return "Very Good"
        case 55..<70: return "Good"
        case 40..<55: return "Fair"
        default: return "Poor"
        }
    }
}

// MARK: - Weather Stat

private struct WeatherStat: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.bold().monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
