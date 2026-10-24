import SwiftUI

/// Browse size and bag limits. Informational only: a footnote makes clear
/// anglers must confirm current local rules. Tap any species for its limits,
/// a quick length check and a link into the species guide.
struct RegulationsView: View {
    @State private var search = ""
    @State private var regulations: [FishingRegulation] = []
    @State private var region: String?
    @State private var selectedId: String?
    @State private var didLoad = false
    @State private var titleShown = false

    private var regions: [String] {
        Array(Set(regulations.map(\.region))).sorted()
    }

    /// Where these limits apply, for the header: the chosen region, or the
    /// only one on file. Nil while several are shown together.
    private var regionLine: String? {
        let named = regions.filter { !$0.isEmpty }
        return region ?? (named.count == 1 ? named.first : nil)
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
                DetailHeader(over: regionLine, title: "Size and bag limits", subtitle: "What you may keep, by species")

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
                            Button { selectedId = reg.id } label: { RegulationRow(reg: reg) }
                                .buttonStyle(.dim)
                        }
                    }
                }

                PFFootnote("A guide only, and it works without signal. Confirm current rules with the local authority before you keep a fish.")
            }
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
        }
        .detailTint(nil)
        .pfTrackScroll($titleShown, threshold: 60)
        .pfScrollTitle("Size and bag limits", shown: titleShown)
        .navigationDestination(item: $selectedId) { id in
            if let reg = regulations.first(where: { $0.id == id }) {
                RegulationDetailView(reg: reg)
            }
        }
        .task {
            RegulationsService.shared.load()
            regulations = RegulationsService.shared.all
            didLoad = true
        }
    }
}

/// A size limit in the units setting: "30 cm", or "11.8 in" in imperial.
/// Regulations are written in inches, so imperial never switches to feet.
private func limitLength(_ cm: Double, imperial: Bool) -> String {
    let (value, unit) = Units.lengthParts(cm: cm, imperial: imperial)
    return "\(value) \(unit)"
}

extension FishingRegulation {
    /// "Min 30 cm, 5 per day", for list rows, in the stored units setting.
    var limitSummary: String { limitSummary(imperial: Units.isImperial) }

    /// "Min 30 cm, 5 per day", or "Min 11.8 in, 5 per day" in imperial.
    func limitSummary(imperial: Bool) -> String {
        var parts: [String] = []
        if let mn = minSizeCm { parts.append("Min " + limitLength(mn, imperial: imperial)) }
        if let mx = maxSizeCm { parts.append("max " + limitLength(mx, imperial: imperial)) }
        if parts.isEmpty { parts.append("No size limit") }
        if let bag = bagLimit {
            parts.append(bag == 0 ? "no take, release every fish" : "\(bag) per day")
        } else {
            parts.append("no bag limit")
        }
        return parts.joined(separator: ", ")
    }

    /// The species guide's record for this fish: by scientific name, else by
    /// the whole common name, else by the first of its slash names
    /// ("Geelbek" of "Geelbek / Cape Salmon"). The other slash names are not
    /// tried: several of them name a different fish in the guide.
    @MainActor
    func species(in repository: SpeciesRepository) -> Species? {
        if let match = (try? repository.fetchByScientificName(scientificName)) ?? nil { return match }
        if let match = (try? repository.fetchByCommonName(commonName)) ?? nil { return match }
        let first = commonName.components(separatedBy: "/").first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard !first.isEmpty, first != commonName else { return nil }
        return (try? repository.fetchByCommonName(first)) ?? nil
    }
}

/// One row: the species art thumb, the name and its key limits.
private struct RegulationRow: View {
    let reg: FishingRegulation
    @Environment(AppState.self) private var appState
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("units") private var units = "metric"
    @State private var species: Species?

    private var lines: Int { typeSize.isAccessibilitySize ? 3 : 1 }

    var body: some View {
        HStack(spacing: 14) {
            if let species {
                ThumbView(species: species, size: 56)
            } else {
                // A fish the guide has no record of: the neutral silhouette
                // of a species not found yet, not a bright stand-in colour.
                ThumbView(systemImage: "fish.fill", tint: Color.dsText3, size: 56)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(reg.commonName)
                    .foregroundStyle(.dsText)
                    .lineLimit(lines)
                Text(reg.limitSummary(imperial: units == "imperial"))
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                    .lineLimit(lines)
                if let closed = reg.closedSeason {
                    Label("Closed season: \(closed)", systemImage: "calendar")
                        .font(.footnote)
                        .foregroundStyle(.dsScoreLow)
                        .lineLimit(lines)
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
                species = reg.species(in: appState.speciesRepository)
            }
        }
    }
}

/// Limits for one species: every limit, closed season, notes, a quick length
/// check and a link into the species guide when the fish is in the dataset.
/// Pushed from the list, tinted with the species' art colour.
struct RegulationDetailView: View {
    let reg: FishingRegulation
    @Environment(AppState.self) private var appState
    @State private var species: Species?
    /// The length being checked, in cm. Whole inches when imperial is on.
    @State private var lengthCm: Double = 40
    @AppStorage("units") private var units = "metric"
    @Environment(\.dynamicTypeSize) private var typeSize

