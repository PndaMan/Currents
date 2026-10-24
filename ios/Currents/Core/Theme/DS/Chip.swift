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
/// gutter. Each chip plays the selection haptic.
struct FilterChips<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String
    var systemImage: ((Item) -> String?)? = nil

    init(_ items: [Item], selection: Binding<Item>, title: @escaping (Item) -> String,
         systemImage: ((Item) -> String?)? = nil) {
        self.items = items
        self._selection = selection
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items, id: \.self) { item in
                    Chip(title(item), systemImage: systemImage?(item), isSelected: item == selection) {
                        selection = item
                    }
                }
            }
            .padding(.horizontal, DS.gutter)
            .padding(.vertical, 4)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
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
