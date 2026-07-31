import SwiftUI
import MapKit
import PhotosUI

struct CatchDetailView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("units") private var units = "metric"
    private var imperial: Bool { units == "imperial" }
    @Environment(\.dismiss) private var dismiss
    @State private var detail: CatchDetail
    @State private var showingDeleteConfirm = false
    @State private var showingEdit = false
    @State private var isGeneratingShareCard = false
    @State private var shareImage: UIImage?
    @State private var showingShareSheet = false
    @State private var trip: Trip?
    @State private var showingPhotoViewer = false
    @State private var carouselIndex = 0
    @State private var isFavorite = false

    init(detail: CatchDetail) {
        _detail = State(initialValue: detail)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CurrentsTheme.paddingM) {
                // Photo carousel (multi-photo)
                photoCarousel

                // Species header
                VStack(alignment: .leading, spacing: 4) {
                    Text(detail.species?.commonName ?? "Unknown Species")
                        .font(.title.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    if let sci = detail.species?.scientificName {
                        Text(sci)
                            .font(.subheadline)
                            .italic()
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        Label(
                            detail.catchRecord.released ? "Released" : "Kept",
                            systemImage: detail.catchRecord.released ? "arrow.uturn.backward" : "bag.fill"
                        )
                        .font(.caption.bold())
                        .glassPill()

                        if let confidence = detail.catchRecord.mlConfidence {
                            Label("AI ID \(Int(confidence * 100))%", systemImage: "sparkles")
                                .font(.caption.bold())
                                .glassPill()
                        }

                        Text(detail.catchRecord.caughtAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }

                // Measurements strip — equal-width stat cells
                HStack(spacing: 12) {
                    if let length = detail.catchRecord.lengthCm {
                        let p = Units.lengthParts(cm: length, imperial: imperial)
                        measureCell(value: p.0, unit: p.1, label: "Length", icon: "ruler")
                    }
                    if let weight = detail.catchRecord.weightKg {
                        let p = Units.weightParts(kg: weight, imperial: imperial)
                        measureCell(value: p.0, unit: p.1, label: "Weight", icon: "scalemass")
                    }
                    if let score = detail.catchRecord.forecastScoreAtCapture {
                        statCard {
                            ScoreGauge(score: score, label: "", size: 32)
                            Text("Bite Score")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Size/bag-limit compliance (when a regulation is on file)
                regulationBadge

                // Location — full-width map with spot overlay
                locationCard

                // Gear
                if let gear = detail.gearLoadout {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeaderView(title: "Gear", systemImage: "wrench.and.screwdriver.fill")
                        if !gear.isAutoCreated {
                            Text(gear.name).font(.subheadline.bold())
                        }
                        GearDetailGrid(loadout: gear)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
                }

                // Trip
                if FeatureFlags.liveTrips, let trip {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeaderView(title: "Trip", systemImage: "tent.fill")
                        HStack {
                            Text(trip.name)
                                .font(.subheadline.bold())
                            Spacer()
                            Text(trip.startDate, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
                }

                // Weather at capture
                if let weatherJSON = detail.catchRecord.weatherSnapshot,
                   let weatherData = weatherJSON.data(using: .utf8),
                   let weather = try? JSONDecoder().decode(WeatherSnapshot.self, from: weatherData) {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeaderView(title: "Weather at Catch", systemImage: "cloud.sun.fill")
                        HStack(spacing: 16) {
                            if let temp = weather.temperatureC {
                                VStack(spacing: 2) {
                                    Image(systemName: "thermometer")
                                        .foregroundStyle(CurrentsTheme.accent)
                                    Text(Units.temperature(temp, imperial: imperial))
                                        .font(.subheadline.bold().monospacedDigit())
                                    Text("Air")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if let waterTemp = weather.waterTempC {
                                VStack(spacing: 2) {
                                    Image(systemName: "drop.fill")
                                        .foregroundStyle(CurrentsTheme.accent)
                                    Text(Units.temperature(waterTemp, imperial: imperial))
                                        .font(.subheadline.bold().monospacedDigit())
                                    Text("Water")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if let wind = weather.windSpeedKmh {
                                VStack(spacing: 2) {
                                    Image(systemName: "wind")
                                        .foregroundStyle(.secondary)
                                    Text("\(Int(imperial ? wind * 0.621371 : wind))")
                                        .font(.subheadline.bold().monospacedDigit())
                                    Text(Units.speedSymbol)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if let pressure = weather.pressureHpa {
                                VStack(spacing: 2) {
                                    Image(systemName: "barometer")
                                        .foregroundStyle(.secondary)
                                    Text("\(Int(pressure))")
                                        .font(.subheadline.bold().monospacedDigit())
                                    Text("hPa")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        if let condition = weather.condition {
                            HStack(spacing: 4) {
                                Image(systemName: "cloud.fill")
                                    .foregroundStyle(.secondary)
                                Text(condition)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .glassCard()
                }

                // Notes
                if let notes = detail.catchRecord.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeaderView(title: "Notes", systemImage: "note.text")
                        Text(notes)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
                }

                // ML Top 3 predictions
                if let mlTop3JSON = detail.catchRecord.mlTop3,
                   let mlData = mlTop3JSON.data(using: .utf8),
                   let predictions = try? JSONDecoder().decode([MLPrediction].self, from: mlData),
                   predictions.count > 1 {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeaderView(title: "AI Predictions", systemImage: "brain")
                        ForEach(predictions, id: \.label) { pred in
                            HStack {
                                Text(pred.label)
                                    .font(.subheadline)
                                Spacer()
                                Text("\(Int(pred.confidence * 100))%")
                                    .font(.subheadline.bold())
                                    .monospacedDigit()
                                    .foregroundStyle(pred.confidence > 0.5 ? .primary : .secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
                }
            }
            .padding()
        }
        .navigationTitle("Catch")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    Button {
                        toggleFavorite()
                    } label: {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .foregroundStyle(isFavorite ? Color.yellow : CurrentsTheme.accent)
                            .symbolEffect(.bounce, value: isFavorite)
                    }

                    Button {
                        generateShareCard()
                    } label: {
                        if isGeneratingShareCard {
                            ProgressView()
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    .disabled(isGeneratingShareCard)

                    Menu {
                        Button {
                            showingEdit = true
                        } label: {
                            Label("Edit Catch", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            showingDeleteConfirm = true
                        } label: {
                            Label("Delete Catch", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .alert("Delete Catch?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                Haptics.warning()
                deleteCatch()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .sheet(isPresented: $showingEdit) {
            EditCatchSheet(
                detail: detail,
                onSave: { updated in
                    var record = updated
                    try? appState.catchRepository.save(&record)
                    reload(with: record)
                }
            )
        }
        .sheet(isPresented: $showingShareSheet) {
            if let shareImage {
                ImageShareSheet(
                    image: shareImage,
                    filename: "Currents-\(detail.species?.commonName ?? "Catch")"
                )
            }
        }
        .fullScreenCover(isPresented: $showingPhotoViewer) {
            FullscreenPhotoViewer(
                photoPaths: detail.catchRecord.allPhotoPaths,
                currentIndex: carouselIndex
            )
        }
        .task {
            isFavorite = detail.catchRecord.isFavorite
            if let tripId = detail.catchRecord.tripId {
                trip = try? appState.tripRepository.fetch(tripId)
            }
        }
        .sensoryFeedback(.selection, trigger: isFavorite)
    }

    private func toggleFavorite() {
        withAnimation(.spring(duration: 0.25)) {
            isFavorite.toggle()
        }
        var record = detail.catchRecord
        record.isFavorite = isFavorite
        try? appState.catchRepository.save(&record)
        detail.catchRecord = record
    }

    /// Rebuild the joined detail after an edit so the open view reflects the
    /// change immediately instead of showing stale data until re-navigation.
    private func reload(with record: Catch) {
        detail.catchRecord = record
        detail.species = record.speciesId.flatMap { id in
            (try? appState.speciesRepository.fetchAll())?.first { $0.id == id }
        }
        detail.spot = record.spotId.flatMap { id in
            (try? appState.spotRepository.fetchAll())?.first { $0.id == id }
        }
        detail.gearLoadout = record.gearLoadoutId.flatMap { id in
            (try? appState.gearRepository.fetchAll())?.first { $0.id == id }
        }
        isFavorite = record.isFavorite
    }

    @ViewBuilder
    private var regulationBadge: some View {
        let result = RegulationsService.shared.verdict(
            species: detail.species,
            lengthCm: detail.catchRecord.lengthCm
        )
        if let reg = result.reg {
            let (icon, tint, text): (String, Color, String) = {
                switch result.verdict {
                case .legal:
                    return ("checkmark.seal.fill", .green, "Legal size to keep in \(reg.region)")
                case .tooSmall(let mn):
                    return ("xmark.seal.fill", .red, "Undersized — \(reg.commonName) minimum is \(Units.length(cm: mn, imperial: imperial)) in \(reg.region)")
                case .tooBig(let mx):
                    return ("xmark.seal.fill", .red, "Over slot — \(reg.commonName) maximum is \(Units.length(cm: mx, imperial: imperial)) in \(reg.region)")
                case .unknownSize:
                    return ("questionmark.circle", .secondary, "Add a length to check against the \(reg.region) limit")
                case .noRegulation:
                    return ("info.circle", .secondary, "")
                }
            }()
            VStack(alignment: .leading, spacing: 4) {
                Label(text, systemImage: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                if let bag = reg.bagLimit {
                    Text("Bag limit \(bag) per person/day\(reg.closedSeason.map { " · \($0)" } ?? "")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text("Informational — confirm current local rules.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
    }

    private func measureCell(value: String, unit: String, label: String, icon: String) -> some View {
        statCard {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(CurrentsTheme.accent)
                .frame(height: 32)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title3.bold())
                    .monospacedDigit()
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Shared container for the Length / Weight / Bite Score tiles so all three
    /// render at an identical size in one row.
    @ViewBuilder
    private func statCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 6) {
            content()
        }
        .frame(maxWidth: .infinity, minHeight: 108)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: CurrentsTheme.cornerRadius))
    }

    private func generateShareCard() {
        isGeneratingShareCard = true
        Task {
            // Share the photo the user is currently looking at in the
            // carousel, not always the first one.
            let paths = detail.catchRecord.allPhotoPaths
            let index = paths.indices.contains(carouselIndex) ? carouselIndex : 0
            guard let photoPath = paths.indices.contains(index) ? paths[index] : paths.first,
                  let photo = PhotoManager.load(photoPath) else {
                isGeneratingShareCard = false
                return
            }

            if let card = await CatchShareCard.render(detail: detail, photo: photo) {
                shareImage = card
                showingShareSheet = true
            }
            isGeneratingShareCard = false
        }
    }

    // MARK: - Photo Carousel

    @ViewBuilder
    private var photoCarousel: some View {
        let photos = detail.catchRecord.allPhotoPaths
        if photos.count > 1 {
            TabView(selection: $carouselIndex) {
                ForEach(Array(photos.enumerated()), id: \.offset) { index, path in
                    if let image = PhotoManager.load(path) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .tag(index)
                            .onTapGesture { showingPhotoViewer = true }
                    }
                }
            }
            .tabViewStyle(.page)
            .frame(height: 280)
            // Top-trailing, well away from the page dots — as a real button it
            // can't fall through to the dots and flip pages any more.
            .overlay(alignment: .topTrailing) { expandButton }
        } else if let photoPath = photos.first,
                  let image = PhotoManager.load(photoPath) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .onTapGesture {
                    carouselIndex = 0
                    showingPhotoViewer = true
                }
                .overlay(alignment: .topTrailing) { expandButton }
        } else if let species = detail.species {
            // No photo — show the species artwork so the catch still reads
            // visually instead of an empty header.
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(CurrentsTheme.accent.opacity(0.10))
                SpeciesArtworkView(species: species, caught: true, size: 180)
            }
            .frame(height: 220)
            .frame(maxWidth: .infinity)
        }
    }

    private var expandButton: some View {
        Button {
            showingPhotoViewer = true
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(8)
                .background(.black.opacity(0.45), in: Circle())
        }
        .padding(10)
    }

    @ViewBuilder private var locationCard: some View {
        let lat = detail.catchRecord.latitude
        let lon = detail.catchRecord.longitude
        if lat != 0 || lon != 0 {
            VStack(spacing: 10) {
                catchMap
                DriveToButton(
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    name: detail.spot?.name ?? detail.species?.commonName ?? "Catch")
            }
        }
    }

    private var catchMap: some View {
        Map(initialPosition: .camera(.init(
            centerCoordinate: CLLocationCoordinate2D(
                latitude: detail.catchRecord.latitude,
                longitude: detail.catchRecord.longitude
            ),
            distance: 2000
        ))) {
            Annotation("", coordinate: CLLocationCoordinate2D(
                latitude: detail.catchRecord.latitude,
                longitude: detail.catchRecord.longitude
            )) {
                Image(systemName: "fish.circle.fill")
                    .font(.title)
                    .foregroundStyle(CurrentsTheme.accent)
            }
        }
        .mapStyle(.hybrid)
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .allowsHitTesting(false)
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 4) {
                Image(systemName: detail.spot != nil ? "mappin.circle.fill" : "location.fill")
                    .font(.caption)
                if let spot = detail.spot {
                    Text(spot.name)
                        .font(.caption.bold())
                        .lineLimit(1)
                } else {
                    Text(String(format: "%.4f, %.4f", detail.catchRecord.latitude, detail.catchRecord.longitude))
                        .font(.caption.bold().monospacedDigit())
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.55), in: Capsule())
            .padding(10)
        }
    }

    private func deleteCatch() {
        let id = detail.catchRecord.id
        PhotoManager.deleteAll(detail.catchRecord.allPhotoPaths)
        try? appState.catchRepository.delete(detail.catchRecord)
        // Pull it from the shared leaderboard + any group feed too.
        Task { await CommunityService.shared.removeCatch(id: id) }
        ToastCenter.shared.show("Catch deleted", style: .info)
        dismiss()
    }
}

// MARK: - Edit Catch Sheet (Full Field Editing)

struct EditCatchSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("units") private var units = "metric"
    private var imperial: Bool { units == "imperial" }
    let detail: CatchDetail
    let onSave: (Catch) -> Void

    @State private var weight: String = ""
    @State private var length: String = ""
    @State private var notes: String = ""
    @State private var released: Bool = true
    @State private var caughtAt: Date = .now
    @State private var selectedSpeciesId: Int64?
    @State private var selectedSpeciesName: String = ""
    @State private var selectedSpotId: String?
    @State private var selectedTripId: String?
    @State private var selectedGearId: String?
    @State private var showingSpeciesPicker = false
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var showingLocationPicker = false

    // Photos — existing (saved paths) plus newly added images.
    @State private var existingPhotoPaths: [String] = []
    @State private var newImages: [UIImage] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showingCamera = false

    // Individual gear fields (matching LogCatchView)
    @State private var gearRod = ""
    @State private var gearReel = ""
    @State private var gearLure = ""
    @State private var gearLureColor = ""
    @State private var gearTechnique = ""
    @State private var showGearDetails = false

    @State private var allSpecies: [Species] = []
    @State private var allSpots: [Spot] = []
    @State private var allGear: [GearLoadout] = []
    @State private var allTrips: [Trip] = []
    @State private var ownedGear: [OwnedGear] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Species") {
                    Button {
                        showingSpeciesPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "fish.fill")
                                .foregroundStyle(CurrentsTheme.accent)
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

                photosSection

                Section("Measurements") {
                    HStack {
                        Text(imperial ? "Weight (lb)" : "Weight (kg)")
                        Spacer()
                        TextField("0.00", text: $weight)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    HStack {
                        Text(imperial ? "Length (in)" : "Length (cm)")
                        Spacer()
                        TextField("0.0", text: $length)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    Toggle("Released", isOn: $released)
                }

                Section("When") {
                    DatePicker("Caught at", selection: $caughtAt)
                }

                Section("Location") {
                    Picker("Spot", selection: $selectedSpotId) {
                        Text("None").tag(nil as String?)
                        ForEach(allSpots) { spot in
                            Text(spot.name).tag(spot.id as String?)
                        }
                    }

                    // Exact pin — editable on the map, same flow as logging.
                    if let coord = coordinate {
                        Map(position: .constant(.camera(.init(
                            centerCoordinate: coord,
                            distance: 2500
                        )))) {
                            Annotation("", coordinate: coord) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.title)
                                    .foregroundStyle(CurrentsTheme.accent)
                            }
                        }
                        .mapStyle(.hybrid)
                        .frame(height: 130)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .allowsHitTesting(false)
                        .listRowInsets(EdgeInsets())

                        HStack {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(CurrentsTheme.accent)
                            Text(String(format: "%.4f, %.4f", coord.latitude, coord.longitude))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Move on Map") {
                                showingLocationPicker = true
                            }
                            .font(.caption.bold())
                        }
                    }
                }

                if FeatureFlags.liveTrips {
                    Section("Trip") {
                        Picker("Trip", selection: $selectedTripId) {
                            Text("None").tag(nil as String?)
                            ForEach(allTrips) { trip in
                                Text(trip.name).tag(trip.id as String?)
                            }
                        }
                    }
                }

                Section("Gear") {
                    DisclosureGroup("Pick Gear", isExpanded: $showGearDetails) {
                        editGearPicker(category: .rod, selection: $gearRod, placeholder: "Rod")
                        editGearPicker(category: .reel, selection: $gearReel, placeholder: "Reel")
                        editGearPicker(category: .lure, selection: $gearLure, placeholder: "Lure / Bait")

                        if !gearLure.isEmpty {
                            TextField("Lure Color", text: $gearLureColor)
                        }

                        TechniquePicker(selection: $gearTechnique)
                    }

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

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle("Edit Catch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .bold()
                }
            }
            .task {
                let c = detail.catchRecord
                if existingPhotoPaths.isEmpty { existingPhotoPaths = c.allPhotoPaths }
                weight = c.weightKg.map { String(format: "%.2f", imperial ? $0 * 2.2046226 : $0) } ?? ""
                length = c.lengthCm.map { String(format: "%.1f", imperial ? $0 / 2.54 : $0) } ?? ""
                notes = c.notes ?? ""
                released = c.released
                caughtAt = c.caughtAt
                selectedSpeciesId = c.speciesId
                selectedSpeciesName = detail.species?.commonName ?? ""
                selectedSpotId = c.spotId
                selectedTripId = c.tripId
                selectedGearId = c.gearLoadoutId
                if coordinate == nil {
                    coordinate = CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude)
                }

                allSpecies = (try? appState.speciesRepository.fetchAll()) ?? []
                allSpots = (try? appState.spotRepository.fetchAll()) ?? []
                allGear = (try? appState.gearRepository.fetchPresets()) ?? []
                allTrips = (try? appState.tripRepository.fetchAll()) ?? []
                ownedGear = (try? appState.ownedGearRepository.fetchAll()) ?? []

                // Pre-fill individual gear from loadout if set
                if let loadout = detail.gearLoadout {
                    gearRod = loadout.rod ?? ""
                    gearReel = loadout.reel ?? ""
                    gearLure = loadout.lure ?? ""
                    gearLureColor = loadout.lureColor ?? ""
                    gearTechnique = loadout.technique ?? ""
                }
            }
            .sheet(isPresented: $showingSpeciesPicker) {
                SpeciesPickerSheet(
                    species: allSpecies,
                    selectedId: $selectedSpeciesId,
                    selectedName: $selectedSpeciesName
                )
            }
            .sheet(isPresented: $showingLocationPicker) {
                LocationPickerSheet(coordinate: $coordinate)
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { image in newImages.append(image) }
                    .ignoresSafeArea()
            }
            .onChange(of: pickerItems) { _, items in
                Task {
                    var loaded: [UIImage] = []
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let img = UIImage(data: data) {
                            loaded.append(img)
                        }
                    }
                    let toAppend = loaded
                    await MainActor.run {
                        newImages.append(contentsOf: toAppend)
                        pickerItems = []
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: released)
        }
    }

    @ViewBuilder
    private var photosSection: some View {
        Section("Photos") {
            if !existingPhotoPaths.isEmpty || !newImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(existingPhotoPaths, id: \.self) { path in
                            if let img = PhotoManager.load(path) {
                                photoThumb(img) { existingPhotoPaths.removeAll { $0 == path } }
                            }
                        }
                        ForEach(newImages.indices, id: \.self) { i in
                            photoThumb(newImages[i]) { newImages.remove(at: i) }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            HStack(spacing: 16) {
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 10, matching: .images) {
                    Label("Add Photo", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.borderless)
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { showingCamera = true } label: {
                        Label("Camera", systemImage: "camera")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .font(.subheadline)
        }
    }

    private func photoThumb(_ image: UIImage, remove: @escaping () -> Void) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .topTrailing) {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white, .black.opacity(0.6))
                }
                .padding(2)
            }
    }

    @ViewBuilder
    private func editGearPicker(category: OwnedGear.Category, selection: Binding<String>, placeholder: String) -> some View {
        let items = ownedGear.filter { $0.category == category }
        if items.isEmpty {
            TextField(placeholder, text: selection)
        } else {
            // Shared picker: custom mode is tracked separately from the
            // value, so typing a custom name doesn't dismiss the field.
            GearFieldPicker(placeholder: placeholder, items: items, selection: selection)
        }
    }

    private func save() {
        var updated = detail.catchRecord

        // Photos: delete removed originals, persist newly-added images, then
        // combine kept + new into the record.
        let removed = detail.catchRecord.allPhotoPaths.filter { !existingPhotoPaths.contains($0) }
        for path in removed { PhotoManager.delete(path) }
        var savedNew: [String] = []
        if !newImages.isEmpty {
            savedNew = (try? PhotoManager.saveMultiple(newImages, catchId: updated.id)) ?? []
        }
        let allPhotos = existingPhotoPaths + savedNew
        updated.photoPath = allPhotos.first
        updated.photoPaths = Catch.encodePhotoPaths(allPhotos)

        updated.weightKg = weight.measurementValue.map { imperial ? $0 / 2.2046226 : $0 }
        updated.lengthCm = length.measurementValue.map { imperial ? $0 * 2.54 : $0 }
        updated.notes = notes.isEmpty ? nil : notes
        updated.released = released
        updated.caughtAt = caughtAt
        updated.speciesId = selectedSpeciesId
        updated.spotId = selectedSpotId
        updated.tripId = selectedTripId
        if let coord = coordinate {
            updated.latitude = coord.latitude
            updated.longitude = coord.longitude
            updated.geohash = Geohash.encode(
                latitude: coord.latitude,
                longitude: coord.longitude,
                precision: 7
            )
        }

        // Gear: start from any chosen preset but keep whatever the user
        // actually filled in. If the effective gear differs from the preset,
        // snapshot it onto a HIDDEN loadout so nothing is lost and the named
        // preset is left untouched.
        let hasIndividualGear = !gearRod.isEmpty || !gearReel.isEmpty || !gearLure.isEmpty || !gearTechnique.isEmpty
        if let selected = selectedGearId,
           let preset = allGear.first(where: { $0.id == selected }) {
            let matchesPreset =
                gearRod == (preset.rod ?? "") &&
                gearReel == (preset.reel ?? "") &&
                gearLure == (preset.lure ?? "") &&
                gearLureColor == (preset.lureColor ?? "") &&
                gearTechnique == (preset.technique ?? "")
            if matchesPreset {
                updated.gearLoadoutId = selected
            } else {
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
                updated.gearLoadoutId = hidden.id
            }
        } else if hasIndividualGear {
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
            updated.gearLoadoutId = hidden.id
        } else {
            updated.gearLoadoutId = nil
        }

        onSave(updated)
        ToastCenter.shared.show("Catch updated")
        dismiss()
    }
}

struct GearDetailGrid: View {
    let loadout: GearLoadout

    var items: [(String, String)] {
        var result: [(String, String)] = []
        if let rod = loadout.rod { result.append(("Rod", rod)) }
        if let reel = loadout.reel { result.append(("Reel", reel)) }
        if let line = loadout.lineLb { result.append(("Line", "\(Int(line)) lb")) }
        if let leader = loadout.leaderLb { result.append(("Leader", "\(Int(leader)) lb")) }
        if let lure = loadout.lure {
            var text = lure
            if let color = loadout.lureColor { text += " (\(color))" }
            if let weight = loadout.lureWeightG { text += " \(Int(weight))g" }
            result.append(("Lure", text))
        }
        if let technique = loadout.technique { result.append(("Technique", technique)) }
        return result
    }

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
        ], spacing: 8) {
            ForEach(items, id: \.0) { label, value in
                VStack(alignment: .leading) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Weather Snapshot (for decoding weatherSnapshot JSON)

private struct WeatherSnapshot: Codable {
    var temperatureC: Double?
    var waterTempC: Double?
    var windSpeedKmh: Double?
    var windDirectionDeg: Double?
    var pressureHpa: Double?
    var condition: String?
}

// MARK: - ML Prediction (for decoding mlTop3 JSON)

private struct MLPrediction: Codable {
    var label: String
    var confidence: Double
}
