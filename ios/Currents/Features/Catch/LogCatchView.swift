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
    @State private var selectedSpeciesName: String = ""
    @State private var selectedSpotId: String?
    @State private var selectedTripId: String?
    @State private var lengthCm: String = ""
    @State private var weightKg: String = ""
    @State private var released = true
    @State private var selectedGearId: String?
    @State private var notes: String = ""
    @State private var caughtAt = Date.now

    // Sheets
    @State private var showingSpeciesPicker = false

    // Data
    @State private var allSpecies: [Species] = []
    @State private var allSpots: [Spot] = []
    @State private var allGear: [GearLoadout] = []
    @State private var allTrips: [Trip] = []

    var body: some View {
        NavigationStack {
            Form {
                // Photo section
                Section("Photo") {
                    photoSection
                }

                // ML results
                if !mlPredictions.isEmpty {
                    Section("AI Fish ID") {
                        ForEach(mlPredictions, id: \.species) { prediction in
                            Button {
                                let match = allSpecies.first {
                                    $0.commonName.localizedCaseInsensitiveContains(prediction.species)
                                }
                                if let match {
                                    selectedSpeciesId = match.id
                                    selectedSpeciesName = match.commonName
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "brain")
                                        .foregroundStyle(.purple)
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

                // Species (tap to open searchable picker)
                Section("Species") {
                    Button {
                        showingSpeciesPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "fish.fill")
                                .foregroundStyle(.blue)
                                .frame(width: 28)
                            if selectedSpeciesId != nil {
                                Text(selectedSpeciesName)
                                    .foregroundStyle(.primary)
                            } else {
                                Text("Select Species")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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

                // Trip
                Section("Trip") {
                    Picker("Trip", selection: $selectedTripId) {
                        Text("None").tag(nil as String?)
                        ForEach(allTrips) { trip in
                            Text(trip.name).tag(trip.id as String?)
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
                allTrips = (try? appState.tripRepository.fetchAll()) ?? []
            }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        capturedImage = image
                        classifyImage(image)
                    }
                }
            }
            .sheet(isPresented: $showingSpeciesPicker) {
                SpeciesPickerSheet(
                    species: allSpecies,
                    selectedId: $selectedSpeciesId,
                    selectedName: $selectedSpeciesName
                )
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
                if let match {
                    selectedSpeciesId = match.id
                    selectedSpeciesName = match.commonName
                }
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
            tripId: selectedTripId,
            notes: notes.isEmpty ? nil : notes
        )

        try? appState.catchRepository.save(&catchRecord)
        dismiss()
    }
}

// MARK: - Species Picker Sheet

struct SpeciesPickerSheet: View {
    let species: [Species]
    @Binding var selectedId: Int64?
    @Binding var selectedName: String
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedHabitat: Species.Habitat?

    var filtered: [Species] {
        var result = species
        if let habitat = selectedHabitat {
            result = result.filter { $0.habitat == habitat }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.commonName.localizedCaseInsensitiveContains(searchText) ||
                $0.scientificName.localizedCaseInsensitiveContains(searchText) ||
                ($0.family ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Habitat filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(title: "All", isSelected: selectedHabitat == nil) {
                            selectedHabitat = nil
                        }
                        FilterChip(title: "Freshwater", isSelected: selectedHabitat == .freshwater) {
                            selectedHabitat = .freshwater
                        }
                        FilterChip(title: "Marine", isSelected: selectedHabitat == .marine) {
                            selectedHabitat = .marine
                        }
                        FilterChip(title: "Brackish", isSelected: selectedHabitat == .brackish) {
                            selectedHabitat = .brackish
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)

                List {
                    // ML Coming Soon banner
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: "brain")
                                .font(.title2)
                                .foregroundStyle(.purple)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("AI Fish ID")
                                    .font(.subheadline.bold())
                                Text("Coming soon — snap a photo to auto-identify")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("Soon")
                                .font(.caption2.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.purple.opacity(0.2))
                                .foregroundStyle(.purple)
                                .clipShape(Capsule())
                        }
                    }

                    // Species list
                    Section("\(filtered.count) Species") {
                        ForEach(filtered) { sp in
                            Button {
                                selectedId = sp.id
                                selectedName = sp.commonName
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    // Fish icon with habitat color
                                    ZStack {
                                        Circle()
                                            .fill(habitatColor(sp.habitat).opacity(0.15))
                                            .frame(width: 44, height: 44)
                                        Image(systemName: "fish.fill")
                                            .foregroundStyle(habitatColor(sp.habitat))
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(sp.commonName)
                                            .font(.body.bold())
                                            .foregroundStyle(.primary)
                                        Text(sp.scientificName)
                                            .font(.caption)
                                            .italic()
                                            .foregroundStyle(.secondary)
                                        if let family = sp.family {
                                            Text(family)
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }

                                    Spacer()

                                    // Temperature range
                                    if let opt = sp.optimalTempC {
                                        VStack(spacing: 2) {
                                            Text("\(Int(opt))°C")
                                                .font(.caption.bold())
                                                .foregroundStyle(.green)
                                            Text("optimal")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    if selectedId == sp.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                            .tint(.primary)
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Select Species")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search by name, family...")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Clear") {
                        selectedId = nil
                        selectedName = ""
                        dismiss()
                    }
                }
            }
        }
    }

    private func habitatColor(_ habitat: Species.Habitat?) -> Color {
        switch habitat {
        case .freshwater: return .green
        case .marine: return .blue
        case .brackish: return .teal
        case nil: return .gray
        }
    }
}
