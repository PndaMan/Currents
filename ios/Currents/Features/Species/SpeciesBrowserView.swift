import SwiftUI

/// Wrapper to avoid `Int64` collisions in navigationDestination.
struct SpeciesNavID: Hashable {
    let id: Int64
}

struct SpeciesBrowserView: View {
    @Environment(AppState.self) private var appState
    @State private var species: [Species] = []
    @State private var caughtIds: Set<Int64> = []
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
                $0.scientificName.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    var body: some View {
        List {
            // Habitat filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    FilterChip(title: "All", isSelected: selectedHabitat == nil) {
                        selectedHabitat = nil
                    }
                    ForEach(Species.Habitat.allCases, id: \.self) { habitat in
                        FilterChip(
                            title: habitat.rawValue.capitalized,
                            isSelected: selectedHabitat == habitat
                        ) {
                            selectedHabitat = habitat
                        }
                    }
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .padding(.vertical, 4)

            ForEach(filtered) { sp in
                NavigationLink {
                    SpeciesDetailView(species: sp)
                } label: {
                    HStack(spacing: 12) {
                        SpeciesArtworkView(species: sp, caught: caughtIds.contains(sp.id), size: 44)
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sp.commonName)
                                .font(.headline)
                            Text(sp.scientificName)
                                .font(.caption)
                                .italic()
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Label(sp.rarity.label, systemImage: sp.rarity.symbol)
                                .font(.caption2.bold())
                                .foregroundStyle(sp.rarity.color)
                            if let habitat = sp.habitat {
                                Text(habitat.rawValue)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: "Search species")
        .navigationTitle("Species")
        .task {
            species = (try? appState.speciesRepository.fetchAll()) ?? []
            caughtIds = (try? appState.speciesRepository.caughtSpeciesIds()) ?? []
        }
    }
}

// FilterChip is defined in LiquidGlass.swift
