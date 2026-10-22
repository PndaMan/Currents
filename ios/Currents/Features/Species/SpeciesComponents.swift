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

/// Twelve tiny bars, one per month, the selected month highlighted. Used at
/// the end of species guide rows.
struct SeasonMiniBars: View {
    let scores: [Int]
    let highlight: Int   // 1 to 12
    var tint: Color = DS.accent

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(scores.enumerated()), id: \.offset) { index, score in
                Capsule()
                    .fill(index + 1 == highlight ? tint : Color.dsText3)
                    .opacity(index + 1 == highlight ? 1 : 0.55)
                    .frame(width: 3, height: max(4, 22 * CGFloat(score) / 100))
            }
        }
        .frame(height: 22, alignment: .bottom)
        .accessibilityHidden(true)
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
                        .frame(height: max(8, 150 * CGFloat(grown ? score : 0) / 100))
                        .frame(maxWidth: .infinity)
                        .animation(reduceMotion ? nil : DS.Motion.softSpring.delay(Double(i) * 0.03), value: grown)
                }
            }
            .frame(height: 150, alignment: .bottom)
            HStack(spacing: 6) {
                ForEach(0..<12, id: \.self) { i in
                    let isNow = i + 1 == currentMonth
                    VStack(spacing: 2) {
                        Circle()
                            .fill(isNow ? Color.dsText : .clear)
                            .frame(width: 4, height: 4)
                        Text(String(SpeciesSeason.shortMonths[i].prefix(1)))
                            .font(.caption.weight(isNow ? .bold : .regular))
                            .foregroundStyle(isNow ? Color.dsText : Color.dsText2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
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

/// A grouped list of label and value rows (the mockup's `kv` block).
struct SpeciesFacts: View {
    let rows: [(String, String)]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.0)
                        .foregroundStyle(.dsText)
                    Spacer(minLength: 12)
                    Text(row.1)
                        .foregroundStyle(.dsText2)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                }
                .font(.body)
                .padding(.horizontal, DS.Space.s4)
                .padding(.vertical, 13)
                .accessibilityElement(children: .combine)
                if index < rows.count - 1 {
                    Rectangle()
                        .fill(Color.dsSeparator)
                        .frame(height: 0.5)
                        .padding(.leading, DS.Space.s4)
                }
            }
        }
        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .padding(.horizontal, DS.gutter)
    }
}

/// A small capsule tag under a detail header.
struct SpeciesTag: View {
    let text: String
    var systemImage: String? = nil
    var tint: Color? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(tint ?? Color.dsText2)
            }
            Text(text)
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(.dsText2)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.dsFill, in: Capsule())
    }
}

/// A grey line under a section (source notes, disclaimers).
struct SectionFootnote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.dsText2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.gutter)
            .padding(.top, DS.Space.s2)
    }
}

extension Species {
    /// "#0046", the Fishdex number.
    var fishdexNumber: String { String(format: "#%04d", id) }
}

extension View {
    /// Keeps a pushed page's big in-content title from being doubled in the
    /// navigation bar: the bar shows `title` only once the content has
    /// scrolled past the title block. Apply to the page's ScrollView.
    func speciesScrollTitle(_ title: String, threshold: CGFloat = 90) -> some View {
        modifier(ScrollRevealTitle(title: title, threshold: threshold))
    }
}

private struct ScrollRevealTitle: ViewModifier {
    let title: String
    let threshold: CGFloat
    @State private var showsTitle = false

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top > threshold
            } action: { _, isPast in
                withAnimation(.easeOut(duration: DS.Motion.fast)) { showsTitle = isPast }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.dsText)
                        .lineLimit(1)
                        .opacity(showsTitle ? 1 : 0)
                        .accessibilityHidden(!showsTitle)
                }
            }
    }
}
