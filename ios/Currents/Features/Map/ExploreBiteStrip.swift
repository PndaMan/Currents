import SwiftUI

/// Today's bite as 24 bars (one per hour, coloured by score, past hours
/// dimmed, a dot under now) with the day's best windows as tiles below.
/// Used on the spot and water pages.
struct BiteStrip: View {
    let bite: BiteSnapshot
    @AppStorage("use24HourTime") private var use24HourTime = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

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
                HStack(spacing: DS.Space.s2) {
                    ForEach(bite.windows) { w in
                        WindowTile(window: w, use24Hour: use24HourTime)
                    }
                }
                .padding(.top, DS.Space.s1)
            }
        }
        .padding(.horizontal, DS.gutter)
        .onAppear { grown = true }
    }

    private var axis: [String] {
        use24HourTime ? ["00:00", "06:00", "12:00", "18:00", "23:00"] : ["12 am", "6 am", "Noon", "6 pm", "11 pm"]
    }

    private func barColor(_ p: (hour: Int, score: Int)) -> Color {
        let base = inWindow(p.hour) ? DS.scoreColor(p.score) : Color.dsText.opacity(0.14)
        return p.hour < nowHour ? base.opacity(0.4) : base
    }

    private var accessibilitySummary: String {
        if let best = bite.best {
            return "Bite by hour. Best \(ExploreFormat.window(best, use24Hour: use24HourTime)), peaking at \(best.peakScore)."
        }
        return "Bite by hour. No strong window today."
    }
}

private struct WindowTile: View {
    let window: BiteWindows.Window
    let use24Hour: Bool
    @Environment(\.colorScheme) private var scheme

    private var passed: Bool { window.hasPassed() }
    private var now: Bool { window.isNow() }

    private var name: String {
        if now { return "Now" }
        switch window.startHour {
        case ..<9: return "Dawn"
        case 9..<16: return "Midday"
        case 16..<20: return "Dusk"
        default: return "Night"
        }
    }

    private var icon: String {
        switch window.startHour {
        case ..<9: "sunrise"
        case 9..<16: "sun.max"
        case 16..<20: "sunset"
        default: "moon.stars"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(name, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(now ? Color.dsText : Color.dsText2)
            Text("\(window.peakScore)")
                .font(.title.bold())
                .monospacedDigit()
                .foregroundStyle(DS.scoreInk(window.peakScore))
            Text(passed ? "Passed" : ExploreFormat.window(window, use24Hour: use24Hour))
                .font(.footnote)
                .foregroundStyle(.dsText2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(now ? DS.scoreColor(window.peakScore).opacity(scheme == .dark ? 0.22 : 0.14) : Color.dsFill,
                    in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
        .opacity(passed ? 0.5 : 1)
        .accessibilityElement(children: .combine)
    }
}
