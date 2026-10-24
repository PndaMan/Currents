import SwiftUI

// The small parts every pushed page shares: the note under a section, the
// empty state inside a section, the grouped label and value rows, and the
// destructive button at the foot of a page. One of each, so the crew,
// logbook, explore and settings pages read the same.

// MARK: - Footnote

/// A short secondary note under a section.
struct SectionFootnote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.dsText2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.gutter)
            .padding(.top, DS.Space.s2)
    }
}

// MARK: - Inline empty

/// An empty state that sits inside a section (Luma's "Nothing planned yet"):
/// icon, one line, and an optional action. The icon's column scales with the
/// text, and at accessibility sizes the icon sits above the text.
struct InlineEmpty: View {
    let systemImage: String
    let text: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var glyphWidth: CGFloat = 24

    init(systemImage: String, text: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.systemImage = systemImage
        self.text = text
        self.actionTitle = actionTitle
        self.action = action
    }

    init(text: String, systemImage: String = "fish") {
        self.init(systemImage: systemImage, text: text)
    }

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Space.s2))
            : AnyLayout(HStackLayout(alignment: .top, spacing: DS.Space.s3))
        layout {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(.dsText3)
                .frame(width: typeSize.isAccessibilitySize ? nil : glyphWidth)
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(TonalButtonStyle(fullWidth: false))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.s4)
        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .padding(.horizontal, DS.gutter)
    }
}

// MARK: - Key-value list

/// Grouped label and value rows on one filled card: rules, totals, sessions,
/// gear specs. Label in the text colour, value secondary, as in Settings.
struct KeyValueList: View {
    struct Row {
        let label: String
        let value: String
        var emphasized = false
    }

    let rows: [Row]

    init(rows: [Row]) { self.rows = rows }

    init(rows: [(String, String)]) {
        self.rows = rows.map { Row(label: $0.0, value: $0.1) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s4) {
                    Text(row.label)
                        .foregroundStyle(.dsText)
                        .fontWeight(row.emphasized ? .semibold : .regular)
                    Spacer(minLength: DS.Space.s4)
                    Text(row.value)
                        .foregroundStyle(row.emphasized ? Color.dsText : Color.dsText2)
                        .fontWeight(row.emphasized ? .semibold : .regular)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.numericText())
                }
                .font(.body)
                .padding(.horizontal, DS.Space.s4)
                .padding(.vertical, 13)
                .accessibilityElement(children: .combine)
                if i < rows.count - 1 {
                    Rectangle().fill(Color.dsSeparator).frame(height: 0.5)
                        .padding(.leading, DS.Space.s4)
                }
            }
        }
        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .padding(.horizontal, DS.gutter)
    }
}

// MARK: - Danger button

/// A full-width red tonal button at the foot of a page (Leave crew, End
/// tournament, Remove friend). The caller confirms with a dialog and sets
/// the space above it. The label is inked so it keeps its contrast on the
/// pale red fill in light mode.
struct DangerButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(role: .destructive, action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(DS.ink(.dsScoreSlow))
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color.dsScoreSlow.opacity(scheme == .dark ? 0.18 : 0.12),
                            in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
        }
        .buttonStyle(.dim)
        .padding(.horizontal, DS.gutter)
    }
}
