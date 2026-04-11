import SwiftUI
import MapKit

struct MapTab: View {
    @Environment(AppState.self) private var appState
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var spots: [Spot] = []
    @State private var catches: [CatchDetail] = []
    @State private var catchCounts: [String: Int] = [:]
    @State private var showingAddSpot = false
    @State private var selectedSpot: Spot?
    @State private var mapStyle: MapStyleOption = .imagery
    @State private var showCatchPins = true
    @State private var showingSpeciesBrowser = false
    @State private var showingForecast = false
    @State private var showingWeather = false
    @State private var weather: WeatherService.WeatherData?

    enum MapStyleOption: String, CaseIterable {
        case standard = "Standard"
        case imagery = "Satellite"
        case hybrid = "Hybrid"
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topTrailing) {
                Map(position: $position) {
                    UserAnnotation()

                    // Spot pins
                    ForEach(spots) { spot in
                        Annotation(spot.name, coordinate: CLLocationCoordinate2D(
                            latitude: spot.latitude,
                            longitude: spot.longitude
                        )) {
                            SpotPin(
                                spot: spot,
                                catchCount: catchCounts[spot.id] ?? 0,
                                isSelected: selectedSpot?.id == spot.id
                            )
                            .onTapGesture {
                                selectedSpot = spot
                            }
                        }
                    }

                    // Catch location pins (individual catches without spots)
                    if showCatchPins {
                        ForEach(catches.filter { $0.catchRecord.spotId == nil }, id: \.catchRecord.id) { detail in
                            Annotation(
                                detail.species?.commonName ?? "Catch",
                                coordinate: CLLocationCoordinate2D(
                                    latitude: detail.catchRecord.latitude,
                                    longitude: detail.catchRecord.longitude
                                )
                            ) {
                                CatchPin(detail: detail)
                            }
                        }
                    }
                }
                .mapStyle(activeMapStyle)
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                    MapScaleView()
                }

                // Right side control buttons
                VStack(spacing: 10) {
                    // Map style picker
                    Menu {
                        ForEach(MapStyleOption.allCases, id: \.self) { style in
                            Button {
                                mapStyle = style
                            } label: {
                                Label(style.rawValue, systemImage: mapStyleIcon(style))
                            }
                        }
                    } label: {
                        mapButton(icon: "map.fill")
                    }

                    // Add spot
                    Button {
                        showingAddSpot = true
                    } label: {
                        mapButton(icon: "mappin.and.ellipse")
                    }

                    // Toggle catch pins
                    Button {
                        showCatchPins.toggle()
                    } label: {
                        mapButton(icon: showCatchPins ? "fish.fill" : "fish")
                    }

                    // Species browser
                    Button {
                        showingSpeciesBrowser = true
                    } label: {
                        mapButton(icon: "book.fill")
                    }

                    // Forecast
                    Button {
                        showingForecast = true
                    } label: {
                        mapButton(icon: "cloud.sun.fill")
                    }
                }
                .padding(.top, 60)
                .padding(.trailing, 12)

