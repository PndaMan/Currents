import SwiftUI
import MapKit

struct MapTab: View {
    @Environment(AppState.self) private var appState
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var spots: [Spot] = []
    @State private var showingAddSpot = false
    @State private var selectedSpot: Spot?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Map(position: $position) {
                UserAnnotation()

                ForEach(spots) { spot in
                    Annotation(spot.name, coordinate: CLLocationCoordinate2D(
                        latitude: spot.latitude,
                        longitude: spot.longitude
                    )) {
                        SpotPin(spot: spot, isSelected: selectedSpot?.id == spot.id)
                            .onTapGesture {
                                selectedSpot = spot
                            }
                    }
                }
            }
            .mapStyle(.imagery(elevation: .realistic))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }

            // Floating action buttons
            VStack(spacing: 12) {
                Button {
                    showingAddSpot = true
                } label: {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.title3)
                        .frame(width: 48, height: 48)
                }
                .glassPill()
            }
            .padding()
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

    private func loadSpots() async {
        spots = (try? appState.spotRepository.fetchAll()) ?? []
    }
}

// MARK: - Spot Pin

struct SpotPin: View {
    let spot: Spot
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: spot.isPrivate ? "lock.fill" : "mappin.circle.fill")
                .font(.title2)
                .foregroundStyle(isSelected ? .blue : .white)
                .padding(6)
                .background(.ultraThinMaterial)
                .clipShape(Circle())

            Text(spot.name)
                .font(.caption2)
                .padding(.horizontal, 4)
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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Spot Name", text: $name)
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Toggle("Private Spot", isOn: $isPrivate)
                } footer: {
                    Text("Private spots are never shared. Public spots are obfuscated by 5-10km when shared.")
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
        var spot = Spot(
            name: name,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            notes: notes.isEmpty ? nil : notes,
            isPrivate: isPrivate
        )
        try? appState.spotRepository.save(&spot)
        dismiss()
    }
}
