import SwiftUI

/// Seven days by 24 hours of bite score, one cell per hour in the score
/// colour. Tap a cell to open that day with the hour selected.
struct SolunarHeatmapView: View {
    let store: ForecastStore
    @AppStorage("use24HourTime") private var use24 = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                Color.clear.frame(width: 40)
                ForEach([0, 6, 12, 18], id: \.self) { h in
                    Text(ForecastFormat.hour(h, use24: use24))
                        .font(.caption2)
                        .foregroundStyle(.dsText2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .accessibilityHidden(true)

            ForEach(0..<7, id: \.self) { offset in
                let day = store.day(offset)
                HStack(spacing: 4) {
                    Text(offset == 0 ? "Today" : ForecastFormat.shortDay(day.date))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.dsText)
                        .frame(width: 36, alignment: .leading)
                    HStack(spacing: 1.5) {
                        ForEach(0..<24, id: \.self) { h in
                            let score = day.score(at: h) ?? 0
                            NavigationLink(value: ForecastRoute.day(offset: offset, hour: h)) {
                                RoundedRectangle(cornerRadius: 2.5, style: .continuous) // ui-lint: allow, heatmap cell, not a card
                                    .fill(DS.scoreColor(score).opacity(0.25 + 0.75 * Double(score) / 100))
                                    .frame(height: 18)
                                    .frame(maxWidth: .infinity)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.dim)
                            .accessibilityLabel("\(ForecastFormat.dayName(offset, date: day.date)) \(ForecastFormat.hour(h, use24: use24)), score \(score)")
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                Text("Slow").font(.caption2).foregroundStyle(.dsText2)
                ForEach([20, 45, 60, 85], id: \.self) { s in
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous) // ui-lint: allow, heatmap cell, not a card
                        .fill(DS.scoreColor(s))
                        .frame(width: 22, height: 8)
                }
                Text("Prime").font(.caption2).foregroundStyle(.dsText2)
                Spacer()
            }
            .padding(.top, 4)
            .accessibilityHidden(true)

            Text("Tap any hour to open that day.")
                .font(.footnote)
                .foregroundStyle(.dsText2)
        }
    }
}
