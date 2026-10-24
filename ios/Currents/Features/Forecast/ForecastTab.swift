import SwiftUI

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
        case .target:
            TargetPage(store: store)
        }
    }
}

/// Choose the species the forecast and lures are tuned for, or none for a
/// general forecast. Pushed from the target page. Saves the shared
/// `targetSpeciesId` the species page's Target button also writes, with
/// recent targets at the top.
struct TargetSpeciesPage: View {
    let store: ForecastStore

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("targetSpeciesId") private var targetSpeciesId: Int = 0
    @AppStorage(RecentTargets.key) private var recentTargets = ""
    @AppStorage("units") private var units = "metric"
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

    /// Recent targets, shown above the list until a search or filter starts.
    private var recents: [Species] {
        guard search.isEmpty, habitat == .all else { return [] }
        let byId = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return RecentTargets.ids(recentTargets).compactMap { byId[$0] }
    }

    var body: some View {
        let rows = filtered
        let recent = recents
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

            if !recent.isEmpty {
                Section {
                    SectionTitle("Recent")
                        .padding(.top, DS.Space.s4)
                        .dsListRow()
                    ForEach(recent) { sp in
                        speciesRow(sp)
                    }
                }
            }

            if loaded && rows.isEmpty && search.isEmpty {
                Section {
                    InlineEmpty(systemImage: all.isEmpty ? "fish" : "line.3.horizontal.decrease",
                                text: all.isEmpty
                                    ? "The species guide is still being set up. Try again in a moment."
                                    : "No species in this group. Pick another habitat.")
                        .padding(.top, DS.Space.s4)
                        .dsListRow()
                }
            }

            if !rows.isEmpty {
                // A row, not a section header: plain-list headers pin and
                // draw over the rows on this clear background.
                Section {
                    SectionTitle("Species", detail: "\(rows.count)")
                        .padding(.top, DS.Space.s4)
                        .dsListRow()
                    ForEach(rows) { sp in
                        speciesRow(sp)
                    }
                }
            }
        }
        .dsPlainList()
        .detailScrollEdge()
        .overlay {
            if !loaded {
                ProgressView()
            } else if rows.isEmpty && !search.isEmpty {
                ContentUnavailableView.search(text: search)
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

    private func speciesRow(_ sp: Species) -> some View {
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

    private func subtitle(for sp: Species) -> String {
        if let t = sp.optimalTempC {
            return "\(sp.scientificName), best at \(Units.temperature(t, imperial: units == "imperial"))"
        }
        return sp.scientificName
    }

    private func pick(_ sp: Species?) {
        targetSpeciesId = Int(sp?.id ?? 0)
        if let sp { recentTargets = RecentTargets.adding(sp.id, to: recentTargets) }
        store.setSpecies(sp)
        TargetText.announce(sp)
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
        case .only(.freshwater): "Freshwater"
        case .only(.marine): "Saltwater"
        case .only(.brackish): "Estuary"
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
