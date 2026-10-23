import SwiftUI
import CoreLocation

/// Notification choices for one saved spot, like a location's page in the
/// Weather app's notification settings: which alerts it sends, the score a
/// window must reach, and the windows that will alert over the next days.
/// Pushed from the spot rows on the Notifications page.
struct SpotAlertsView: View {
    let spot: Spot
    @Environment(AppState.self) private var appState
    @AppStorage("alertsEnabled") private var alertsEnabled = false
    @AppStorage("primeWindowAlerts") private var primeWindowAlerts = false
    @AppStorage("alertThreshold") private var defaultThreshold = 75.0
    @AppStorage("targetSpeciesId") private var targetSpeciesId: Int = 0

    @State private var choice: SpotAlert
    /// What is stored, so loading it is not mistaken for a change to save.
    @State private var stored: SpotAlert?
    @State private var windows: [BiteWindows.Upcoming] = []
    @State private var loadingWindows = true
    @State private var titleShown = false

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
        List {
            Section {
                DetailHeader(over: "Notifications", title: spot.name)
                    .padding(.bottom, DS.Space.s2)
                    .pfBareRow()
            }

            Section {
                PFToggleRow(title: "Bite window opens", detail: "When a window reaching the score starts",
                            systemImage: "fish.fill", color: .green, isOn: $choice.biteAlerts)
                PFToggleRow(title: "Heads-up", detail: "About 45 minutes before the window",
                            systemImage: "alarm.fill", color: .orange, isOn: $choice.headsUp)
            } header: {
                Text("Alerts")
            } footer: {
                if let note = offNote { Text(note) }
            }
            .pfRows()

            Section {
                Picker("Alert at", selection: $choice.threshold.haptic()) {
                    Text("Default (\(Int(defaultThreshold)))").tag(Int?.none)
                    ForEach(Self.thresholds, id: \.self) { value in
                        Text("\(value) or more").tag(Int?.some(value))
                    }
                }
            } header: {
                Text("Score")
            } footer: {
                Text("The default is set on the Notifications page.")
            }
            .pfRows()

            upcomingSection
        }
        .pfGroupedList()
        .detailTint(.red)
        .pfTrackScroll($titleShown)
        .pfScrollTitle(spot.name, shown: titleShown)
        .task { await load() }
        .onChange(of: choice) { _, newValue in
            guard let stored, newValue != stored else { return }
            save(newValue)
        }
    }

    /// Why nothing will arrive even though this spot is on.
    private var offNote: String? {
        if !alertsEnabled && !primeWindowAlerts {
            return "Bite alerts are off for every spot. Turn them on on the Notifications page."
        }
        if choice.biteAlerts && !alertsEnabled {
            return "Bite window alerts are off for every spot on the Notifications page."
        }
        if choice.headsUp && !primeWindowAlerts {
            return "Heads-ups are off for every spot on the Notifications page."
        }
        return nil
    }

    // MARK: - Upcoming

    private var upcomingSection: some View {
        Section {
            if loadingWindows {
                HStack {
                    Text("Working out the next windows")
                        .foregroundStyle(.dsText2)
                    Spacer()
                    ProgressView()
                }
            } else if alerting.isEmpty {
                Text("No window reaches \(threshold) in the next three days.")
                    .foregroundStyle(.dsText2)
            } else {
                ForEach(alerting, id: \.start) { window in
                    windowRow(window)
                }
            }
        } header: {
            Text("Next three days")
        } footer: {
            Text("Worked out from the latest weather. Alerts move if the forecast changes.")
        }
        .pfRows()
    }

    private func windowRow(_ window: BiteWindows.Upcoming) -> some View {
        LabeledContent {
            Text("Up to \(window.peakScore)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(DS.scoreInk(window.peakScore))
        } label: {
            Text(Self.dayName(window.start))
                .foregroundStyle(.dsText)
            Text("\(window.start.formatted(date: .omitted, time: .shortened)) to \(window.end.formatted(date: .omitted, time: .shortened))")
                .foregroundStyle(.dsText2)
        }
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
        windows = BiteWindows.upcoming(coordinate: coordinate, current: current, outlook: outlook,
                                       species: species, days: 3)
        loadingWindows = false
    }

    private func save(_ newValue: SpotAlert) {
        stored = newValue
        try? appState.spotRepository.saveAlert(newValue)
        Task { await BackgroundRefresh.rescheduleAlerts(appState: appState) }
    }
}
