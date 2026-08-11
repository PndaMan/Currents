import SwiftUI
import CoreLocation

/// Plan an upcoming session: name it, pick a date/time, and see a multi-day
/// bite-score outlook with the best times to fish each day + a gear checklist.
/// Saved as a planned session that reminds you to start near the time. The
/// session itself uses your current location when you start it; the outlook is
/// computed for your current location by default, or for a pin you drop purely
/// to preview the forecast somewhere else.
struct PlanSessionSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    /// When set, the sheet edits this existing (planned) trip instead of
    /// creating a new one. Its returned id is reported via `onSaved`.
    let editingTrip: Trip?
    /// Called with the saved trip's id (useful for linking a group trip).
    var onSaved: ((String) -> Void)?

    init(editingTrip: Trip? = nil, onSaved: ((String) -> Void)? = nil) {
        self.editingTrip = editingTrip
        self.onSaved = onSaved
    }

    @State private var name = SessionFormat.defaultName()
    @State private var date = defaultPlanDate()
    @State private var dayCount = 3
    /// A pin dropped ONLY to preview the bite forecast somewhere other than
    /// your current location. It never changes where the session records — that
    /// always uses your live GPS location when you start.
    @State private var forecastPin: CLLocationCoordinate2D?
    @State private var showingPinPicker = false
    @State private var outlook: [DayOutlook] = []
    @State private var checklist: [Trip.ChecklistItem] = PlanSessionSheet.defaultChecklist
    @State private var newItem = ""
    @State private var loaded = false
    @State private var isSaving = false

    static let defaultChecklist: [Trip.ChecklistItem] = [
        "Rod & reel", "Tackle box / lures", "Bait", "Licence / permit",
        "Landing net", "Pliers & line cutter", "Sun protection & hat",
        "Water & snacks", "First-aid kit", "Phone charged / power bank",
    ].map { Trip.ChecklistItem(name: $0) }

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
                Section {
                    TextField("Name", text: $name)
                    DatePicker("Date & time", selection: $date, displayedComponents: [.date, .hourAndMinute])
                } header: {
                    Text("Session")
                } footer: {
                    Text("The session records your current location when you start it. The bite outlook below is just a preview — it doesn't change where the session tracks.")
                }

                Section {
                    Button {
                        showingPinPicker = true
                    } label: {
                        HStack {
                            Label("Forecast location", systemImage: "mappin.and.ellipse")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(forecastPin == nil ? "My location" : "Dropped pin")
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    if forecastPin != nil {
                        Button(role: .destructive) { forecastPin = nil } label: {
                            Label("Use my current location", systemImage: "location.fill")
                        }
                    }
                    Stepper("Show \(dayCount) \(dayCount == 1 ? "day" : "days")", value: $dayCount, in: 1...14)
                } header: {
                    Text("Best times to fish")
                } footer: {
                    Text("Drop a pin to preview the bite forecast anywhere you're thinking of fishing — it only changes the outlook below, not the session. Based on solunar feeding windows, tides, sun and moon for that spot; no internet needed.")
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

                Section {
                    // Checkbox rows, not switches — a packing list ticks off.
                    ForEach($checklist) { $item in
                        Button {
                            withAnimation(.snappy(duration: 0.15)) { item.checked.toggle() }
                            Haptics.tap()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.checked ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(item.checked ? CurrentsTheme.accent : .secondary)
                                    .contentTransition(.symbolEffect(.replace))
                                Text(item.name)
                                    .strikethrough(item.checked, color: .secondary)
                                    .foregroundStyle(item.checked ? .secondary : .primary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { checklist.remove(atOffsets: $0) }
                    HStack {
                        Image(systemName: "plus.circle.fill").foregroundStyle(CurrentsTheme.accent)
                        TextField("Add an item", text: $newItem)
                            .onSubmit(addChecklistItem)
                        if !newItem.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button("Add", action: addChecklistItem).font(.caption.bold())
                        }
                    }
                } header: {
                    Text("Gear checklist")
                } footer: {
                    Text("Ticked items are saved with the session — reopen it any time and your checklist is right where you left it.")
                }
            }
            .navigationTitle(editingTrip == nil ? "Plan a Session" : "Edit Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editingTrip == nil ? "Save Plan" : "Save") { savePlan() }
                        .bold().disabled(name.isEmpty || isSaving)
                }
            }
            .sheet(isPresented: $showingPinPicker) {
                LocationPickerSheet(coordinate: $forecastPin)
            }
            .task {
                if !loaded { loadEditingTrip(); loaded = true }
                recompute()
            }
            .onChange(of: date) { _, _ in recompute() }
            .onChange(of: dayCount) { _, _ in recompute() }
            .onChange(of: forecastPin?.latitude) { _, _ in recompute() }
            .sensoryFeedback(.selection, trigger: dayCount)
            .sensoryFeedback(.selection, trigger: checklist.map(\.checked))
        }
    }

    /// Where the bite outlook is computed: the dropped forecast pin if set,
    /// otherwise your current location.
    private var coordinate: CLLocationCoordinate2D {
        forecastPin
            ?? appState.locationManager.currentLocation?.coordinate
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

    private func addChecklistItem() {
        let n = newItem.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        checklist.append(Trip.ChecklistItem(name: n))
        newItem = ""
    }

    /// Populate the sheet from an existing planned trip when editing.
    private func loadEditingTrip() {
        guard let t = editingTrip else { return }
        name = t.name
        date = t.plannedDate ?? t.startDate
        let items = t.decodedChecklist
        if !items.isEmpty { checklist = items }
        // Restore a previously-chosen forecast pin (session location is always
        // live GPS, so this coordinate is only ever the outlook preview).
        forecastPin = t.plannedCoordinate
    }

    private func savePlan() {
        guard !isSaving else { return }
        isSaving = true
        // Edit in place when we opened an existing trip, else create a new one.
        // The session uses your current location when you start it, so no
        // location is stored on the plan itself.
        var trip = editingTrip ?? Trip(name: name, startDate: date, plannedDate: date)
        trip.name = name
        trip.startDate = date
        trip.plannedDate = date
        trip.spotId = nil
        // Persist the forecast pin only as a preview hint. `startPlanned` clears
        // these and tracks live GPS, so it never affects the session location.
        trip.plannedLatitude = forecastPin?.latitude
        trip.plannedLongitude = forecastPin?.longitude
        trip.checklist = Trip.encodeChecklist(checklist)
        try? appState.tripRepository.save(&trip)
        Task { await NotificationManager.shared.schedulePlannedSessionAlert(trip: trip) }
        ToastCenter.shared.show(editingTrip == nil ? "Session planned" : "Session updated")
        onSaved?(trip.id)
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
}
