import SwiftUI
import CoreLocation

/// The home screen: the three questions an angler actually has, answered in
/// one scroll — how good is it right now, when are the windows, and what
/// should I tie on. Everything denser than that lives one tap away.
struct TodayTab: View {
    @Environment(AppState.self) private var appState
    @AppStorage("use24HourTime") private var use24HourTime = true
    /// Angler's clarity call, remembered between sessions. Empty = infer it.
    @AppStorage("waterClarityOverride") private var clarityOverride = ""

    @State private var weather: WeatherService.WeatherData?
    @State private var forecast: ForecastEngine.ForecastResult?
    @State private var allSpecies: [Species] = []
    @State private var selectedSpecies: Species?
    @State private var ownedGear: [OwnedGear] = []
    @State private var history: [CatchDetail] = []
    @State private var isLoading = true
    @State private var showSpeciesPicker = false
    @State private var showFullForecast = false
    @State private var showAllLures = false
    @State private var showSettings = false

    private var coordinate: CLLocationCoordinate2D {
        appState.locationManager.currentLocation?.coordinate
            ?? CLLocationCoordinate2D(latitude: -33.9, longitude: 18.4)
    }

    private var clarity: WaterClarity {
        WaterClarity(rawValue: clarityOverride)
            ?? WaterClarity.inferred(precipMm: weather?.precipMm)
    }

    private var conditions: LureEngine.Conditions {
        LureEngine.Conditions(
            waterTempC: weather?.waterTempC,
            clarity: clarity,
            cloudCoverPct: weather?.cloudCoverPct,
            windSpeedKmh: weather?.windSpeedKmh,
            pressureChange6h: weather?.pressureChange6h
        )
    }

    private var suggestions: [LureEngine.Suggestion] {
        LureEngine.recommend(conditions: conditions, species: selectedSpecies,
                             ownedGear: ownedGear, history: history)
    }

