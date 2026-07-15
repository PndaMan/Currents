import SwiftUI
import CoreLocation
import UserNotifications

struct AlertSettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("alertsEnabled") private var alertsEnabled = false
    @AppStorage("alertThreshold") private var alertThreshold = 75.0
    @AppStorage("primeWindowAlerts") private var primeWindowAlerts = false
    @AppStorage("lowStockAlerts") private var lowStockAlerts = true

    @State private var permissionStatus: UNAuthorizationStatus = .notDetermined
    @State private var spots: [Spot] = []
    @State private var spotScores: [String: Int] = [:]
    @State private var isLoadingScores = false
    @State private var busyPush = false
    @State private var pushTick = 0   // forces the diagnostics rows to re-read

    private var svc: CommunityService { .shared }

    private var permissionLabel: String {
        switch permissionStatus {
        case .authorized, .provisional, .ephemeral: return "Allowed"
        case .denied: return "Denied — enable in iOS Settings"
        case .notDetermined: return "Not set"
        @unknown default: return "Unknown"
        }
    }

    var body: some View {
        Form {
            // MARK: - Alerts Toggle
            Section {
                Toggle("Bite Alerts", isOn: $alertsEnabled)
                    .tint(CurrentsTheme.accent)

                if alertsEnabled && permissionStatus != .authorized {
                    Button {
                        Haptics.tap()
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
                Toggle("Prime-Window Heads-Up", isOn: $primeWindowAlerts)
                    .tint(CurrentsTheme.accent)
                    .disabled(permissionStatus != .authorized)
                    .onChange(of: primeWindowAlerts) { _, _ in
                        Task { await reschedulePrimeWindows() }
                    }
                Toggle("Low Tackle-Box Stock", isOn: $lowStockAlerts)
                    .tint(CurrentsTheme.accent)
            } header: {
                Text("Notifications")
            } footer: {
                Text("Bite Alerts notify you when a spot is firing right now. Prime-Window Heads-Up looks ahead and pings you ~45 minutes before the best feeding window at your spots over the next day. Low Tackle-Box Stock reminds you to restock line, lures, bait and hooks when they run low. All processing happens on-device.")
            }

            // MARK: - Push diagnostics
            Section {
                LabeledContent("Permission") {
                    Text(permissionLabel).foregroundStyle(permissionStatus == .authorized ? .green : .orange)
                }
                Button {
                    Haptics.tap()
                    Task { await NotificationManager.shared.sendTestNotification() }
                } label: {
                    Label("Send test notification", systemImage: "bell.badge.fill")
                }
                if svc.joined {
                    LabeledContent("Push delivery (APNs)") {
                        Text(svc.apnsRegistered ? "Registered" : "Not registered")
                            .foregroundStyle(svc.apnsRegistered ? .green : .orange)
                    }
                    LabeledContent("Community alerts") {
                        Text(svc.pushSubscriptionsCreated ? "On" : "Off")
                            .foregroundStyle(svc.pushSubscriptionsCreated ? .green : .orange)
                    }
                    Button {
                        Haptics.tap()
                        busyPush = true
                        Task {
                            await svc.forcePushReenable()
                            busyPush = false
                            pushTick += 1
                        }
                    } label: {
                        HStack {
                            if busyPush { ProgressView() }
                            Label("Re-enable community notifications", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(busyPush)
                    if let e = svc.pushSubsError {
                        Text("Subscription error: \(e)").font(.caption).foregroundStyle(.orange)
                    }
                    if !svc.apnsRegistered, let e = svc.apnsRegisterError {
                        Text("APNs error: \(e)").font(.caption).foregroundStyle(.orange)
                    }
                }
            } header: {
                Text("Push diagnostics")
            } footer: {
                Text("“Send test notification” fires a local alert in a few seconds — if it appears, notifications work on this device. Community push (friend requests, trip invites) also needs Push delivery = Registered and Community alerts = On. If APNs shows Not registered, the build lacks the push entitlement (enable Push Notifications on the App ID and ship a new build). If Community alerts stays Off, the CloudKit schema/indexes aren't deployed to this environment yet.")
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
                    ContentUnavailableView("No saved spots", systemImage: "mappin.slash",
                        description: Text("Save a spot to get bite-score alerts for it."))
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
        .sensoryFeedback(.selection, trigger: alertsEnabled)
        .sensoryFeedback(.selection, trigger: primeWindowAlerts)
        .sensoryFeedback(.selection, trigger: lowStockAlerts)
        .task {
            permissionStatus = await NotificationManager.shared.checkPermissionStatus()
            spots = (try? appState.spotRepository.fetchAll()) ?? []
            await loadScores()
            await reschedulePrimeWindows()
        }
    }

    private func reschedulePrimeWindows() async {
        guard primeWindowAlerts, permissionStatus == .authorized else { return }
        await NotificationManager.shared.schedulePrimeWindowAlerts(
            spots: spots, using: WeatherService.shared
        )
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
                    date: .now,
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
