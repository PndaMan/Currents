import SwiftUI

// MARK: - Wording

enum ThrowText {
    /// One line on what the picks are based on: water temperature, clarity,
    /// light and pressure.
    static func why(_ w: WeatherService.WeatherData?, clarity: WaterClarity) -> String {
        let water = clarity.label.lowercased() + " water"
        guard let w else { return "Picked for \(water). The rest fills in when the weather loads." }
        let temp = w.waterTempC.map { "\(Int($0.rounded()))° " } ?? ""
        return "Picked for \(temp)\(water), \(light(w.cloudCoverPct)) and \(pressure(w.pressureChange6h))."
    }

    static func light(_ cloud: Int) -> String {
        if cloud >= 60 { return "low light" }
        if cloud <= 25 { return "bright sun" }
        return "broken cloud"
    }

    static func pressure(_ change: Double) -> String {
        if change < -1 { return "falling pressure" }
        if change > 1 { return "rising pressure" }
        return "steady pressure"
    }

    /// Engine copy joins clauses with dashes; read them as short sentences.
    static func sentence(_ text: String) -> String {
        let parts = text.replacingOccurrences(of: " + ", with: " and ")
            .components(separatedBy: " — ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { capitalised($0) }
        let joined = parts.joined(separator: ". ")
        guard let last = joined.last, !".!?".contains(last) else { return joined }
        return joined + "."
    }

    private static func capitalised(_ text: String) -> String {
        guard let first = text.first else { return text }
        return String(first).uppercased() + text.dropFirst()
    }

    /// "0.5–2 m" reads as "0.5 to 2 m".
    static func depth(_ text: String) -> String {
        text.replacingOccurrences(of: "–", with: " to ")
    }

    /// The first reason that is about the conditions; ownership and your
    /// own catches have their own labelled values.
    static func reason(_ s: LureEngine.Suggestion) -> String? {
        s.reasons.first { !$0.hasPrefix("In your tackle box") && !$0.hasPrefix("Caught you") }
    }

    /// Low light when it is overcast or outside the middle of the day.
    static func isLowLight(_ w: WeatherService.WeatherData?) -> Bool {
        let hour = Calendar.current.component(.hour, from: .now)
        return (w?.cloudCoverPct ?? 0) >= 60 || hour < 7 || hour >= 18
    }
}

// MARK: - One pick

/// A ranked lure: rank, picture, name, colour and how to fish it. The full
/// version adds depth, the reason and your own history as labelled values.
struct LureSuggestionRow: View {
    let suggestion: LureEngine.Suggestion
    let rank: Int
    var full: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text("\(rank)")
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(.dsText2)
                    .frame(minWidth: 16, alignment: .leading)
                    .padding(.top, 2)
                    .accessibilityLabel("Pick \(rank)")

                LureArtView(name: suggestion.lure, size: full ? 64 : 56)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(suggestion.lure)
                            .font(.headline)
                            .foregroundStyle(.dsText)
                        if suggestion.isOwned {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.subheadline)
                                .foregroundStyle(Color.dsScoreGood)
                                .accessibilityLabel("In your tackle box")
                        }
                    }
                    HStack(spacing: 6) {
                        LureColorSwatch(name: suggestion.color, size: 12)
                        Text(suggestion.color)
                            .font(.subheadline)
                            .foregroundStyle(.dsText2)
                    }
                    Text(ThrowText.sentence(suggestion.technique))
                        .font(.subheadline)
                        .foregroundStyle(.dsText2)
                        .lineLimit(full ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }

            if full {
                HStack(alignment: .top, spacing: 20) {
                    ThrowValue(label: "Depth", value: ThrowText.depth(suggestion.depth))
                    if let reason = ThrowText.reason(suggestion) {
                        ThrowValue(label: "Why", value: ThrowText.sentence(reason))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 28 + 64 + 12)

                if suggestion.personalCatches > 0 || suggestion.ownedName != nil {
                    HStack(alignment: .top, spacing: 20) {
                        if suggestion.personalCatches > 0 {
                            ThrowValue(label: "Your catches", value: "\(suggestion.personalCatches)")
                        }
                        if let owned = suggestion.ownedName {
                            ThrowValue(label: "In your tackle box", value: owned)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 28 + 64 + 12)
                }
            }
        }
        .padding(.horizontal, DS.gutter)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A small label over its value.
struct ThrowValue: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.dsText2)
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.dsText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Colour advice as a row of swatches with names.
struct LureColourStrip: View {
    let names: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(names, id: \.self) { name in
                    HStack(spacing: 8) {
                        LureColorSwatch(name: name, size: 18)
                        Text(name)
                            .font(.subheadline)
                            .foregroundStyle(.dsText)
                            .lineLimit(1)
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 12)
                    .padding(.vertical, 8)
                    .background(Color.dsFill, in: Capsule())
                }
            }
            .padding(.horizontal, DS.gutter)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }
}

// MARK: - Which fish

