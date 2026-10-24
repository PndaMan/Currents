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
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var permissionStatus: UNAuthorizationStatus = .notDetermined
    @State private var spots: [Spot] = []
    @State private var spotAlerts: [String: SpotAlert] = [:]
    @State private var spotScores: [String: Int] = [:]
    @State private var isLoadingScores = false
    @State private var busyPush = false
    @State private var pushTick = 0   // forces the diagnostics rows to re-read
    /// TestFlight or Xcode: shows the alert preview, which App Store users never see.
    @State private var isTestBuild = false

    private var svc: CommunityService { .shared }

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

    var body: some View {
        TodayPage("Notifications", subtitle: "Only what you turn on.") {
            permissionNotice
            CardSection("Bite") {
                CardToggleRow("Bite window opens", subtitle: "A saved spot reaches your score",
                              systemImage: "fish.fill", tint: .blue, isOn: $alertsEnabled)
                    .onChange(of: alertsEnabled) { _, on in alertTypeChanged(on) }
                CardToggleRow("Heads-up", subtitle: "45 minutes before that window",
                              systemImage: "alarm.fill", tint: .orange, isOn: $primeWindowAlerts)
                    .onChange(of: primeWindowAlerts) { _, on in alertTypeChanged(on) }
                CardToggleRow("Slow bite nudge", subtitle: "45 minutes in a session with no catch",
                              systemImage: "timer", tint: .cyan, isOn: $coldStreakNudges)
            }
            thresholdSection
            spotsSection
            CardSection("Kit", note: "Licence reminders start a month before expiry.") {
                CardToggleRow("Low tackle box stock", subtitle: "An item hits its reminder level",
                              systemImage: "shippingbox.fill", tint: .orange, isOn: $lowStockAlerts)
            }
            if svc.joined {
                crewSection
            }
            if isTestBuild {
                diagnostics
            }
        }
        .task {
            isTestBuild = await BuildChannel.isTesting()
            permissionStatus = await NotificationManager.shared.checkPermissionStatus()
            spots = (try? appState.spotRepository.fetchAll()) ?? []
            spotAlerts = (try? appState.spotRepository.alerts()) ?? [:]
            await loadScores()
        }
        .onAppear {
            // Back from a spot's page with changed choices.
            spotAlerts = (try? appState.spotRepository.alerts()) ?? [:]
        }
    }

    // MARK: - Crew

    /// Friend requests and trip invites arrive by push. When that has stopped
    /// working, one button sets it up again.
    private var crewSection: some View {
        CardSection("Crew") {
            HStack(spacing: 14) {
                TintIcon(systemImage: "person.2.fill", tint: .blue)
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
            .padding(.horizontal, DS.Space.s4)
            .padding(.vertical, 10)
            .accessibilityElement(children: .contain)
        }
        .id(pushTick)
    }

    // MARK: - Sections

    private var permissionNotice: some View {
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
                    .foregroundStyle(DS.ink(DS.accent))
            }
        }
    }

    /// The default score as a big number with its ring, then the slider.
    private var thresholdSection: some View {
        CardSection("Default score", note: "Each spot can set its own.") {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                HStack(spacing: 14) {
                    ScoreRing(score: Int(alertThreshold), size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Alert at \(Int(alertThreshold)) or more")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.dsText)
                            .contentTransition(.numericText())
                        Text("Lower means more alerts")
                            .font(.subheadline)
                            .foregroundStyle(.dsText2)
                    }
                }
                Slider(value: $alertThreshold, in: 50...95, step: 5, onEditingChanged: { editing in
                    if !editing { Task { await reschedule() } }
                })
                .accessibilityLabel("Alert threshold")
                .accessibilityValue("\(Int(alertThreshold))")
            }
            .padding(DS.Space.s4)
            .haptic(.selection, trigger: alertThreshold)
        }
    }

    private var spotsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Spots", detail: spots.isEmpty ? nil : "\(spots.count)")
                .overlay(alignment: .trailing) {
                    if isLoadingScores {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, DS.gutter)
                            .padding(.bottom, DS.Space.s2)
                    }
                }
            if spots.isEmpty {
                InlineEmpty(systemImage: "mappin.slash", text: "Save a spot to get bite alerts for it.")
            } else {
                CardGroup(separatorInset: 74) {
                    ForEach(spots) { spot in
                        NavigationLink {
                            SpotAlertsView(spot: spot)
                        } label: {
                            spotRow(spot)
                        }
                        .buttonStyle(.dsCardRow)
                    }
                }
            }
        }
    }

    // MARK: - Testing

    /// TestFlight and Xcode only: the test sends, and why crew alerts aren't
    /// arriving when they aren't.
    private var diagnostics: some View {
        CardSection("Testing", note: "Only shows in TestFlight builds.") {
            Button {
                Haptics.tap()
                Task { await NotificationManager.shared.sendTestNotification() }
                ToastCenter.shared.show("Test notification on its way", style: .info, haptic: false)
            } label: {
                CardRow("Send a test notification", systemImage: "paperplane.fill", tint: .indigo)
            }
            .buttonStyle(.dsCardRow)
            Button {
                Haptics.tap()
                Task { await NotificationManager.shared.sendEveryAlertPreview(spotName: spots.first?.name) }
                ToastCenter.shared.show("Eight sample alerts over the next 40 seconds. Lock your phone to see them.",
                                        style: .info, haptic: false)
            } label: {
                CardRow("Preview every alert", subtitle: "Eight samples, 5 seconds apart",
                        systemImage: "bell.badge.fill", tint: .orange)
            }
            .buttonStyle(.dsCardRow)
            if svc.joined {
                CardRow("Push delivery",
                        subtitle: svc.apnsRegistered ? nil : (svc.apnsRegisterError ?? "No answer from Apple yet"),
                        systemImage: "antenna.radiowaves.left.and.right", tint: .blue,
                        value: svc.apnsRegistered ? "Registered" : "Not registered",
                        valueTint: svc.apnsRegistered ? .dsScoreGood : .dsScoreLow)
                CardRow("Friend requests and invites",
                        subtitle: svc.pushSubscriptionsCreated ? nil : (svc.pushSubsError ?? "Not set up yet"),
                        systemImage: "person.2.fill", tint: .teal,
                        value: svc.pushSubscriptionsCreated ? "On" : "Off",
                        valueTint: svc.pushSubscriptionsCreated ? .dsScoreGood : .dsScoreLow)
                CardRow("Crew posts and trips",
                        subtitle: svc.eventSubscriptionsSynced ? nil : (svc.eventSubsError ?? "Not set up yet"),
                        systemImage: "figure.fishing", tint: .green,
                        value: svc.eventSubscriptionsSynced ? "On" : "Off",
                        valueTint: svc.eventSubscriptionsSynced ? .dsScoreGood : .dsScoreLow)
            }
        }
        .id(pushTick)
    }

    private func reschedule() async {
        await BackgroundRefresh.rescheduleAlerts(appState: appState)
    }

    /// Turning an alert type on asks for permission the first time, then
    /// plans the alerts. Turning one off clears what it had scheduled.
    private func alertTypeChanged(_ on: Bool) {
        Task {
            if on, permissionStatus == .notDetermined {
                let granted = await NotificationManager.shared.requestPermission()
                permissionStatus = granted ? .authorized : .denied
            }
            await reschedule()
        }
    }

    // MARK: - Spot row

    private func spotRow(_ spot: Spot) -> some View {
        let choice = spotAlerts[spot.id] ?? .defaults(for: spot.id)
        let threshold = choice.threshold ?? Int(alertThreshold)
        return HStack(spacing: 14) {
            PlaceSnapshotThumb(spot: spot, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(spot.name)
                    .foregroundStyle(.dsText)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 2)
                Text(rowStatus(choice, threshold: threshold, score: spotScores[spot.id]))
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                    .lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
            }
            Spacer(minLength: 8)
            // The subtitle says "now 77", so the ring reads as the score now
            // and not as the alert threshold. A spot that sends nothing
            // shows no score.
            if let score = spotScores[spot.id], Self.sends(choice, bite: alertsEnabled, headsUp: primeWindowAlerts) {
                ScoreRing(score: score, size: 36)
                    .accessibilityHidden(true)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.dsText3)
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// The second line of a spot row: what that spot will send, with the
    /// score now. A type switched off above sends nothing at any spot, as
    /// `NotificationManager.rescheduleBiteAlerts` plans it.
    private func rowStatus(_ choice: SpotAlert, threshold: Int, score: Int?) -> String {
        let status = Self.status(choice, threshold: threshold, bite: alertsEnabled, headsUp: primeWindowAlerts)
        guard let score, Self.sends(choice, bite: alertsEnabled, headsUp: primeWindowAlerts) else { return status }
        return "\(status), now \(score)"
    }

    /// True when the spot will send something.
    private static func sends(_ choice: SpotAlert, bite: Bool, headsUp: Bool) -> Bool {
        (bite && choice.biteAlerts) || (headsUp && choice.headsUp)
    }

    private static func status(_ choice: SpotAlert, threshold: Int, bite: Bool, headsUp: Bool) -> String {
        switch (bite && choice.biteAlerts, headsUp && choice.headsUp) {
        case (false, false): return "Off"
        case (false, true): return "Heads-up only, at \(threshold) or more"
        case (true, false): return "Window opens only, at \(threshold) or more"
        case (true, true): return "At \(threshold) or more"
        }
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
                    waterTempC: weather.measured?.waterTempC,
                    windSpeedKmh: weather.measured?.windSpeedKmh,
                    windDirection: weather.measured?.windDirectionDeg,
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
