import SwiftUI
import CoreLocation
import UserNotifications

struct AlertSettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("alertsEnabled") private var alertsEnabled = false
    @AppStorage("alertThreshold") private var alertThreshold = 75.0
    @AppStorage("primeWindowAlerts") private var primeWindowAlerts = false
    @AppStorage("lowStockAlerts") private var lowStockAlerts = true
    /// Read by `NotificationManager.scheduleColdStreakNudge`.
    @AppStorage("coldStreakNudges") private var coldStreakNudges = true
    @State private var titleShown = false

    @State private var permissionStatus: UNAuthorizationStatus = .notDetermined
    @State private var spots: [Spot] = []
    @State private var spotScores: [String: Int] = [:]
    @State private var isLoadingScores = false
    @State private var busyPush = false
    @State private var pushTick = 0   // forces the diagnostics rows to re-read

    private var svc: CommunityService { .shared }

    /// The test notification and push status rows. Built for tracking down
    /// delivery problems, not shown in the app.
    private static let showsDiagnostics = false

    /// Crew pushes need the phone registered and both subscription sets made.
    private var crewAlertsWorking: Bool {
        svc.apnsRegistered && svc.pushSubscriptionsCreated && svc.eventSubscriptionsSynced
    }

    private var allowed: Bool {
        switch permissionStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    private var permissionTitle: String {
        switch permissionStatus {
        case .authorized, .provisional, .ephemeral: return "Allowed for Currents"
        case .denied: return "Turned off for Currents"
        default: return "Not set up yet"
        }
    }

    private var permissionDetail: String {
        switch permissionStatus {
        case .authorized, .provisional, .ephemeral: return "Banners, sounds and the Lock Screen"
        case .denied: return "Turn notifications on in the Settings app to get alerts"
        default: return "Allow notifications to get bite alerts"
        }
    }

    private var aboveThreshold: Int {
        spotScores.values.filter { $0 >= Int(alertThreshold) }.count
    }

    var body: some View {
        List {
            Section {
                DetailHeader(title: "Notifications", subtitle: "Only what you turn on. No marketing, ever.")
                    .padding(.bottom, DS.Space.s2)
                    .pfBareRow()
                PFNotice(systemImage: allowed ? "bell.badge.fill" : "bell.slash.fill",
                         tint: allowed ? .dsScoreGood : .dsScoreLow,
                         title: permissionTitle, message: permissionDetail) {
                    if permissionStatus == .notDetermined {
                        Button("Allow") {
                            Task {
                                let granted = await NotificationManager.shared.requestPermission()
                                permissionStatus = granted ? .authorized : .denied
                            }
                        }
                        .buttonStyle(TonalButtonStyle(fullWidth: false))
                    } else if let url = URL(string: UIApplication.openSettingsURLString) {
                        Link("Change", destination: url)
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .pfBareRow()
            }

            Section {
                PFToggleRow(title: "Bite alerts", detail: "When a saved spot reaches your threshold",
                            systemImage: "fish.fill", color: .green, isOn: $alertsEnabled)
                PFToggleRow(title: "Prime window heads-up", detail: "About 45 minutes before the best window",
                            systemImage: "alarm.fill", color: .orange, isOn: $primeWindowAlerts)
                    .disabled(!allowed)
                    .onChange(of: primeWindowAlerts) { _, _ in
                        Task { await reschedulePrimeWindows() }
                    }
                PFToggleRow(title: "Slow bite nudge", detail: "After 45 minutes with no catch in a session",
                            systemImage: "timer", color: .cyan, isOn: $coldStreakNudges)
            } header: {
                Text("Bite")
            }
            .pfRows()

            Section {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    HStack {
                        Text("Tell me at")
                            .foregroundStyle(.dsText)
                        Text("\(Int(alertThreshold))")
                            .font(.body.weight(.semibold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(DS.scoreInk(Int(alertThreshold)))
                        Text("or more")
                            .foregroundStyle(.dsText)
                    }
                    Slider(value: $alertThreshold, in: 50...95, step: 5)
                        .accessibilityLabel("Alert threshold")
                        .accessibilityValue("\(Int(alertThreshold))")
                }
                .padding(.vertical, DS.Space.s1)
                .haptic(.selection, trigger: alertThreshold)
            } header: {
                Text("Alert threshold")
            } footer: {
                if spotScores.isEmpty {
                    Text("Lower values mean more alerts.")
                } else if aboveThreshold == 0 {
                    Text("None of your spots reach \(Int(alertThreshold)) right now. You will not be disturbed.")
                } else {
                    Text(aboveThreshold == 1
                         ? "1 of your spots is at \(Int(alertThreshold)) or more right now."
                         : "\(aboveThreshold) of your spots are at \(Int(alertThreshold)) or more right now.")
                }
            }
            .pfRows()

            Section {
                if spots.isEmpty {
                    ContentUnavailableView("No saved spots", systemImage: "mappin.slash",
                        description: Text("Save a spot to get bite alerts for it."))
                } else {
                    ForEach(spots) { spot in
                        spotRow(spot)
                    }
                }
            } header: {
                HStack {
                    Text("Your spots")
                    if isLoadingScores {
                        Spacer()
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .pfRows()

            Section {
                PFToggleRow(title: "Low tackle box stock", detail: "When an item drops to its reminder level",
                            systemImage: "shippingbox.fill", color: .orange, isOn: $lowStockAlerts)
            } header: {
                Text("Kit")
            } footer: {
                Text("Licence reminders start a month before expiry.")
            }
            .pfRows()

            if svc.joined {
                crewSection
            }

            if Self.showsDiagnostics {
                diagnostics
            }
        }
        .pfGroupedList()
        .detailTint(.red)
        .pfTrackScroll($titleShown)
        .pfScrollTitle("Notifications", shown: titleShown)
        .task {
            permissionStatus = await NotificationManager.shared.checkPermissionStatus()
            spots = (try? appState.spotRepository.fetchAll()) ?? []
            await loadScores()
            await reschedulePrimeWindows()
        }
    }

    // MARK: - Crew

    /// Friend requests and trip invites arrive by push. When that has stopped
    /// working, one button sets it up again.
    private var crewSection: some View {
        Section {
            HStack(spacing: 14) {
                PFIcon(systemImage: "person.2.fill", color: .blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Friend requests and invites")
                        .foregroundStyle(.dsText)
                    Text(crewAlertsWorking ? "On" : "Not arriving on this phone")
                        .font(.subheadline)
                        .foregroundStyle(crewAlertsWorking ? Color.dsText2 : Color.dsScoreLow)
                }
                Spacer(minLength: 8)
                if !crewAlertsWorking {
                    Button {
                        busyPush = true
                        Task {
                            await svc.forcePushReenable()
                            busyPush = false
                            pushTick += 1
                        }
                    } label: {
                        if busyPush {
                            ProgressView()
                        } else {
                            Text("Turn on")
                        }
                    }
                    .buttonStyle(TonalButtonStyle(fullWidth: false))
                    .disabled(busyPush || !allowed)
                }
            }
            .accessibilityElement(children: .contain)
        } header: {
            Text("Crew")
        }
        .pfRows()
        .id(pushTick)
    }

    // MARK: - Diagnostics

    private var diagnostics: some View {
        Section {
            Button {
                Haptics.tap()
                Task { await NotificationManager.shared.sendTestNotification() }
                ToastCenter.shared.show("Test notification on its way", style: .info, haptic: false)
            } label: {
                PFRowLabel(title: "Send a test notification", systemImage: "paperplane.fill", color: .indigo)
            }
            if svc.joined {
                LabeledContent("Push delivery") {
                    statusText(svc.apnsRegistered ? "Registered" : "Not registered", ok: svc.apnsRegistered)
                }
                LabeledContent("Crew alerts") {
                    statusText(svc.pushSubscriptionsCreated ? "On" : "Off", ok: svc.pushSubscriptionsCreated)
                }
                LabeledContent("Trip and crew events") {
                    statusText(svc.eventSubscriptionsSynced ? "On" : "Off", ok: svc.eventSubscriptionsSynced)
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
                        Text("Turn crew notifications on again")
                            .foregroundStyle(.tint)
                        Spacer()
                        if busyPush { ProgressView() }
                    }
                }
                .disabled(busyPush)
                if let e = svc.pushSubsError {
                    Text("Subscription error: \(e)").font(.footnote).foregroundStyle(.dsScoreLow)
                }
                if let e = svc.eventSubsError {
                    Text("Crew alerts error: \(e)").font(.footnote).foregroundStyle(.dsScoreLow)
                }
                if !svc.apnsRegistered, let e = svc.apnsRegisterError {
                    Text("Push error: \(e)").font(.footnote).foregroundStyle(.dsScoreLow)
                }
            }
        } header: {
            Text("Diagnostics")
        } footer: {
            Text(svc.joined
                 ? "Bite alerts are worked out and scheduled on your phone, so they arrive with no signal. Friend requests and trip invites also need push delivery registered and crew alerts on."
                 : "Bite alerts are worked out and scheduled on your phone, so they arrive with no signal. A test notification arrives in a few seconds.")
        }
        .pfRows()
        .id(pushTick)
    }

    private func statusText(_ text: String, ok: Bool) -> some View {
        Text(text).foregroundStyle(ok ? Color.dsScoreGood : Color.dsScoreLow)
    }

    private func reschedulePrimeWindows() async {
        guard primeWindowAlerts, permissionStatus == .authorized else { return }
        await NotificationManager.shared.schedulePrimeWindowAlerts(
            spots: spots, using: WeatherService.shared
        )
    }

    // MARK: - Spot row

    private func spotRow(_ spot: Spot) -> some View {
        let score = spotScores[spot.id]
        let below = (score ?? 0) < Int(alertThreshold)
        return HStack(spacing: 14) {
            ThumbView(systemImage: "mappin", tint: DS.accent, size: 40)
            Text(spot.name)
                .foregroundStyle(.dsText)
                .lineLimit(1)
            Spacer()
            if let score {
                Text("\(score)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(DS.scoreInk(score))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(DS.scoreColor(score).opacity(0.18), in: Capsule())
            } else if !isLoadingScores {
                Text("No data")
                    .font(.subheadline)
                    .foregroundStyle(.dsText3)
            }
        }
        .opacity(score != nil && below ? 0.55 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityValue(score.map { below ? "Score \($0), below your threshold" : "Score \($0)" } ?? "")
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
}