/// The fish a place's picks can be for. Starts on the fish you track when it
/// is known here or can live in this water, otherwise the one you catch most
/// here, then the first the water holds that has bait records.
struct ThrowSpeciesChoice {
    var tracked: Species?
    /// Caught here, most caught first.
    var caught: [Species] = []
    /// Known in this water, with bait records.
    var inWater: [Species] = []
    /// Fresh or salt water; nil when the place does not say.
    var freshwater: Bool?

    struct FishGroup: Identifiable {
        let title: String
        let species: [Species]
        var id: String { title }
    }

    /// Tracked, caught here, then the rest of the water's, each fish once.
    var groups: [FishGroup] {
        let trackedList: [Species] = tracked.map { [$0] } ?? []
        let lists: [(String, [Species])] = [
            ("Tracking", trackedList),
            ("Caught here", caught),
            ("In this water", inWater),
        ]
        var seen = Set<Int64>()
        var result: [FishGroup] = []
        for (title, list) in lists {
            let unseen = list.filter { seen.insert($0.id).inserted }
            if !unseen.isEmpty { result.append(FishGroup(title: title, species: unseen)) }
        }
        return result
    }

    var options: [Species] { groups.flatMap(\.species) }

    /// The fish to start on.
    var suggested: Species? {
        if let tracked, isKnown(tracked) || Self.suits(tracked, freshwater: freshwater) {
            return tracked
        }
        return caught.first ?? inWater.first
    }

    /// The fish picked from the menu while it is still listed, otherwise the
    /// suggested one.
    func species(chosen id: Int64?) -> Species? {
        if let id, let match = options.first(where: { $0.id == id }) { return match }
        return suggested
    }

    private func isKnown(_ species: Species) -> Bool {
        caught.contains { $0.id == species.id } || inWater.contains { $0.id == species.id }
    }

    /// Only a sea fish in fresh water, or a freshwater fish in the sea, does
    /// not fit. Unknown on either side counts as a fit.
    static func suits(_ species: Species, freshwater: Bool?) -> Bool {
        guard let freshwater, let habitat = species.habitat else { return true }
        return freshwater ? habitat != .marine : habitat != .freshwater
    }

    /// Fresh inland, salt at sea, nil for estuaries and general spots.
    static func isFreshwater(_ type: Spot.SpotType) -> Bool? {
        switch type {
        case .lake, .dam, .river, .creek, .pond, .canal: true
        case .beach, .rocks, .pier, .harbour, .reef, .offshore: false
        case .estuary, .general: nil
        }
    }
}

/// "What to throw" with a menu of the fish the picks can be for, the current
/// one checked. The title keeps its space and a long name truncates; at
/// accessibility sizes the menu drops below the title.
struct ThrowSpeciesTitle: View {
    let choice: ThrowSpeciesChoice
    /// The fish picked from the menu; nil follows `choice.suggested`.
    @Binding var chosenId: Int64?

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if let species = choice.species(chosen: chosenId) {
            row(species)
        } else {
            SectionTitle("What to throw")
        }
    }

    private func row(_ species: Species) -> some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Space.s2))
            : AnyLayout(HStackLayout(alignment: .center, spacing: DS.Space.s3))
        return layout {
            Text("What to throw")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.dsText)
                .layoutPriority(1)
                .accessibilityAddTraits(.isHeader)
            if !stacked {
                Spacer(minLength: 0)
            }
            menu(species, lines: stacked ? 2 : 1)
        }
        .padding(.horizontal, DS.gutter)
        .padding(.bottom, DS.Space.s2)
    }

    private func menu(_ species: Species, lines: Int) -> some View {
        Menu {
            Picker("Fish", selection: selection(species)) {
                ForEach(choice.groups) { group in
                    Section(group.title) {
                        ForEach(group.species) { sp in
                            Text(sp.commonName).tag(sp.id)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(species.commonName)
                    .lineLimit(lines)
                    .truncationMode(.tail)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.dsText2)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.dsText)
            .padding(.horizontal, DS.Space.s3)
            .padding(.vertical, 6)
            .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
        }
        .accessibilityLabel("Fish")
        .accessibilityValue(species.commonName)
        .accessibilityHint("Changes which fish the picks are for")
    }

    /// Plays the selection haptic when the menu changes the fish.
    private func selection(_ current: Species) -> Binding<Int64> {
        Binding(get: { current.id }, set: { chosenId = $0 })
            .haptic()
            .animation(DS.Motion.easeOut)
    }
}

// MARK: - Today section

/// What to throw on Today: why, the clarity call, the top three picks and the
/// colours. The title opens every pick.
struct WhatToThrowSection: View {
    let suggestions: [LureEngine.Suggestion]
    let weather: WeatherService.WeatherData?
    let clarity: WaterClarity
    let clarityIsGuess: Bool
    let hasGear: Bool
    let onClarity: (WaterClarity) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: ForecastRoute.lures) {
                SectionTitle("What to throw", chevron: true)
            }
            .buttonStyle(.dim)
            .accessibilityHint("Shows every pick and the colours to use")

            VStack(alignment: .leading, spacing: 12) {
                Text(ThrowText.why(weather, clarity: clarity))
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                    .fixedSize(horizontal: false, vertical: true)
                ClaritySegments(selection: clarity, onSelect: onClarity)
                if clarityIsGuess {
                    Text("Clarity is a guess from recent rain. Tap what you see.")
                        .font(.footnote)
                        .foregroundStyle(.dsText3)
                }
            }
            .padding(.horizontal, DS.gutter)
            .padding(.bottom, 4)

            if suggestions.isEmpty {
                Text("No picks yet. They appear once the weather loads.")
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                    .padding(.horizontal, DS.gutter)
                    .padding(.vertical, 12)
            } else {
                ForEach(Array(suggestions.prefix(3).enumerated()), id: \.element.id) { index, s in
                    NavigationLink(value: ForecastRoute.lures) {
                        LureSuggestionRow(suggestion: s, rank: index + 1)
                    }
                    .buttonStyle(.dsRow)
                }
            }

            Text("Colours for \(clarity.label.lowercased()) water")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.dsText)
                .padding(.horizontal, DS.gutter)
                .padding(.top, 8)
                .padding(.bottom, 8)
            LureColourStrip(names: LureEngine.colors(for: clarity, lowLight: ThrowText.isLowLight(weather)))

            if !hasGear {
                NavigationLink(value: AppRoute.gear) {
                    ArtRow(title: "Add your tackle", subtitle: "Lures you own rank first", chevron: true) {
                        ThumbView(systemImage: "shippingbox", tint: DS.accent, size: 52)
                    }
                }
                .buttonStyle(.dsRow)
                .padding(.top, 8)
            }
        }
    }
}

