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
                store.setLocation(loc.coordinate, name: "Current location")
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
        case .lures:
            WhatToThrowPage(store: store)
        case .targetSpecies:
            TargetSpeciesPage(store: store)
        }
    }
}

/// Choose the species the forecast and lures are tuned for, or none for a
/// general forecast. Pushed from Today and the day page. Saves the shared
/// `targetSpeciesId` the species page's Target button also writes.
struct TargetSpeciesPage: View {
    let store: ForecastStore

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("targetSpeciesId") private var targetSpeciesId: Int = 0
    @State private var all: [Species] = []
    @State private var loaded = false
    @State private var search = ""
    @State private var habitat: SpeciesHabitatFilter = .all

    private var filtered: [Species] {
        var result = all
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
        let rows = filtered
        List {
            Section {
                FilterChips(SpeciesHabitatFilter.options, selection: $habitat, title: { $0.title })
                    .dsListRow()
                Button { pick(nil) } label: {
                    ArtRow(title: "Any species", subtitle: "General forecast and lures") {
                        ThumbView(systemImage: "scope", tint: DS.accent, size: 48)
                    } trailing: {
                        SpeciesCheckmark(isOn: store.species == nil)
                    }
                }
                .buttonStyle(.dsRow)
                .dsListRow()
            }

            if !rows.isEmpty {
                // A row, not a section header: plain-list headers pin and
                // draw over the rows on this clear background.
                Section {
                    SectionTitle("Species", detail: "\(rows.count)")
                        .padding(.top, DS.Space.s4)
                        .dsListRow()
                    ForEach(rows) { sp in
                        Button { pick(sp) } label: {
                            ArtRow(title: sp.commonName, subtitle: subtitle(for: sp)) {
                                ThumbView(species: sp, size: 48)
                            } trailing: {
                                SpeciesCheckmark(isOn: store.species?.id == sp.id)
                            }
                        }
                        .buttonStyle(.dsRow)
                        .dsListRow()
                    }
                }
            }
        }
        .dsPlainList()
        .detailScrollEdge()
        .overlay {
            if !loaded {
                ProgressView()
            } else if all.isEmpty {
                ContentUnavailableView("No species yet", systemImage: "fish",
                                       description: Text("The species guide is still being set up. Try again in a moment."))
            } else if rows.isEmpty {
                if search.isEmpty {
                    ContentUnavailableView("None in this group", systemImage: "line.3.horizontal.decrease",
                                           description: Text("Pick another habitat."))
                } else {
                    ContentUnavailableView.search(text: search)
                }
            }
        }
        .navigationTitle("Target species")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Name or family")
        .task {
            guard !loaded else { return }
            all = (try? appState.speciesRepository.fetchAll()) ?? []
            loaded = true
        }
    }

    private func subtitle(for sp: Species) -> String {
        if let t = sp.optimalTempC {
            return "\(sp.scientificName), best at \(Int(t))°"
        }
        return sp.scientificName
    }

    private func pick(_ sp: Species?) {
        targetSpeciesId = Int(sp?.id ?? 0)
        store.setSpecies(sp)
        ToastCenter.shared.show(sp.map { "Targeting \($0.commonName)" } ?? "Forecast for any species",
                                style: .info, haptic: false, icon: "scope")
        dismiss()
    }
}

/// Habitat filter for the species list.
enum SpeciesHabitatFilter: Hashable {
    case all
    case only(Species.Habitat)

    static var options: [SpeciesHabitatFilter] { [.all] + Species.Habitat.allCases.map { .only($0) } }

    var title: String {
        switch self {
        case .all: "All"
        case .only(let h): h.rawValue.capitalized
        }
    }
}

private struct SpeciesCheckmark: View {
    let isOn: Bool

    var body: some View {
        if isOn {
            Image(systemName: "checkmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(DS.accent)
                .accessibilityLabel("Selected")
        }
    }
}
