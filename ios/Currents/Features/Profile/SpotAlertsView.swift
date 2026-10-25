import SwiftUI
import CoreLocation
import UserNotifications

/// Notification choices for one saved spot, like an app's page in the
/// Settings app's notifications: the spot's own switch, then what it
/// notifies about and the score a window must reach, then the windows that
/// will alert over the next days. New spots start switched off, and while a
/// spot is off only its switch shows. Pushed from the spot rows on the
/// Notifications page and from a saved spot's place page.
struct SpotAlertsView: View {
    let spot: Spot
    @Environment(AppState.self) private var appState
    @AppStorage("alertsEnabled") private var alertsEnabled = false
    @AppStorage("primeWindowAlerts") private var primeWindowAlerts = false
    @AppStorage("alertThreshold") private var defaultThreshold = 75.0
    @AppStorage("targetSpeciesId") private var targetSpeciesId: Int = 0
    @AppStorage("use24HourTime") private var use24 = true
    /// A window card's width, growing with the text size.
    @ScaledMetric(relativeTo: .footnote) private var windowCardWidth: CGFloat = 112

    @State private var choice: SpotAlert
    /// What is stored, so loading it is not mistaken for a change to save.
    /// Nil until loaded, and the page shows no choices until then.
    @State private var stored: SpotAlert?
    @State private var permission: UNAuthorizationStatus = .notDetermined
    @State private var windows: [BiteWindows.Upcoming] = []
    @State private var loadingWindows = true
    /// No weather was ever fetched here and the phone is offline, so no
    /// alerts are planned until there is signal.
    @State private var noWeather = false

    private static let thresholds = Array(stride(from: 50, through: 95, by: 5))

    init(spot: Spot) {
        self.spot = spot
        _choice = State(initialValue: .off(for: spot.id))
    }

    /// The two things a spot notifies about. Each is also switched on or off
    /// for every spot on the Notifications page.
    private enum Kind {
        case windowOpens, headsUp
    }

    private var threshold: Int { choice.threshold ?? Int(defaultThreshold) }

    private func onForAllSpots(_ kind: Kind) -> Bool {
        kind == .windowOpens ? alertsEnabled : primeWindowAlerts
    }

    /// True when this spot will send something, as
    /// `NotificationManager.rescheduleBiteAlerts` plans it.
    private var sends: Bool {
        choice.enabled && ((alertsEnabled && choice.biteAlerts) || (primeWindowAlerts && choice.headsUp))
    }

    private var alerting: [BiteWindows.Upcoming] {
        windows.filter { $0.peakScore >= threshold && $0.end > .now }
    }

    var body: some View {
        TodayPage(spot.name, subtitle: "Spot notifications") {
            if stored != nil {
                CardSection(note: choice.enabled ? nil : "Get a notification when a bite window opens here.") {
                    CardToggleRow("Alerts for this spot", subtitle: switchSummary,
                                  systemImage: "bell.fill", tint: .red, isOn: enabledBinding)
                }
                if choice.enabled {
                    permissionNotice
                    notifyWhenSection
                    if sends {
                        upcomingSection
                    }
                }
            }
        }
        .task { await load() }
        .onChange(of: choice) { _, newValue in
            guard let stored, newValue != stored else { return }
            save(newValue)
        }
    }

    /// The switch row's second line: what this spot sends.
    private var switchSummary: String {
        if !choice.enabled { return "Off" }
        if !sends { return "Nothing turned on below" }
        return "At \(threshold) or more"
    }

    /// The spot's switch. Turning it on asks for permission the first time,
    /// as the switches on the Notifications page do.
    private var enabledBinding: Binding<Bool> {
        Binding {
            choice.enabled
        } set: { on in
            withAnimation(DS.Motion.softSpring) { choice.enabled = on }
            if on, permission == .notDetermined {
                Task {
                    await askPermission()
                    await reschedule()
                }
            }
        }
    }

    // MARK: - Permission

