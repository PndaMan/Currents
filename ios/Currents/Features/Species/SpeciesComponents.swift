import SwiftUI

/// Push value for a species page. Carries the record so the destination
/// doesn't need a lookup; distinct from `Species` so it never collides with
/// other screens' `navigationDestination(for: Species.self)`.
struct SpeciesRoute: Hashable {
    let species: Species
}

/// The species page's `.navigationTransition(.zoom)` source, when the push
/// came from a thumbnail that registered one.
struct SpeciesZoomSource {
    let id: Int64
    let namespace: Namespace.ID
}

/// Twelve tiny bars, one per month, the selected month highlighted, over a
/// caption naming the peak months ("Nov to Mar"): the peak that holds the
/// selected month, else the best one. Used at the end of species guide rows.
struct SeasonMiniBars: View {
    let scores: [Int]
    let highlight: Int   // 1 to 12
    var tint: Color = DS.accent
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(scores.enumerated()), id: \.offset) { index, score in
                    Capsule()
                        .fill(index + 1 == highlight ? tint : Color.dsText3)
                        .opacity(index + 1 == highlight ? 1 : 0.55)
                        .frame(width: 3, height: max(4, 22 * CGFloat(score) / 100))
                }
            }
            .frame(height: 22, alignment: .bottom)
            if let caption = SpeciesSeason.shortPeakText(scores, month: highlight) {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.dsText2)
                    .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(scores.isEmpty ? "Season not known"
                            : SpeciesSeason.peakText(scores, month: highlight) ?? "No clear peak season")
    }
}

/// The species page season chart: twelve bars, in-season months in the
/// species colour, the current month marked under the axis.
struct SeasonChart: View {
    let scores: [Int]
    let inSeason: [Bool]
    let tint: Color
    var currentMonth: Int = SpeciesSeason.currentMonth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(0..<12, id: \.self) { i in
                    let score = i < scores.count ? scores[i] : 0
                    let on = i < inSeason.count && inSeason[i]
                    RoundedRectangle(cornerRadius: DS.Radius.thumb / 2, style: .continuous) // ui-lint: allow, chart bar not a card
                        .fill(on ? tint : Color.dsText.opacity(0.16))
                        .frame(height: max(8, 130 * CGFloat(grown ? score : 0) / 100))
                        .frame(maxWidth: .infinity)
                        .animation(reduceMotion ? nil : DS.Motion.softSpring.delay(Double(i) * 0.03), value: grown)
                }
            }
            .frame(height: 130, alignment: .bottom)
            HStack(spacing: 6) {
                ForEach(0..<12, id: \.self) { i in
                    let isNow = i + 1 == currentMonth
                    VStack(spacing: 2) {
                        Text(String(SpeciesSeason.shortMonths[i].prefix(1)))
                            .font(.caption.weight(isNow ? .bold : .regular))
                            .foregroundStyle(isNow ? Color.dsText : Color.dsText2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Circle()
                            .fill(isNow ? Color.dsText : .clear)
                            .frame(width: 4, height: 4)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            // Twelve letters side by side outgrow a phone at the largest
            // accessibility sizes; the chart reads as a whole for VoiceOver.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
        .padding(.horizontal, DS.gutter)
        .onAppear { grown = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let months = (0..<12).filter { $0 < inSeason.count && inSeason[$0] }
            .map { SpeciesSeason.fullMonths[$0] }
        return months.isEmpty ? "Not in season in any month" : "In season in " + months.joined(separator: ", ")
    }
}

/// A small capsule tag under a detail header, styled like the tags on a
/// catch page.
struct SpeciesTag: View {
    let text: String
    var systemImage: String? = nil
    var tint: Color = .dsText2

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
            }
            Text(text)
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(.dsText)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.dsFill, in: Capsule())
    }
}

/// Tags that wrap onto a new line when they run out of room, so a row of
/// them can never widen the page.
struct SpeciesTagFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = fitted(s, width)
            if x > 0 && x + size.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += size.width + spacing
            rowH = max(rowH, size.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: maxX, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let size = fitted(s, bounds.width)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }

    /// A tag's natural size, or wrapped to the row when it is wider.
    private func fitted(_ s: LayoutSubview, _ width: CGFloat) -> CGSize {
        let natural = s.sizeThatFits(.unspecified)
        guard natural.width > width, width.isFinite else { return natural }
        return s.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }
}

/// A species' temperature band on a short scale, for the visual slot of a
/// condition tile: the band in green and, when given, a reading as a dot.
/// The same look as the water tile on a catch page. Tiles side by side pass
/// one `scale`, so their bands line up.
struct SpeciesTempBar: View {
    let low: Double
    let high: Double
    var value: Double? = nil
    /// The stretch of temperature the bar spans. Defaults to the band and
    /// the reading with 4 degrees either side.
    var scale: ClosedRange<Double>? = nil

    var body: some View {
        GeometryReader { geo in
            let reading = value ?? low
            let minT = scale?.lowerBound ?? (min(low, reading) - 4)
            let maxT = scale?.upperBound ?? (max(high, reading) + 4)
            let span = max(maxT - minT, 1)
            let x: (Double) -> CGFloat = { CGFloat((min(max($0, minT), maxT) - minT) / span) * geo.size.width }
            ZStack(alignment: .leading) {
                Capsule().fill(Color.dsFill2).frame(height: 6)
                Capsule().fill(Color.dsScoreGood.opacity(0.7))
                    .frame(width: max(4, x(high) - x(low)), height: 6)
                    .offset(x: x(low))
                if let value {
                    Circle().fill(Color.dsText)
                        .frame(width: 12, height: 12)
                        .offset(x: x(value) - 6)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 34)
        .accessibilityHidden(true)
    }
}

extension Species {
    /// "#0046", the Fishdex number: the species' place in the seed's order,
    /// so the numbers run from 1 with no gaps. The record id until the dex
    /// has been counted (`FishdexNumbers`).
    @MainActor
    var fishdexNumber: String { String(format: "#%04d", FishdexNumbers.position(of: id)) }
}

/// Fishdex numbers by seed order. The seed lists species by rising id, with
/// gaps where records were dropped, so a species' number is its rank among
/// the ids, counted from 1.
@MainActor
enum FishdexNumbers {
    private static var positions: [Int64: Int] = [:]

    /// Numbers every species from the full list, in any order.
    static func count(_ species: [Species]) {
        let ids = species.map(\.id).sorted()
        var numbers: [Int64: Int] = [:]
        numbers.reserveCapacity(ids.count)
        for (index, id) in ids.enumerated() { numbers[id] = index + 1 }
        positions = numbers
    }

    /// Counts from the database the first time a page needs a number and
    /// neither the guide nor the Fishdex has counted yet.
    static func countIfNeeded(_ repository: SpeciesRepository) {
        guard positions.isEmpty else { return }
        count((try? repository.fetchAll()) ?? [])
    }

    static func position(of id: Int64) -> Int { positions[id] ?? Int(id) }
}

/// Common names that more than one species in a list carries, worked out
/// from the list itself, so a row can add the scientific name and the two
/// fish can be told apart.
struct RepeatedNames {
    private var keys: Set<String> = []

    init() {}

    init(_ species: [Species]) {
        var seen: Set<String> = []
        for sp in species {
            let key = Self.key(sp.commonName)
            if !seen.insert(key).inserted { keys.insert(key) }
        }
    }

    func contains(_ species: Species) -> Bool {
        keys.contains(Self.key(species.commonName))
    }

    private static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
