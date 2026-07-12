import SwiftUI
import PhotosUI
import MapKit
import ImageIO

struct LogCatchView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("units") private var units = "metric"
    /// Length/weight fields hold values in the user's chosen unit; converted to
    /// metric (the stored canonical) at save.
    private var imperial: Bool { units == "imperial" }

    // Photos (multi-photo)
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var capturedImages: [UIImage] = []
    @State private var showingCamera = false
    @State private var showingARMeasure = false

    // ML — BioCLIP only; no guessing fallbacks.
    @State private var speciesMatches: [SpeciesMatch] = []
    @State private var isClassifying = false
    @State private var autoSelectedFromML = false
    @State private var modelReady = false
    @State private var hasScanned = false

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
    @State private var isSaving = false   // guards against double-tap → duplicate catches

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
    @State private var ownedGear: [OwnedGear] = []

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
                if FeatureFlags.liveTrips {
                    tripSection
                }
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
                    Button("Save") { Task { await saveCatch() } }
                        .bold()
                        .disabled(isSaving)
                }
            }
            .task {
                allSpecies = (try? appState.speciesRepository.fetchAll()) ?? []
                allSpots = (try? appState.spotRepository.fetchAll()) ?? []
                allGear = (try? appState.gearRepository.fetchPresets()) ?? []
                allTrips = (try? appState.tripRepository.fetchAll()) ?? []
                ownedGear = (try? appState.ownedGearRepository.fetchAll()) ?? []

                // Auto-select active trip so catches link automatically
                if selectedTripId == nil {
                    selectedTripId = allTrips.first(where: { $0.endDate == nil })?.id
                }

                if let loc = appState.locationManager.currentLocation {
                    pinCoordinate = loc.coordinate
                }
            }
            .onChange(of: selectedPhotos) { _, items in
                loadPhotos(items)
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
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { image in
                    capturedImages.append(image)
                    if speciesMatches.isEmpty { classifyImage(image) }
                }
                .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $showingARMeasure) {
                ARMeasureView { cm in
                    lengthCm = String(format: "%.1f", imperial ? cm / 2.54 : cm)
                }
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

    // MARK: - Photo Section (Multi-Photo)

    @ViewBuilder
    private var photoSection: some View {
        Section("Photos") {
            if !capturedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(capturedImages.indices, id: \.self) { index in
                            Image(uiImage: capturedImages[index])
                                .resizable()
                                .scaledToFill()
                                .frame(width: 120, height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        capturedImages.remove(at: index)
                                        if capturedImages.isEmpty {
                                            speciesMatches = []
                                            hasScanned = false
                                        }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.title3)
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.5))
                                    }
                                    .padding(4)
                                }
                        }

                        // Add more — camera
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button { showingCamera = true } label: {
                                addTile(icon: "camera", label: "Camera")
                            }
                            .buttonStyle(.plain)
                        }
                        // Add more — library
                        PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 10, matching: .images) {
                            addTile(icon: "photo.on.rectangle", label: "Library")
                        }
                    }
                    .padding(.vertical, 4)
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
                // Camera-first: lead with Take Photo, keep Choose Photos.
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { showingCamera = true } label: {
                        Label("Take Photo", systemImage: "camera.fill")
                    }
                }
                PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 10, matching: .images) {
                    Label("Choose Photos", systemImage: "photo.on.rectangle")
                }
            }
        }
    }

    private func addTile(icon: String, label: String) -> some View {
        VStack {
            Image(systemName: icon).font(.title2)
            Text(label).font(.caption)
        }
        .foregroundStyle(.secondary)
        .frame(width: 120, height: 120)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - ML Section

    @ViewBuilder
    private var mlSection: some View {
        if isClassifying {
            Section("AI Fish ID") {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Identifying species…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        } else if !speciesMatches.isEmpty {
            Section {
                // Top match — presented as the auto-selected result.
                if let top = speciesMatches.first {
                    let isSelected = selectedSpeciesId == top.species.id
                    HStack(spacing: 12) {
                        SpeciesArtworkView(species: top.species, caught: true, size: 40)
                            .frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(top.species.commonName)
                                .font(.subheadline.bold())
                            Text(top.species.scientificName)
                                .font(.caption2).italic()
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(Int(top.confidence * 100))%")
                                .font(.subheadline.bold())
                                .foregroundStyle(CurrentsTheme.accent)
                            Text(confidenceLabel(top.confidence))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? CurrentsTheme.accent : .secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selectSpecies(top.species) }
                }

                // Alternative matches
                if speciesMatches.count > 1 {
                    DisclosureGroup("Other possibilities") {
                        ForEach(speciesMatches.dropFirst(), id: \.species.id) { m in
                            Button {
                                selectSpecies(m.species)
                            } label: {
                                HStack {
                                    Text(m.species.commonName)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text("\(Int(m.confidence * 100))%")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if selectedSpeciesId == m.species.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(CurrentsTheme.accent)
                                    }
                                }
                            }
                            .tint(.primary)
                        }
                    }
                }
            } header: {
                HStack {
                    Label("AI Fish ID", systemImage: "sparkles")
                    Spacer()
                    Button("Re-scan") {
                        if let first = capturedImages.first { classifyImage(first) }
                    }
                    .font(.caption)
                }
            } footer: {
                if autoSelectedFromML {
                    Text("Auto-selected the top match. Tap to change, or pick manually below.")
                }
            }
        } else if hasScanned && !capturedImages.isEmpty {
            Section {
                if modelReady {
                    Text("No confident match — pick the species manually below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("The AI model is still downloading (~90 MB, needs internet once).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Try again") {
                            if let first = capturedImages.first { classifyImage(first) }
                        }
                        .font(.caption.bold())
                    }
                }
            } header: {
                Label("AI Fish ID", systemImage: "sparkles")
            }
        }
    }

    private func confidenceLabel(_ c: Float) -> String {
        switch c {
        case 0.85...: "Very confident"
        case 0.6..<0.85: "Likely"
        case 0.4..<0.6: "Best guess"
        default: "Uncertain"
        }
    }

    private func selectSpecies(_ species: Species) {
        selectedSpeciesId = species.id
        selectedSpeciesName = species.commonName
    }

    // MARK: - Species Section

    private var speciesSection: some View {
        Section("Species") {
            Button {
                showingSpeciesPicker = true
            } label: {
                HStack {
                    Image(systemName: "fish.fill")
                        .foregroundStyle(CurrentsTheme.accent)
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
                Text(imperial ? "in" : "cm")
                    .foregroundStyle(.secondary)
                if ARMeasureView.isSupported {
                    Button {
                        showingARMeasure = true
                    } label: {
                        Image(systemName: "arkit")
                            .foregroundStyle(CurrentsTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                TextField("Weight", text: $weightKg)
                    .keyboardType(.decimalPad)
                Text(imperial ? "lb" : "kg")
                    .foregroundStyle(.secondary)
            }
            // Length-based weight estimate — offered when a length is entered
            // but no weight yet (uses the selected species' body shape). Field
            // values are in the display unit, so convert length → cm for the
            // estimator and the result kg → display unit.
            if let lenTyped = lengthCm.measurementValue, lenTyped > 0, weightKg.measurementValue == nil,
               let estKg = WeightEstimator.estimateKg(
                   lengthCm: imperial ? lenTyped * 2.54 : lenTyped,
                   species: allSpecies.first { $0.id == selectedSpeciesId }
               ) {
                let estDisplay = imperial ? estKg * 2.2046226 : estKg
                Button {
                    weightKg = String(format: "%.2f", estDisplay)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "scalemass")
                        Text("Estimated ~\(String(format: "%.1f", estDisplay)) \(imperial ? "lb" : "kg")")
                        Spacer()
                        Text("Use").fontWeight(.semibold)
                    }
                    .font(.caption)
                    .foregroundStyle(CurrentsTheme.accent)
                }
                .buttonStyle(.plain)
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
                            .foregroundStyle(CurrentsTheme.accent)
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
                            .foregroundStyle(CurrentsTheme.accent)
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

    // MARK: - Gear (Individual items from owned gear + loadout presets)

    @State private var gearRod = ""
    @State private var gearReel = ""
    @State private var gearLure = ""
    @State private var gearLureColor = ""
    @State private var gearTechnique = ""
    @State private var showGearDetails = false

    private var gearSection: some View {
        Section("Gear") {
            // Individual gear picks from owned items
            DisclosureGroup("Pick Gear", isExpanded: $showGearDetails) {
                gearPicker(category: .rod, selection: $gearRod, placeholder: "Rod")
                gearPicker(category: .reel, selection: $gearReel, placeholder: "Reel")
                gearPicker(category: .lure, selection: $gearLure, placeholder: "Lure / Bait")

                if !gearLure.isEmpty {
                    TextField("Lure Color", text: $gearLureColor)
                }

                // Technique — preset list plus a free-text custom option.
                TechniquePicker(selection: $gearTechnique)
            }

            // Quick loadout preset
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
                    showGearDetails = true
                }
            }
        }
    }

    @ViewBuilder
    private func gearPicker(category: OwnedGear.Category, selection: Binding<String>, placeholder: String) -> some View {
        let items = ownedGear.filter { $0.category == category }
        if items.isEmpty {
            TextField(placeholder, text: selection)
        } else {
            GearFieldPicker(placeholder: placeholder, items: items, selection: selection)
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

    private func loadPhotos(_ items: [PhotosPickerItem]) {
        Task {
            var newImages: [UIImage] = []
            var extractedDate: Date?
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    newImages.append(uiImage)
                    // Extract EXIF date from first photo
                    if extractedDate == nil {
                        extractedDate = Self.extractDateFromEXIF(data: data)
                    }
                }
            }
            capturedImages = newImages
            if let date = extractedDate {
                caughtAt = date
            }
            if let first = newImages.first {
                classifyImage(first)
            }
        }
    }

    private static func extractDateFromEXIF(data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let dateString = exif[kCGImagePropertyExifDateTimeOriginal] as? String
                ?? exif[kCGImagePropertyExifDateTimeDigitized] as? String else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: dateString)
    }

    private func classifyImage(_ image: UIImage) {
        isClassifying = true
        autoSelectedFromML = false
        Task {
            // BioCLIP is the only identifier — the old artwork-similarity and
            // Vision fallbacks produced junk guesses and were removed. Nudge
            // the model download in case the launch attempt had no network.
            await appState.fishModelDownloader.ensureModelDownloaded()

            let byId = Dictionary(uniqueKeysWithValues: allSpecies.map { ($0.id, $0) })
            let ranked = await appState.embeddingIdentifier.identify(image: image)
            speciesMatches = ranked.compactMap { r in
                byId[r.speciesId].map { SpeciesMatch(species: $0, confidence: r.confidence) }
            }
            modelReady = await appState.fishModelDownloader.isModelAvailable
            hasScanned = true
            isClassifying = false

            if let top = speciesMatches.first, selectedSpeciesId == nil {
                selectSpecies(top.species)
                autoSelectedFromML = true
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

    /// Codable matching CatchDetailView's WeatherSnapshot keys so the stored
    /// conditions decode back on the catch detail.
    private struct WxSnap: Codable {
        var temperatureC: Double?
        var waterTempC: Double?
        var windSpeedKmh: Double?
        var windDirectionDeg: Double?
        var pressureHpa: Double?
        var condition: String?
    }

    private func saveCatch() async {
        // Re-entrancy guard: a rapid double-tap creates two Tasks; the second
        // sees isSaving == true (set synchronously before any await) and bails,
        // so we never save the same catch twice.
        guard !isSaving else { return }
        isSaving = true
        let (lat, lon) = resolveLocation()
        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let catchId = UUID().uuidString

        // Save multiple photos
        var photoPaths: [String] = []
        if !capturedImages.isEmpty {
            photoPaths = (try? PhotoManager.saveMultiple(capturedImages, catchId: catchId)) ?? []
        }

        // Capture the actual conditions at the catch (weather + real bite score).
        let wx = await WeatherService.shared.current(for: coord)
        let species = allSpecies.first(where: { $0.id == selectedSpeciesId })
        let forecast = ForecastEngine.forecast(
            date: caughtAt,
            coordinate: coord,
            currentPressureHpa: wx?.pressureHpa,
            pressureChange6h: wx?.pressureChange6h,
            waterTempC: wx?.waterTempC,
            windSpeedKmh: wx?.windSpeedKmh,
            windDirection: wx?.windDirectionDeg,
            species: species,
            isInSpawningZone: false
        )
        let weatherJSON: String? = wx.flatMap {
            let snap = WxSnap(temperatureC: $0.temperatureC, waterTempC: $0.waterTempC,
                              windSpeedKmh: $0.windSpeedKmh, windDirectionDeg: $0.windDirectionDeg,
                              pressureHpa: $0.pressureHpa, condition: $0.condition)
            return (try? JSONEncoder().encode(snap)).flatMap { String(data: $0, encoding: .utf8) }
        }
        // Any fish logged while a session is recording belongs to that session.
        let tripId = appState.tripTracker.activeTrip?.id ?? selectedTripId

        // Gear the catch is saved with. Starting from any chosen preset, the
        // user can still fill fields the preset didn't cover (or tweak ones it
        // did). If the effective gear differs from the preset, snapshot it onto
        // a HIDDEN loadout so the catch keeps exactly what was used — the named
        // preset stays untouched, and the Presets tab isn't polluted.
        var gearId = selectedGearId
        let hasIndividualGear = !gearRod.isEmpty || !gearReel.isEmpty || !gearLure.isEmpty || !gearTechnique.isEmpty

        if let selected = selectedGearId,
           let preset = allGear.first(where: { $0.id == selected }) {
            let matchesPreset =
                gearRod == (preset.rod ?? "") &&
                gearReel == (preset.reel ?? "") &&
                gearLure == (preset.lure ?? "") &&
                gearLureColor == (preset.lureColor ?? "") &&
                gearTechnique == (preset.technique ?? "")
            if !matchesPreset {
                var hidden = GearLoadout(
                    name: preset.name,
                    rod: gearRod.isEmpty ? nil : gearRod,
                    reel: gearReel.isEmpty ? nil : gearReel,
                    lineLb: preset.lineLb,
                    leaderLb: preset.leaderLb,
                    lure: gearLure.isEmpty ? nil : gearLure,
                    lureColor: gearLureColor.isEmpty ? nil : gearLureColor,
                    lureWeightG: preset.lureWeightG,
                    technique: gearTechnique.isEmpty ? nil : gearTechnique,
                    isAutoCreated: true
                )
                try? appState.gearRepository.save(&hidden)
                gearId = hidden.id
            }
        } else if gearId == nil && hasIndividualGear {
            var hidden = GearLoadout(
                name: "Catch gear",
                rod: gearRod.isEmpty ? nil : gearRod,
                reel: gearReel.isEmpty ? nil : gearReel,
                lure: gearLure.isEmpty ? nil : gearLure,
                lureColor: gearLureColor.isEmpty ? nil : gearLureColor,
                technique: gearTechnique.isEmpty ? nil : gearTechnique,
                isAutoCreated: true
            )
            try? appState.gearRepository.save(&hidden)
            gearId = hidden.id
        }

        var catchRecord = Catch(
            id: catchId,
            speciesId: selectedSpeciesId,
            spotId: locationMode == .spot ? selectedSpotId : nil,
            caughtAt: caughtAt,
            latitude: lat,
            longitude: lon,
            lengthCm: lengthCm.measurementValue.map { imperial ? $0 * 2.54 : $0 },
            weightKg: weightKg.measurementValue.map { imperial ? $0 / 2.2046226 : $0 },
            released: released,
            photoPath: photoPaths.first,
            photoPaths: Catch.encodePhotoPaths(photoPaths),
            mlConfidence: speciesMatches.first.map { Double($0.confidence) },
            forecastScoreAtCapture: forecast.score,
            weatherSnapshot: weatherJSON,
            gearLoadoutId: gearId,
            tripId: tripId,
            notes: notes.isEmpty ? nil : notes
        )

        try? appState.catchRepository.save(&catchRecord)

        // Reset the cold-streak nudge — you just caught something.
        if tripId != nil, appState.tripTracker.isTracking {
            await NotificationManager.shared.scheduleColdStreakNudge()
        }

        // Auto-share to iNaturalist when the user has connected their account.
        // No-op otherwise, so nothing leaves the device by default.
        appState.inaturalist.uploadIfConnected(
            catchRecord,
            species: allSpecies.first(where: { $0.id == selectedSpeciesId }),
            catchRepository: appState.catchRepository
        )

        // Publish a measured catch to the community leaderboard and, when this
        // trip is a shared group trip, to the group's live feed. No-op unless
        // the angler has joined; carries species + size + broad region (and the
        // photo). Coordinates are attached only if the angler opted into catch-
        // location sharing, and are offset by their honey-hole radius.
        if catchRecord.weightKg != nil || catchRecord.lengthCm != nil {
            let name = species?.commonName ?? "Fish"
            let groupCode = tripId.flatMap { CommunityService.shared.groupCode(forTripId: $0) }
            await CommunityService.shared.publish(
                catchRecord: catchRecord,
                speciesName: name,
                region: CommunityService.shared.myRegion,
                groupCode: groupCode
            )
        }

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

// MARK: - Location Picker Sheet (Pin Drop with Search)

struct LocationPickerSheet: View {
    @Binding var coordinate: CLLocationCoordinate2D?
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var cameraPosition: MapCameraPosition
    @State private var pinPosition: CLLocationCoordinate2D?
    @State private var searchText = ""
    @State private var searchModel = MapSearchCompleter()
    @State private var isSearching = false
    @FocusState private var searchFocused: Bool

    init(coordinate: Binding<CLLocationCoordinate2D?>) {
        _coordinate = coordinate
        // Open centred on the existing pin when there is one (e.g. editing a
        // spot or catch far from where the user is standing right now),
        // otherwise on the user's current location.
        //
        // We deliberately pin an EXPLICIT coordinate rather than using
        // `.userLocation(fallback:)`: that mode keeps re-centring as the async
        // location fix resolves, and a late fix would clobber a location the
        // user had already panned to — dropping the pin far from where they
        // placed it. Seeding `pinPosition` up front also means Confirm can
        // never save a nil/stale coordinate.
        let start = coordinate.wrappedValue
            ?? LocationPickerSheet.lastKnownCoordinate
        if let start {
            _cameraPosition = State(initialValue: .camera(.init(
                centerCoordinate: start,
                distance: 3000
            )))
            _pinPosition = State(initialValue: start)
        } else {
            _cameraPosition = State(initialValue: .userLocation(fallback: .automatic))
        }
    }

    /// Best-effort last known device location, captured synchronously at init
    /// so the picker can seed its pin without waiting on an async fix.
    private static var lastKnownCoordinate: CLLocationCoordinate2D? {
        CLLocationManager().location?.coordinate
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Map(position: $cameraPosition) {
                    UserAnnotation()
                    if let pin = pinPosition {
                        Annotation("Catch Location", coordinate: pin) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title)
                                .foregroundStyle(CurrentsTheme.accent)
                        }
                    }
                }
                .mapStyle(.hybrid(elevation: .realistic))
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                }

                // Center crosshair
                VStack {
                    Spacer()
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(CurrentsTheme.accent)
                        .shadow(radius: 3)
                    Spacer()
                }

                // Search bar + type-ahead results overlay (same behaviour as
                // the main map: results show while the keyboard is up, and
                // there's an explicit keyboard-dismiss button).
                VStack(spacing: 4) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search location...", text: $searchText)
                            .textFieldStyle(.plain)
                            .focused($searchFocused)
                            .submitLabel(.search)
                            .autocorrectionDisabled()
                            .onSubmit {
                                if let first = searchModel.completions.first {
                                    select(first)
                                }
                                searchFocused = false
                            }
                            .onChange(of: searchText) { _, newValue in
                                searchModel.update(
                                    query: newValue,
                                    near: pinPosition ?? appState.locationManager.currentLocation?.coordinate
                                )
                            }
                        if isSearching {
                            ProgressView()
                                .controlSize(.small)
                        }
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                                searchModel.clear()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if searchFocused {
                            Button {
                                searchFocused = false
                            } label: {
                                Image(systemName: "keyboard.chevron.compact.down")
                                    .foregroundStyle(CurrentsTheme.accent)
                            }
                        }
                    }
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                    .padding(.top, 8)

                    if !searchModel.completions.isEmpty && !searchText.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(searchModel.completions.prefix(6).enumerated()), id: \.offset) { index, completion in
                                Button {
                                    select(completion)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(completion.title)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        if !completion.subtitle.isEmpty {
                                            Text(completion.subtitle)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                                }
                                if index < min(searchModel.completions.count, 6) - 1 {
                                    Divider()
                                }
                            }
                        }
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                    }

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
                        coordinate = pinPosition
                        dismiss()
                    }
                    .bold()
                }
            }
            // Track the centre continuously so the pin always reflects the
            // live crosshair position — `.onEnd` can miss the final resting
            // spot and leave a stale coordinate behind on Confirm.
            .onMapCameraChange(frequency: .continuous) { context in
                pinPosition = context.camera.centerCoordinate
            }
        }
    }

    /// Resolve a tapped suggestion to coordinates, move the camera and pin.
    private func select(_ completion: MKLocalSearchCompletion) {
        searchFocused = false
        isSearching = true
        searchText = completion.title
        Task {
            let search = MKLocalSearch(request: MKLocalSearch.Request(completion: completion))
            let response = try? await search.start()
            if let coord = response?.mapItems.first?.placemark.location?.coordinate {
                cameraPosition = .camera(.init(centerCoordinate: coord, distance: 5000))
                pinPosition = coord
            }
            searchModel.clear()
            isSearching = false
        }
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
                    // Species list
                    Section("\(filtered.count) Species") {
                        ForEach(filtered) { sp in
                            Button {
                                selectedId = sp.id
                                selectedName = sp.commonName
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    SpeciesArtworkView(species: sp, caught: true, size: 44)
                                        .frame(width: 44, height: 44)

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
                                                .foregroundStyle(CurrentsTheme.accent)
                                            Text("optimal")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    if selectedId == sp.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(CurrentsTheme.accent)
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

}

// MARK: - Camera Picker

/// Full-screen system camera for capturing a catch photo directly, so users
/// aren't forced through the photo library.
struct CameraPicker: UIViewControllerRepresentable {
    var onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

/// Gear field with an owned-gear picker plus a "Custom…" option that reveals a
/// free-text field. Custom mode is tracked separately from the value, so typing
/// a custom name no longer hides the field (the old code bound the field
/// directly to the "__custom__" sentinel, so the first keystroke dismissed it).
struct GearFieldPicker: View {
    let placeholder: String
    let items: [OwnedGear]
    @Binding var selection: String
    @State private var isCustom = false
    @State private var customText = ""

    var body: some View {
        Picker(placeholder, selection: Binding(
            get: { isCustom ? "__custom__" : selection },
            set: { newValue in
                if newValue == "__custom__" {
                    isCustom = true
                    selection = customText   // keep any text already typed
                } else {
                    isCustom = false
                    selection = newValue
                }
            }
        )) {
            Text("None").tag("")
            ForEach(items) { item in
                Text(item.displayName).tag(item.displayName)
            }
            Text("Custom…").tag("__custom__")
        }

        if isCustom {
            TextField("Custom \(placeholder.lowercased())", text: $customText)
                .onChange(of: customText) { _, newValue in selection = newValue }
        }
    }

    init(placeholder: String, items: [OwnedGear], selection: Binding<String>) {
        self.placeholder = placeholder
        self.items = items
        self._selection = selection
        // Resume in custom mode if the stored value isn't one of the owned items.
        let value = selection.wrappedValue
        let isKnown = value.isEmpty || items.contains { $0.displayName == value }
        _isCustom = State(initialValue: !isKnown)
        _customText = State(initialValue: isKnown ? "" : value)
    }
}
