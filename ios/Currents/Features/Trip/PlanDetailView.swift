import SwiftUI
import MapKit
import UserNotifications

/// A planned session: the bite on the day, Start now / Edit / Reminder, the
/// gear checklist, notes, where it is, and Delete plan. Pushed from the
/// Logbook's Plans segment and the Sessions list.
struct PlanDetailView: View {
    let tripId: String
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var trip: Trip?
    @State private var loaded = false
    @State private var spot: Spot?
    @State private var checklist: [Trip.ChecklistItem] = []
    @State private var newItem = ""
    @AppStorage("use24HourTime") private var use24 = true
    @State private var forecast: ForecastEngine.ForecastResult?
    @State private var selectedHour: Int?
    @State private var solunar: SolunarEngine.SolunarDay?
    @State private var reminderOn = false
    @State private var showingEdit = false
    @State private var confirmingStart = false
    @State private var confirmingDelete = false
    @State private var titleShown = false
    @FocusState private var addingItem: Bool

    private var tracker: TripTracker { appState.tripTracker }

    var body: some View {
        Group {
            if let trip {
                content(trip)
            } else if loaded {
                ContentUnavailableView("This plan is gone", systemImage: "calendar.badge.exclamationmark",
                                       description: Text("It was started or deleted. Started plans are in your sessions."))
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .dsScreenBackground()
        .detailScrollEdge()
        .pfTrackScroll($titleShown, threshold: 60)
        .pfScrollTitle(trip?.name ?? "Plan", shown: titleShown)
        .sheet(isPresented: $showingEdit, onDismiss: load) {
            if let trip { PlanSessionSheet(editingTrip: trip) }
        }
        .confirmationDialog(trip.map { "Start \($0.name) now?" } ?? "Start now?",
                            isPresented: $confirmingStart, titleVisibility: .visible) {
            Button("Start session") { start() }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let trip {
                Text("It is planned for \(LogbookFormat.longDay(plannedDate(trip))), \(ForecastFormat.time(plannedDate(trip), use24: use24)).")
            }
        }
        .confirmationDialog("Delete this plan?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete plan", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The plan and its checklist are removed.")
        }
        .task(id: tripId) { load() }
    }

    // MARK: - Content

    private func plannedDate(_ trip: Trip) -> Date { trip.plannedDate ?? trip.startDate }

    private func content(_ trip: Trip) -> some View {
        let date = plannedDate(trip)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    DetailHeader(over: LogbookFormat.longDay(date),
                                 title: trip.name,
                                 subtitle: "Planned for \(ForecastFormat.time(date, use24: use24))")
                    if let forecast, let peak = forecast.hourlyScores.map(\.score).max() {
                        ScoreRing(score: peak, size: 64, caption: "best")
                            .padding(.trailing, DS.gutter)
                            .padding(.top, DS.Space.s2)
                    }
                }

                ActionTriple {
                    Button { confirmingStart = true } label: {
                        Label("Start now", systemImage: "play.fill")
                    }
                    .buttonStyle(ActionTileStyle(.primary))
                    .disabled(tracker.isTracking)

                    Button { showingEdit = true } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .buttonStyle(ActionTileStyle(.tonal))

                    Button { toggleReminder(trip) } label: {
                        Label(reminderOn ? "Reminder on" : "Reminder",
                              systemImage: reminderOn ? "bell.fill" : "bell")
                            .symbolEffect(.bounce, value: reminderOn)
                    }
                    .buttonStyle(ActionTileStyle(.tonal))
                    .accessibilityValue(reminderOn ? "On, 30 minutes before" : "Off")
                    .accessibilityAddTraits(reminderOn ? .isSelected : [])
                }
                .padding(.top, DS.Space.s5)

                if tracker.isTracking {
                    SectionFootnote("End the session that is running before you start this one.")
                }

                biteSection(date)

                checklistSection(trip)

                if let notes = trip.notes, !notes.isEmpty {
                    SectionTitle("Notes")
                        .padding(.top, DS.Space.s8)
                    Text(notes)
                        .font(.body)
                        .foregroundStyle(.dsText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DS.gutter)
                }

                whereSection(trip)

                DangerButton(title: "Delete plan", systemImage: "trash") { confirmingDelete = true }
                    .padding(.top, DS.Space.s8)
            }
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Bite on the day

    @ViewBuilder
    private func biteSection(_ date: Date) -> some View {
        SectionTitle("Bite on the day")
            .padding(.top, DS.Space.s8)
        if let forecast, !forecast.hourlyScores.isEmpty {
            let cal = Calendar.current
            let plannedHour = cal.component(.hour, from: date)
            let window = plannedHour...(min(23, plannedHour + 3))
            let windows = BiteWindows.best(from: forecast.hourlyScores)
            let shownHour = selectedHour ?? plannedHour
            let bestHour = forecast.hourlyScores.max { $0.score < $1.score }?.hour ?? plannedHour
            VStack(alignment: .leading, spacing: 8) {
                hourReadout(forecast, hour: shownHour, planned: window.contains(shownHour))
                BiteBars(hourly: forecast.hourlyScores, windows: windows,
                         currentHour: cal.isDateInToday(date) ? cal.component(.hour, from: .now) : nil,
                         selected: Binding(get: { shownHour }, set: { selectedHour = $0 }),
                         height: 72, use24: use24)
                HourAxis(labels: use24 ? ["00:00", "06:00", "12:00", "18:00", "23:00"]
                                       : ["12 am", "6 am", "Noon", "6 pm", "11 pm"])
                BiteWindowTiles(windows: windows, bestHour: bestHour, hour: plannedHour, use24: use24)
                    .padding(.top, 6)
            }
            .padding(.horizontal, DS.gutter)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                let planned = forecast.hourlyScores.filter { window.contains($0.hour) }.map(\.score)
                ConditionTile("Your hours", systemImage: "clock", iconTint: DS.accent,
                              value: planned.max().map { "\($0)" } ?? "\(forecast.score)",
                              footnote: "\(ForecastFormat.hour(window.lowerBound, use24: use24)) to \(ForecastFormat.hour(window.upperBound + 1, use24: use24))")
                if let solunar {
                    ConditionTile("Sunrise", systemImage: "sunrise.fill", iconTint: .dsScoreLow,
                                  value: ForecastFormat.time(solunar.sunrise, use24: use24),
                                  footnote: "Sunset \(ForecastFormat.time(solunar.sunset, use24: use24))")
                    ConditionTile("Moon", systemImage: "moon.fill", iconTint: .dsScoreFair,
                                  value: "\(Int((solunar.moonIllumination * 100).rounded()))", unit: "%",
                                  footnote: CatchDetailView.sentenceCase(solunar.moonPhase.displayName)) {
                        Image(systemName: solunar.moonPhase.symbolName)
                            .font(.title)
                            .foregroundStyle(.dsText2)
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(.horizontal, DS.gutter)
            .padding(.top, DS.Space.s4)
        } else {
            ArtRow(title: "No forecast yet", subtitle: "Turn on location or edit the plan to pick a place") {
                ThumbView(systemImage: "location.slash", tint: DS.accent, size: 44)
            }
        }
    }

    /// The tapped hour (or the planned start) with its score, above the bars.
    private func hourReadout(_ f: ForecastEngine.ForecastResult, hour: Int, planned: Bool) -> some View {
        let score = f.hourlyScores.first { $0.hour == hour }?.score ?? f.score
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(ForecastFormat.hour(hour, use24: use24))
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(.dsText)
            Text(planned ? "Your hours" : ForecastFormat.windowName(hour))
                .font(.subheadline)
                .foregroundStyle(.dsText2)
            Spacer(minLength: 0)
            Text("\(score)")
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(DS.scoreInk(score))
                .contentTransition(.numericText(value: Double(score)))
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Checklist

    @ViewBuilder
    private func checklistSection(_ trip: Trip) -> some View {
        SectionTitle("Gear checklist",
                     detail: checklist.isEmpty ? nil : "\(checklist.filter(\.checked).count) of \(checklist.count)")
            .padding(.top, DS.Space.s8)
        VStack(spacing: 0) {
            ForEach($checklist) { $item in
                HStack(spacing: 0) {
                    Button {
                        withAnimation(DS.Motion.press) { item.checked.toggle() }
                        saveChecklist()
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
                        .padding(.leading, DS.gutter)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.dsRow)
                    .buttonHaptic(.toggle)
                    .accessibilityAddTraits(item.checked ? .isSelected : [])

                    Button {
                        let id = item.id
                        withAnimation(DS.Motion.press) { checklist.removeAll { $0.id == id } }
                        saveChecklist()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.dsText3)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.dim)
                    .accessibilityLabel("Remove \(item.name)")
                    .padding(.trailing, DS.gutter - 12)
                }
            }
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(DS.accent)
                TextField("Add an item", text: $newItem)
                    .focused($addingItem)
                    .submitLabel(.done)
                    .onSubmit(addItem)
                if !newItem.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button("Add item", action: addItem)
                        .buttonStyle(TonalButtonStyle(fullWidth: false))
                }
            }
            .padding(.vertical, 11)
            .padding(.horizontal, DS.gutter)
        }
    }

    // MARK: - Where

    @ViewBuilder
    private func whereSection(_ trip: Trip) -> some View {
        let coord = spot.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            ?? trip.plannedCoordinate
        if spot != nil || coord != nil {
            SectionTitle(spot == nil ? "Forecast pin" : "Spot")
                .padding(.top, DS.Space.s8)
            if let spot {
                Button { appState.pendingDeepLink = MapLink.spot(spot) } label: {
                    ArtRow(title: spot.name,
                           subtitle: spot.type == .general ? nil : spot.type.label,
                           chevron: true) {
                        PlaceSnapshotThumb(spot: spot, size: 52)
                    }
                }
                .buttonStyle(.dsRow)
            }
            if let coord {
                locationMap(coord)
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, DS.Space.s2)
                DirectionsButton(coordinate: coord, name: spot?.name ?? trip.name)
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, DS.Space.s3)
                if spot == nil {
                    SectionFootnote("The session tracks wherever you are when you start it.")
                }
            }
        }
    }

    /// The plan's place on a map. Tapping it opens the place on the Explore
    /// map in its sheet: the spot, or a forecast pin as a dropped pin.
    @ViewBuilder
    private func locationMap(_ coord: CLLocationCoordinate2D) -> some View {
        let map = Map(initialPosition: .camera(MapCamera(centerCoordinate: coord, distance: 3000))) {
            Marker(spot?.name ?? "Forecast pin", systemImage: "mappin", coordinate: coord)
                .tint(DS.accent)
        }
        .mapStyle(.hybrid)
        .frame(height: 170)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .allowsHitTesting(false)

        if let spot {
            Button { appState.pendingDeepLink = MapLink.spot(spot) } label: { map }
                .buttonStyle(.dim)
                .accessibilityLabel("Show \(spot.name) on the map")
        } else {
            Button { appState.pendingDeepLink = MapLink.point(coord, title: "Forecast pin") } label: { map }
                .buttonStyle(.dim)
                .accessibilityLabel("Show the forecast pin on the map")
        }
    }

    // MARK: - Actions

    private func load() {
        trip = try? appState.tripRepository.fetch(tripId)
        loaded = true
        guard let trip, trip.isPlanned else {
            // Started or deleted elsewhere.
            if trip?.isPlanned == false { self.trip = nil }
            return
        }
        checklist = trip.decodedChecklist
        spot = trip.spotId.flatMap { id in
            (try? appState.spotRepository.fetchAll())?.first { $0.id == id }
        }
        let date = plannedDate(trip)
        let coord = spot.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            ?? trip.plannedCoordinate
            ?? appState.locationManager.currentLocation?.coordinate
        if let coord {
            forecast = ForecastEngine.forecast(date: date, coordinate: coord,
                                               currentPressureHpa: nil, pressureChange6h: nil,
                                               waterTempC: nil, windSpeedKmh: nil, windDirection: nil,
                                               species: nil, isInSpawningZone: false)
            solunar = SolunarEngine.compute(date: date, coordinate: coord)
        } else {
            forecast = nil
            solunar = nil
        }
        let id = "session-plan-\(trip.id)"
        Task {
            let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
            reminderOn = pending.contains { $0.identifier == id }
        }
    }

    private func saveChecklist() {
        guard var t = trip else { return }
        t.checklist = Trip.encodeChecklist(checklist)
        try? appState.tripRepository.save(&t)
        trip = t
    }

    private func addItem() {
        let name = newItem.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        withAnimation(DS.Motion.spring) {
            checklist.append(Trip.ChecklistItem(name: name))
        }
        newItem = ""
        saveChecklist()
        addingItem = true
    }

    /// Turns the 30-minute reminder on, or off when it is already on.
    private func toggleReminder(_ trip: Trip) {
        guard !reminderOn else {
            NotificationManager.shared.cancelPlannedSessionAlert(tripId: trip.id)
            withAnimation(DS.Motion.spring) { reminderOn = false }
            ToastCenter.shared.show("Reminder off", style: .info, icon: "bell.slash")
            return
        }
        guard plannedDate(trip).addingTimeInterval(-30 * 60) > .now else {
            ToastCenter.shared.show("This plan starts too soon for a reminder", style: .info, icon: "bell.slash")
            return
        }
        Task {
            await NotificationManager.shared.schedulePlannedSessionAlert(trip: trip)
            let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
            let on = pending.contains { $0.identifier == "session-plan-\(trip.id)" }
            withAnimation(DS.Motion.spring) { reminderOn = on }
            if on {
                ToastCenter.shared.show("Reminder set for 30 minutes before", icon: "bell.fill")
            } else {
                ToastCenter.shared.show("Allow notifications in Settings to get reminders", style: .info, icon: "bell.slash")
            }
        }
    }

    /// Starts the plan, leaves this page (it is a session now, not a plan)
    /// and opens the live session on Explore, as the launch prompt does.
    private func start() {
        guard let trip else { return }
        Haptics.success()
        _ = tracker.startPlanned(trip)
        ToastCenter.shared.show("Session started", icon: "play.fill")
        dismiss()
        appState.pendingDeepLink = URL(string: "currents://session")
    }

    private func delete() {
        guard let trip else { return }
        do {
            try appState.tripRepository.delete(trip)
        } catch {
            ToastCenter.shared.show("Could not delete this plan", style: .error)
            return
        }
        Haptics.warning()
        NotificationManager.shared.cancelPlannedSessionAlert(tripId: trip.id)
        PlanWidget.refresh(appState.tripRepository)
        ToastCenter.shared.show("Plan deleted", style: .info, haptic: false, icon: "trash")
        dismiss()
    }
}
