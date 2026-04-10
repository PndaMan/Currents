import SwiftUI

struct SpeciesDetailView: View {
    let species: Species

    var body: some View {
        List {
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "fish.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.blue)
                        Text(species.commonName)
                            .font(.title2.bold())
                        Text(species.scientificName)
                            .font(.subheadline)
                            .italic()
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .listRowBackground(Color.clear)

            Section("Classification") {
                if let family = species.family {
                    LabeledContent("Family", value: family)
                }
                if let habitat = species.habitat {
                    LabeledContent("Habitat", value: habitat.rawValue.capitalized)
                }
                if let fbId = species.fishbaseId {
                    LabeledContent("FishBase ID", value: "\(fbId)")
                }
            }

            if species.minTempC != nil || species.optimalTempC != nil || species.maxTempC != nil {
                Section("Temperature Range") {
                    HStack(spacing: 0) {
                        if let min = species.minTempC {
                            tempBlock(value: min, label: "Min", color: .blue)
                        }
                        if let optimal = species.optimalTempC {
                            tempBlock(value: optimal, label: "Optimal", color: .green)
                        }
                        if let max = species.maxTempC {
                            tempBlock(value: max, label: "Max", color: .red)
                        }
                    }
                }
            }
        }
        .navigationTitle(species.commonName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tempBlock(value: Double, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(String(format: "%.0f°C", value))
                .font(.title3.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
