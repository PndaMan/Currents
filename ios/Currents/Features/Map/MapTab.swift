import SwiftUI
import MapKit

struct MapTab: View {
    @Environment(AppState.self) private var appState
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var spots: [Spot] = []
    @State private var catchCounts: [String: Int] = [:] // spotId -> count
    @State private var showingAddSpot = false
    @State private var selectedSpot: Spot?
    @State private var mapStyle: MapStyleOption = .imagery
    @State private var longPressLocation: CLLocationCoordinate2D?
    @State private var showingLongPressAdd = false

    enum MapStyleOption: String, CaseIterable {
        case standard = "Standard"
        case imagery = "Satellite"
        case hybrid = "Hybrid"
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Map(position: $position) {
                UserAnnotation()

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
            }
            .mapStyle(activeMapStyle)
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .onMapCameraChange { context in
                // Could be used for loading spots in viewport
            }

            // Controls overlay
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
                    Image(systemName: "map.fill")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }

                // Add spot
                Button {
                    showingAddSpot = true
                } label: {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }

                // Navigate to species browser
                NavigationLink {
                    SpeciesBrowserView()
                } label: {
                    Image(systemName: "fish.fill")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }

                // Quick forecast
                NavigationLink {
                    ForecastTab()
                } label: {
                    Image(systemName: "cloud.sun.fill")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
            }
            .padding(.top, 60)
            .padding(.trailing, 12)

            // Bottom info bar
            VStack {
                Spacer()
                if !spots.isEmpty {
                    HStack {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(.blue)
                        Text("\(spots.count) spots")
                            .font(.subheadline.bold())
                        Spacer()
                        let totalCatches = catchCounts.values.reduce(0, +)
                        Text("\(totalCatches) catches")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
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
        .task {
            await loadSpots()
        }
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

    private func loadSpots() async {
        spots = (try? appState.spotRepository.fetchAll()) ?? []
        // Load catch counts per spot
        for spot in spots {
            let catches = (try? appState.catchRepository.fetchForSpot(spot.id)) ?? []
            catchCounts[spot.id] = catches.count
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
            // Catch count badge
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
            // Label
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
    let spot: Spot
    @State private var catches: [CatchDetail] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CurrentsTheme.paddingM) {
                    // Location info
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

                    // Quick stats
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

                    // Catches at this spot
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

                Section {
                    Toggle("Private Spot", isOn: $isPrivate)
                } footer: {
                    Text("Private spots are never shared. Public spots are obfuscated by your privacy radius when shared.")
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
                }
            }
        }
    }

    private func saveSpot() {
        guard let location = appState.locationManager.currentLocation else { return }
        let fullNotes = spotType == .general ? notes : "[\(spotType.rawValue)] \(notes)"
        var spot = Spot(
            name: name,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            notes: fullNotes.isEmpty ? nil : fullNotes,
            isPrivate: isPrivate
        )
        try? appState.spotRepository.save(&spot)
        dismiss()
    }
}
