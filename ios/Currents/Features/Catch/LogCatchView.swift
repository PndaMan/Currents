import SwiftUI
import PhotosUI
import MapKit

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

    // Location
    @State private var locationMode: LocationMode = .current
    @State private var pinCoordinate: CLLocationCoordinate2D?
    @State private var showingLocationPicker = false
    @State private var showingNewSpot = false
    @State private var newSpotName = ""

    // Sheets
    @State private var showingSpeciesPicker = false

    // Data
    @State private var allSpecies: [Species] = []
    @State private var allSpots: [Spot] = []
    @State private var allGear: [GearLoadout] = []
    @State private var allTrips: [Trip] = []

    enum LocationMode: String, CaseIterable {
        case current = "Current Location"
        case spot = "Saved Spot"
        case pin = "Drop Pin"
    }

    var body: some View {
        NavigationStack {
            Form {
                photoSection
                mlSection
                speciesSection
                measurementsSection
                locationSection
                tripSection
                gearSection
                notesSection
                timeSection
            }
            .navigationTitle("Log Catch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveCatch() }
                        .bold()
                }
            }
            .task {
                allSpecies = (try? appState.speciesRepository.fetchAll()) ?? []
                allSpots = (try? appState.spotRepository.fetchAll()) ?? []
                allGear = (try? appState.gearRepository.fetchAll()) ?? []
                allTrips = (try? appState.tripRepository.fetchAll()) ?? []

                if let loc = appState.locationManager.currentLocation {
                    pinCoordinate = loc.coordinate
                }
            }
            .onChange(of: selectedPhoto) { _, item in
                loadPhoto(item)
            }
            .sheet(isPresented: $showingSpeciesPicker) {
                SpeciesPickerSheet(
                    species: allSpecies,
                    selectedId: $selectedSpeciesId,
                    selectedName: $selectedSpeciesName
                )
            }
            .sheet(isPresented: $showingLocationPicker) {
                LocationPickerSheet(coordinate: $pinCoordinate)
            }
            .alert("New Spot", isPresented: $showingNewSpot) {
                TextField("Spot name", text: $newSpotName)
                Button("Save") { saveNewSpot() }
                Button("Cancel", role: .cancel) { newSpotName = "" }
            } message: {
                Text("Save this pin as a new fishing spot")
            }
        }
    }

    // MARK: - Photo Section

    @ViewBuilder
    private var photoSection: some View {
        Section("Photo") {
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
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.5))
                        }
                        .padding(8)
                    }

                if isClassifying {
                    HStack {
                        ProgressView()
                        Text("Identifying fish...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack(spacing: 16) {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Photo Library", systemImage: "photo.on.rectangle")
                    }
                }
            }
        }
    }

    // MARK: - ML Section

    @ViewBuilder
    private var mlSection: some View {
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
    }

    // MARK: - Species Section

    private var speciesSection: some View {
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
    }

    // MARK: - Measurements

    private var measurementsSection: some View {
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
    }

    // MARK: - Location Section

    private var locationSection: some View {
        Section("Location") {
            Picker("Location", selection: $locationMode) {
                ForEach(LocationMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            switch locationMode {
            case .current:
                if let loc = appState.locationManager.currentLocation {
                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading) {
                            Text("Using current location")
                                .font(.subheadline)
                            Text(String(format: "%.4f, %.4f", loc.coordinate.latitude, loc.coordinate.longitude))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Label("Waiting for location...", systemImage: "location.slash")
                        .foregroundStyle(.secondary)
                }

            case .spot:
                if allSpots.isEmpty {
                    Text("No saved spots yet")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Spot", selection: $selectedSpotId) {
                        Text("Select a spot").tag(nil as String?)
                        ForEach(allSpots) { spot in
                            HStack {
                                Text(spot.name)
                                Text(String(format: "(%.2f, %.2f)", spot.latitude, spot.longitude))
                                    .font(.caption)
                            }
                            .tag(spot.id as String?)
                        }
                    }
                }

            case .pin:
                if let coord = pinCoordinate {
                    HStack {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(.red)
                        VStack(alignment: .leading) {
                            Text("Pin dropped")
                                .font(.subheadline)
                            Text(String(format: "%.4f, %.4f", coord.latitude, coord.longitude))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Move") {
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

                Button {
                    showingNewSpot = true
                } label: {
                    Label("Save as new spot", systemImage: "mappin.and.ellipse")
                }
                .disabled(pinCoordinate == nil)
            }
        }
    }

    // MARK: - Trip

    private var tripSection: some View {
        Section("Trip") {
            Picker("Trip", selection: $selectedTripId) {
                Text("None").tag(nil as String?)
                ForEach(allTrips) { trip in
                    Text(trip.name).tag(trip.id as String?)
                }
            }
        }
    }

    // MARK: - Gear

    @State private var gearRod = ""
    @State private var gearReel = ""
    @State private var gearLure = ""
    @State private var gearLureColor = ""
    @State private var gearTechnique = ""
    @State private var showGearDetails = false

    private let techniques = [
        "Drop Shot", "Carolina Rig", "Texas Rig", "Jigging", "Trolling",
        "Topwater", "Crankbait", "Spinnerbait", "Fly Fishing", "Live Bait",
        "Bottom Fishing", "Cast & Retrieve", "Slow Roll", "Finesse",
        "Power Fishing", "Sight Fishing", "Drift Fishing", "Vertical Jigging"
    ]

    private var gearSection: some View {
        Section("Gear") {
            // Quick loadout picker
            Picker("Loadout Preset", selection: $selectedGearId) {
                Text("Custom / None").tag(nil as String?)
                ForEach(allGear) { loadout in
                    Text(loadout.name).tag(loadout.id as String?)
                }
            }
            .onChange(of: selectedGearId) { _, newId in
                if let loadout = allGear.first(where: { $0.id == newId }) {
                    gearRod = loadout.rod ?? ""
                    gearReel = loadout.reel ?? ""
                    gearLure = loadout.lure ?? ""
                    gearLureColor = loadout.lureColor ?? ""
                    gearTechnique = loadout.technique ?? ""
                }
            }

            DisclosureGroup("Individual Gear", isExpanded: $showGearDetails) {
                TextField("Rod", text: $gearRod)
                TextField("Reel", text: $gearReel)

                // Technique picker
                Picker("Technique", selection: $gearTechnique) {
                    Text("None").tag("")
                    ForEach(techniques, id: \.self) { t in
                        Text(t).tag(t)
                    }
                }

                TextField("Lure / Bait", text: $gearLure)
                if !gearLure.isEmpty {
                    TextField("Lure Color", text: $gearLureColor)
                }
            }
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        Section("Notes") {
            TextField("Any notes...", text: $notes, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    // MARK: - Time

    private var timeSection: some View {
        Section("When") {
            DatePicker("Caught at", selection: $caughtAt)
        }
    }

    // MARK: - Actions

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            // Try loading as Image first (more reliable), then fallback to Data
            if let imageData = try? await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: imageData) {
                capturedImage = uiImage
                classifyImage(uiImage)
            }
        }
    }

    private func classifyImage(_ image: UIImage) {
        isClassifying = true
        Task {
            let predictions = try? await appState.fishClassifier.classify(image: image)
            mlPredictions = predictions ?? []
            isClassifying = false

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

    private func saveNewSpot() {
        guard let coord = pinCoordinate, !newSpotName.isEmpty else { return }
        var spot = Spot(
            name: newSpotName,
            latitude: coord.latitude,
            longitude: coord.longitude,
            isPrivate: true
        )
        try? appState.spotRepository.save(&spot)
        allSpots.insert(spot, at: 0)
        selectedSpotId = spot.id
        locationMode = .spot
        newSpotName = ""
    }

    private func saveCatch() {
        let (lat, lon) = resolveLocation()

        var photoPath: String?
        if let image = capturedImage {
            let id = UUID().uuidString
            photoPath = try? PhotoManager.save(image, id: id)
        }

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

        // If custom gear fields are filled but no loadout selected, create one
        var gearId = selectedGearId
        let hasCustomGear = !gearRod.isEmpty || !gearReel.isEmpty || !gearLure.isEmpty || !gearTechnique.isEmpty
        if gearId == nil && hasCustomGear {
            let name = [gearRod, gearLure, gearTechnique]
                .filter { !$0.isEmpty }
                .joined(separator: " + ")
            var loadout = GearLoadout(
                name: name.isEmpty ? "Quick Setup" : name,
                rod: gearRod.isEmpty ? nil : gearRod,
                reel: gearReel.isEmpty ? nil : gearReel,
                lure: gearLure.isEmpty ? nil : gearLure,
                lureColor: gearLureColor.isEmpty ? nil : gearLureColor,
                technique: gearTechnique.isEmpty ? nil : gearTechnique
            )
            try? appState.gearRepository.save(&loadout)
            gearId = loadout.id
        }

        var catchRecord = Catch(
            speciesId: selectedSpeciesId,
            spotId: locationMode == .spot ? selectedSpotId : nil,
            caughtAt: caughtAt,
            latitude: lat,
            longitude: lon,
            lengthCm: Double(lengthCm),
            weightKg: Double(weightKg),
            released: released,
            photoPath: photoPath,
            mlConfidence: mlPredictions.first.map { Double($0.confidence) },
            forecastScoreAtCapture: forecast.score,
            gearLoadoutId: gearId,
            tripId: selectedTripId,
            notes: notes.isEmpty ? nil : notes
        )

        try? appState.catchRepository.save(&catchRecord)
        dismiss()
    }

    private func resolveLocation() -> (Double, Double) {
        switch locationMode {
        case .current:
            let loc = appState.locationManager.currentLocation
            return (loc?.coordinate.latitude ?? 0, loc?.coordinate.longitude ?? 0)
        case .spot:
            if let spot = allSpots.first(where: { $0.id == selectedSpotId }) {
                return (spot.latitude, spot.longitude)
            }
            let loc = appState.locationManager.currentLocation
            return (loc?.coordinate.latitude ?? 0, loc?.coordinate.longitude ?? 0)
        case .pin:
            if let coord = pinCoordinate {
                return (coord.latitude, coord.longitude)
            }
            let loc = appState.locationManager.currentLocation
            return (loc?.coordinate.latitude ?? 0, loc?.coordinate.longitude ?? 0)
        }
    }
}

// MARK: - Location Picker Sheet (Pin Drop)

struct LocationPickerSheet: View {
    @Binding var coordinate: CLLocationCoordinate2D?
    @Environment(\.dismiss) private var dismiss
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var pinPosition: CLLocationCoordinate2D?

    var body: some View {
        NavigationStack {
            ZStack {
                Map(position: $cameraPosition) {
                    UserAnnotation()
                    if let pin = pinPosition {
                        Annotation("Catch Location", coordinate: pin) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .mapStyle(.hybrid(elevation: .realistic))
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                }
                .onTapGesture { position in
                    // Note: MapKit tap-to-coordinate requires MapReader
                }

                // Center crosshair for pin placement
                VStack {
                    Spacer()
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.red)
                        .shadow(radius: 3)
                    Spacer()
                }

                // Instructions
                VStack {
                    Text("Move the map to position the pin")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(.top, 8)
                    Spacer()
                }
            }
            .navigationTitle("Drop Pin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
                        confirmPin()
                    }
                    .bold()
                }
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                pinPosition = context.camera.centerCoordinate
            }
        }
    }

    private func confirmPin() {
        coordinate = pinPosition
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
