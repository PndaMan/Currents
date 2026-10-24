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
/// recent targets at the top, then the fish found around the forecast's
/// place, then every species.
struct TargetSpeciesPage: View {
    let store: ForecastStore

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("targetSpeciesId") private var targetSpeciesId: Int = 0
    @AppStorage(RecentTargets.key) private var recentTargets = ""
    @State private var all: [Species] = []
    /// Fish around the forecast's place, likeliest first.
    @State private var nearbyIds: [Int64] = []
    @State private var loaded = false
    @State private var search = ""
    @State private var habitat: SpeciesHabitatFilter = .all
    @State private var titleShown = false

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

    /// Fish caught or known in the water around the forecast's place, shown
    /// under the recent targets until a search or filter starts. A recent
    /// target is not listed twice.
    private func nearby(excluding recent: [Species]) -> [Species] {
        guard search.isEmpty, habitat == .all else { return [] }
        let byId = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let shown = Set(recent.map(\.id))
        return Array(nearbyIds.filter { !shown.contains($0) }.compactMap { byId[$0] }.prefix(8))
    }

    /// "Near you" at the phone's location, otherwise the place's name.
    private var nearbyTitle: String {
        store.placeName == "Current location" ? "Near you" : "Near \(store.placeName)"
    }

    var body: some View {
        let rows = filtered
        let recent = recents
        let near = nearby(excluding: recent)
        List {
            Section {
                DetailHeader(title: "Target species")
                    .dsListRow()
                // In the list, as on the species guide, rather than the
                // system's floating search capsule.
                PFSearchField(prompt: "Name or family", text: $search)
                    .padding(.top, DS.Space.s2)
                    .dsListRow()
                FilterChips(SpeciesHabitatFilter.options, selection: $habitat, title: { $0.title })
                    .padding(.top, DS.Space.s2)
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

            if !near.isEmpty {
                Section {
                    SectionTitle(nearbyTitle)
                        .padding(.top, DS.Space.s4)
                        .dsListRow()
                    ForEach(near) { sp in
                        speciesRow(sp)
                    }
                }
            }

            if loaded && rows.isEmpty {
                Section {
                    emptyState
                        .padding(.top, DS.Space.s4)
                        .dsListRow()
                }
            }

            if !rows.isEmpty {
                // A row, not a section header: plain-list headers pin and
                // draw over the rows on this clear background.
                Section {
                    SectionTitle("Species", detail: rows.count.formatted())
                        .padding(.top, DS.Space.s4)
                        .dsListRow()
                    ForEach(rows) { sp in
                        speciesRow(sp)
                    }
                }
            }
        }
        .dsPlainList()
        .scrollDismissesKeyboard(.immediately)
        .detailScrollEdge()
        .overlay {
            if !loaded {
                FishLoader(message: "Loading species")
            }
        }
        .forecastTracksTitle($titleShown)
        .forecastInlineTitle("Target species", shown: titleShown)
        .task {
            guard !loaded else { return }
            all = (try? appState.speciesRepository.fetchAll()) ?? []
            nearbyIds = TargetData.nearbySpeciesIds(near: store.coordinate, appState: appState)
            loaded = true
        }
    }

    /// Nothing to list: the guide is not set up yet, the search matches
    /// nothing, or the habitat has no species.
    @ViewBuilder
    private var emptyState: some View {
        if all.isEmpty {
            InlineEmpty(systemImage: "fish",
                        text: "The species guide is still being set up. Try again in a moment.")
        } else if !search.isEmpty {
            InlineEmpty(systemImage: "magnifyingglass",
                        text: "No species found. Try the common name, the family or the scientific name.")
        } else {
            InlineEmpty(systemImage: "line.3.horizontal.decrease",
                        text: "No species in this group. Pick another habitat.")
        }
    }

    private func speciesRow(_ sp: Species) -> some View {
        Button { pick(sp) } label: {
            ArtRow(title: sp.commonName, subtitle: sp.scientificName) {
                ThumbView(species: sp, size: 48)
            } trailing: {
                SpeciesCheckmark(isOn: store.species?.id == sp.id)
            }
        }
        .buttonStyle(.dsRow)
        .dsListRow()
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
