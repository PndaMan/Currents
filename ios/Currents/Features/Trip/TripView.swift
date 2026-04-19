import SwiftUI
import CoreLocation

struct TripNavID: Hashable {
    let id: String
}

struct TripListView: View {
    @Environment(AppState.self) private var appState
    @State private var trips: [Trip] = []
    @State private var showingNewTrip = false
    @State private var activeTrip: Trip?

    var body: some View {
        Group {
            if trips.isEmpty && activeTrip == nil {
                ContentUnavailableView(
                    "No Trips Yet",
                    systemImage: "tent.fill",
                    description: Text("Start a trip to group your catches together")
                )
            } else {
                List {
                    // Active trip banner
                    if let active = activeTrip {
                        Section("Active Trip") {
                            ActiveTripBanner(trip: active, onEnd: {
                                endTrip(active)
                            })
                        }
                    }

                    // Past trips
                    let pastTrips = trips.filter { $0.endDate != nil }
                    if !pastTrips.isEmpty {
                        Section("Past Trips") {
                            ForEach(pastTrips) { trip in
                                NavigationLink {
                                    TripTimelineView(trip: trip)
                                } label: {
                                    TripRow(trip: trip, appState: appState)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        try? appState.tripRepository.delete(trip)
                                        Task { await refresh() }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Trips")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewTrip = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewTrip) {
            NewTripSheet()
                .presentationBackground(.ultraThinMaterial)
        }
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private func refresh() async {
        trips = (try? appState.tripRepository.fetchAll()) ?? []
        activeTrip = trips.first(where: { $0.endDate == nil })
    }

    private func endTrip(_ trip: Trip) {
        var updated = trip
        updated.endDate = .now
        try? appState.tripRepository.save(&updated)
        Task { await refresh() }
    }
}

// MARK: - Active Trip Banner

struct ActiveTripBanner: View {
    let trip: Trip
    let onEnd: () -> Void
    @State private var elapsed: TimeInterval = 0
    @State private var timer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "tent.fill")
                    .foregroundStyle(CurrentsTheme.accent)
                Text(trip.name)
                    .font(.headline)
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(CurrentsTheme.accent)
                        .frame(width: 6, height: 6)
                    Text("LIVE")
                        .font(.caption2.bold())
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(CurrentsTheme.accent.opacity(0.2))
                .foregroundStyle(CurrentsTheme.accent)
                .clipShape(Capsule())
            }

            // Live timer
            HStack(spacing: 16) {
                timerUnit(value: Int(elapsed) / 3600, label: "hr")
                timerUnit(value: (Int(elapsed) % 3600) / 60, label: "min")
                timerUnit(value: Int(elapsed) % 60, label: "sec")
            }
            .frame(maxWidth: .infinity)

            if let conditions = trip.weatherConditions {
                Label(conditions, systemImage: "cloud.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(role: .destructive) {
                onEnd()
            } label: {
                Label("End Trip", systemImage: "stop.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .onAppear {
            elapsed = Date.now.timeIntervalSince(trip.startDate)
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                elapsed = Date.now.timeIntervalSince(trip.startDate)
            }
        }
        .onDisappear { timer?.invalidate() }
    }

    private func timerUnit(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title.bold().monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Trip Row

struct TripRow: View {
    let trip: Trip
    let appState: AppState
    @State private var catchCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(trip.name)
                .font(.headline)

            HStack(spacing: 12) {
                Label(trip.startDate.formatted(.dateTime.month().day()), systemImage: "calendar")
                if let end = trip.endDate {
                    let duration = end.timeIntervalSince(trip.startDate)
                    let hours = Int(duration / 3600)
                    Text("\(hours)h")
                        .foregroundStyle(.secondary)
                }
                Label("\(catchCount) catches", systemImage: "fish.fill")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let notes = trip.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .task {
            catchCount = (try? appState.tripRepository.catchCount(tripId: trip.id)) ?? 0
        }
    }
}

// MARK: - Trip Detail View

struct TripDetailView: View {
    @Environment(AppState.self) private var appState
    let trip: Trip
    @State private var catches: [CatchDetail] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CurrentsTheme.paddingM) {
                // Trip header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(trip.name)
                                .font(.title2.bold())
                            Text(trip.startDate.formatted(.dateTime.weekday(.wide).month().day().year()))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let end = trip.endDate {
                            let duration = end.timeIntervalSince(trip.startDate)
                            let hours = Int(duration / 3600)
                            VStack {
                                Text("\(hours)")
                                    .font(.title.bold())
                                Text("hours")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let conditions = trip.weatherConditions {
                        Label(conditions, systemImage: "cloud.fill")
                            .font(.caption)
                            .glassPill()
                    }
                }
                .glassCard()

                // Trip stats
                if !catches.isEmpty {
                    HStack(spacing: 12) {
                        StatCard(value: "\(catches.count)", label: "Catches", icon: "fish.fill")
                        let species = Set(catches.compactMap { $0.species?.id }).count
                        StatCard(value: "\(species)", label: "Species", icon: "leaf.fill")
                        let released = catches.filter { $0.catchRecord.released }.count
                        StatCard(value: "\(released)", label: "Released", icon: "arrow.uturn.backward")
                    }
                }

                // Notes
                if let notes = trip.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notes")
                            .font(.headline)
                        Text(notes)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .glassCard()
                }

                // Catches
                if !catches.isEmpty {
                    Text("Catches")
                        .font(.headline)

                    ForEach(catches, id: \.catchRecord.id) { detail in
                        CatchRow(detail: detail)
                            .padding(.vertical, 4)
                        Divider()
                    }
                } else {
                    ContentUnavailableView(
                        "No catches on this trip",
                        systemImage: "fish",
                        description: Text("Catches logged during this trip will appear here")
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Trip")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            catches = (try? appState.tripRepository.catches(tripId: trip.id)) ?? []
        }
    }
}

// MARK: - New Trip Sheet

struct NewTripSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var notes = ""
    @State private var selectedSpotId: String?
    @State private var weatherConditions = ""
    @State private var allSpots: [Spot] = []
    @State private var isLoadingWeather = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Trip Info") {
                    TextField("Trip Name (e.g. Saturday Bass Session)", text: $name)
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Location") {
                    Picker("Spot", selection: $selectedSpotId) {
                        Text("None").tag(nil as String?)
                        ForEach(allSpots) { spot in
                            Text(spot.name).tag(spot.id as String?)
                        }
                    }
                }

                Section {
                    if isLoadingWeather {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Fetching weather...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        TextField("Weather conditions", text: $weatherConditions)
                    }
                } header: {
                    Text("Conditions")
                } footer: {
                    Text("Auto-filled from current weather. You can edit.")
                }
            }
            .navigationTitle("New Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start Trip") { saveTrip() }
                        .disabled(name.isEmpty)
                }
            }
            .task {
                allSpots = (try? appState.spotRepository.fetchAll()) ?? []

                // Auto-fill name
                if name.isEmpty {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "EEEE d MMM"
                    name = "\(formatter.string(from: .now)) Session"
                }

                // Auto-fill weather (best effort)
                let coord = appState.locationManager.currentLocation?.coordinate
                if let coord,
                   let w = await WeatherService.shared.current(for: coord) {
                    weatherConditions = "\(w.condition.capitalized), \(Int(w.temperatureC))°C, \(Int(w.windSpeedKmh))km/h wind"
                }
                isLoadingWeather = false
            }
        }
    }

    private func saveTrip() {
        var trip = Trip(
            name: name,
            startDate: .now,
            spotId: selectedSpotId,
            notes: notes.isEmpty ? nil : notes,
            weatherConditions: weatherConditions.isEmpty ? nil : weatherConditions
        )
        try? appState.tripRepository.save(&trip)
        dismiss()
    }
}
