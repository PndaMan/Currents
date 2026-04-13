import SwiftUI
import MapKit

struct CatchDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    var detail: CatchDetail
    @State private var showingDeleteConfirm = false
    @State private var showingEdit = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CurrentsTheme.paddingM) {
                // Photo carousel (multi-photo)
                photoCarousel

                // Species + ML confidence
                HStack {
                    VStack(alignment: .leading) {
                        Text(detail.species?.commonName ?? "Unknown Species")
                            .font(.title.bold())
                        if let sci = detail.species?.scientificName {
                            Text(sci)
                                .font(.subheadline)
                                .italic()
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let confidence = detail.catchRecord.mlConfidence {
                        VStack {
                            Text("\(Int(confidence * 100))%")
                                .font(.title3.bold())
                            Text("AI ID")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .glassPill()
                    }
                }

                // Measurements
                if detail.catchRecord.lengthCm != nil || detail.catchRecord.weightKg != nil {
                    HStack(spacing: 16) {
                        if let length = detail.catchRecord.lengthCm {
                            Label(String(format: "%.1f cm", length), systemImage: "ruler")
                                .glassPill()
                        }
                        if let weight = detail.catchRecord.weightKg {
                            Label(String(format: "%.2f kg", weight), systemImage: "scalemass")
                                .glassPill()
                        }
                        if detail.catchRecord.released {
                            Label("Released", systemImage: "arrow.uturn.backward")
                                .glassPill()
                        }
                    }
                }

                // Location map
                locationCard

                // Spot
                if let spot = detail.spot {
                    HStack {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading) {
                            Text(spot.name)
                                .font(.headline)
                            Text(String(format: "%.4f, %.4f", spot.latitude, spot.longitude))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .glassCard()
                }

                // Gear
                if let gear = detail.gearLoadout {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Gear")
                            .font(.headline)
                        Text(gear.name).font(.subheadline.bold())
                        GearDetailGrid(loadout: gear)
                    }
                    .glassCard()
                }

                // Forecast at capture
                if let score = detail.catchRecord.forecastScoreAtCapture {
                    HStack {
                        ScoreGauge(score: score, label: "Forecast")
                        VStack(alignment: .leading) {
                            Text("Conditions at catch time")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .glassCard()
                }

                // Notes
                if let notes = detail.catchRecord.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notes")
                            .font(.headline)
                        Text(notes)
                            .foregroundStyle(.secondary)
                    }
                    .glassCard()
                }

                // Timestamp
                HStack {
                    Image(systemName: "clock")
                    Text(detail.catchRecord.caughtAt, style: .date)
                    Text("at")
                    Text(detail.catchRecord.caughtAt, style: .time)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Catch")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
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
        .alert("Delete Catch?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
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
                }
            )
        }
    }

    // MARK: - Photo Carousel

    @ViewBuilder
    private var photoCarousel: some View {
        let photos = detail.catchRecord.allPhotoPaths
        if photos.count > 1 {
            TabView {
                ForEach(photos, id: \.self) { path in
                    if let image = PhotoManager.load(path) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .tabViewStyle(.page)
            .frame(height: 280)
        } else if let photoPath = photos.first,
                  let image = PhotoManager.load(photoPath) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private var locationCard: some View {
        Map(initialPosition: .camera(.init(
            centerCoordinate: CLLocationCoordinate2D(
                latitude: detail.catchRecord.latitude,
                longitude: detail.catchRecord.longitude
            ),
            distance: 2000
        ))) {
            Annotation("Catch", coordinate: CLLocationCoordinate2D(
                latitude: detail.catchRecord.latitude,
                longitude: detail.catchRecord.longitude
            )) {
                Image(systemName: "fish.circle.fill")
                    .font(.title)
                    .foregroundStyle(.green)
            }
        }
        .mapStyle(.hybrid)
        .frame(height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .allowsHitTesting(false)
    }

    private func deleteCatch() {
        PhotoManager.deleteAll(detail.catchRecord.allPhotoPaths)
        try? appState.catchRepository.delete(detail.catchRecord)
        dismiss()
    }
}

// MARK: - Edit Catch Sheet (Full Field Editing)

struct EditCatchSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
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

    @State private var allSpecies: [Species] = []
    @State private var allSpots: [Spot] = []
    @State private var allGear: [GearLoadout] = []
    @State private var allTrips: [Trip] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Species") {
                    Button {
                        showingSpeciesPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "fish.fill")
                                .foregroundStyle(.blue)
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

                Section("Measurements") {
                    HStack {
                        Text("Weight (kg)")
                        Spacer()
                        TextField("0.00", text: $weight)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    HStack {
                        Text("Length (cm)")
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
                }

                Section("Trip") {
                    Picker("Trip", selection: $selectedTripId) {
                        Text("None").tag(nil as String?)
                        ForEach(allTrips) { trip in
                            Text(trip.name).tag(trip.id as String?)
                        }
                    }
                }

                Section("Gear") {
                    Picker("Loadout", selection: $selectedGearId) {
                        Text("None").tag(nil as String?)
                        ForEach(allGear) { loadout in
                            Text(loadout.name).tag(loadout.id as String?)
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
                // Pre-populate from existing catch
                let c = detail.catchRecord
                weight = c.weightKg.map { String(format: "%.2f", $0) } ?? ""
                length = c.lengthCm.map { String(format: "%.1f", $0) } ?? ""
                notes = c.notes ?? ""
                released = c.released
                caughtAt = c.caughtAt
                selectedSpeciesId = c.speciesId
                selectedSpeciesName = detail.species?.commonName ?? ""
                selectedSpotId = c.spotId
                selectedTripId = c.tripId
                selectedGearId = c.gearLoadoutId

                allSpecies = (try? appState.speciesRepository.fetchAll()) ?? []
                allSpots = (try? appState.spotRepository.fetchAll()) ?? []
                allGear = (try? appState.gearRepository.fetchAll()) ?? []
                allTrips = (try? appState.tripRepository.fetchAll()) ?? []
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

    private func save() {
        var updated = detail.catchRecord
        updated.weightKg = Double(weight)
        updated.lengthCm = Double(length)
        updated.notes = notes.isEmpty ? nil : notes
        updated.released = released
        updated.caughtAt = caughtAt
        updated.speciesId = selectedSpeciesId
        updated.spotId = selectedSpotId
        updated.tripId = selectedTripId
        updated.gearLoadoutId = selectedGearId
        onSave(updated)
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
