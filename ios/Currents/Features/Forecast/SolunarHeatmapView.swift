import SwiftUI
import CoreLocation

/// A 7-day × 24-hour heatmap of solunar bite quality for a location. Each cell
/// is tinted by the hourly solunar score (red = poor … green = prime), so an
/// angler can eyeball the best days and times of day at a glance.
struct SolunarHeatmapView: View {
    let coordinate: CLLocationCoordinate2D
    @State private var days: [DayScores] = []

    struct DayScores: Identifiable {
        let id = UUID()
        let label: String
        let scores: [Double]   // 24 hourly scores, 0…1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Solunar Bite Heatmap", systemImage: "moon.stars.fill")
                    .font(.headline)
                Spacer()
                Text("Next 7 days").font(.caption2).foregroundStyle(.secondary)
            }

            if days.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 8)
            } else {
                // Hour axis
                HStack(spacing: 0) {
                    Color.clear.frame(width: 34)
                    ForEach([0, 6, 12, 18], id: \.self) { h in
                        Text("\(h)h")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                ForEach(days) { day in
                    HStack(spacing: 3) {
                        Text(day.label)
                            .font(.caption2.bold())
                            .frame(width: 31, alignment: .leading)
                        HStack(spacing: 1) {
                            ForEach(0..<24, id: \.self) { h in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(CurrentsTheme.scoreColor(Int((day.scores[safe: h] ?? 0) * 100)))
                                    .frame(height: 15)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }

                // Legend
                HStack(spacing: 5) {
                    Text("Poor").font(.system(size: 9)).foregroundStyle(.secondary)
                    ForEach([10, 35, 55, 80, 100], id: \.self) { s in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(CurrentsTheme.scoreColor(s))
                            .frame(width: 16, height: 8)
                    }
                    Text("Prime").font(.system(size: 9)).foregroundStyle(.secondary)
                    Spacer()
                    Text("Tap a day in the picker for detail")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 2)
            }
        }
        .glassCard()
        .task(id: "\(coordinate.latitude),\(coordinate.longitude)") { compute() }
    }

    private func compute() {
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE"
        var out: [DayScores] = []
        for offset in 0..<7 {
            guard let date = cal.date(byAdding: .day, value: offset, to: Date()) else { continue }
            let hourly = SolunarEngine.hourlyScores(date: date, coordinate: coordinate)
            out.append(DayScores(label: fmt.string(from: date), scores: hourly.map(\.score)))
        }
        days = out
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
