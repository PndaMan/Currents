import SwiftUI
import CoreLocation
import MapKit

/// Plan an upcoming session: name it, choose a location (current, a saved spot,
/// or a dropped pin, optionally saving it as a spot), pick a date/time, and see
/// a multi-day bite-score outlook with the best times to fish each day + a gear
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
    @State private var savePinAsSpot = false
    @State private var pinSpotName = ""
    @State private var date = defaultPlanDate()
    @State private var dayCount = 3
    @State private var outlook: [DayOutlook] = []
    @State private var checklist: [ChecklistItem] = ChecklistItem.defaults

    enum PlanLocationMode: String, CaseIterable { case current = "Current", spot = "Saved Spot", pin = "Drop Pin" }

    /// A day's bite outlook: peak bite score + the best fishing windows.
    struct DayOutlook: Identifiable {
        let id = UUID()
        let date: Date
        let peakScore: Int
        let windows: [BiteWindow]
    }
    struct BiteWindow: Identifiable {
        let id = UUID()
        let label: String      // e.g. "Major" / "Dawn"
        let range: String      // e.g. "5:12–7:12 AM"
        let prime: Bool
    }

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
                        if pinCoordinate != nil {
                            Toggle("Save this pin as a spot", isOn: $savePinAsSpot)
                            if savePinAsSpot {
                                TextField("Spot name", text: $pinSpotName)
                            }
                        }
                    }
                }

                Section {
                    Stepper("Show \(dayCount) \(dayCount == 1 ? "day" : "days")", value: $dayCount, in: 1...14)
                } header: {
                    Text("Best times to fish")
                } footer: {
                    Text("Bite outlook is based on solunar feeding windows, tides, sun and moon for this location — no internet needed. Log-day weather refines the live bite score on the Forecast tab.")
                }

                ForEach(outlook) { day in
                    Section {
                        HStack {
                            Label("Bite score", systemImage: "gauge.with.dots.needle.67percent")
                            Spacer()
                            Text("\(day.peakScore)").font(.title3.bold())
                                .foregroundStyle(scoreColor(day.peakScore))
                            Text("/100").font(.caption).foregroundStyle(.secondary)
                        }
                        if day.windows.isEmpty {
                            Text("No standout windows — fish dawn and dusk.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            ForEach(day.windows) { w in
                                HStack {
                                    Image(systemName: w.prime ? "star.fill" : "clock")
                                        .font(.caption).foregroundStyle(w.prime ? CurrentsTheme.accent : .secondary)
                                    Text(w.label).font(.subheadline)
                                    Spacer()
                                    Text(w.range).font(.subheadline.monospacedDigit())
                                        .foregroundStyle(w.prime ? .primary : .secondary)
                                }
                            }
                        }
                    } header: {
                        Text(day.date.formatted(.dateTime.weekday(.wide).month().day()))
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
            .onChange(of: dayCount) { _, _ in recompute() }
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
        let coord = coordinate
        let cal = Calendar.current
        outlook = (0..<dayCount).map { offset in
            let day = cal.date(byAdding: .day, value: offset, to: date) ?? date
            let f = ForecastEngine.forecast(
                date: day, coordinate: coord,
                currentPressureHpa: nil, pressureChange6h: nil,
                waterTempC: nil, windSpeedKmh: nil, windDirection: nil,
                species: nil, isInSpawningZone: false)
            let peak = f.hourlyScores.map(\.score).max() ?? f.score

            let solunar = SolunarEngine.compute(date: day, coordinate: coord)
            // Collect the day's feeding windows (major/minor solunar + golden
            // hours) and present them in chronological order.
            let dated: [(Date, BiteWindow)] =
                solunar.majorPeriods.map { ($0.start, BiteWindow(label: "Major feed", range: rangeLabel($0.start, $0.end), prime: true)) }
                + [(solunar.dawnGoldenHour.lowerBound, BiteWindow(label: "Dawn", range: rangeLabel(solunar.dawnGoldenHour.lowerBound, solunar.dawnGoldenHour.upperBound), prime: true))]
                + [(solunar.duskGoldenHour.lowerBound, BiteWindow(label: "Dusk", range: rangeLabel(solunar.duskGoldenHour.lowerBound, solunar.duskGoldenHour.upperBound), prime: true))]
                + solunar.minorPeriods.map { ($0.start, BiteWindow(label: "Minor feed", range: rangeLabel($0.start, $0.end), prime: false)) }
            let windows = dated.sorted { $0.0 < $1.0 }.map(\.1)

            return DayOutlook(date: day, peakScore: peak, windows: windows)
        }
    }

    private func rangeLabel(_ start: Date, _ end: Date) -> String {
        "\(start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))"
    }

    private func savePlan() {
        let coord = coordinate
        // Optionally persist a dropped pin as a reusable spot.
        var savedSpotId: String? = locationMode == .spot ? spotId : nil
        if locationMode == .pin, savePinAsSpot, let pin = pinCoordinate {
            let spotName = pinSpotName.trimmingCharacters(in: .whitespaces)
            var spot = Spot(
                name: spotName.isEmpty ? name : spotName,
                latitude: pin.latitude, longitude: pin.longitude,
                notes: "Created while planning “\(name)”",
                spotType: .general
            )
            try? appState.spotRepository.save(&spot)
            savedSpotId = spot.id
        }
        var trip = Trip(
            name: name,
            startDate: date,
            spotId: savedSpotId,
            plannedDate: date,
            plannedLatitude: locationMode == .current ? nil : coord.latitude,
            plannedLongitude: locationMode == .current ? nil : coord.longitude
        )
        try? appState.tripRepository.save(&trip)
        Task { await NotificationManager.shared.schedulePlannedSessionAlert(trip: trip) }
        dismiss()
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 75...: .green
        case 55..<75: CurrentsTheme.accent
        case 35..<55: .orange
        default: .secondary
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
