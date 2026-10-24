import SwiftUI
import CoreLocation
import UserNotifications

/// Plan an upcoming session in one short flow: name, when, where, a bite
/// outlook per day (tap a day to plan it, a bar to set the start time), then
/// what to bring. Saved as a planned session that reminds you near the time.
/// The session records wherever you are when you start it; the place picked
/// here sets the forecast and, for a saved spot, the spot it is logged at.
struct PlanSessionSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("use24HourTime") private var use24 = true
    @ScaledMetric(relativeTo: .headline) private var dayWidth: CGFloat = 60

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
    /// Where the outlook is worked out: a saved spot's position or a dropped
    /// pin. Nil means your current location.
    @State private var forecastPin: CLLocationCoordinate2D?
    @State private var spotId: String?
    @State private var spots: [Spot] = []
    @State private var showingPinPicker = false
    @State private var outlook: [DayOutlook] = []
    @State private var checklist: [Trip.ChecklistItem] = PlanSessionSheet.defaultChecklist
    @State private var newItem = ""
    @State private var loaded = false
    @State private var isSaving = false
    @FocusState private var focus: Field?

    private enum Field { case name, item }

    static let defaultChecklist: [Trip.ChecklistItem] = [
        "Rod and reel", "Tackle box and lures", "Bait", "Licence or permit",
        "Landing net", "Pliers and line cutter", "Sun protection and hat",
        "Water and snacks", "First-aid kit", "Phone charged or power bank",
    ].map { Trip.ChecklistItem(name: $0) }

    /// One day of the outlook: the bite by hour and its best windows.
    struct DayOutlook: Identifiable {
        let date: Date
        let hourly: [(hour: Int, score: Int)]
        let windows: [BiteWindows.Window]

        var id: Date { date }
        var peakScore: Int { hourly.map(\.score).max() ?? 0 }
        var bestHour: Int { hourly.max { $0.score < $1.score }?.hour ?? 6 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    nameField
                    whenSection
                    whereSection
                    outlookSection
                    bringSection
                }
                .padding(.bottom, DS.Space.s6)
                .pageWidth()
            }
            .scrollDismissesKeyboard(.interactively)
            .detailScrollEdge()
            .dsScreenBackground()
            .navigationTitle(editingTrip == nil ? "Plan a session" : "Edit plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focus = nil }
                }
            }
            .safeAreaInset(edge: .bottom) { saveBar }
            .sheet(isPresented: $showingPinPicker) {
                LocationPickerSheet(coordinate: pinBinding, pinLabel: "Forecast location")
            }
            .task {
                if !loaded {
                    loadEditingTrip()
                    loadSpots()
                    loaded = true
                }
                recompute()
            }
            .onChange(of: forecastPin?.latitude) { _, _ in recompute() }
            .onChange(of: forecastPin?.longitude) { _, _ in recompute() }
            .onChange(of: Calendar.current.startOfDay(for: date)) { _, day in
                // Only rebuild when the date picker jumps outside the strip.
                if !outlook.contains(where: { $0.date == day }) { recompute() }
            }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Name

    private var nameField: some View {
        TripNameField("Name this session", text: $name)
            .focused($focus, equals: .name)
            .padding(.top, DS.Space.s4)
    }

    // MARK: - When

    private var whenSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("When")
                .padding(.top, DS.Space.s8)
            HStack(spacing: 14) {
                ThumbView(systemImage: "calendar", tint: DS.accent, size: 44)
                DatePicker("Starts", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    .font(.body.weight(.medium))
                    .foregroundStyle(.dsText)
            }
            .padding(.horizontal, DS.gutter)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Where

    private var whereSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Where")
                .padding(.top, DS.Space.s8)

            ChoiceRow(title: "My location",
                      subtitle: appState.locationManager.currentLocation == nil ? "Location is off" : "Wherever you are",
                      systemImage: "location.fill",
                      selected: spotId == nil && forecastPin == nil) {
                spotId = nil
                forecastPin = nil
            }

            ForEach(spots) { spot in
                ChoiceRow(spot: spot, subtitle: spotSubtitle(spot), selected: spotId == spot.id) {
                    spotId = spot.id
                    forecastPin = CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude)
                }
            }

            let pinned = spotId == nil && forecastPin != nil
            ChoiceRow(title: pinned ? "Dropped pin" : "Drop a pin",
                      subtitle: pinned ? "Tap to move it" : "Anywhere on the map",
                      systemImage: "mappin.and.ellipse", selected: pinned) {
                showingPinPicker = true
            }
        }
    }

    private func spotSubtitle(_ spot: Spot) -> String? {
        guard let here = appState.locationManager.currentLocation else {
            return spot.type == .general ? nil : spot.type.label
        }
        let metres = CLLocation(latitude: spot.latitude, longitude: spot.longitude).distance(from: here)
        return "\(Units.distance(m: metres)) away"
    }

    // MARK: - Bite outlook

    private var outlookSection: some View {
        let planDay = Calendar.current.startOfDay(for: date)
        return VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Bite outlook")
                .padding(.top, DS.Space.s8)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(outlook) { day in
                            dayCell(day, selected: day.date == planDay)
                                .id(day.date)
                        }
                    }
                    .padding(.horizontal, DS.gutter)
                }
                .onChange(of: outlook.map(\.date)) { _, _ in
                    proxy.scrollTo(planDay, anchor: .center)
                }
            }

            if let day = outlook.first(where: { $0.date == planDay }) {
                let isToday = Calendar.current.isDateInToday(day.date)
                VStack(alignment: .leading, spacing: 8) {
                    BiteBars(hourly: day.hourly, windows: day.windows,
                             currentHour: isToday ? Calendar.current.component(.hour, from: .now) : nil,
                             selected: startHour, height: 64, use24: use24)
                    HourAxis(labels: use24 ? ["00:00", "06:00", "12:00", "18:00", "23:00"]
                                           : ["12 am", "6 am", "Noon", "6 pm", "11 pm"])
                    BiteWindowTiles(windows: day.windows, bestHour: day.bestHour,
                                    hour: Calendar.current.component(.hour, from: date),
                                    use24: use24) { setStart(hour: $0) }
                        .padding(.top, 6)
                }
                .padding(.horizontal, DS.gutter)
                .padding(.top, DS.Space.s5)
                SectionFoot("Tap a day to plan it, or a bar to set the start time.")
            }
        }
    }

    private func dayCell(_ day: DayOutlook, selected: Bool) -> some View {
        let cal = Calendar.current
        let label = cal.isDateInToday(day.date) ? "Today" : ForecastFormat.shortDay(day.date)
        return Button {
            pick(day)
        } label: {
            VStack(spacing: 6) {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.dsText2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(ForecastFormat.dayNumber(day.date))
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(.dsText)
                ScoreRing(score: day.peakScore, size: 40)
            }
            .frame(width: dayWidth)
            .padding(.vertical, 10)
            .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
                        .strokeBorder(Color.dsText, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.dim)
        .buttonHaptic(.selection)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ForecastFormat.longDate(day.date)), best bite \(day.peakScore)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Bring

    private var bringSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Bring",
                         detail: checklist.isEmpty ? nil : "\(checklist.filter(\.checked).count) of \(checklist.count)")
                .padding(.top, DS.Space.s8)
            ForEach($checklist) { $item in
                Button {
                    withAnimation(DS.Motion.press) { item.checked.toggle() }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.checked ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(item.checked ? DS.accent : Color.dsText3)
                            .contentTransition(.symbolEffect(.replace))
                        Text(item.name)
                            .font(.body)
                            .strikethrough(item.checked, color: .dsText3)
                            .foregroundStyle(item.checked ? Color.dsText2 : Color.dsText)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 11)
                    .padding(.horizontal, DS.gutter)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.dsRow)
                .buttonHaptic(.toggle)
                .accessibilityAddTraits(item.checked ? .isSelected : [])
                .contextMenu {
                    Button(role: .destructive) {
                        withAnimation(DS.Motion.press) { checklist.removeAll { $0.id == item.id } }
                    } label: {
                        Label("Remove item", systemImage: "trash")
                    }
                }
            }
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(DS.accent)
                TextField("Add an item", text: $newItem)
                    .focused($focus, equals: .item)
                    .submitLabel(.done)
                    .onSubmit(addChecklistItem)
                if !newItem.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button("Add item", action: addChecklistItem)
                        .font(.subheadline.weight(.semibold))
                }
            }
            .padding(.vertical, 11)
            .padding(.horizontal, DS.gutter)
            SectionFoot("Long-press an item to remove it.")
        }
    }

    // MARK: - Save bar

    private var saveBar: some View {
        SheetActionBar(editingTrip == nil ? "Save plan" : "Save changes",
                       systemImage: "calendar.badge.checkmark",
                       disabled: trimmedName.isEmpty || isSaving) {
            savePlan()
        }
    }

    // MARK: - Logic

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Where the bite outlook is computed: the chosen spot or pin, otherwise
    /// your current location.
    private var coordinate: CLLocationCoordinate2D {
        forecastPin
            ?? appState.locationManager.currentLocation?.coordinate
            ?? ForecastStore.fallbackCoordinate
    }

    /// The bite bars' outlined hour is the planned start hour. Tapping a bar
    /// moves the start there; tapping it again leaves it as it is.
    private var startHour: Binding<Int?> {
        Binding(get: { Calendar.current.component(.hour, from: date) },
                set: { hour in if let hour { setStart(hour: hour) } })
    }

    /// The pin picker shows the dropped pin, not a saved spot's position.
    private var pinBinding: Binding<CLLocationCoordinate2D?> {
        Binding(get: { spotId == nil ? forecastPin : nil },
                set: { new in
                    guard let new else { return }
                    spotId = nil
                    forecastPin = new
                })
    }

    private func pick(_ day: DayOutlook) {
        let cal = Calendar.current
        let h = cal.component(.hour, from: date)
        let m = cal.component(.minute, from: date)
        let new = cal.date(bySettingHour: h, minute: m, second: 0, of: day.date) ?? day.date
        withAnimation(reduceMotion ? nil : DS.Motion.softSpring) { date = new }
    }

    private func setStart(hour: Int) {
        let new = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: date) ?? date
        withAnimation(reduceMotion ? nil : DS.Motion.softSpring) { date = new }
    }

    /// Two weeks from today, or a week around the plan's day when it falls
    /// outside that.
    private func recompute() {
        let coord = coordinate
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let planDay = cal.startOfDay(for: date)
        let ahead = cal.dateComponents([.day], from: today, to: planDay).day ?? 0
        let first = (0...13).contains(ahead) ? today : (cal.date(byAdding: .day, value: -3, to: planDay) ?? planDay)
        let count = first == today ? 14 : 7
        outlook = (0..<count).compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: offset, to: first) else { return nil }
            let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
            let f = ForecastEngine.forecast(
                date: noon, coordinate: coord,
                currentPressureHpa: nil, pressureChange6h: nil,
                waterTempC: nil, windSpeedKmh: nil, windDirection: nil,
                species: nil, isInSpawningZone: false)
            return DayOutlook(date: day, hourly: f.hourlyScores,
                              windows: BiteWindows.best(from: f.hourlyScores))
        }
    }

    /// The nearest few saved spots, plus the plan's own spot when editing.
    private func loadSpots() {
        let all = (try? appState.spotRepository.fetchAll()) ?? []
        var nearest = all
        if let here = appState.locationManager.currentLocation {
            nearest.sort {
                CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: here)
                    < CLLocation(latitude: $1.latitude, longitude: $1.longitude).distance(from: here)
            }
        }
        var picked = Array(nearest.prefix(3))
        if let id = spotId, !picked.contains(where: { $0.id == id }),
           let own = all.first(where: { $0.id == id }) {
            picked.insert(own, at: 0)
        }
        spots = picked
    }

    private func addChecklistItem() {
        let n = newItem.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        withAnimation(DS.Motion.spring) {
            checklist.append(Trip.ChecklistItem(name: n))
        }
        newItem = ""
        focus = .item
    }

    /// Populate the sheet from an existing planned trip when editing.
    private func loadEditingTrip() {
        guard let t = editingTrip else { return }
        name = t.name
        date = t.plannedDate ?? t.startDate
        let items = t.decodedChecklist
        if !items.isEmpty { checklist = items }
        spotId = t.spotId
        forecastPin = t.plannedCoordinate
    }

    private func savePlan() {
        guard !isSaving else { return }
        isSaving = true
        // Edit in place when we opened an existing trip, else create a new one.
        var trip = editingTrip ?? Trip(name: trimmedName, startDate: date, plannedDate: date)
        trip.name = trimmedName
        trip.startDate = date
        trip.plannedDate = date
        trip.spotId = spotId
        // The forecast position only. `startPlanned` clears it and tracks
        // live GPS, so it never moves where the session records.
        trip.plannedLatitude = forecastPin?.latitude
        trip.plannedLongitude = forecastPin?.longitude
        trip.checklist = Trip.encodeChecklist(checklist)
        do {
            try appState.tripRepository.save(&trip)
        } catch {
            isSaving = false
            ToastCenter.shared.show("Could not save this plan", style: .error)
            return
        }
        PlanWidget.refresh(appState.tripRepository)
        let saved = trip
        let previousDate = editingTrip?.plannedDate
        Task {
            // An edited plan keeps a reminder that was switched off: no
            // reminder pending while its time was still ahead means it is off.
            if let previousDate, previousDate.addingTimeInterval(-30 * 60) > .now {
                let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
                guard pending.contains(where: { $0.identifier == "session-plan-\(saved.id)" }) else { return }
            }
            await NotificationManager.shared.schedulePlannedSessionAlert(trip: saved)
        }
        ToastCenter.shared.show(editingTrip == nil ? "Session planned" : "Plan updated", icon: "calendar.badge.checkmark")
        onSaved?(trip.id)
        dismiss()
    }

    private static func defaultPlanDate() -> Date {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: .now) ?? .now
        return cal.date(bySettingHour: 6, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}
