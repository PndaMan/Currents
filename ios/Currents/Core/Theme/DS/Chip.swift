import SwiftUI

/// A selectable pill (forecast day tabs, filters): filled with the primary
/// button colour when selected, `dsFill` otherwise.
struct Chip: View {
    let title: String
    var systemImage: String? = nil
    let isSelected: Bool
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage).font(.footnote.weight(.semibold))
                }
                Text(title).lineLimit(1)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isSelected ? Color.dsOnPrimary : Color.dsText)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? Color.dsPrimaryButton : Color.dsFill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.dim)
        .buttonHaptic(.selection)
        .animation(.easeOut(duration: DS.Motion.fast), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A horizontally scrolling row of `Chip`s bound to a selection, inset to the
/// gutter. Each chip plays the selection haptic. At accessibility sizes the
/// chips wrap onto more lines instead, so none sit off screen.
struct FilterChips<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String
    var systemImage: ((Item) -> String?)? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    init(_ items: [Item], selection: Binding<Item>, title: @escaping (Item) -> String,
         systemImage: ((Item) -> String?)? = nil) {
        self.items = items
        self._selection = selection
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        if typeSize.isAccessibilitySize {
            ChipFlow(spacing: 6) { chips }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.gutter)
                .padding(.vertical, 4)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) { chips }
                    .padding(.horizontal, DS.gutter)
                    .padding(.vertical, 4)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
    }

    private var chips: some View {
        ForEach(items, id: \.self) { item in
            Chip(title(item), systemImage: systemImage?(item), isSelected: item == selection) {
                selection = item
            }
        }
    }
}

/// FilterChips at accessibility sizes: chips left to right, onto a new line
/// when the row is full. A chip wider than the row is offered the row's width.
private struct ChipFlow: Layout {
    var spacing: CGFloat

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

    /// A chip's natural size, or fitted to the row when it is wider.
    private func fitted(_ s: LayoutSubview, _ width: CGFloat) -> CGSize {
        let natural = s.sizeThatFits(.unspecified)
        guard natural.width > width, width.isFinite else { return natural }
        return s.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }
}

/// An outlined action chip (quick links, suggestions): icon in its own tint,
/// title, optional dimmed detail. 42 pt tall, button radius, hairline border.
/// Pass the raw hue as `iconTint`; the glyph goes through `DS.ink`.
struct OutlineChip: View {
    let title: String
    let systemImage: String
    var iconTint: Color = .dsText2
    var detail: String? = nil
    let action: () -> Void

    init(_ title: String, systemImage: String, iconTint: Color = .dsText2,
         detail: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.iconTint = iconTint
        self.detail = detail
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.ink(iconTint))
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.dsText)
                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.dsText2)
                }
            }
            .lineLimit(1)
            .padding(.leading, 12)
            .padding(.trailing, 14)
            .frame(minHeight: 42)
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
                .strokeBorder(Color.dsSeparator, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
        }
        .buttonStyle(.dim)
    }
}
