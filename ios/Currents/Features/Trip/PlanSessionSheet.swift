import SwiftUI
import CoreLocation

/// Plan an upcoming session: pick a spot + date and see the solunar rating,
/// best feeding windows, sun times and a gear checklist for that day.
struct PlanSessionSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var spots: [Spot] = []
    @State private var spotId: String?
    @State private var date = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
    @State private var solunar: SolunarEngine.SolunarDay?
    @State private var checklist: [ChecklistItem] = ChecklistItem.defaults

    var body: some View {
        NavigationStack {
            Form {
                Section("Where & when") {
                    Picker("Spot", selection: $spotId) {
                        Text("Current location").tag(nil as String?)
                        ForEach(spots) { Text($0.name).tag($0.id as String?) }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                if let solunar {
                    Section("Forecast for the day") {
                        HStack {
                            Label("Solunar rating", systemImage: "moon.stars.fill")
                            Spacer()
                            Text(solunar.dayRating.label)
                                .font(.subheadline.bold())
                                .foregroundStyle(ratingColor(solunar.dayRating))
                        }
                        infoRow("Sunrise", solunar.sunrise.formatted(date: .omitted, time: .shortened))
                        infoRow("Sunset", solunar.sunset.formatted(date: .omitted, time: .shortened))
                        ForEach(Array(solunar.majorPeriods.enumerated()), id: \.offset) { _, p in
                            infoRow("Major (\(p.kind.rawValue))",
                                    "\(p.start.formatted(date: .omitted, time: .shortened))–\(p.end.formatted(date: .omitted, time: .shortened))")
                        }
                    }
                }

                Section("Gear checklist") {
                    ForEach($checklist) { $item in
                        Toggle(item.name, isOn: $item.checked)
                    }
                }
            }
            .navigationTitle("Plan a Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task {
                spots = (try? appState.spotRepository.fetchAll()) ?? []
                recompute()
            }
            .onChange(of: spotId) { _, _ in recompute() }
            .onChange(of: date) { _, _ in recompute() }
        }
    }

    private var coordinate: CLLocationCoordinate2D {
        if let spotId, let spot = spots.first(where: { $0.id == spotId }) {
            return CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude)
        }
        return appState.locationManager.currentLocation?.coordinate
            ?? CLLocationCoordinate2D(latitude: -33.9, longitude: 18.4)
    }

    private func recompute() {
        solunar = SolunarEngine.compute(date: date, coordinate: coordinate)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value) }
            .font(.subheadline)
    }

    private func ratingColor(_ r: SolunarEngine.DayRating) -> Color {
        switch r {
        case .best: .green
        case .good: CurrentsTheme.accent
        case .fair: .orange
        case .poor: .secondary
        }
    }

    struct ChecklistItem: Identifiable {
        let id = UUID()
        var name: String
        var checked: Bool = false

        static let defaults: [ChecklistItem] = [
            .init(name: "Rod & reel"), .init(name: "Tackle box / lures"),
            .init(name: "Bait"), .init(name: "Licence / permit"),
            .init(name: "Landing net"), .init(name: "Pliers & line cutter"),
            .init(name: "Sun protection & hat"), .init(name: "Water & snacks"),
            .init(name: "First-aid kit"), .init(name: "Phone charged / power bank"),
        ]
    }
}
