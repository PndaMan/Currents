import SwiftUI
import PhotosUI

struct LogCatchView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    // Photo
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var capturedImage: UIImage?
    @State private var showingCamera = false

    // ML
    @State private var mlPredictions: [FishClassifier.Prediction] = []
    @State private var isClassifying = false

    // Catch data
    @State private var selectedSpeciesId: Int64?
    @State private var selectedSpotId: String?
    @State private var lengthCm: String = ""
    @State private var weightKg: String = ""
    @State private var released = true
    @State private var selectedGearId: String?
    @State private var notes: String = ""
    @State private var caughtAt = Date.now

    // Data
    @State private var allSpecies: [Species] = []
    @State private var allSpots: [Spot] = []
    @State private var allGear: [GearLoadout] = []
    @State private var speciesSearch = ""

    var body: some View {
        NavigationStack {
            Form {
                // Photo section
                Section("Photo") {
                    photoSection
                }

                // ML results
                if !mlPredictions.isEmpty {
                    Section("Fish ID") {
                        ForEach(mlPredictions, id: \.species) { prediction in
                            Button {
                                // Try to find a matching species in our DB
                                let match = allSpecies.first {
                                    $0.commonName.localizedCaseInsensitiveContains(prediction.species)
                                }
                                selectedSpeciesId = match?.id
                            } label: {
                                HStack {
                                    Text(prediction.species)
                                    Spacer()
                                    Text("\(Int(prediction.confidence * 100))%")
                                        .foregroundStyle(.secondary)
                                    if let match = allSpecies.first(where: {
                                        $0.commonName.localizedCaseInsensitiveContains(prediction.species)
                                    }), selectedSpeciesId == match.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                }
                            }
                            .tint(.primary)
                        }
                    }
                }

                // Species (manual pick or confirm ML)
                Section("Species") {
                    Picker("Species", selection: $selectedSpeciesId) {
                        Text("Unknown").tag(nil as Int64?)
                        ForEach(allSpecies) { species in
                            Text(species.commonName).tag(species.id as Int64?)
                        }
                    }
                }

                // Measurements
                Section("Measurements") {
                    HStack {
                        TextField("Length", text: $lengthCm)
                            .keyboardType(.decimalPad)
                        Text("cm")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        TextField("Weight", text: $weightKg)
                            .keyboardType(.decimalPad)
                        Text("kg")
                            .foregroundStyle(.secondary)
                    }
                    Toggle("Released", isOn: $released)
                }

                // Location
                Section("Spot") {
                    Picker("Spot", selection: $selectedSpotId) {
                        Text("Current Location").tag(nil as String?)
                        ForEach(allSpots) { spot in
                            Text(spot.name).tag(spot.id as String?)
                        }
                    }
                }

                // Gear
                Section("Gear") {
                    Picker("Loadout", selection: $selectedGearId) {
                        Text("None").tag(nil as String?)
                        ForEach(allGear) { loadout in
                            Text(loadout.name).tag(loadout.id as String?)
                        }
                    }
                }

                // Notes
                Section("Notes") {
                    TextField("Any notes...", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                // Time
                Section("When") {
                    DatePicker("Caught at", selection: $caughtAt)
                }
            }
            .navigationTitle("Log Catch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveCatch() }
                }
            }
            .task {
                allSpecies = (try? appState.speciesRepository.fetchAll()) ?? []
                allSpots = (try? appState.spotRepository.fetchAll()) ?? []
                allGear = (try? appState.gearRepository.fetchAll()) ?? []
            }
        }
    }

    @ViewBuilder
    private var photoSection: some View {
        if let image = capturedImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topTrailing) {
                    Button {
                        capturedImage = nil
                        mlPredictions = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                    }
                    .padding(8)
                }

            if isClassifying {
                ProgressView("Identifying fish...")
            }
        } else {
            HStack {
                Button {
                    showingCamera = true
                } label: {
                    Label("Camera", systemImage: "camera.fill")
                }

                Spacer()

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Library", systemImage: "photo.on.rectangle")
                }
            }
        }
    }

    private func classifyImage(_ image: UIImage) {
        isClassifying = true
        Task {
            let predictions = try? await appState.fishClassifier.classify(image: image)
            mlPredictions = predictions ?? []
            isClassifying = false

            // Auto-select top prediction if confidence > 0.7
            if let top = predictions?.first, top.confidence > 0.7 {
                let match = allSpecies.first {
                    $0.commonName.localizedCaseInsensitiveContains(top.species)
                }
                selectedSpeciesId = match?.id
            }
        }
    }

    private func saveCatch() {
        let location = appState.locationManager.currentLocation
        let lat = location?.coordinate.latitude ?? 0
        let lon = location?.coordinate.longitude ?? 0

        var photoPath: String?
        if let image = capturedImage {
            let id = UUID().uuidString
            photoPath = try? PhotoManager.save(image, id: id)
        }

        // Compute forecast score at capture time
        let moonPhase = MoonPhase.current(for: caughtAt)
        let forecast = ForecastEngine.compute(
            currentPressureHpa: nil,
            pressureChange6h: nil,
            tidePhase: nil,
            moonPhase: moonPhase,
            waterTempC: nil,
            species: allSpecies.first(where: { $0.id == selectedSpeciesId }),
            isInSpawningZone: false
        )

        var catchRecord = Catch(
            speciesId: selectedSpeciesId,
            spotId: selectedSpotId,
            caughtAt: caughtAt,
            latitude: lat,
            longitude: lon,
            lengthCm: Double(lengthCm),
            weightKg: Double(weightKg),
            released: released,
            photoPath: photoPath,
            mlConfidence: mlPredictions.first.map { Double($0.confidence) },
            forecastScoreAtCapture: forecast.score,
            gearLoadoutId: selectedGearId,
            notes: notes.isEmpty ? nil : notes
        )

        try? appState.catchRepository.save(&catchRecord)
        dismiss()
    }
}
