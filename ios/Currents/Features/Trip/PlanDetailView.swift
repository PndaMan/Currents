import SwiftUI
import MapKit
import Charts
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
    @State private var forecast: ForecastEngine.ForecastResult?
    @State private var solunar: SolunarEngine.SolunarDay?
    @State private var reminderOn = false
    @State private var showingEdit = false
    @State private var confirmingStart = false
    @State private var confirmingDelete = false
    @State private var showingActive = false
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
        .navigationTitle(trip?.name ?? "Plan")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEdit, onDismiss: load) {
            if let trip { PlanSessionSheet(editingTrip: trip) }
        }
        .confirmationDialog(trip.map { "Start \($0.name) now?" } ?? "Start now?",
                            isPresented: $confirmingStart, titleVisibility: .visible) {
            Button("Start session") { start() }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let trip {
                Text("It is planned for \(LogbookFormat.longDay(plannedDate(trip))), \(LogbookFormat.time(plannedDate(trip))). Starting now records your track and catches from here.")
            }
        }
        .confirmationDialog("Delete this plan?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete plan", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The plan and its checklist are removed.")
        }
        .navigationDestination(isPresented: $showingActive) {
            ActiveSessionView()
        }
        .sensoryFeedback(.selection, trigger: checklist.map(\.checked))
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
                                 subtitle: "Planned for \(LogbookFormat.time(date))")
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

                    Button { setReminder(trip) } label: {
                        Label(reminderOn ? "Reminder on" : "Reminder",
                              systemImage: reminderOn ? "bell.fill" : "bell")
                            .symbolEffect(.bounce, value: reminderOn)
                    }
                    .buttonStyle(ActionTileStyle(.tonal))
                    .accessibilityValue(reminderOn ? "On, 30 minutes before" : "Off")
                }
                .padding(.top, DS.Space.s5)

                if tracker.isTracking {
                    SectionFoot("End the session that is running before you start this one.")
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

                Button(role: .destructive) { confirmingDelete = true } label: {
                    Label("Delete plan", systemImage: "trash")
                        .foregroundStyle(Color.dsScoreSlow)
                }
                .buttonStyle(.dsTonal)
                .padding(.horizontal, DS.gutter)
                .padding(.top, DS.Space.s8)
            }
            .padding(.bottom, DS.Space.s8)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Bite on the day

    @ViewBuilder
    private func biteSection(_ date: Date) -> some View {
        SectionTitle("Bite on the day")
            .padding(.top, DS.Space.s8)
        if let forecast, !forecast.hourlyScores.isEmpty {
            let plannedHour = Calendar.current.component(.hour, from: date)
            let window = plannedHour...(min(23, plannedHour + 3))
            Chart {
                ForEach(forecast.hourlyScores, id: \.hour) { h in
                    BarMark(x: .value("Hour", h.hour), y: .value("Score", h.score), width: .ratio(0.7))
                        .foregroundStyle(window.contains(h.hour) ? DS.scoreColor(h.score) : Color.dsFill2)
                }
            }
            .chartYScale(domain: 0...100)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                    AxisValueLabel {
                        if let h = value.as(Int.self) { Text(SessionBiteChart.hourLabel(h)) }
                    }
                }
            }
            .frame(height: 140)
            .padding(.horizontal, DS.gutter)
            .accessibilityLabel("Bite score by hour on the day")
            .accessibilityValue(bestText(forecast) ?? "")
            SectionFoot("Your planned hours are highlighted. Worked out on your phone, so it works without signal.")

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                let planned = forecast.hourlyScores.filter { window.contains($0.hour) }.map(\.score)
                ConditionTile("Your hours", systemImage: "clock", iconTint: DS.accent,
                              value: planned.max().map { "\($0)" } ?? "\(forecast.score)",
                              footnote: "\(SessionBiteChart.hourLabel(window.lowerBound)) to \(SessionBiteChart.hourLabel(window.upperBound))")
                if let best = forecast.hourlyScores.max(by: { $0.score < $1.score }) {
                    ConditionTile("Best", systemImage: "star.fill", iconTint: .dsScoreFair,
                                  value: "\(best.score)",
                                  footnote: "Around \(SessionBiteChart.hourLabel(best.hour))")
                }
                if let solunar {
                    ConditionTile("Sunrise", systemImage: "sunrise.fill", iconTint: .dsScoreLow,
                                  value: LogbookFormat.time(solunar.sunrise),
                                  footnote: "Sunset \(LogbookFormat.time(solunar.sunset))")
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
        } else if forecastOpens(date) > .now {
            Text("The forecast for \(LogbookFormat.longDay(date)) opens on \(LogbookFormat.longDay(forecastOpens(date))), seven days out.")
                .font(.subheadline)
                .foregroundStyle(.dsText2)
                .padding(.horizontal, DS.gutter)
        } else {
            Text("Turn on location or add a spot to the plan to see the bite on the day.")
                .font(.subheadline)
                .foregroundStyle(.dsText2)
                .padding(.horizontal, DS.gutter)
        }
    }

    private func bestText(_ f: ForecastEngine.ForecastResult) -> String? {
        guard let best = f.hourlyScores.max(by: { $0.score < $1.score }) else { return nil }
        return "Best \(best.score) around \(SessionBiteChart.hourLabel(best.hour))"
    }

    private func forecastOpens(_ date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: -7, to: Calendar.current.startOfDay(for: date)) ?? date
    }

    // MARK: - Checklist

    @ViewBuilder
    private func checklistSection(_ trip: Trip) -> some View {
        SectionTitle("Gear checklist",
                     detail: checklist.isEmpty ? nil : "\(checklist.filter(\.checked).count) of \(checklist.count)")
            .padding(.top, DS.Space.s8)
        VStack(spacing: 0) {
            ForEach($checklist) { $item in
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
                    .padding(.horizontal, DS.gutter)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.dsRow)
                .accessibilityAddTraits(item.checked ? .isSelected : [])
                .contextMenu {
                    Button(role: .destructive) {
                        checklist.removeAll { $0.id == item.id }
                        saveChecklist()
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
                    .focused($addingItem)
                    .submitLabel(.done)
                    .onSubmit(addItem)
                if !newItem.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button("Add item", action: addItem)
                        .font(.subheadline.weight(.semibold))
                }
            }
            .padding(.vertical, 11)
            .padding(.horizontal, DS.gutter)
        }
        SectionFoot("Ticks save as you go. Long-press an item to remove it.")
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
                NavigationLink {
                    SpotDetailView(spot: spot)
                } label: {
                    ArtRow(title: spot.name,
                           subtitle: spot.type == .general ? nil : spot.type.rawValue,
                           chevron: true) {
                        ThumbView(systemImage: spot.type.icon, tint: DS.accent, size: 52)
                    }
                }
                .buttonStyle(.dsRow)
            }
            if let coord {
                Map(initialPosition: .camera(MapCamera(centerCoordinate: coord, distance: 3000))) {
                    Marker(spot?.name ?? "Forecast pin", systemImage: "mappin", coordinate: coord)
                        .tint(DS.accent)
                }
                .mapStyle(.hybrid)
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                .allowsHitTesting(false)
                .accessibilityLabel("Map of the plan's location")
                .padding(.horizontal, DS.gutter)
                .padding(.top, DS.Space.s2)
                DirectionsButton(coordinate: coord, name: spot?.name ?? trip.name)
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, DS.Space.s3)
                if spot == nil {
                    SectionFoot("The session records wherever you are when you start it. The pin only sets the forecast.")
                }
            }
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
        if let coord, date <= Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now {
            forecast = ForecastEngine.forecast(date: date, coordinate: coord,
                                               currentPressureHpa: nil, pressureChange6h: nil,
                                               waterTempC: nil, windSpeedKmh: nil, windDirection: nil,
                                               species: nil, isInSpawningZone: false)
            solunar = SolunarEngine.compute(date: date, coordinate: coord)
        } else {
            forecast = nil
            solunar = coord.map { SolunarEngine.compute(date: date, coordinate: $0) }
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

    /// Schedules the 30-minute reminder. There is no way to switch one off
    /// yet, so when it is on this only confirms it.
    private func setReminder(_ trip: Trip) {
        guard !reminderOn else {
            ToastCenter.shared.show("Reminder on, 30 minutes before", style: .info, icon: "bell.fill")
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

    private func start() {
        guard let trip else { return }
        Haptics.success()
        _ = tracker.startPlanned(trip)
        ToastCenter.shared.show("Session started", icon: "play.fill")
        showingActive = true
    }

    private func delete() {
        guard let trip else { return }
        Haptics.warning()
        try? appState.tripRepository.delete(trip)
        ToastCenter.shared.show("Plan deleted", style: .info, haptic: false, icon: "trash")
        dismiss()
    }
}