    private var windows: [BiteWindows.Window] {
        BiteWindows.best(from: forecast?.hourlyScores ?? [])
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CurrentsTheme.paddingM) {
                    if let forecast {
                        scoreHero(forecast)
                    } else {
                        FishLoader(message: "Reading the bite…").frame(height: 120)
                    }
                    targetSpeciesRow
                    if !windows.isEmpty { bestWindowsCard }
                    whatToThrowCard
                    quickActions
                    fullForecastLink
                }
                .padding()
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .refreshable { await load(force: true) }
            .task {
                allSpecies = (try? appState.speciesRepository.fetchAll()) ?? []
                await load()
            }
            .sheet(isPresented: $showSpeciesPicker) {
                ForecastSpeciesPickerSheet(allSpecies: allSpecies,
                                           selectedSpecies: $selectedSpecies,
                                           onSelect: { recompute() })
            }
            .sheet(isPresented: $showFullForecast) { ForecastTab(presentedAsSheet: true) }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showAllLures) {
                WhatToThrowDetailView(suggestions: suggestions, clarity: clarity,
                                      species: selectedSpecies)
            }
        }
    }

    // MARK: - Bite score hero

    private func scoreHero(_ f: ForecastEngine.ForecastResult) -> some View {
        VStack(spacing: 6) {
            Text("\(f.score)")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundStyle(CurrentsTheme.scoreColor(f.score))
            Text(verdict(f.score)).font(.headline)
            if let reason = f.reasons.first {
                Text(reason).font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .glassCard()
    }

    private func verdict(_ s: Int) -> String {
        switch s {
        case 80...:   "Excellent — go now"
        case 65..<80: "Good conditions"
        case 50..<65: "Fair — work for them"
        default:      "Slow — finesse it"
        }
    }

    // MARK: - Target species

    private var targetSpeciesRow: some View {
        Button { showSpeciesPicker = true } label: {
            HStack {
                Label("Target", systemImage: "target").font(.subheadline)
                Spacer()
                Text(selectedSpecies?.commonName ?? "Any species")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(CurrentsTheme.accent)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .glassCard()
    }

    // MARK: - Best windows (BiteTime)

    private var bestWindowsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Best Windows Today", systemImage: "clock.badge.checkmark")
                .font(.headline)
            ForEach(windows) { w in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(w.label(use24Hour: use24HourTime))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                        if w.isNow() {
                            Text("NOW").font(.caption2.bold())
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(CurrentsTheme.scoreColor(w.peakScore).opacity(0.2),
                                            in: Capsule())
                        }
                        Spacer()
                        Text("\(w.peakScore)")
                            .font(.subheadline.bold())
                            .foregroundStyle(CurrentsTheme.scoreColor(w.peakScore))
                    }
                    Text(BiteWindows.guidance(forScore: w.peakScore))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .opacity(w.hasPassed() ? 0.45 : 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: - What to Throw

    private var whatToThrowCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("What to Throw", systemImage: "fish.fill").font(.headline)
                Spacer()
                Button("See all") { showAllLures = true }
                    .font(.caption).foregroundStyle(CurrentsTheme.accent)
            }

            // Clarity is the biggest lever on colour, and only the angler can
            // actually see it — so it's a first-class control, pre-filled.
            VStack(alignment: .leading, spacing: 4) {
                Text("Water clarity").font(.caption).foregroundStyle(.secondary)
                Picker("Water clarity", selection: Binding(
                    get: { clarity },
                    set: { clarityOverride = $0.rawValue }
                )) {
                    ForEach(WaterClarity.allCases) { c in Text(c.label).tag(c) }
                }
                .pickerStyle(.segmented)
            }

            if isLoading {
                FishLoader(message: "Matching conditions…").frame(height: 80)
            } else {
                ForEach(suggestions.prefix(3)) { s in
                    LureRow(suggestion: s)
                    if s.id != suggestions.prefix(3).last?.id { Divider() }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: - Actions

    private var quickActions: some View {
        HStack(spacing: 10) {
            if appState.tripTracker.isTracking {
                Button {
                    _ = appState.tripTracker.end()
                } label: {
                    Label("End Session", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(.red)
            } else {
                Button {
                    _ = appState.tripTracker.start(name: SessionFormat.defaultName(), spotId: nil)
                } label: {
                    Label("Start Session", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            Button {
                appState.siriRequestedLogCatch = true
            } label: {
                Label("Log Catch", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private var fullForecastLink: some View {
        Button { showFullForecast = true } label: {
            HStack {
                Label("Full forecast, tides & solunar", systemImage: "chart.xyaxis.line")
                    .font(.subheadline)
                Spacer()
                Image(systemName: "chevron.right").font(.caption)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .glassCard()
    }

    // MARK: - Data

    private func load(force: Bool = false) async {
        isLoading = true
        ownedGear = (try? appState.ownedGearRepository.fetchAll()) ?? []
        history = (try? appState.catchRepository.fetchAll(limit: 200)) ?? []
        weather = await WeatherService.shared.current(for: coordinate, force: force)
        recompute()
        isLoading = false
    }

    private func recompute() {
        let f = ForecastEngine.forecast(
            coordinate: coordinate,
            currentPressureHpa: weather?.pressureHpa,
            pressureChange6h: weather?.pressureChange6h,
            waterTempC: weather?.waterTempC,
            windSpeedKmh: weather?.windSpeedKmh,
            windDirection: weather?.windDirectionDeg,
            species: selectedSpecies,
            isInSpawningZone: false
        )
        forecast = f
        WidgetSnapshotWriter.writeBite(
            score: f.score, verdict: verdict(f.score), location: "",
            hourly: WidgetSnapshotWriter.hourlyEntries(from: f.hourlyScores))
    }
}

// MARK: - One recommendation

struct LureRow: View {
    let suggestion: LureEngine.Suggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(suggestion.lure).font(.subheadline.weight(.semibold))
                if suggestion.isOwned {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption2).foregroundStyle(.green)
                }
                Spacer()
                confidenceBar
            }
            Text(suggestion.color)
                .font(.caption.weight(.medium))
                .foregroundStyle(CurrentsTheme.accent)
            Text(suggestion.technique).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                chip(suggestion.depth, icon: "arrow.down.to.line")
                ForEach(suggestion.reasons.prefix(2), id: \.self) { chip($0, icon: nil) }
            }
        }
        .padding(.vertical, 2)
    }

    private var confidenceBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.gray.opacity(0.25))
                Capsule()
                    .fill(CurrentsTheme.scoreColor(Int(suggestion.score * 100)))
                    .frame(width: geo.size.width * suggestion.score)
            }
        }
        .frame(width: 44, height: 5)
    }

    private func chip(_ text: String, icon: String?) -> some View {
        HStack(spacing: 3) {
            if let icon { Image(systemName: icon).font(.system(size: 8)) }
            Text(text).font(.caption2)
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(.gray.opacity(0.15), in: Capsule())
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

// MARK: - Full list

struct WhatToThrowDetailView: View {
    let suggestions: [LureEngine.Suggestion]
    let clarity: WaterClarity
    let species: Species?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(suggestions) { s in
                        VStack(alignment: .leading, spacing: 6) {
                            LureRow(suggestion: s)
                            if s.personalCatches > 0 {
                                Label("\(s.personalCatches) of your catches came on this",
                                      systemImage: "chart.line.uptrend.xyaxis")
                                    .font(.caption2).foregroundStyle(.green)
                            }
                            if let owned = s.ownedName {
                                Label(owned, systemImage: "shippingbox")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("\(clarity.label) water · \(clarity.detail)")
                } footer: {
                    Text("Ranked for current water temperature, clarity, light, wind and pressure\(species.map { ", targeting \($0.commonName)" } ?? ""). Lures you own rank first.")
                }

                Section("Colours for \(clarity.label.lowercased()) water") {
                    ForEach(LureEngine.colors(for: clarity, lowLight: false), id: \.self) {
                        Text($0).font(.subheadline)
                    }
                }
            }
            .navigationTitle("What to Throw")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
