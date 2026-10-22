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
                    .scrollBounceBehavior(.basedOnSize, axes: [.horizontal])
                }

                PFSearchField(prompt: "Search species", text: $search)

                if !didLoad {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, DS.Space.s6)
                } else if regulations.isEmpty {
                    ContentUnavailableView("Limits not available", systemImage: "list.bullet.clipboard",
                                           description: Text("Check with the local authority before you keep a fish."))
                        .padding(.top, DS.Space.s6)
                } else if filtered.isEmpty {
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

                PFFootnote("A guide only, and it works without signal. Confirm current rules with the local authority before you keep a fish.")
            }
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
        }
        .detailTint(.purple)
        .pfTrackScroll($titleShown, threshold: 60)
        .pfScrollTitle("Size and bag limits", shown: titleShown)
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
    @Environment(\.dynamicTypeSize) private var typeSize

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
                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        limitTiles
                        if let closed = reg.closedSeason, !closed.isEmpty {
                            HStack(spacing: 12) {
                                ThumbView(systemImage: "calendar", tint: .dsScoreLow, size: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Closed season")
                                        .foregroundStyle(.dsText)
                                    Text(closed)
                                        .font(.subheadline)
                                        .foregroundStyle(.dsText2)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(DS.Space.s3)
                            .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.horizontal, DS.gutter)
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
                            LegalRangeBar(lengthCm: Double(lengthCm), minCm: reg.minSizeCm, maxCm: reg.maxSizeCm)
                                .padding(.horizontal, DS.Space.s4)
                                .padding(.bottom, DS.Space.s3)
                            Rectangle().fill(Color.dsSeparator).frame(height: 0.5).padding(.leading, DS.Space.s4)
                            verdictRow
                                .padding(.horizontal, DS.Space.s4)
                                .padding(.vertical, 12)
                        }
                        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                        .padding(.horizontal, DS.gutter)
                    }
                }

                if let species {
                    NavigationLink(value: species) {
                        Label("View in the species guide", systemImage: "book.fill")
                    }
                    .buttonStyle(.dsTonal)
                    .padding(.horizontal, DS.gutter)
                }

                PFFootnote("Rules change. Confirm them with the local authority before you keep a fish.")
            }
            .padding(.vertical, DS.Space.s4)
            .pageWidth()
        }
        .dsScreenBackground()
        .detailScrollEdge()
        .navigationDestination(for: Species.self) { SpeciesDetailView(species: $0) }
        .navigationTitle(reg.commonName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task {
            species = (try? appState.speciesRepository.fetchByScientificName(reg.scientificName)) ?? nil
            if let mn = reg.minSizeCm { lengthCm = Int(mn) }
            else if let mx = reg.maxSizeCm { lengthCm = Int(mx) }
        }
    }

    /// Minimum, maximum and daily bag as big numbers, side by side, stacked
    /// at accessibility sizes.
    @ViewBuilder private var limitTiles: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: DS.Space.s2))
            : AnyLayout(HStackLayout(spacing: DS.Space.s2))
        layout {
            StatTile("Minimum", systemImage: "ruler", tint: .purple,
                     value: reg.minSizeCm.map { "\(Int($0))" } ?? "None",
                     unit: reg.minSizeCm == nil ? nil : "cm",
                     footnote: reg.minSizeCm == nil ? nil : "Total length", width: nil)
            if let mx = reg.maxSizeCm {
                StatTile("Maximum", systemImage: "ruler", tint: .purple,
                         value: "\(Int(mx))", unit: "cm", footnote: "Total length", width: nil)
            }
            StatTile("Daily bag", systemImage: "basket.fill", tint: reg.bagLimit == 0 ? Color.dsScoreSlow : Color.purple,
                     value: reg.bagLimit.map { $0 == 0 ? "No take" : "\($0)" } ?? "None",
                     footnote: (reg.bagLimit ?? 0) > 0 ? "Per person" : nil, width: nil)
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

/// The legal window on a ruler: red where the fish must go back, green where
/// it may be kept, and a marker at the length being checked.
private struct LegalRangeBar: View {
    let lengthCm: Double
    let minCm: Double?
    let maxCm: Double?
    @ScaledMetric(relativeTo: .caption2) private var labelHeight: CGFloat = 16
    private let barHeight: CGFloat = 10

    /// The ruler runs a little past the largest number on it.
    private var upper: Double {
        let top = maxCm ?? (minCm ?? 0) * 1.6
        return max(top, lengthCm, 10) * 1.15
    }

    var body: some View {
        Canvas { context, size in
            let barTop: CGFloat = 5
            let x = { (cm: Double) -> CGFloat in CGFloat(min(max(cm / upper, 0), 1)) * size.width }
            let track = CGRect(x: 0, y: barTop, width: size.width, height: barHeight)

            var bar = context
            bar.clip(to: Path(roundedRect: track, cornerRadius: barHeight / 2))
            bar.fill(Path(track), with: .color(Color.dsScoreSlow.opacity(0.35)))
            let legalStart = x(minCm ?? 0)
            let legal = CGRect(x: legalStart, y: barTop, width: x(maxCm ?? upper) - legalStart, height: barHeight)
            bar.fill(Path(legal), with: .color(Color.dsScoreGood.opacity(0.7)))

            let markerX = min(max(x(lengthCm), 2), size.width - 2)
            let marker = CGRect(x: markerX - 2, y: 0, width: 4, height: barHeight + barTop * 2)
            context.fill(Path(roundedRect: marker, cornerRadius: 2), with: .color(Color.dsText))

            for cm in [minCm, maxCm].compactMap({ $0 }) {
                let label = context.resolve(Text("\(Int(cm)) cm")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.dsText2))
                let half = label.measure(in: size).width / 2
                let centre = min(max(x(cm), half), size.width - half)
                context.draw(label, at: CGPoint(x: centre, y: barTop * 2 + barHeight + 4), anchor: .top)
            }
        }
        .frame(height: barHeight + 14 + labelHeight)
        .accessibilityHidden(true)
    }
}
