import SwiftUI

/// Browse size and bag limits. Informational only: a footnote makes clear
/// anglers must confirm current local rules. Tap any species for its limits,
/// a quick length check and a link into the species guide.
struct RegulationsView: View {
    @State private var search = ""
    @State private var regulations: [FishingRegulation] = []
    @State private var region: String?
    @State private var selected: FishingRegulation?
    @State private var didLoad = false
    @State private var titleShown = false

    private var regions: [String] {
        Array(Set(regulations.map(\.region))).sorted()
    }

    private var filtered: [FishingRegulation] {
        regulations.filter {
            (region == nil || $0.region == region)
            && (search.isEmpty
                || $0.commonName.localizedCaseInsensitiveContains(search)
                || $0.scientificName.localizedCaseInsensitiveContains(search))
        }
        .sorted { $0.commonName < $1.commonName }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                DetailHeader(title: "Size and bag limits", subtitle: "What you may keep, by species")

                if regions.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            Chip("All", isSelected: region == nil) { region = nil }
                            ForEach(regions, id: \.self) { r in
                                Chip(r, isSelected: region == r) { region = region == r ? nil : r }
                            }
                        }
                        .padding(.horizontal, DS.gutter)
                    }
                    .sensoryFeedback(.selection, trigger: region)
                }

                PFSearchField(prompt: "Search species", text: $search)

                if didLoad && filtered.isEmpty {
                    ContentUnavailableView("No rules for that species", systemImage: "magnifyingglass",
                                           description: Text("It may have no limits here. Check with the local authority."))
                        .padding(.top, DS.Space.s6)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { reg in
                            Button { selected = reg } label: { RegulationRow(reg: reg) }
                                .buttonStyle(.dim)
                        }
                    }
                }

                PFFootnote("Bundled with Currents and works without signal. Informational only: rules change and vary by area and permit, so confirm the current rules with the local authority before you keep a fish.")
            }
            .padding(.bottom, DS.Space.s8)
        }
        .detailTint(.purple)
        .pfTrackScroll($titleShown, threshold: 60)
        .pfScrollTitle("Size and bag limits", shown: titleShown)
        .sensoryFeedback(.selection, trigger: selected?.id)
        .sheet(item: $selected) { reg in
            NavigationStack { RegulationDetailView(reg: reg) }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task {
            RegulationsService.shared.load()
            regulations = RegulationsService.shared.all
            didLoad = true
        }
    }
}

extension FishingRegulation {
    /// "Min 30 cm, 5 per day", for list rows.
    var limitSummary: String {
        var parts: [String] = []
        if let mn = minSizeCm { parts.append("Min \(Int(mn)) cm") }
        if let mx = maxSizeCm { parts.append("max \(Int(mx)) cm") }
        if parts.isEmpty { parts.append("No size limit") }
        if let bag = bagLimit {
            parts.append(bag == 0 ? "no take, release every fish" : "\(bag) per day")
        } else {
            parts.append("no bag limit")
        }
        return parts.joined(separator: ", ")
    }
}

/// One row: the species art thumb, the name and its key limits.
private struct RegulationRow: View {
    let reg: FishingRegulation
    @Environment(AppState.self) private var appState
    @State private var species: Species?

    var body: some View {
        HStack(spacing: 14) {
            if let species {
                ThumbView(species: species, size: 56)
            } else {
                ThumbView(systemImage: "fish.fill", tint: .purple, size: 56)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(reg.commonName)
                    .foregroundStyle(.dsText)
                    .lineLimit(1)
                Text(reg.limitSummary)
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                    .lineLimit(1)
                if let closed = reg.closedSeason {
                    Label("Closed season: \(closed)", systemImage: "calendar")
                        .font(.footnote)
                        .foregroundStyle(.dsScoreLow)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.dsText3)
        }
        .padding(.horizontal, DS.gutter)
        .padding(.vertical, DS.Space.s2)
        .contentShape(Rectangle())
        .task {
            if species == nil {
                species = (try? appState.speciesRepository.fetchByScientificName(reg.scientificName)) ?? nil
            }
        }
    }
}

/// Limits for one species: every limit, closed season, notes, a quick length
/// check and a link into the species guide when the fish is in the dataset.
struct RegulationDetailView: View {
    let reg: FishingRegulation
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var species: Species?
    @State private var lengthCm: Int = 40

