import SwiftUI
import MapKit

struct CatchDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    var detail: CatchDetail
    @State private var showingDeleteConfirm = false
    @State private var showingEdit = false
    @State private var editWeight: String = ""
    @State private var editLength: String = ""
    @State private var editNotes: String = ""
    @State private var editReleased: Bool = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CurrentsTheme.paddingM) {
                // Photo
                if let photoPath = detail.catchRecord.photoPath,
                   let image = PhotoManager.load(photoPath) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }

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
                        editWeight = detail.catchRecord.weightKg.map { String(format: "%.2f", $0) } ?? ""
                        editLength = detail.catchRecord.lengthCm.map { String(format: "%.1f", $0) } ?? ""
                        editNotes = detail.catchRecord.notes ?? ""
                        editReleased = detail.catchRecord.released
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
                catchRecord: detail.catchRecord,
                weight: $editWeight,
                length: $editLength,
                notes: $editNotes,
                released: $editReleased,
                onSave: { updated in
                    var record = updated
                    try? appState.catchRepository.save(&record)
                }
            )
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
        if let photoPath = detail.catchRecord.photoPath {
            PhotoManager.delete(photoPath)
        }
        try? appState.catchRepository.delete(detail.catchRecord)
        dismiss()
    }
}

// MARK: - Edit Catch Sheet

struct EditCatchSheet: View {
    @Environment(\.dismiss) private var dismiss
    let catchRecord: Catch
    @Binding var weight: String
    @Binding var length: String
    @Binding var notes: String
    @Binding var released: Bool
    let onSave: (Catch) -> Void

    var body: some View {
        NavigationStack {
            Form {
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
                    Button("Save") {
                        var updated = catchRecord
                        updated.weightKg = Double(weight)
                        updated.lengthCm = Double(length)
                        updated.notes = notes.isEmpty ? nil : notes
                        updated.released = released
                        onSave(updated)
                        dismiss()
                    }
                    .bold()
                }
            }
        }
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
