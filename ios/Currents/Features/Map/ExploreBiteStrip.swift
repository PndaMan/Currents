import SwiftUI

/// Today's bite as 24 bars (one per hour, lit by Today's rule, lit past
/// hours dimmed, a dot under now) with the day's best windows as tiles below.
/// Used on the spot and water pages.
struct BiteStrip: View {
    let bite: BiteSnapshot
    @AppStorage("use24HourTime") private var use24HourTime = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var grown = false

    /// Three tiles side by side, stacked at accessibility text sizes.
    private var tileLayout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: DS.Space.s2))
            : AnyLayout(HStackLayout(spacing: 10))
    }

    private var nowHour: Int { Calendar.current.component(.hour, from: .now) }

    private func inWindow(_ hour: Int) -> Bool {
        bite.windows.contains { hour >= $0.startHour && hour <= $0.endHour }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(bite.hourly.enumerated()), id: \.offset) { index, point in
                    VStack(spacing: 4) {
                        GeometryReader { geo in
                            VStack {
                                Spacer(minLength: 0)
                                RoundedRectangle(cornerRadius: ExploreMetrics.barRadius, style: .continuous)
                                    .fill(barColor(point))
                                    .frame(height: max(6, geo.size.height * CGFloat(point.score) / 100 * (grown ? 1 : 0.05)))
                            }
                        }
                        .frame(height: 96)
                        Circle()
                            .fill(point.hour == nowHour ? Color.dsText : Color.clear)
                            .frame(width: 5, height: 5)
                    }
                    .animation(reduceMotion ? nil : DS.Motion.softSpring.delay(Double(index) * 0.015), value: grown)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)

            HStack {
                ForEach(axis, id: \.self) { label in
                    Text(label)
                    if label != axis.last { Spacer(minLength: 0) }
                }
            }
            .font(.caption)
            .foregroundStyle(.dsText2)
            .accessibilityHidden(true)

            if !bite.windows.isEmpty {
                tileLayout {
                    ForEach(bite.windows) { w in
                        WindowTile(window: w, use24Hour: use24HourTime)
                    }
                }
                .padding(.top, DS.Space.s1)
            }

            if let note = footnote {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.dsText2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, DS.gutter)
        .onAppear { grown = true }
    }

    private var axis: [String] {
        use24HourTime ? ["00:00", "06:00", "12:00", "18:00", "23:00"] : ["12 am", "6 am", "Noon", "6 pm", "11 pm"]
    }

    /// The one line under the tiles: tomorrow's best once today's windows
    /// are over, or that today has none.
    private var footnote: String? {
        if bite.windows.isEmpty { return "No strong window today." }
        guard bite.allPassed, let line = bite.bestLine(use24: use24HourTime) else { return nil }
        return line + "."
    }

    /// Today's rule from the forecast bars: an hour in a window, the hour
    /// now, or any hour scoring 50 or more is lit in its score colour.
    /// Lit past hours are dimmed; unlit bars keep their full fill so they
    /// still show on a white page.
    private func barColor(_ p: (hour: Int, score: Int)) -> Color {
        let lit = inWindow(p.hour) || p.hour == nowHour || p.score >= 50
        guard lit else { return Color.dsFill2 }
        let color = DS.scoreColor(p.score)
        return p.hour < nowHour ? color.opacity(0.35) : color
    }

    private var accessibilitySummary: String {
        if let line = bite.bestLine(use24: use24HourTime) {
            return "Bite by hour. \(line)."
        }
        return "Bite by hour. No strong window today."
    }
}

/// One bite window, drawn as Today's window tiles are: the time of day,
/// "Peak" and the best hour's score, and the hours, "Until" while it runs
/// or "Passed". The outline marks the window you are in.
private struct WindowTile: View {
    let window: BiteWindows.Window
    let use24Hour: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    private var passed: Bool { window.hasPassed() }
    private var now: Bool { window.isNow() }

    private var time: String {
        if now { return "Until \(ForecastFormat.hour(window.endHour + 1, use24: use24Hour))" }
        return passed ? "Passed" : ForecastFormat.range(window, use24: use24Hour)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(ForecastFormat.windowName(window.startHour),
                  systemImage: ForecastFormat.windowIcon(window.startHour))
                .font(.subheadline)
                .foregroundStyle(.dsText2)
                .labelStyle(TintedIconLabelStyle(tint: DS.scoreInk(window.peakScore)))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("Peak")
                    .font(.footnote)
                    .foregroundStyle(.dsText2)
                Text("\(window.peakScore)")
                    .font(.title.bold())
                    .monospacedDigit()
                    .foregroundStyle(DS.scoreInk(window.peakScore))
            }
            Text(time)
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.dsText2)
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                .minimumScaleFactor(0.75)
        }
        // A passed window dims its content; the card keeps its full fill so
        // it still reads on a white page.
        .opacity(passed ? 0.5 : 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .overlay {
            if now {
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .strokeBorder(DS.scoreColor(window.peakScore), lineWidth: 1.5)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
