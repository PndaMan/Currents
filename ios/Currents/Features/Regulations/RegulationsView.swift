import SwiftUI

/// Browse size & bag limits. Informational only — a disclaimer makes clear
/// anglers must confirm current local rules.
struct RegulationsView: View {
    @State private var search = ""

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
                        VStack(alignment: .leading, spacing: 4) {
                            Text(reg.commonName).font(.subheadline.bold())
                            Text(reg.scientificName).font(.caption2).italic().foregroundStyle(.secondary)
                            HStack(spacing: 10) {
                                if let mn = reg.minSizeCm {
                                    limitPill("Min \(Int(mn)) cm", "ruler")
                                }
                                if let mx = reg.maxSizeCm {
                                    limitPill("Max \(Int(mx)) cm", "ruler")
                                }
                                if let bag = reg.bagLimit {
                                    limitPill("Bag \(bag)", "number")
                                }
                            }
                            if let closed = reg.closedSeason {
                                Label(closed, systemImage: "calendar.badge.exclamationmark")
                                    .font(.caption2).foregroundStyle(.orange)
                            }
                            if let notes = reg.notes {
                                Text(notes).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("Regulations")
        .searchable(text: $search, prompt: "Search species")
        .task { RegulationsService.shared.load() }
    }

    private func limitPill(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption2.bold())
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(.ultraThinMaterial, in: Capsule())
    }
}
