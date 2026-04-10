import SwiftUI

struct CatchDetailView: View {
    @Environment(AppState.self) private var appState
    let detail: CatchDetail

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

                // Spot
                if let spot = detail.spot {
                    Section {
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
                    } header: {
                        Text("Location")
                            .font(.headline)
                    }
                }

                // Gear
                if let gear = detail.gearLoadout {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(gear.name).font(.headline)
                            GearDetailGrid(loadout: gear)
                        }
                    } header: {
                        Text("Gear")
                            .font(.headline)
                    }
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
                    Section {
                        Text(notes)
                    } header: {
                        Text("Notes")
                            .font(.headline)
                    }
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
