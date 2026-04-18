import SwiftUI
import CoreLocation

struct AlertSettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("alertsEnabled") private var alertsEnabled = false
    @AppStorage("alertThreshold") private var alertThreshold = 75.0

    @State private var permissionStatus: UNAuthorizationStatus = .notDetermined
    @State private var spots: [Spot] = []
    @State private var spotScores: [String: Int] = [:]
    @State private var isLoadingScores = false

    var body: some View {
        Form {
            // MARK: - Alerts Toggle
            Section {
                Toggle("Bite Alerts", isOn: $alertsEnabled)
                    .tint(CurrentsTheme.accent)

                if alertsEnabled && permissionStatus != .authorized {
                    Button {
                        Task {
                            let granted = await NotificationManager.shared.requestPermission()
                            permissionStatus = granted ? .authorized : .denied
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "bell.badge")
                                .foregroundStyle(CurrentsTheme.accent)
                            Text("Grant Notification Permission")
                            Spacer()
                            if permissionStatus == .denied {
                                Text("Denied")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text("When enabled, Currents checks your saved spots and notifies you when conditions produce a high bite score. All processing happens on-device.")
            }

            // MARK: - Threshold Slider
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Minimum Score")
                        Spacer()
                        Text("\(Int(alertThreshold))")
                            .font(.body.bold())
                            .monospacedDigit()
                            .foregroundStyle(CurrentsTheme.scoreColor(Int(alertThreshold)))
                    }

                    Slider(value: $alertThreshold, in: 50...95, step: 5)
                        .tint(CurrentsTheme.accent)

                    HStack {
                        Text("50")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("95")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Alert Threshold")
            } footer: {
                Text("You will only be notified when a spot's bite score reaches this value or higher. Lower values mean more alerts.")
            }

            // MARK: - Spot Scores
            Section {
                if spots.isEmpty {
                    HStack {
                        Image(systemName: "mappin.slash")
                            .foregroundStyle(.secondary)
                        Text("No saved spots yet")
                            .foregroundStyle(.secondary)
                    }
                } else if isLoadingScores {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Checking conditions...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(spots) { spot in
                        spotRow(spot)
                    }
                }
            } header: {
                Text("Your Spots")
            } footer: {
                if !spots.isEmpty {
                    Text("Current bite scores for each of your saved spots. Spots at or above your threshold will trigger alerts.")
                }
            }
        }
        .navigationTitle("Bite Alerts")
        .task {
            permissionStatus = await NotificationManager.shared.checkPermissionStatus()
            spots = (try? appState.spotRepository.fetchAll()) ?? []
            await loadScores()
        }
    }

    // MARK: - Spot Row

    private func spotRow(_ spot: Spot) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(spot.name)
                    .font(.body.bold())

                Text(String(format: "%.3f, %.3f", spot.latitude, spot.longitude))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let score = spotScores[spot.id] {
                HStack(spacing: 6) {
                    if score >= Int(alertThreshold) {
                        Image(systemName: "bell.fill")
                            .font(.caption)
                            .foregroundStyle(CurrentsTheme.accent)
                    }

                    ScoreGauge(score: score, label: "", size: 36)
                }
            } else {
                Text("--")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .glassCard()
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: - Score Loading

    private func loadScores() async {
        guard !spots.isEmpty else { return }
        isLoadingScores = true

        for spot in spots {
            let coordinate = CLLocationCoordinate2D(
                latitude: spot.latitude,
                longitude: spot.longitude
            )

            if let weather = await WeatherService.shared.current(for: coordinate) {
                let result = ForecastEngine.forecast(
                    coordinate: coordinate,
                    currentPressureHpa: weather.pressureHpa,
                    pressureChange6h: weather.pressureChange6h,
                    waterTempC: weather.waterTempC,
                    windSpeedKmh: weather.windSpeedKmh,
                    windDirection: weather.windDirectionDeg,
                    species: nil,
                    isInSpawningZone: false
                )
                spotScores[spot.id] = result.score
            }
        }

        isLoadingScores = false
    }
}

#Preview {
    NavigationStack {
        AlertSettingsView()
    }
    .environment(AppState())
    .preferredColorScheme(.dark)
}