                // Bottom bar
                VStack {
                    Spacer()

                    HStack(spacing: 12) {
                        // Weather quick view
                        if let weather {
                            HStack(spacing: 6) {
                                WeatherIcon(condition: weather.condition)
                                Text("\(Int(weather.temperatureC))°")
                                    .font(.subheadline.bold())
                                    .monospacedDigit()
                                Text("\(Int(weather.windSpeedKmh))km/h")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if !spots.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundStyle(.blue)
                                Text("\(spots.count) spots")
                                    .font(.subheadline.bold())
                                let totalCatches = catchCounts.values.reduce(0, +)
                                Text("\(totalCatches) catches")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
            .sheet(item: $selectedSpot) { spot in
                SpotDetailSheet(spot: spot)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(.ultraThinMaterial)
            }
            .sheet(isPresented: $showingAddSpot) {
                AddSpotSheet()
                    .presentationDetents([.medium])
                    .presentationBackground(.ultraThinMaterial)
            }
            .sheet(isPresented: $showingSpeciesBrowser) {
                NavigationStack {
                    SpeciesBrowserView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showingSpeciesBrowser = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $showingForecast) {
                ForecastTab()
            }
            .task {
                await loadData()
            }
        }
    }

    @ViewBuilder
    private func mapButton(icon: String) -> some View {
        Image(systemName: icon)
            .font(.title3)
            .frame(width: 44, height: 44)
            .background(.ultraThinMaterial)
            .clipShape(Circle())
    }

    private var activeMapStyle: MapStyle {
        switch mapStyle {
        case .standard: .standard(elevation: .realistic)
        case .imagery: .imagery(elevation: .realistic)
        case .hybrid: .hybrid(elevation: .realistic)
        }
    }

    private func mapStyleIcon(_ style: MapStyleOption) -> String {
        switch style {
        case .standard: "map"
        case .imagery: "globe.americas.fill"
        case .hybrid: "square.split.2x2"
        }
    }

    private func loadData() async {
        spots = (try? appState.spotRepository.fetchAll()) ?? []
        catches = (try? appState.catchRepository.fetchAll(limit: 200)) ?? []

        for spot in spots {
            let spotCatches = (try? appState.catchRepository.fetchForSpot(spot.id)) ?? []
            catchCounts[spot.id] = spotCatches.count
        }

        // Fetch weather for map overlay
        let coord = appState.locationManager.currentLocation?.coordinate ??
            CLLocationCoordinate2D(latitude: -33.9, longitude: 18.4)
        weather = await WeatherService.shared.current(for: coord)
    }
}

// MARK: - Catch Pin (for individual catches on map)

struct CatchPin: View {
    let detail: CatchDetail

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(.green)
                    .frame(width: 28, height: 28)
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                Image(systemName: "fish.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
            }
            if let name = detail.species?.commonName {
                Text(name)
                    .font(.system(size: 9).bold())
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }
        }
    }
}

// MARK: - Spot Pin

struct SpotPin: View {
    let spot: Spot
    let catchCount: Int
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(isSelected ? .blue : .white)
                    .frame(width: 40, height: 40)
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)

                if spot.isPrivate {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(isSelected ? .white : .blue)
                } else {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(isSelected ? .white : .blue)
                }
            }
            if catchCount > 0 {
                Text("\(catchCount)")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .offset(y: -4)
            }
            Text(spot.name)
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
        }
    }
}

// MARK: - Spot Detail Sheet

