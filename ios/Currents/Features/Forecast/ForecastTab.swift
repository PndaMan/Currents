import SwiftUI
import CoreLocation

/// The forecast on its own, for places outside Today (the Explore map opens it
/// as a sheet). Today pushes the same pages onto its own stack instead.
struct ForecastTab: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    var presentedAsSheet: Bool = false
    @State private var store = ForecastStore()

    var body: some View {
        NavigationStack {
            ForecastDayPage(store: store)
                .toolbar {
                    if presentedAsSheet {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { dismiss() }
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { await store.load(force: true) }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Refresh forecast")
                        .disabled(store.isLoading)
                    }
                }
                .navigationDestination(for: ForecastRoute.self) { route in
                    ForecastDestination(store: store, route: route)
                }
        }
        .dsScreenBackground()
        .syncsTargetSpecies(store)
        .task {
            if let loc = appState.locationManager.currentLocation {
                store.setLocation(loc.coordinate, name: "Your location")
            }
            await store.load()
        }
    }
}

/// The page for a forecast route. Declare with
/// `.navigationDestination(for: ForecastRoute.self)` inside the stack's root.
struct ForecastDestination: View {
    let store: ForecastStore
    let route: ForecastRoute

    var body: some View {
        switch route {
        case .day(let offset, let hour):
            ForecastDayPage(store: store, initialDay: offset, initialHour: hour)
        case .week:
            ForecastWeekPage(store: store)
        case .condition(let condition, let day):
            ConditionPage(store: store, condition: condition, dayOffset: day)
        }
    }
}

/// Choose the species the forecast is tuned for, or none for a general one.
struct ForecastSpeciesPickerSheet: View {
    let allSpecies: [Species]
    @Binding var selectedSpecies: Species?
    let onSelect: () -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var loaded: [Species] = []
    @State private var search = ""
    @State private var habitat: HabitatFilter = .all

    init(allSpecies: [Species], selectedSpecies: Binding<Species?>, onSelect: @escaping () -> Void) {
        self.allSpecies = allSpecies
        self._selectedSpecies = selectedSpecies
        self.onSelect = onSelect
    }

    /// Loads the species list itself and reports the pick.
    init(selected: Species?, onPick: @escaping (Species?) -> Void) {
        var current = selected
        self.allSpecies = []
        self._selectedSpecies = Binding(get: { current }, set: { current = $0; onPick($0) })
        self.onSelect = {}
    }

    enum HabitatFilter: Hashable {
        case all
        case only(Species.Habitat)

        static var options: [HabitatFilter] { [.all] + Species.Habitat.allCases.map { .only($0) } }

        var title: String {
            switch self {
            case .all: "All"
            case .only(let h): h.rawValue.capitalized
            }
        }
    }

    private var source: [Species] { allSpecies.isEmpty ? loaded : allSpecies }

    private var filtered: [Species] {
        var result = source
        if case .only(let h) = habitat {
            result = result.filter { $0.habitat == h }
        }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            result = result.filter {
                $0.commonName.lowercased().contains(q)
                    || $0.scientificName.lowercased().contains(q)
                    || ($0.family ?? "").lowercased().contains(q)
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    FilterChips(HabitatFilter.options, selection: $habitat, title: { $0.title })
                        .dsListRow()
                }

                Section {
                    Button { pick(nil) } label: {
                        ArtRow(title: "Any species", subtitle: "General forecast") {
                            ThumbView(systemImage: "globe", tint: DS.accent, size: 48)
                        } trailing: {
                            checkmark(selectedSpecies == nil)
                        }
                    }
                    .buttonStyle(.dsRow)
                    .dsListRow()
                }

                Section {
                    ForEach(filtered) { sp in
                        Button { pick(sp) } label: {
                            ArtRow(title: sp.commonName, subtitle: subtitle(for: sp)) {
                                ThumbView(species: sp, size: 48)
                            } trailing: {
                                checkmark(selectedSpecies?.id == sp.id)
                            }
                        }
                        .buttonStyle(.dsRow)
                        .dsListRow()
                    }
                } header: {
                    Text(filtered.count == 1 ? "1 species" : "\(filtered.count) species")
                }
            }
            .dsPlainList()
            .overlay {
                if filtered.isEmpty && !source.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .navigationTitle("Target species")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Name or family")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            if allSpecies.isEmpty && loaded.isEmpty {
                loaded = (try? appState.speciesRepository.fetchAll()) ?? []
            }
        }
    }

    private func subtitle(for sp: Species) -> String {
        if let t = sp.optimalTempC {
            return "\(sp.scientificName), best at \(Int(t))°"
        }
        return sp.scientificName
    }

    @ViewBuilder
    private func checkmark(_ on: Bool) -> some View {
        if on {
            Image(systemName: "checkmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(DS.accent)
                .accessibilityLabel("Selected")
        }
    }

    private func pick(_ sp: Species?) {
        selectedSpecies = sp
        onSelect()
        dismiss()
    }
}