    private var rows: [(String, String)] {
        var result: [(String, String)] = [
            ("Minimum size", reg.minSizeCm.map { "\(Int($0)) cm" } ?? "None"),
        ]
        if let mx = reg.maxSizeCm { result.append(("Maximum size", "\(Int(mx)) cm")) }
        result.append(("Daily bag", reg.bagLimit.map { $0 == 0 ? "No take" : "\($0) per person" } ?? "None"))
        result.append(("Closed season", reg.closedSeason ?? "None"))
        return result
    }

    private var hasSizeRule: Bool { reg.minSizeCm != nil || reg.maxSizeCm != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s5) {
                if let species {
                    ThumbView(species: species, size: 120)
                        .padding(.horizontal, DS.gutter)
                }
                DetailHeader(over: reg.region, title: reg.commonName, subtitle: reg.scientificName)

                if reg.bagLimit == 0 {
                    PFNotice(systemImage: "hand.raised.fill", tint: .dsScoreSlow,
                             title: "No take", message: "Release every \(reg.commonName.lowercased()) you catch.")
                }

                VStack(alignment: .leading, spacing: 0) {
                    SectionTitle("Limits")
                    PFKeyValueCard(rows: rows)
                }

                if let notes = reg.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionTitle("Notes")
                        Text(notes)
                            .foregroundStyle(.dsText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(DS.Space.s4)
                            .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                            .padding(.horizontal, DS.gutter)
                    }
                }

                if hasSizeRule && reg.bagLimit != 0 {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionTitle("Check a fish")
                        VStack(spacing: 0) {
                            HStack {
                                Text("Length").foregroundStyle(.dsText)
                                Spacer()
                                PFStepper(value: "\(lengthCm) cm", canDecrement: lengthCm > 1, label: "Length") { delta in
                                    lengthCm = max(1, lengthCm + delta)
                                }
                            }
                            .padding(.horizontal, DS.Space.s4)
                            .padding(.vertical, 10)
                            Rectangle().fill(Color.dsSeparator).frame(height: 0.5).padding(.leading, DS.Space.s4)
                            verdictRow
                                .padding(.horizontal, DS.Space.s4)
                                .padding(.vertical, 12)
                        }
                        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                        .padding(.horizontal, DS.gutter)
                        .sensoryFeedback(.selection, trigger: lengthCm)
                    }
                }

                if let species {
                    NavigationLink {
                        SpeciesDetailView(species: species)
                    } label: {
                        Label("View in the species guide", systemImage: "book.fill")
                    }
                    .buttonStyle(.dsTonal)
                    .padding(.horizontal, DS.gutter)
                }

                PFFootnote("Rules change and vary by area and permit. Confirm the current rules before you keep a fish.")
            }
            .padding(.vertical, DS.Space.s4)
        }
        .dsScreenBackground()
        .navigationTitle(reg.commonName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task {
            species = (try? appState.speciesRepository.fetchByScientificName(reg.scientificName)) ?? nil
            if let mn = reg.minSizeCm { lengthCm = Int(mn) }
            else if let mx = reg.maxSizeCm { lengthCm = Int(mx) }
        }
    }

    private var verdictRow: some View {
        let length = Double(lengthCm)
        let (text, icon, color): (String, String, Color) = {
            if let mn = reg.minSizeCm, length < mn {
                return ("Undersized by \(Int(mn - length)) cm, release it", "exclamationmark.circle.fill", .dsScoreSlow)
            }
            if let mx = reg.maxSizeCm, length > mx {
                return ("Over the \(Int(mx)) cm limit by \(Int(length - mx)) cm, release it", "exclamationmark.circle.fill", .dsScoreSlow)
            }
            return ("Legal size to keep", "checkmark.circle.fill", .dsScoreGood)
        }()
        return Label(text, systemImage: icon)
            .font(.body.weight(.semibold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentTransition(.opacity)
            .accessibilityAddTraits(.updatesFrequently)
    }
}
