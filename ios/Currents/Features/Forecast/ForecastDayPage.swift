import SwiftUI

/// One day of the forecast, pushed from Today: date strip, hero ring, Plan /
/// Alert me / Share, bite by hour, best windows, hour by hour weather, the
/// condition tiles and the nine-factor breakdown.
struct ForecastDayPage: View {
    let store: ForecastStore

    @State private var offset: Int
    @State private var selectedHour: Int?
    @State private var showPlanner = false
    @State private var showAlerts = false
    @AppStorage("use24HourTime") private var use24 = true
    @AppStorage("alertsEnabled") private var alertsEnabled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(store: ForecastStore, initialDay: Int = 0, initialHour: Int? = nil) {
        self.store = store
        _offset = State(initialValue: min(6, max(0, initialDay)))
        _selectedHour = State(initialValue: initialHour)
    }

    var body: some View {
        let day = store.day(offset)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    dateStrip
                    hero(day)
                    actions(day)

                    VStack(alignment: .leading, spacing: 0) {
                        SectionTitle("Bite by hour")
                        VStack(spacing: 8) {
                            BiteBars(hourly: day.result.hourlyScores, windows: day.windows,
                                     currentHour: day.isToday ? Calendar.current.component(.hour, from: .now) : nil,
                                     selected: $selectedHour, height: 110, use24: use24)
                            HourAxis(labels: use24 ? ["00:00", "06:00", "12:00", "18:00", "23:00"] : ["12 am", "6 am", "Noon", "6 pm", "11 pm"])
                            HourInfoBox(store: store, day: day, hour: selectedHour, use24: use24)
                                .padding(.top, 6)
                        }
                        .padding(.horizontal, DS.gutter)
                    }
                    .id("chart")

                    VStack(alignment: .leading, spacing: 0) {
                        SectionTitle("Best windows")
                        WindowTiles(day: day, use24: use24) { hour in
                            withAnimation(reduceMotion ? nil : DS.Motion.softSpring) {
                                selectedHour = hour
                                proxy.scrollTo("chart", anchor: .center)
                            }
                        }
                        .padding(.horizontal, DS.gutter)
                    }

                    if !day.hours.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            SectionTitle("Hour by hour")
                            HourStrip(day: day, use24: use24)
                        }
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        SectionTitle("Conditions")
                        ConditionGrid(store: store, day: day, use24: use24)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        SectionTitle(day.isToday ? "Why it scores \(day.result.score) now"
                                                 : "Why midday scores \(day.result.score)")
                        FactorBreakdown(breakdown: day.result.breakdown, species: store.species)
                        Text("Worked out on your phone. No signal needed.")
                            .font(.footnote)
                            .foregroundStyle(.dsText2)
                            .padding(.horizontal, DS.gutter)
                            .padding(.top, 10)
                    }

                    TargetRow(store: store)
                }
                .padding(.top, 4)
                .padding(.bottom, 40)
                .pageWidth()
            }
        }
        .detailTint(DS.scoreColor(day.peakScore))
        .navigationTitle(ForecastFormat.dayName(offset, date: day.date))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await store.load(force: true)
            Haptics.softPress()
        }
        .sheet(isPresented: $showPlanner) { PlanSessionSheet() }
        .navigationDestination(isPresented: $showAlerts) { AlertSettingsView() }
    }

    // MARK: - Date strip

    private var dateStrip: some View {
        ForecastDayStrip(store: store, selection: $offset) { selectedHour = nil }
    }

    // MARK: - Hero

    private func hero(_ day: ForecastDay) -> some View {
        let reason = day.result.reasons.first.map(ForecastFormat.clean) ?? ForecastFormat.guidance(day.peakScore)
        let sub = day.isToday ? "Right now \(day.result.score). \(reason)" : reason
        return HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ForecastFormat.longDate(day.date))
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                Text(ForecastFormat.verdict(day.peakScore))
                    .font(.title.bold())
                    .foregroundStyle(.dsText)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                Text(sub)
                    .font(.callout)
                    .foregroundStyle(.dsText2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            ScoreRing(score: day.peakScore, size: 96, caption: "of 100")
        }
        .padding(.horizontal, DS.gutter)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Actions

    private func actions(_ day: ForecastDay) -> some View {
        ActionTriple {
            Button { showPlanner = true } label: {
                Label("Plan", systemImage: "calendar.badge.plus")
            }
            .buttonStyle(ActionTileStyle(.primary))

            Button { showAlerts = true } label: {
                Label(alertsEnabled ? "Alerts on" : "Alert me", systemImage: alertsEnabled ? "bell.fill" : "bell")
            }
            .buttonStyle(ActionTileStyle(.tonal))

            ShareLink(item: shareText(day)) {
                ActionTileLabel("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.dim)
        }
    }

    private func shareText(_ day: ForecastDay) -> String {
        var text = "\(ForecastFormat.dayName(day.offset, date: day.date)) at \(store.placeName): bite score \(day.peakScore) of 100, \(ForecastFormat.verdict(day.peakScore).lowercased())."
        if let best = day.bestWindow {
            text += " Best \(ForecastFormat.range(best, use24: use24))."
        }
        return text + " Forecast from Currents."
    }
}

/// A short weather line for week rows and day cards.
enum ForecastWeatherLine {
    static func summary(_ w: WeatherService.WeatherData?) -> String? {
        guard let w else { return nil }
        return "\(Int(w.temperatureC.rounded()))°, \(w.condition.lowercased()), wind \(Int(w.windSpeedKmh.rounded())) km/h"
    }
}

// MARK: - Week

/// The next seven days: best day, a row per day and the all-week heatmap.
struct ForecastWeekPage: View {
    let store: ForecastStore
    @AppStorage("use24HourTime") private var use24 = true
    @ScaledMetric(relativeTo: .largeTitle) private var bestSize: CGFloat = 44

    var body: some View {
        let days = (0..<7).map { store.day($0) }
        let best = days.max { $0.peakScore < $1.peakScore } ?? store.day(0)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DetailHeader(over: store.placeName, title: "Next 7 days",
                             subtitle: "\(ForecastFormat.longDate(days.first?.date ?? .now)) to \(ForecastFormat.longDate(days.last?.date ?? .now))")

                bestDay(best)

                VStack(spacing: 0) {
                    ForEach(days, id: \.offset) { d in
                        NavigationLink(value: ForecastRoute.day(offset: d.offset, hour: nil)) {
                            weekRow(d)
                        }
                        .buttonStyle(.dsRow)
                        if d.offset < 6 {
                            Divider().overlay(Color.dsSeparator).padding(.leading, DS.gutter + 70)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    SectionTitle("Hour by hour, all week")
                    SolunarHeatmapView(store: store)
                        .padding(.horizontal, DS.gutter)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 40)
            .pageWidth()
        }
        .detailTint(nil)
        .navigationTitle("Next 7 days")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await store.load(force: true)
            Haptics.softPress()
        }
    }

    private func bestDay(_ d: ForecastDay) -> some View {
        NavigationLink(value: ForecastRoute.day(offset: d.offset, hour: d.bestWindow?.startHour)) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Best day this week", systemImage: "trophy")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.scoreInk(d.peakScore))
                    Text("\(ForecastFormat.dayName(d.offset, date: d.date)), \(d.bestWindow.map { ForecastFormat.range($0, use24: use24) } ?? "all day")")
                        .font(.headline)
                        .foregroundStyle(.dsText)
                    Text(d.result.reasons.first.map(ForecastFormat.clean) ?? ForecastFormat.guidance(d.peakScore))
                        .font(.subheadline)
                        .foregroundStyle(.dsText2)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Text("\(d.peakScore)")
                    .font(.system(size: bestSize, weight: .bold)) // ui-lint: allow, @ScaledMetric numeral
                    .monospacedDigit()
                    .foregroundStyle(DS.scoreInk(d.peakScore))
            }
            .padding(16)
            .background(DS.scoreColor(d.peakScore).opacity(0.16),
                        in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .padding(.horizontal, DS.gutter)
        }
        .buttonStyle(.dim)
        .accessibilityElement(children: .combine)
    }

    private func weekRow(_ d: ForecastDay) -> some View {
        HStack(spacing: 14) {
            VStack(spacing: 0) {
                Text(d.offset == 0 ? "Today" : ForecastFormat.shortDay(d.date))
                    .font(.footnote)
                    .foregroundStyle(.dsText2)
                Text(ForecastFormat.dayNumber(d.date))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.dsText)
            }
            .frame(width: 56, height: 56)
            .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(ForecastFormat.verdict(d.peakScore))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.dsText)
                if let line = ForecastWeatherLine.summary(d.weather) {
                    Label(line, systemImage: WeatherIcon(condition: d.weather?.condition ?? "").systemName)
                        .font(.subheadline)
                        .foregroundStyle(.dsText2)
                        .symbolRenderingMode(.hierarchical)
                        .lineLimit(1)
                }
                Text(d.bestWindow.map { "Best \(ForecastFormat.range($0, use24: use24))" } ?? "No strong window")
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                    .monospacedDigit()
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(d.peakScore)")
                    .font(.title2.bold())
                    .monospacedDigit()
                    .foregroundStyle(DS.scoreInk(d.peakScore))
                Sparkline(values: d.result.hourlyScores.map { Double($0.score) }, tint: DS.scoreColor(d.peakScore), lineWidth: 1.8)
                    .frame(width: 64, height: 20)
            }
        }
        .padding(.horizontal, DS.gutter)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Seven day chips (Today, Fri 23 ...) with each day's best score as a dot.
/// Used at the top of the day page and the condition pages.
struct ForecastDayStrip: View {
    let store: ForecastStore
    @Binding var selection: Int
    var onChange: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    chip(i)
                }
            }
            .padding(.horizontal, DS.gutter - 4)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private func chip(_ i: Int) -> some View {
        let d = store.day(i)
        let on = i == selection
        return Button {
            withAnimation(reduceMotion ? nil : DS.Motion.softSpring) {
                selection = i
                onChange?()
            }
        } label: {
            VStack(spacing: 3) {
                Text(i == 0 ? "Today" : ForecastFormat.shortDay(d.date))
                    .font(.subheadline)
                Text(ForecastFormat.dayNumber(d.date))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Circle()
                    .fill(DS.scoreColor(d.peakScore))
                    .frame(width: 6, height: 6)
            }
            .foregroundStyle(on ? Color.dsOnPrimary : Color.dsText)
            .frame(width: 54)
            .padding(.vertical, 10)
            .background {
                if on {
                    RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous).fill(Color.dsPrimaryButton)
                }
            }
        }
        .buttonStyle(.dim)
        .buttonHaptic(.selection)
        .accessibilityLabel("\(ForecastFormat.dayName(i, date: d.date)), best score \(d.peakScore)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
