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
    @State private var selectedWaterbody: Waterbody?
    @State private var selectedSpot: Spot?

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
            .sheet(item: $selectedWaterbody) { wb in
                WaterbodyDetailSheet(waterbody: wb)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(.ultraThinMaterial)
            }
            .sheet(item: $selectedSpot) { spot in
                SpotDetailSheet(spot: spot)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(.ultraThinMaterial)
                    .presentationDragIndicator(.visible)
                    .presentationContentInteraction(.resizes)
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
                    .tint(CurrentsTheme.accent)
            }
            .mapStyle(.hybrid)
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .allowsHitTesting(false)

            HStack {
                Image(systemName: "scope")
                    .foregroundStyle(CurrentsTheme.accent)
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
                .foregroundStyle(CurrentsTheme.accent)
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
                Text("No mapped dams or lakes near this tap — try closer to water.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(probableSpots) { p in
                    Button {
                        selectedWaterbody = p.waterbody
                    } label: {
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
                                    .foregroundStyle(.primary)
                                Text(p.reason)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Text(p.distanceString)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
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
                    Button {
                        selectedSpot = entry.spot
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(CurrentsTheme.accent)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.spot.name)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.primary)
                                Text("\(entry.catchCount) catch\(entry.catchCount == 1 ? "" : "es")")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(entry.distanceString)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
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
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        // Nearby saved spots — shown in "Your Spots Nearby".
        let spots = (try? appState.spotRepository.fetchNearby(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            radiusKm: 50
        )) ?? []

        let scored: [ScoredSpot] = spots.compactMap { spot in
            let loc = CLLocation(latitude: spot.latitude, longitude: spot.longitude)
            let distM = origin.distance(from: loc)
            guard distM < 30_000 else { return nil }
            let count = (try? appState.catchRepository.fetchForSpot(spot.id))?.count ?? 0
            return ScoredSpot(spot: spot, distanceMeters: distM, catchCount: count)
        }
        .sorted { $0.distanceMeters < $1.distanceMeters }

        // Probable fishing spots — real dams/lakes/rivers around the tap
        // (OpenStreetMap-backed waterbody DB), NOT the user's saved spots.
        let delta = 0.45 // ≈ 50 km
        let minLat = coordinate.latitude - delta
        let maxLat = coordinate.latitude + delta
        let minLon = coordinate.longitude - delta
        let maxLon = coordinate.longitude + delta

        func cachedBodies() -> [Waterbody] {
            (try? appState.waterbodyRepository.fetchForRegion(
                minLat: minLat, maxLat: maxLat,
                minLon: minLon, maxLon: maxLon,
                minSurfaceAreaKm2: 0,
                includeNilArea: true,
                limit: 200
            )) ?? []
        }

        var bodies = cachedBodies()

        // Top up from Overpass when online so we surface as many dams as possible.
        if let fresh = await OverpassService.shared.fetchWaterbodies(
            minLat: minLat, maxLat: maxLat,
            minLon: minLon, maxLon: maxLon
        ) {
            _ = try? appState.waterbodyRepository.insertFromOverpass(fresh)
            bodies = cachedBodies()
        }

        let baseScore = forecast?.score ?? 50
        let probable = bodies
            .map { wb -> (Waterbody, Double) in
                let d = origin.distance(from: CLLocation(latitude: wb.latitude, longitude: wb.longitude))
                return (wb, d)
            }
            .sorted { $0.1 < $1.1 }
            .prefix(15)
            .map { wb, distM -> ProbableSpot in
                // Bite score for the area, slightly decayed by distance.
                let score = max(5, min(100, baseScore - Int(distM / 1000 / 3)))
                return ProbableSpot(
                    id: "waterbody-\(wb.id ?? 0)-\(wb.name)",
                    name: wb.name,
                    score: score,
                    reason: probableReason(for: wb),
                    distanceMeters: distM,
                    waterbody: wb
                )
            }

        return (Array(scored.prefix(5)), Array(probable))
    }

    private func probableReason(for wb: Waterbody) -> String {
        let typeLabel = switch wb.type {
        case .dam: "Dam"
        case .lake: "Lake"
        case .river: "River"
        case .estuary: "Estuary"
        case .coast: "Coastline"
        }
        if let area = wb.surfaceAreaKm2, area > 0 {
            return "\(typeLabel) • \(String(format: "%.1f", area)) km² of water"
        }
        return "\(typeLabel) • mapped water body"
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
    let waterbody: Waterbody

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