// MARK: - Full page

/// Every pick for the conditions, with depth, why and your history, then the
/// colours for the water.
struct WhatToThrowPage: View {
    let store: ForecastStore

    @Environment(AppState.self) private var appState
    @AppStorage("waterClarityOverride") private var clarityOverride = ""
    @State private var ownedGear: [OwnedGear] = []
    @State private var history: [CatchDetail] = []
    @State private var loaded = false

    private var weather: WeatherService.WeatherData? { store.weather(for: 0) }

    private var clarity: WaterClarity {
        WaterClarity(rawValue: clarityOverride) ?? WaterClarity.inferred(precipMm: weather?.precipMm)
    }

    private var suggestions: [LureEngine.Suggestion] {
        let conditions = LureEngine.Conditions(
            waterTempC: weather?.waterTempC,
            clarity: clarity,
            cloudCoverPct: weather?.cloudCoverPct,
            windSpeedKmh: weather?.windSpeedKmh,
            pressureChange6h: weather?.pressureChange6h
        )
        return LureEngine.recommend(conditions: conditions, species: store.species,
                                    ownedGear: ownedGear, history: history)
    }

    var body: some View {
        let picks = suggestions
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DetailHeader(over: store.species.map { "Targeting \($0.commonName)" } ?? store.placeName,
                             title: "What to throw",
                             subtitle: ThrowText.why(weather, clarity: clarity))

                VStack(alignment: .leading, spacing: 8) {
                    ClaritySegments(selection: clarity) { clarityOverride = $0.rawValue }
                    Text("\(clarity.label): \(clarity.detail.lowercased()).")
                        .font(.footnote)
                        .foregroundStyle(.dsText2)
                }
                .padding(.horizontal, DS.gutter)
                .padding(.top, 20)
                .padding(.bottom, 24)

                SectionTitle("Best picks", detail: picks.isEmpty ? nil : "\(picks.count)")
                if picks.isEmpty && loaded {
                    ContentUnavailableView("No picks yet", systemImage: "fish",
                                           description: Text("Picks appear once the weather has loaded."))
                        .padding(.vertical, 20)
                } else {
                    ForEach(Array(picks.enumerated()), id: \.element.id) { index, s in
                        LureSuggestionRow(suggestion: s, rank: index + 1, full: true)
                        if index < picks.count - 1 {
                            Divider()
                                .overlay(Color.dsSeparator)
                                .padding(.leading, DS.gutter + 28 + 64 + 12)
                        }
                    }
                }

                SectionTitle("Colours for \(clarity.label.lowercased()) water")
                    .padding(.top, 24)
                LureColourStrip(names: LureEngine.colors(for: clarity, lowLight: ThrowText.isLowLight(weather)))

                Text(ownedGear.isEmpty
                     ? "Add your tackle in Profile and the lures you own rank first."
                     : "Lures you own rank first.")
                    .font(.footnote)
                    .foregroundStyle(.dsText2)
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, 20)
            }
            .padding(.top, 8)
            .padding(.bottom, 40)
            .pageWidth()
        }
        .detailTint(DS.accent)
        .navigationTitle("What to throw")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            ownedGear = (try? appState.ownedGearRepository.fetchAll()) ?? []
            history = (try? appState.catchRepository.fetchAll(limit: 200)) ?? []
            loaded = true
        }
    }
}