struct SpotDetailSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let spot: Spot
    @State private var catches: [CatchDetail] = []
    @State private var showingDeleteConfirm = false
    @State private var showingEditName = false
    @State private var editedName = ""
    @State private var editedNotes = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CurrentsTheme.paddingM) {
                    // Map preview
                    Map(initialPosition: .camera(.init(
                        centerCoordinate: CLLocationCoordinate2D(
                            latitude: spot.latitude, longitude: spot.longitude
                        ),
                        distance: 1500
                    ))) {
                        Annotation(spot.name, coordinate: CLLocationCoordinate2D(
                            latitude: spot.latitude, longitude: spot.longitude
                        )) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title)
                                .foregroundStyle(.blue)
                        }
                    }
                    .mapStyle(.hybrid)
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .allowsHitTesting(false)

                    HStack {
                        VStack(alignment: .leading) {
                            Text(spot.name)
                                .font(.title2.bold())
                            Text(String(format: "%.4f, %.4f", spot.latitude, spot.longitude))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if spot.isPrivate {
                            Label("Private", systemImage: "lock.fill")
                                .font(.caption)
                                .glassPill()
                        }
                    }

                    if !catches.isEmpty {
                        HStack(spacing: 12) {
                            StatCard(value: "\(catches.count)", label: "Catches", icon: "fish.fill")
                            let species = Set(catches.compactMap { $0.species?.commonName }).count
                            StatCard(value: "\(species)", label: "Species", icon: "leaf.fill")
                            if let best = catches.max(by: { ($0.catchRecord.weightKg ?? 0) < ($1.catchRecord.weightKg ?? 0) }),
                               let weight = best.catchRecord.weightKg {
                                StatCard(value: String(format: "%.1fkg", weight), label: "Best", icon: "trophy.fill")
                            }
                        }
                    }

                    if let notes = spot.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    // Actions
                    HStack(spacing: 12) {
                        Button {
                            editedName = spot.name
                            editedNotes = spot.notes ?? ""
                            showingEditName = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button(role: .destructive) {
                            showingDeleteConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    if !catches.isEmpty {
                        Text("Catches Here")
                            .font(.headline)
                        ForEach(catches, id: \.catchRecord.id) { detail in
                            CatchRow(detail: detail)
                        }
                    } else {
                        ContentUnavailableView(
                            "No catches yet",
                            systemImage: "fish",
                            description: Text("Log your first catch at this spot")
                        )
                    }
                }
                .padding()
            }
        }
        .task {
            catches = (try? appState.catchRepository.fetchForSpot(spot.id)) ?? []
        }
        .alert("Delete Spot?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                try? appState.spotRepository.delete(spot)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the spot but keep any catches logged here.")
        }
        .alert("Edit Spot", isPresented: $showingEditName) {
            TextField("Name", text: $editedName)
            TextField("Notes", text: $editedNotes)
            Button("Save") {
                var updated = spot
                updated.name = editedName
                updated.notes = editedNotes.isEmpty ? nil : editedNotes
                try? appState.spotRepository.save(&updated)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Add Spot Sheet

struct AddSpotSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var notes = ""
    @State private var isPrivate = true
    @State private var spotType: SpotType = .general
    @State private var usePin = false
    @State private var pinCoordinate: CLLocationCoordinate2D?
    @State private var showingLocationPicker = false

    enum SpotType: String, CaseIterable {
        case general = "General"
        case structure = "Structure"
        case dropoff = "Drop-off"
        case weedbed = "Weed Bed"
        case point = "Point"
        case inlet = "Inlet/Outlet"
        case dock = "Dock/Pier"
        case reef = "Reef"
        case channel = "Channel"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Spot Name", text: $name)
                    Picker("Type", selection: $spotType) {
                        ForEach(SpotType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Location") {
                    Toggle("Drop pin on map", isOn: $usePin)

                    if usePin {
                        if let coord = pinCoordinate {
                            HStack {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundStyle(.red)
                                Text(String(format: "%.4f, %.4f", coord.latitude, coord.longitude))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Change") {
                                    showingLocationPicker = true
                                }
                                .font(.caption)
                            }
                        } else {
                            Button {
                                showingLocationPicker = true
                            } label: {
                                Label("Choose location on map", systemImage: "map")
                            }
                        }
                    } else {
                        if let loc = appState.locationManager.currentLocation {
                            HStack {
                                Image(systemName: "location.fill")
                                    .foregroundStyle(.blue)
                                Text(String(format: "%.4f, %.4f", loc.coordinate.latitude, loc.coordinate.longitude))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Label("Waiting for location...", systemImage: "location.slash")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Toggle("Private Spot", isOn: $isPrivate)
                } footer: {
                    Text("Private spots are never shared.")
                }
            }
            .navigationTitle("New Spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveSpot() }
                        .disabled(name.isEmpty)
                        .bold()
                }
            }
            .sheet(isPresented: $showingLocationPicker) {
                LocationPickerSheet(coordinate: $pinCoordinate)
            }
        }
    }

    private func saveSpot() {
        let lat: Double
        let lon: Double

        if usePin, let coord = pinCoordinate {
            lat = coord.latitude
            lon = coord.longitude
        } else if let location = appState.locationManager.currentLocation {
            lat = location.coordinate.latitude
            lon = location.coordinate.longitude
        } else {
            return
        }

        let fullNotes = spotType == .general ? notes : "[\(spotType.rawValue)] \(notes)"
        var spot = Spot(
            name: name,
            latitude: lat,
            longitude: lon,
            notes: fullNotes.isEmpty ? nil : fullNotes,
            isPrivate: isPrivate
        )
        try? appState.spotRepository.save(&spot)
        dismiss()
    }
}
