import SwiftUI

// Parts for pages that should read like Today: a large title page on the
// plain background, sections under `SectionTitle`, and grouped rows on one
// `dsFill` card led by a coloured symbol tile (the symbol in its colour on a
// faint tile of the same colour). Settings, wallets and lists use these
// instead of a system inset grouped List.

// MARK: - Page

/// A pushed page in Today's layout: large title, optional one-line subtitle,
/// then the sections, with the inline title fading in once the header has
/// scrolled away. Pass `tint` for a faint art-colour fade at the top.
struct TodayPage<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var tint: Color? = nil
    private let content: Content
    @State private var titleShown = false

    init(_ title: String, subtitle: String? = nil, tint: Color? = nil,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                DetailHeader(title: title, subtitle: subtitle)
                content
            }
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
        }
        .detailTint(tint)
        .onScrollGeometryChange(for: Bool.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top > 60
        } action: { _, past in
            titleShown = past
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .opacity(titleShown ? 1 : 0)
                    .animation(.easeOut(duration: DS.Motion.fast), value: titleShown)
                    .accessibilityHidden(!titleShown)
            }
        }
    }
}

// MARK: - Sections and cards

/// A section of a Today-style page: `SectionTitle`, then its rows on one
/// card, then an optional one-line note.
struct CardSection<Content: View>: View {
    let title: String?
    var note: String? = nil
    private let content: Content

    init(_ title: String? = nil, note: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.note = note
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title { SectionTitle(title) }
            CardGroup { content }
            if let note, !note.isEmpty { SectionFootnote(note) }
        }
    }
}

/// Rows on one `dsFill` card, hairlines between them, inset past the icon
/// tile. Each direct child view is one row.
struct CardGroup<Content: View>: View {
    var separatorInset: CGFloat = 64
    private let content: Content

    init(separatorInset: CGFloat = 64, @ViewBuilder content: () -> Content) {
        self.separatorInset = separatorInset
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(rows) { row in
                    row
                    if row.id != rows.last?.id {
                        Rectangle()
                            .fill(Color.dsSeparator)
                            .frame(height: 0.5)
                            .padding(.leading, separatorInset)
                    }
                }
            }
        }
        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .padding(.horizontal, DS.gutter)
    }
}

// MARK: - Icon tile

/// The coloured symbol tile that leads a card row: the symbol in `tint` on a
/// faint tile of the same colour, like Today's plan row.
struct TintIcon: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = 34

    var body: some View {
        ThumbView(tint: tint, size: size) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Rows

/// One row on a `CardGroup`: tint icon, title, optional one-line subtitle,
/// trailing content or value, optional chevron. Wrap in a Button or
/// NavigationLink with `.buttonStyle(.dsCardRow)`.
struct CardRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    var tint: Color = DS.accent
    var value: String? = nil
    var valueTint: Color = .dsText2
    var showsChevron = false
    private let trailing: Trailing
    @Environment(\.dynamicTypeSize) private var typeSize

    init(_ title: String, subtitle: String? = nil, systemImage: String? = nil, tint: Color = DS.accent,
         value: String? = nil, valueTint: Color = .dsText2, chevron: Bool = false,
         @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.value = value
        self.valueTint = valueTint
        self.showsChevron = chevron
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 14) {
            if let systemImage {
                TintIcon(systemImage: systemImage, tint: tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.dsText)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.dsText2)
                        .lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
            if let value, !value.isEmpty {
                Text(value)
                    .font(.body)
                    .foregroundStyle(valueTint)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.dsText3)
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, 10)
        .frame(minHeight: 54)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension CardRow where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil, systemImage: String? = nil, tint: Color = DS.accent,
         value: String? = nil, valueTint: Color = .dsText2, chevron: Bool = false) {
        self.init(title, subtitle: subtitle, systemImage: systemImage, tint: tint,
                  value: value, valueTint: valueTint, chevron: chevron) { EmptyView() }
    }
}

/// A switch row on a `CardGroup`, with the same icon tile and one subtitle.
struct CardToggleRow: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    var tint: Color = DS.accent
    @Binding var isOn: Bool

    init(_ title: String, subtitle: String? = nil, systemImage: String? = nil, tint: Color = DS.accent,
         isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self._isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 14) {
                if let systemImage {
                    TintIcon(systemImage: systemImage, tint: tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.dsText)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.dsText2)
                    }
                }
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, 10)
        .frame(minHeight: 54)
    }
}

// MARK: - Press style

/// Press feedback for a row on a `dsFill` card: the row darkens to `dsFill2`
/// while held, like a native cell highlight.
struct CardRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .background(configuration.isPressed ? Color.dsFill2 : Color.clear)
            .animation(DS.Motion.press, value: configuration.isPressed)
            .pressHaptic(configuration.isPressed, .softPress)
    }
}

extension ButtonStyle where Self == CardRowPressStyle {
    /// `.buttonStyle(.dsCardRow)`
    static var dsCardRow: CardRowPressStyle { CardRowPressStyle() }
}

// MARK: - Hero

/// Today's hero: a subheadline label, a bold title-sized value, one short
/// callout line, and a visual on the right (ScoreRing, big number, art).
struct PageHero<Visual: View>: View {
    let label: String
    let value: String
    var callout: String? = nil
    private let visual: Visual

    init(label: String, value: String, callout: String? = nil, @ViewBuilder visual: () -> Visual) {
        self.label = label
        self.value = value
        self.callout = callout
        self.visual = visual()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                Text(value)
                    .font(.title.bold())
                    .foregroundStyle(.dsText)
                    .fixedSize(horizontal: false, vertical: true)
                if let callout, !callout.isEmpty {
                    Text(callout)
                        .font(.callout)
                        .foregroundStyle(.dsText2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            visual
        }
        .padding(.horizontal, DS.gutter)
        .accessibilityElement(children: .combine)
    }
}