    /// Why nothing will arrive on this phone, with the way to fix it.
    @ViewBuilder
    private var permissionNotice: some View {
        switch permission {
        case .authorized, .provisional, .ephemeral:
            EmptyView()
        case .denied:
            PFNotice(systemImage: "bell.slash.fill", tint: .dsScoreLow,
                     title: "Turned off for Currents",
                     message: "Turn notifications on in the Settings app to get alerts") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Link("Change", destination: url)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.ink(DS.accent))
                }
            }
        default:
            PFNotice(systemImage: "bell.badge.fill", tint: .dsScoreLow,
                     title: "Not set up yet", message: "Allow notifications to get bite alerts") {
                Button("Allow") {
                    Task {
                        await askPermission()
                        await reschedule()
                    }
                }
                .buttonStyle(TonalButtonStyle(fullWidth: false))
            }
        }
    }

    // MARK: - Notify when

    private var notifyWhenSection: some View {
        CardSection("Notify when",
                    note: choice.biteAlerts || choice.headsUp ? nil : "Turn one on to get alerts here.") {
            kindRow(.windowOpens)
            kindRow(.headsUp)
            scoreRow
        }
    }

    /// A switch for this spot, or, while that kind is off for every spot, a
    /// button that turns it on, so the row never shows a switch that does
    /// nothing.
    @ViewBuilder
    private func kindRow(_ kind: Kind) -> some View {
        let title = kind == .windowOpens ? "A bite window opens" : "45 minutes before"
        let systemImage = kind == .windowOpens ? "fish.fill" : "alarm.fill"
        let tint: Color = kind == .windowOpens ? .blue : .orange
        if onForAllSpots(kind) {
            CardToggleRow(title,
                          subtitle: kind == .windowOpens ? "Right as it starts" : "Time to get to the water",
                          systemImage: systemImage, tint: tint,
                          isOn: kind == .windowOpens ? $choice.biteAlerts : $choice.headsUp)
        } else {
            CardRow(title, subtitle: "Off for all spots", systemImage: systemImage, tint: tint,
                    combinesChildren: false) {
                Button("Turn on") { turnOnForAllSpots(kind) }
                    .buttonStyle(TonalButtonStyle(fullWidth: false))
            }
        }
    }

    /// The score a window must reach here, from a menu like the log form's
    /// rows. Default follows the score on the Notifications page.
    private var scoreRow: some View {
        Menu {
            Picker("Score to reach", selection: $choice.threshold.haptic()) {
                Text("Default (\(Int(defaultThreshold)))").tag(Int?.none)
                ForEach(Self.thresholds, id: \.self) { value in
                    Text("\(value) or more").tag(Int?.some(value))
                }
            }
        } label: {
            CardRow("Score to reach", subtitle: choice.threshold == nil ? "Your default" : nil,
                    systemImage: "gauge.with.dots.needle.67percent", tint: DS.scoreColor(threshold)) {
                MenuValue(text: "\(threshold) or more")
            }
        }
        .buttonStyle(.dsCardRow)
    }

    /// Turns a kind on for every spot, as its switch on the Notifications
    /// page does, and on for this spot. Asks for permission the first time.
    private func turnOnForAllSpots(_ kind: Kind) {
        Haptics.tap()
        withAnimation(DS.Motion.softSpring) {
            switch kind {
            case .windowOpens:
                alertsEnabled = true
                choice.biteAlerts = true
            case .headsUp:
                primeWindowAlerts = true
                choice.headsUp = true
            }
        }
        Task {
            if permission == .notDetermined { await askPermission() }
            await reschedule()
        }
    }

    // MARK: - Upcoming

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Next three days", detail: alerting.isEmpty ? nil : "\(alerting.count)")
            if loadingWindows {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
            } else if noWeather {
                InlineEmpty(systemImage: "wifi.slash", text: "No weather offline. Alerts are planned once there is signal.")
            } else if alerting.isEmpty {
                InlineEmpty(systemImage: "moon.zzz", text: "No window reaches \(threshold) in the next three days.")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(alerting, id: \.start) { window in
                            windowCard(window)
                        }
                    }
                    .padding(.horizontal, DS.gutter)
                }
            }
        }
    }

    /// A window as Today's day card: day, peak score ring, start and end.
    private func windowCard(_ window: BiteWindows.Upcoming) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Self.dayName(window.start))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.dsText)
                .lineLimit(1)
            ScoreRing(score: window.peakScore, size: 52)
            Text(span(window))
                .font(.footnote)
                .foregroundStyle(.dsText2)
                .monospacedDigit()
                .lineLimit(2)
        }
        .frame(width: windowCardWidth, alignment: .leading)
        .padding(14)
        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Self.dayName(window.start)), up to \(window.peakScore)")
    }

    private func span(_ window: BiteWindows.Upcoming) -> String {
        let start = ForecastFormat.time(window.start, use24: use24)
        let end = ForecastFormat.time(window.end, use24: use24)
        return "\(start) to \(end)"
    }

    private static func dayName(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.wide))
    }

    // MARK: - Data

    private func load() async {
        // Permission first, so an allowed phone never flashes the notice.
        permission = await NotificationManager.shared.checkPermissionStatus()
        let saved = (try? appState.spotRepository.alert(for: spot.id)) ?? .defaults(for: spot.id)
        stored = saved
        choice = saved
        let coordinate = CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude)
        let current = await WeatherService.shared.current(for: coordinate)
        let outlook = await WeatherService.shared.forecastDays(for: coordinate)
        let species = targetSpeciesId > 0
            ? try? appState.speciesRepository.fetch(id: Int64(targetSpeciesId))
            : nil
        // Bite alerts skip an offline estimate, so the windows here do too.
        noWeather = current?.isEstimated == true
        windows = noWeather ? [] : BiteWindows.upcoming(coordinate: coordinate, current: current, outlook: outlook,
                                                        species: species, days: 3)
        loadingWindows = false
    }

    private func save(_ newValue: SpotAlert) {
        do {
            try appState.spotRepository.saveAlert(newValue)
            stored = newValue
        } catch {
            ToastCenter.shared.show("Couldn't save the change", style: .error)
            if let stored { choice = stored }
            return
        }
        Task { await reschedule() }
    }

    private func askPermission() async {
        let granted = await NotificationManager.shared.requestPermission()
        permission = granted ? .authorized : .denied
    }

    private func reschedule() async {
        await BackgroundRefresh.rescheduleAlerts(appState: appState)
    }
}
