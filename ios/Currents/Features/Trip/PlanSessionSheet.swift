import SwiftUI
import CoreLocation
import MapKit

/// Plan an upcoming session: name it, choose a location (current, a saved spot,
/// or a dropped pin), pick a date/time, and see the solunar outlook + a gear
/// checklist. Saved as a planned session that reminds you to start near the time.
struct PlanSessionSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var name = SessionFormat.defaultName()
    @State private var spots: [Spot] = []
    @State private var locationMode: PlanLocationMode = .current
    @State private var spotId: String?
    @State private var pinCoordinate: CLLocationCoordinate2D?
    @State private var showingPinPicker = false
    @State private var date = defaultPlanDate()
    @State private var solunar: SolunarEngine.SolunarDay?
    @State private var checklist: [ChecklistItem] = ChecklistItem.defaults

    enum PlanLocationMode: String, CaseIterable { case current = "Current", spot = "Saved Spot", pin = "Drop Pin" }

    var body: some View {
        NavigationStack {
            Form {
                Section("Session") {
                    TextField("Name", text: $name)
                    DatePicker("Date & time", selection: $date, displayedComponents: [.date, .hourAndMinute])
                }

                Section("Location") {
                    Picker("Location", selection: $locationMode) {
                        ForEach(PlanLocationMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    switch locationMode {
                    case .current:
                        Label("Uses your current location", systemImage: "location.fill")
                            .font(.caption).foregroundStyle(.secondary)
                    case .spot:
                        Picker("Spot", selection: $spotId) {
                            Text("Choose…").tag(nil as String?)
                            ForEach(spots) { Text($0.name).tag($0.id as String?) }
                        }
                    case .pin:
                        Button {
                            showingPinPicker = true
                        } label: {
                            if let c = pinCoordinate {
                                Label(String(format: "Pin: %.4f, %.4f", c.latitude, c.longitude), systemImage: "mappin.circle.fill")
                            } else {
                                Label("Drop a pin on the map", systemImage: "mappin.and.ellipse")
                            }
                        }
                    }
                }

                if let solunar {
                    Section("Outlook for the day") {
                        HStack {
                            Label("Solunar rating", systemImage: "moon.stars.fill")
                            Spacer()
                            Text(solunar.dayRating.label).font(.subheadline.bold())
                                .foregroundStyle(ratingColor(solunar.dayRating))
                        }
                        infoRow("Sunrise", solunar.sunrise.formatted(date: .omitted, time: .shortened))
                        infoRow("Sunset", solunar.sunset.formatted(date: .omitted, time: .shortened))
                        ForEach(Array(solunar.majorPeriods.enumerated()), id: \.offset) { _, p in
                            infoRow("Major", "\(p.start.formatted(date: .omitted, time: .shortened))–\(p.end.formatted(date: .omitted, time: .shortened))")
                        }
                    }
                }

                Section("Gear checklist") {
                    ForEach($checklist) { $item in Toggle(item.name, isOn: $item.checked) }
                }
            }
            .navigationTitle("Plan a Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Plan") { savePlan() }.bold().disabled(name.isEmpty)
                }
            }
            .sheet(isPresented: $showingPinPicker) {
                LocationPickerSheet(coordinate: $pinCoordinate)
            }
            .task {
                spots = (try? appState.spotRepository.fetchAll()) ?? []
                recompute()
            }
            .onChange(of: spotId) { _, _ in recompute() }
            .onChange(of: pinCoordinate?.latitude) { _, _ in recompute() }
            .onChange(of: locationMode) { _, _ in recompute() }
            .onChange(of: date) { _, _ in recompute() }
        }
    }

    private var coordinate: CLLocationCoordinate2D {
        switch locationMode {
        case .spot:
            if let spotId, let s = spots.first(where: { $0.id == spotId }) {
                return CLLocationCoordinate2D(latitude: s.latitude, longitude: s.longitude)
            }
        case .pin:
            if let pinCoordinate { return pinCoordinate }
        case .current:
            break
        }
        return appState.locationManager.currentLocation?.coordinate
            ?? CLLocationCoordinate2D(latitude: -33.9, longitude: 18.4)
    }

    private func recompute() {
        solunar = SolunarEngine.compute(date: date, coordinate: coordinate)
    }

    private func savePlan() {
        let coord = coordinate
        var trip = Trip(
            name: name,
            startDate: date,
            spotId: locationMode == .spot ? spotId : nil,
            plannedDate: date,
            plannedLatitude: locationMode == .current ? nil : coord.latitude,
            plannedLongitude: locationMode == .current ? nil : coord.longitude
        )
        try? appState.tripRepository.save(&trip)
        Task { await NotificationManager.shared.schedulePlannedSessionAlert(trip: trip) }
        dismiss()
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value) }.font(.subheadline)
    }

    private func ratingColor(_ r: SolunarEngine.DayRating) -> Color {
        switch r {
        case .best: .green
        case .good: CurrentsTheme.accent
        case .fair: .orange
        case .poor: .secondary
        }
    }

    private static func defaultPlanDate() -> Date {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: .now) ?? .now
        return cal.date(bySettingHour: 6, minute: 0, second: 0, of: tomorrow) ?? tomorrow
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
