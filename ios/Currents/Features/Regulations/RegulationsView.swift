import SwiftUI

/// Browse size & bag limits. Informational only — a disclaimer makes clear
/// anglers must confirm current local rules. Tap any species for the full
/// detail card with its artwork and a link into the species guide.
struct RegulationsView: View {
    @State private var search = ""
    @State private var selected: FishingRegulation?

    private var grouped: [(region: String, regs: [FishingRegulation])] {
        let all = RegulationsService.shared.all.filter {
            search.isEmpty
            || $0.commonName.localizedCaseInsensitiveContains(search)
            || $0.scientificName.localizedCaseInsensitiveContains(search)
        }
        let dict = Dictionary(grouping: all, by: \.region)
        return dict.keys.sorted().map { ($0, dict[$0]!.sorted { $0.commonName < $1.commonName }) }
    }

    var body: some View {
        List {
            Section {
                Label("Informational only — regulations change and vary by area and permit. Always confirm current local rules before keeping a fish.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(grouped, id: \.region) { group in
                Section(group.region) {
                    ForEach(group.regs) { reg in
                        Button { selected = reg } label: { RegulationRow(reg: reg) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Regulations")
        .searchable(text: $search, prompt: "Search species")
        .sheet(item: $selected) { reg in
            NavigationStack { RegulationDetailView(reg: reg) }
                .presentationDragIndicator(.visible)
        }
        .task { RegulationsService.shared.load() }
    }
}

/// One compact row: a fish artwork bubble, the name, and its key limits.
private struct RegulationRow: View {
    let reg: FishingRegulation
    @Environment(AppState.self) private var appState
    @State private var species: Species?

    var body: some View {
        HStack(spacing: 12) {
            RegulationFishBubble(species: species, size: 46)
            VStack(alignment: .leading, spacing: 4) {
                Text(reg.commonName).font(.subheadline.bold())
                Text(reg.scientificName).font(.caption2).italic().foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    if let mn = reg.minSizeCm { limitPill("Min \(Int(mn)) cm", "ruler") }
                    if let mx = reg.maxSizeCm { limitPill("Max \(Int(mx)) cm", "ruler") }
                    if let bag = reg.bagLimit {
                        limitPill(bag == 0 ? "No-take" : "Bag \(bag)", bag == 0 ? "hand.raised.fill" : "number")
                    }
                }
                if reg.closedSeason != nil {
                    Label("Seasonal closure", systemImage: "calendar.badge.exclamationmark")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .task {
            if species == nil {
                species = (try? appState.speciesRepository.fetchByScientificName(reg.scientificName)) ?? nil
            }
        }
    }

    private func limitPill(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption2.bold())
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(.ultraThinMaterial, in: Capsule())
    }
}

/// The fish artwork in a soft circular bubble, or a fallback fish glyph when the
/// species isn't in the guide.
private struct RegulationFishBubble: View {
    let species: Species?
    var size: CGFloat = 46
    var body: some View {
        ZStack {
            Circle().fill(CurrentsTheme.accent.opacity(0.12)).frame(width: size, height: size)
            if let species {
                SpeciesArtworkView(species: species, caught: true, size: size * 0.82)
            } else {
                Image(systemName: "fish.fill")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(CurrentsTheme.accent.opacity(0.7))
            }
        }
        .frame(width: size, height: size)
    }
}

/// Full detail card for a regulation: big artwork, every limit, closed season,
/// notes, and a link into the species guide when the fish is in the dataset.
struct RegulationDetailView: View {
    let reg: FishingRegulation
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var species: Species?

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    RegulationFishBubble(species: species, size: 120)
                    Text(reg.commonName).font(.title3.bold()).multilineTextAlignment(.center)
                    Text(reg.scientificName).font(.caption).italic().foregroundStyle(.secondary)
                    Text(reg.region).font(.caption2).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 6)
                .listRowBackground(Color.clear)
            }

            Section("Limits") {
                if let mn = reg.minSizeCm { limitRow("Minimum size", "\(Int(mn)) cm", "ruler") }
                if let mx = reg.maxSizeCm { limitRow("Maximum size", "\(Int(mx)) cm", "ruler") }
                if let bag = reg.bagLimit {
                    limitRow("Bag limit", bag == 0 ? "No-take (release)" : "\(bag) per person/day",
                             bag == 0 ? "hand.raised.fill" : "number")
                }
                if let closed = reg.closedSeason {
                    limitRow("Closed season", closed, "calendar.badge.exclamationmark", tint: .orange)
                }
                if reg.minSizeCm == nil && reg.maxSizeCm == nil && reg.bagLimit == nil {
                    Text("No size or bag limit on file — still confirm local rules.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if let notes = reg.notes {
                Section("Notes") {
                    Text(notes).font(.subheadline)
                }
            }

            if let species {
                Section {
                    NavigationLink { SpeciesDetailView(species: species) } label: {
                        Label("View in Species Guide", systemImage: "book.fill")
                    }
                }
            }

            Section {
                Label("Regulations change and vary by area and permit — always confirm current local rules before keeping a fish.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Regulation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task {
            species = (try? appState.speciesRepository.fetchByScientificName(reg.scientificName)) ?? nil
        }
    }

    private func limitRow(_ label: String, _ value: String, _ icon: String, tint: Color = CurrentsTheme.accent) -> some View {
        HStack {
            Label(label, systemImage: icon).foregroundStyle(tint)
            Spacer()
            Text(value).font(.subheadline.bold()).foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
    }
}
