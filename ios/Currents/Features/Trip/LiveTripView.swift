import SwiftUI
import CoreLocation

struct LiveTripView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let trip: Trip

    @State private var catches: [CatchDetail] = []
    @State private var weather: WeatherService.WeatherData?
    @State private var forecast: ForecastEngine.ForecastResult?
    @State private var showingLogCatch = false
    @State private var showingEndConfirm = false
    @State private var nearbySpot: Spot?

    private func timerString(for date: Date) -> String {
        let elapsed = Int(date.timeIntervalSince(trip.startDate))
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Live timer using TimelineView (MainActor-safe)
                TimelineView(.periodic(from: trip.startDate, by: 1)) { context in
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(CurrentsTheme.accent)
                                .frame(width: 8, height: 8)
                            Text("LIVE")
                                .font(.caption.bold())
                                .foregroundStyle(CurrentsTheme.accent)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(CurrentsTheme.accent.opacity(0.15))
                        .clipShape(Capsule())

                        Text(timerString(for: context.date))
                            .font(.system(size: 52, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(.white)

                        Text("Trip Duration")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .glassCard()
                }

                // Weather + bite score
                if let w = weather, let f = forecast {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                WeatherIcon(condition: w.condition)
                                Text("\(Int(w.temperatureC))°C")
                                    .font(.title3.bold())
                            }
                            Label("\(Int(w.windSpeedKmh)) km/h", systemImage: "wind")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        ScoreGauge(score: f.score, label: "Bite", size: 64)
                    }
                    .glassCard()
                }

                // Nearby spot
                if let spot = nearbySpot {
                    HStack(spacing: 10) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(CurrentsTheme.accent)
                        Text("Near: \(spot.name)")
                            .font(.subheadline.bold())
                        Spacer()
                    }
                    .glassCard()
                }

                // Quick log
                Button {
                    showingLogCatch = true
                } label: {
                    Label("Log Catch", systemImage: "fish.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(CurrentsTheme.accent)

                // Trip catches
                if !catches.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Trip Feed")
                            .font(.headline)
                        ForEach(catches, id: \.catchRecord.id) { detail in
                            HStack {
                                Image(systemName: "fish.fill")
                                    .foregroundStyle(CurrentsTheme.accent)
                                Text(detail.species?.commonName ?? "Catch")
                                Spacer()
                                Text(detail.catchRecord.caughtAt, style: .time)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .glassCard()
                }

                // End trip
                Button(role: .destructive) {
                    showingEndConfirm = true
                } label: {
                    Label("End Trip", systemImage: "stop.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(trip.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadData()
        }
        .fullScreenCover(isPresented: $showingLogCatch, onDismiss: {
            Task { await loadCatches() }
        }) {
            LogCatchView()
        }
        .alert("End Trip?", isPresented: $showingEndConfirm) {
            Button("End Trip", role: .destructive) { endTrip() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will finish the current session.")
        }
    }

    private func loadData() async {
        await loadCatches()
        let coord = appState.locationManager.currentLocation?.coordinate ??
            CLLocationCoordinate2D(latitude: -33.9, longitude: 18.4)
        let w = await WeatherService.shared.current(for: coord)
        weather = w
        forecast = ForecastEngine.forecast(
            date: .now,
            coordinate: coord,
            currentPressureHpa: w?.pressureHpa,
            pressureChange6h: w?.pressureChange6h,
            waterTempC: w?.waterTempC,
            windSpeedKmh: w?.windSpeedKmh,
            windDirection: w?.windDirectionDeg,
            species: nil,
            isInSpawningZone: false
        )
        detectNearbySpot(coordinate: coord)
    }

    private func loadCatches() async {
        catches = (try? appState.tripRepository.catches(tripId: trip.id)) ?? []
    }

    private func detectNearbySpot(coordinate: CLLocationCoordinate2D) {
        guard let allSpots = try? appState.spotRepository.fetchAll() else { return }
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        var closest: Spot?
        var closestDist: CLLocationDistance = .greatestFiniteMagnitude
        for spot in allSpots {
            let d = here.distance(from: CLLocation(latitude: spot.latitude, longitude: spot.longitude))
            if d < 500 && d < closestDist {
                closestDist = d
                closest = spot
            }
        }
        nearbySpot = closest
    }

    private func endTrip() {
        var updated = trip
        updated.endDate = .now
        try? appState.tripRepository.save(&updated)
        dismiss()
    }
}
