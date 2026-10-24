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
        .pageTitleFade(title)
    }
}

/// TodayPage's inline title: hidden at rest, faded in once the page's
/// `DetailHeader` over line and large title have scrolled under the bar, so
/// the large title is never doubled. Apply to the page's ScrollView. Pages
/// that draw their own header (a count or a hero rather than the page name)
/// use it too; without a `DetailHeader` it waits for one large title line,
/// and a page whose header sits below other content passes a `threshold`.
struct PageTitleFade: ViewModifier {
    let title: String
    var threshold: CGFloat? = nil
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .modifier(PageTitleTracking(shown: $shown, threshold: threshold))
            .pageInlineTitle(title, shown: shown)
    }
}

/// Sets `shown` once the page has scrolled past its header: `threshold`
/// points when given, otherwise what the page's `DetailHeader` reports,
/// otherwise one large title line.
private struct PageTitleTracking: ViewModifier {
    @Binding var shown: Bool
    let threshold: CGFloat?
    /// What the page's `DetailHeader` reports; 0 until it does.
    @State private var headerHeight: CGFloat = 0
    @ScaledMetric(relativeTo: .largeTitle) private var titleLine: CGFloat = 41

    func body(content: Content) -> some View {
        let limit = threshold ?? (headerHeight > 0 ? headerHeight : titleLine)
        content
            .onPreferenceChange(DetailHeaderTitleHeightKey.self) { headerHeight = $0 }
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top >= limit
            } action: { _, past in
                shown = past
            }
    }
}

/// The inline title of a pushed page, faded in with a hairline under the
/// bar while `shown`, as Today's inline title comes in.
private struct PageInlineTitle: ViewModifier {
    let title: String
    let shown: Bool

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                        .opacity(shown ? 1 : 0)
                        .animation(.easeOut(duration: DS.Motion.fast), value: shown)
                        .accessibilityHidden(!shown)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 0)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Color.dsSeparator)
                            .frame(height: 0.5)
                            .opacity(shown ? 1 : 0)
                            .animation(.easeOut(duration: DS.Motion.fast), value: shown)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}

extension View {
    /// The inline title that fades in once the page's header has scrolled
    /// away, as on TodayPage. Leave `threshold` out to follow the page's
    /// `DetailHeader`; pass one, in points of scroll, when the header sits
    /// below a hero, an avatar or an icon.
    func pageTitleFade(_ title: String, threshold: CGFloat? = nil) -> some View {
        modifier(PageTitleFade(title: title, threshold: threshold))
    }

    /// Sets `shown` once the page has scrolled past its header, by the same
    /// rule as `pageTitleFade`, for pages that show the title themselves
    /// (with `pageInlineTitle`). Apply to the page's ScrollView.
    func pageTitleTracking(_ shown: Binding<Bool>, threshold: CGFloat? = nil) -> some View {
        modifier(PageTitleTracking(shown: shown, threshold: threshold))
    }

    /// A pushed page's inline title and the hairline under the bar, shown
    /// while `shown` is true. For pages that work out when their own header
    /// or hero has gone; `pageTitleFade` uses it. Apply outside
    /// `detailTint` or `detailScrollEdge`, so the hairline draws over the
    /// bar backdrop.
    func pageInlineTitle(_ title: String, shown: Bool) -> some View {
        modifier(PageInlineTitle(title: title, shown: shown))
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
/// faint tile of the same colour, like Today's plan row. Pass the raw hue;
/// the glyph goes through `DS.ink`, so pale tints still read in light mode.
/// The glyph is sized from the tile, not the text size, so it never
/// outgrows the tile at accessibility sizes.
struct TintIcon: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = 34

    var body: some View {
        ThumbView(tint: tint, size: size) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.44, weight: .semibold)) // ui-lint: allow glyph sized from its fixed tile
                .foregroundStyle(DS.ink(tint))
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Rows

/// One row on a `CardGroup`: tint icon, title, optional one-line subtitle,
/// trailing content or value, optional chevron. Wrap in a Button or
/// NavigationLink with `.buttonStyle(.dsCardRow)`. `tint` is the raw hue
/// (TintIcon inks the glyph); `valueTint` is drawn as given, so pass
/// `DS.ink(...)` there for a coloured value. At accessibility sizes the text
/// wraps without a limit and the icon sits by the title.
struct CardRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    var tint: Color = DS.accent
    var value: String? = nil
    var valueTint: Color = .dsText2
    var showsChevron = false
    /// False keeps a button or menu in `trailing` reachable by VoiceOver;
    /// true reads the row as one element.
    var combinesChildren = true
    private let trailing: Trailing
    @Environment(\.dynamicTypeSize) private var typeSize

    init(_ title: String, subtitle: String? = nil, systemImage: String? = nil, tint: Color = DS.accent,
         value: String? = nil, valueTint: Color = .dsText2, chevron: Bool = false,
         combinesChildren: Bool = true,
         @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.value = value
        self.valueTint = valueTint
        self.showsChevron = chevron
        self.combinesChildren = combinesChildren
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: typeSize.isAccessibilitySize ? .top : .center, spacing: 14) {
            if let systemImage {
                TintIcon(systemImage: systemImage, tint: tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.dsText)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.dsText2)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
            if let value, !value.isEmpty {
                Text(value)
                    .font(.body)
                    .foregroundStyle(valueTint)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
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
        .accessibilityElement(children: combinesChildren ? .combine : .contain)
    }
}

extension CardRow where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil, systemImage: String? = nil, tint: Color = DS.accent,
         value: String? = nil, valueTint: Color = .dsText2, chevron: Bool = false,
         combinesChildren: Bool = true) {
        self.init(title, subtitle: subtitle, systemImage: systemImage, tint: tint,
                  value: value, valueTint: valueTint, chevron: chevron,
                  combinesChildren: combinesChildren) { EmptyView() }
    }
}

/// A switch row on a `CardGroup`, with the same icon tile and one subtitle.
/// At accessibility sizes the icon sits by the title.
struct CardToggleRow: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    var tint: Color = DS.accent
    @Binding var isOn: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

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
            HStack(alignment: typeSize.isAccessibilitySize ? .top : .center, spacing: 14) {
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
/// callout line, and a visual on the right (ScoreRing, big number, art). At
/// accessibility sizes the visual moves under the text, both leading, so the
/// value gets the full width.
struct PageHero<Visual: View>: View {
    let label: String
    let value: String
    var callout: String? = nil
    private let visual: Visual
    @Environment(\.dynamicTypeSize) private var typeSize

    init(label: String, value: String, callout: String? = nil, @ViewBuilder visual: () -> Visual) {
        self.label = label
        self.value = value
        self.callout = callout
        self.visual = visual()
    }

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
        layout {
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
            if !stacked { Spacer(minLength: 0) }
            visual
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.gutter)
        .accessibilityElement(children: .combine)
    }
}
