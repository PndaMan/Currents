import SwiftUI

struct SpeciesBrowserView: View {
    @Environment(AppState.self) private var appState
    @State private var species: [Species] = []
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
                NavigationLink(value: sp.id) {
                    HStack {
                        Image(systemName: "fish.fill")
                            .foregroundStyle(.blue)
                            .frame(width: 40)
                        VStack(alignment: .leading) {
                            Text(sp.commonName)
                                .font(.headline)
                            Text(sp.scientificName)
                                .font(.caption)
                                .italic()
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let habitat = sp.habitat {
                            Text(habitat.rawValue)
                                .font(.caption2)
                                .glassPill()
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: "Search species")
        .navigationTitle("Species")
        .navigationDestination(for: Int64.self) { speciesId in
            if let sp = species.first(where: { $0.id == speciesId }) {
                SpeciesDetailView(species: sp)
            }
        }
        .task {
            species = (try? appState.speciesRepository.fetchAll()) ?? []
        }
    }
}

// FilterChip is defined in LiquidGlass.swift
