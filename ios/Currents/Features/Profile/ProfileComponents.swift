import SwiftUI

// Small pieces shared by the profile, settings, tackle box, licences, knots
// and limits pages. They sit on top of the design system in Core/Theme/DS.

// MARK: - Settings row icon

/// The tile at the start of a settings row: the symbol in its colour on a
/// faint tile of the same colour, as on Today.
struct PFIcon: View {
    let systemImage: String
    let color: Color
    var size: CGFloat = 32

    var body: some View {
        TintIcon(systemImage: systemImage, tint: color, size: size)
    }
}

/// A settings row: coloured icon, title, an optional value on the right.
/// Put it inside a NavigationLink or Button in a List; the List adds the chevron.
struct PFRowLabel: View {
    let title: String
    let systemImage: String
    let color: Color
    var value: String? = nil
    var valueColor: Color = .dsText2

    var body: some View {
        HStack(spacing: 14) {
            PFIcon(systemImage: systemImage, color: color)
            Text(title)
                .foregroundStyle(.dsText)
            Spacer(minLength: 8)
            if let value, !value.isEmpty {
                Text(value)
                    .foregroundStyle(valueColor)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
    }
}

/// A toggle row with an optional second line, for settings pages.
struct PFToggleRow: View {
    let title: String
    var detail: String? = nil
    var systemImage: String? = nil
    var color: Color = .dsText2
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 14) {
                if let systemImage {
                    PFIcon(systemImage: systemImage, color: color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.dsText)
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.dsText2)
                    }
                }
            }
        }
        // The system switch plays its own haptic.
    }
}

// MARK: - Grouped list styling

extension View {
    /// An inset grouped List on the page background with `dsFill` rows, so it
    /// reads the same in light and dark.
    func pfGroupedList() -> some View {
        listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .listSectionSpacing(20)
            .contentMargins(.horizontal, DS.gutter, for: .scrollContent)
    }

    /// One settings row on its own `dsFill` card, in the gutter (a toggle
    /// under a section title on a scroll page).
    func pfCard() -> some View {
        padding(.horizontal, DS.Space.s4)
            .padding(.vertical, 12)
            .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .padding(.horizontal, DS.gutter)
    }

    /// Row fill for a Section in a `pfGroupedList`.
    func pfRows() -> some View {
        listRowBackground(Color.dsFill)
    }

    /// A content row that bleeds to the screen edges with no card behind it
    /// (headers, action rows, art). The content brings its own gutter.
    func pfBareRow() -> some View {
        padding(.horizontal, -DS.gutter)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// Luma keeps the large title in the page and only shows the small title
    /// in the bar once the header has scrolled away. Pair with
    /// `pfTrackScroll(_:)` on the scroll view.
    func pfScrollTitle(_ title: String, shown: Bool) -> some View {
        navigationTitle(title)
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
    }

    /// Sets `shown` once the page has scrolled past its header.
    func pfTrackScroll(_ shown: Binding<Bool>, threshold: CGFloat = 90) -> some View {
        onScrollGeometryChange(for: Bool.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top > threshold
        } action: { _, past in
            shown.wrappedValue = past
        }
    }
}

/// The hairline between rows on a `dsFill` card, inset like a list separator.
struct PFDivider: View {
    var inset: CGFloat = DS.Space.s4

    var body: some View {
        Rectangle()
            .fill(Color.dsSeparator)
            .frame(height: 0.5)
            .padding(.leading, inset)
    }
}

// MARK: - Key and value card

/// Luma's plain key and value block: label on the left, value on the right,
/// hairlines between, on a `dsFill` card.
struct PFKeyValueCard: View {
    let rows: [(String, String)]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(row.0)
                        .foregroundStyle(.dsText2)
                    Spacer(minLength: 8)
                    Text(row.1)
                        .foregroundStyle(.dsText)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.body)
                .padding(.horizontal, DS.Space.s4)
                .padding(.vertical, 12)
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

// MARK: - Notice

/// A tinted notice card ("Running low on …", "Expires in 12 days").
struct PFNotice<Accessory: View>: View {
    let systemImage: String
    let tint: Color
    let title: String
    var message: String? = nil
    private let accessory: Accessory

    init(systemImage: String, tint: Color, title: String, message: String? = nil,
         @ViewBuilder accessory: () -> Accessory) {
        self.systemImage = systemImage
        self.tint = tint
        self.title = title
        self.message = message
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.dsText)
                if let message, !message.isEmpty {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.dsText2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            accessory
        }
        .padding(DS.Space.s4)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .padding(.horizontal, DS.gutter)
    }
}

extension PFNotice where Accessory == EmptyView {
    init(systemImage: String, tint: Color, title: String, message: String? = nil) {
        self.init(systemImage: systemImage, tint: tint, title: title, message: message) { EmptyView() }
    }
}

// MARK: - Search field

/// An in-page search field (Luma keeps search in the content, under the title).
struct PFSearchField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.dsText2)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.dsText3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 40)
        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous))
        .padding(.horizontal, DS.gutter)
    }
}

// MARK: - Footnote under a block

struct PFFootnote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.dsText2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.gutter + 4)
    }
}

// MARK: - Stepper capsule

/// A compact minus / value / plus capsule, for stock counts and lengths.
/// `tint` colours the value, for example a low stock count.
struct PFStepper: View {
    let value: String
    let canDecrement: Bool
    var label: String = "Value"
    var tint: Color = .dsText
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button { onChange(-1) } label: {
                Image(systemName: "minus")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(!canDecrement)
            .accessibilityLabel("Less")
            Text(value)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                .frame(minWidth: 34)
            Button { onChange(1) } label: {
                Image(systemName: "plus")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("More")
        }
        .buttonStyle(.dim)
        .buttonHaptic(.selection)
        .foregroundStyle(.dsText)
        .background(Color.dsFill2, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}
