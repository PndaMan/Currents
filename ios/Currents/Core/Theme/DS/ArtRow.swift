import SwiftUI

/// Luma's plain list row: square thumbnail, optional over line, title,
/// subtitle (with optional leading icon), trailing content, optional chevron.
/// Full width with gutter padding. Wrap in a NavigationLink or Button with
/// `.buttonStyle(.dsRow)`; in a List add `.dsListRow()`.
struct ArtRow<Leading: View, Trailing: View>: View {
    var over: String? = nil
    let title: String
    var subtitle: String? = nil
    var subtitleIcon: String? = nil
    var showsChevron: Bool = false
    private let leading: Leading
    private let trailing: Trailing

    init(over: String? = nil, title: String, subtitle: String? = nil, subtitleIcon: String? = nil,
         chevron: Bool = false,
         @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.over = over
        self.title = title
        self.subtitle = subtitle
        self.subtitleIcon = subtitleIcon
        self.showsChevron = chevron
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 14) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                if let over, !over.isEmpty {
                    Text(over)
                        .font(.footnote)
                        .foregroundStyle(.dsText2)
                        .lineLimit(1)
                }
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.dsText)
                    .lineLimit(2)
                if let subtitle, !subtitle.isEmpty {
                    HStack(spacing: 5) {
                        if let subtitleIcon {
                            Image(systemName: subtitleIcon)
                                .font(.footnote)
                                .foregroundStyle(.dsText3)
                        }
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.dsText2)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(.dsText)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.dsText3)
            }
        }
        .padding(.horizontal, DS.gutter)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension ArtRow where Trailing == EmptyView {
    init(over: String? = nil, title: String, subtitle: String? = nil, subtitleIcon: String? = nil,
         chevron: Bool = false, @ViewBuilder leading: () -> Leading) {
        self.init(over: over, title: title, subtitle: subtitle, subtitleIcon: subtitleIcon,
                  chevron: chevron, leading: leading, trailing: { EmptyView() })
    }
}

// MARK: - List helpers

extension View {
    /// For `ArtRow` (or any full-bleed row) inside a SwiftUI List: no system
    /// insets, background or separator, so the row supplies its own.
    func dsListRow() -> some View {
        listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// A plain List on the page background (Luma lists are not grouped cards).
    func dsPlainList() -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
    }
}
