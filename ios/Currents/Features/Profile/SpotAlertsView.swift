import SwiftUI
import CoreLocation

/// Notification choices for one saved spot, like a location's page in the
/// Weather app's notification settings: which alerts it sends, the score a
/// window must reach, and the windows that will alert over the next days.
/// Pushed from the spot rows on the Notifications page and from a saved
/// spot's place page.
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
    @State private var stored: SpotAlert?
    @State private var windows: [BiteWindows.Upcoming] = []
    @State private var loadingWindows = true
    /// No weather was ever fetched here and the phone is offline, so no
    /// alerts are planned until there is signal.
    @State private var noWeather = false

    private static let thresholds = Array(stride(from: 50, through: 95, by: 5))

    init(spot: Spot) {
        self.spot = spot
        _choice = State(initialValue: .defaults(for: spot.id))
    }

    private var threshold: Int { choice.threshold ?? Int(defaultThreshold) }

    private var alerting: [BiteWindows.Upcoming] {
        windows.filter { $0.peakScore >= threshold && $0.end > .now }
    }

    var body: some View {
        TodayPage(spot.name, subtitle: "Spot notifications") {
            CardSection("Alerts", note: offNote) {
                CardToggleRow("Bite window opens", subtitle: "A window reaches the score",
                              systemImage: "fish.fill", tint: .blue, isOn: $choice.biteAlerts)
                CardToggleRow("Heads-up", subtitle: "45 minutes before the window",
                              systemImage: "alarm.fill", tint: .orange, isOn: $choice.headsUp)
            }
            CardSection("Score") {
                CardRow("Alert at", systemImage: "gauge.with.dots.needle.67percent",
                        tint: DS.scoreColor(threshold), combinesChildren: false) {
                    Picker("Alert at", selection: $choice.threshold.haptic()) {
                        Text("Default (\(Int(defaultThreshold)))").tag(Int?.none)
                        ForEach(Self.thresholds, id: \.self) { value in
                            Text("\(value) or more").tag(Int?.some(value))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }
            upcomingSection
        }
        .task { await load() }
        .onChange(of: choice) { _, newValue in
            guard let stored, newValue != stored else { return }
            save(newValue)
        }
    }

    /// Why nothing will arrive even though this spot is on.
    private var offNote: String? {
        if !alertsEnabled && !primeWindowAlerts {
            return "Bite alerts are off on the Notifications page."
        }
        if choice.biteAlerts && !alertsEnabled {
            return "Window alerts are off on the Notifications page."
        }
        if choice.headsUp && !primeWindowAlerts {
            return "Heads-ups are off on the Notifications page."
        }
        return nil
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
        stored = newValue
        try? appState.spotRepository.saveAlert(newValue)
        Task { await BackgroundRefresh.rescheduleAlerts(appState: appState) }
    }
}
