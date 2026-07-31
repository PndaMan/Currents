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
    /// Hour tapped on the day timeline; nil shows the window list instead.
    @State private var selectedHour: Int?

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
            // Same ring as the tapped-hour card, so the two read as one idea.
            ScoreRing(score: f.score, size: 116, caption: "bite score")
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

            // The whole day at a glance: one bar per hour, coloured by score,
            // with a marker on now. Reading the shape is faster than reading
            // three time ranges. Tapping an hour swaps the window list below
            // for that hour's detail; tapping it again puts the list back.
            DayTimeline(hourly: forecast?.hourlyScores ?? [], selected: $selectedHour)

            if let hour = selectedHour, let point = hourPoint(hour) {
                hourDetail(hour: hour, score: point)
            } else {
                windowList
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func hourPoint(_ hour: Int) -> Int? {
        forecast?.hourlyScores.first { $0.hour == hour }?.score
    }

    /// Replaces the window list while an hour is selected. Built for this
    /// card rather than borrowed from the full forecast's hourly drill-down:
    /// a ring you can read at arm's length, the change against right now, and
    /// what to actually do in that hour.
    private func hourDetail(hour: Int, score: Int) -> some View {
        let nowScore = hourPoint(Calendar.current.component(.hour, from: .now))
        let delta = nowScore.map { score - $0 }

        return HStack(alignment: .top, spacing: 14) {
            ScoreRing(score: score, size: 62)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(BiteWindows.Window(startHour: hour, endHour: hour, peakScore: score)
                        .label(use24Hour: use24HourTime))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    if let delta, delta != 0 {
                        Label("\(abs(delta))", systemImage: delta > 0 ? "arrow.up" : "arrow.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(delta > 0 ? .green : .orange)
                            .labelStyle(.titleAndIcon)
                        Text("vs now").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                Text(BiteWindows.guidance(forScore: score))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    withAnimation(.snappy(duration: 0.2)) { selectedHour = nil }
                } label: {
                    Label("Back to windows", systemImage: "chevron.left")
                        .font(.caption2.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(CurrentsTheme.accent)
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var windowList: some View {
        VStack(alignment: .leading, spacing: 10) {
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
        .transition(.opacity)
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
            // actually see it — so it's a first-class control, pre-filled from
            // recent rainfall and shown as water rather than words.
            ClarityPicker(selection: Binding(
                get: { clarity },
                set: { if let new = $0 { clarityOverride = new.rawValue } }
            ))

            if isLoading {
                FishLoader(message: "Matching conditions…").frame(height: 80)
            } else {
                let top = Array(suggestions.prefix(3))
                ForEach(Array(top.enumerated()), id: \.element.id) { index, s in
                    LureRow(suggestion: s, rank: index + 1)
                    if index < top.count - 1 { Divider() }
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
    /// 1-based position, shown as a rank badge so the ordering is explicit
    /// rather than implied by a bar you have to squint at.
    var rank: Int? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let rank { rankBadge(rank) }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(suggestion.lure).font(.subheadline.weight(.semibold))
                    if suggestion.isOwned {
                        Text("HAVE IT")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(.green.opacity(0.18), in: Capsule())
                            .foregroundStyle(.green)
                    }
                    Spacer(minLength: 0)
                }

                // The colour shown as the colour — "Chartreuse / White" is
                // meaningless at a glance, two stripes of it are not.
                HStack(spacing: 6) {
                    LureColorSwatch(name: suggestion.color)
                    Text(suggestion.color)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                }

                Text(suggestion.technique)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                FlowChips(items: [suggestion.depth] + suggestion.reasons.prefix(2))
            }
        }
        .padding(.vertical, 4)
    }

    private func rankBadge(_ n: Int) -> some View {
        Text("\(n)")
            .font(.caption.bold())
            .monospacedDigit()
            .frame(width: 22, height: 22)
            .background(CurrentsTheme.scoreColor(Int(suggestion.score * 100)).opacity(0.18),
                        in: Circle())
            .foregroundStyle(CurrentsTheme.scoreColor(Int(suggestion.score * 100)))
    }
}

/// The day's bite as 24 bars. Height and colour both carry the score so it
/// reads at a glance in sunlight, with a marker on the current hour.
struct DayTimeline: View {
    let hourly: [(hour: Int, score: Int)]
    @Binding var selected: Int?

    private var currentHour: Int { Calendar.current.component(.hour, from: .now) }

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(hourly, id: \.hour) { point in
                    let isNow = point.hour == currentHour
                    let isSelected = point.hour == selected
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(CurrentsTheme.scoreColor(point.score)
                            .opacity(point.hour < currentHour && !isSelected ? 0.35 : 1))
                        .frame(height: max(4, CGFloat(point.score) * 0.28))
                        .overlay {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 1.5)
                                    .strokeBorder(.primary, lineWidth: 1.5)
                            } else if isNow {
                                RoundedRectangle(cornerRadius: 1.5)
                                    .strokeBorder(.primary.opacity(0.7), lineWidth: 1)
                            }
                        }
                        // A 4pt bar is far too small a target, so each one gets
                        // the full height of the strip to be tapped in.
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.snappy(duration: 0.2)) {
                                selected = isSelected ? nil : point.hour
                            }
                        }
                }
            }
            .frame(height: 30, alignment: .bottom)

            HStack {
                Text("12 AM").font(.system(size: 8))
                Spacer()
                Text("Noon").font(.system(size: 8))
                Spacer()
                Text("11 PM").font(.system(size: 8))
            }
            .foregroundStyle(.tertiary)
        }
    }
}

/// Chips that wrap instead of clipping — reason text varies in length and a
/// single HStack would truncate the useful ones.
struct FlowChips: View {
    let items: [String]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 5) { chips }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) { chip(items.first ?? "") }
                HStack(spacing: 5) {
                    ForEach(Array(items.dropFirst()), id: \.self) { chip($0) }
                }
            }
        }
    }

    private var chips: some View {
        ForEach(items, id: \.self) { chip($0) }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 7).padding(.vertical, 3)
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
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, s in
                        VStack(alignment: .leading, spacing: 6) {
                            LureRow(suggestion: s, rank: index + 1)
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