    private var imperial: Bool { units == "imperial" }
    private var hasSizeRule: Bool { reg.minSizeCm != nil || reg.maxSizeCm != nil }
    /// One step of the length stepper: 1 cm, or 1 inch in imperial.
    private var stepCm: Double { imperial ? 2.54 : 1 }

    var body: some View {
        TodayPage(reg.commonName, subtitle: reg.scientificName, tint: species?.artTint) {
            if let species {
                ThumbView(species: species, size: 120)
                    .padding(.horizontal, DS.gutter)
            }

            if reg.bagLimit == 0 {
                PFNotice(systemImage: "hand.raised.fill", tint: .dsScoreSlow,
                         title: "No take", message: "Release every \(reg.commonName.lowercased()) you catch.")
            }

            VStack(alignment: .leading, spacing: 0) {
                SectionTitle(reg.region.isEmpty ? "Limits" : "Limits in \(reg.region)")
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
                            PFStepper(value: limitLength(lengthCm, imperial: imperial),
                                      canDecrement: (lengthCm / stepCm).rounded() > 1,
                                      label: "Length") { delta in
                                step(delta)
                            }
                        }
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.vertical, 10)
                        LegalRangeBar(lengthCm: lengthCm, minCm: reg.minSizeCm, maxCm: reg.maxSizeCm,
                                      imperial: imperial)
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
                NavigationLink {
                    SpeciesDetailView(species: species)
                } label: {
                    Label("View in the species guide", systemImage: "book.fill")
                }
                .buttonStyle(.dsTonal)
                .padding(.horizontal, DS.gutter)
            }

            PFFootnote("Rules change. Confirm them with the local authority before you keep a fish.")
        }
        .task {
            species = reg.species(in: appState.speciesRepository)
            if let mn = reg.minSizeCm { lengthCm = snapped(mn, .up) }
            else if let mx = reg.maxSizeCm { lengthCm = snapped(mx, .down) }
        }
    }

    /// A length rounded to the stepper's whole units: cm, or inches in
    /// imperial. Rounding a minimum up and a maximum down keeps the
    /// starting length legal.
    private func snapped(_ cm: Double, _ rule: FloatingPointRoundingRule) -> Double {
        max(1, (cm / stepCm).rounded(rule)) * stepCm
    }

    private func step(_ delta: Int) {
        let whole = max(1, (lengthCm / stepCm).rounded() + Double(delta))
        lengthCm = whole * stepCm
    }

    /// Minimum, maximum and daily bag as big numbers, side by side, stacked
    /// at accessibility sizes.
    @ViewBuilder private var limitTiles: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: DS.Space.s2))
            : AnyLayout(HStackLayout(spacing: DS.Space.s2))
        let minimum = reg.minSizeCm.map { Units.lengthParts(cm: $0, imperial: imperial) }
        layout {
            StatTile("Minimum", systemImage: "ruler", tint: .purple,
                     value: minimum?.0 ?? "None",
                     unit: minimum?.1,
                     footnote: minimum == nil ? nil : "Total length", width: nil)
            if let mx = reg.maxSizeCm {
                let maximum = Units.lengthParts(cm: mx, imperial: imperial)
                StatTile("Maximum", systemImage: "ruler", tint: .purple,
                         value: maximum.0, unit: maximum.1, footnote: "Total length", width: nil)
            }
            StatTile("Daily bag", systemImage: "basket.fill", tint: reg.bagLimit == 0 ? Color.dsScoreSlow : Color.purple,
                     value: reg.bagLimit.map { $0 == 0 ? "No take" : "\($0)" } ?? "None",
                     footnote: (reg.bagLimit ?? 0) > 0 ? "Per person" : nil, width: nil)
        }
    }

    private var verdictRow: some View {
        let length = lengthCm
        let (text, icon, color): (String, String, Color) = {
            if let mn = reg.minSizeCm, length < mn {
                return ("Undersized by \(limitLength(mn - length, imperial: imperial)), release it",
                        "exclamationmark.circle.fill", .dsScoreSlow)
            }
            if let mx = reg.maxSizeCm, length > mx {
                return ("Over the \(limitLength(mx, imperial: imperial)) limit by \(limitLength(length - mx, imperial: imperial)), release it",
                        "exclamationmark.circle.fill", .dsScoreSlow)
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
    var imperial = false
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
                let label = context.resolve(Text(limitLength(cm, imperial: imperial))
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
