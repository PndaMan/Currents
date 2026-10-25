import SwiftUI

/// A Logbook top card: icon and label, big bold number with optional unit,
/// and an optional footnote pinned to the bottom. 148 pt wide by default
/// (pass nil to fill), fill background, card radius. Only a tile with a
/// footnote keeps the 112 pt minimum height; without one the tile hugs its
/// number, so in a row either every tile has a footnote or none does.
/// Pass the raw hue as `tint`; the glyph goes through `DS.ink`. At
/// accessibility sizes the icon sits above the label, the unit goes under
/// the value and the tile fills the offered width, so callers stack tiles
/// vertically there.
struct StatTile: View {
    let label: String
    let systemImage: String
    var tint: Color
    let value: String
    var unit: String? = nil
    var footnote: String? = nil
    var width: CGFloat? = 148
    @ScaledMetric(relativeTo: .title) private var valueSize: CGFloat = 28
    /// One box height for the head glyph, so tiles with symbols of different
    /// shapes keep their numbers on one line, as ActionTriple does.
    @ScaledMetric(relativeTo: .footnote) private var headIconHeight: CGFloat = 16
    @Environment(\.dynamicTypeSize) private var typeSize

    init(_ label: String, systemImage: String, tint: Color = DS.accent,
         value: String, unit: String? = nil, footnote: String? = nil,
         width: CGFloat? = 148) {
        self.label = label
        self.systemImage = systemImage
        self.tint = tint
        self.value = value
        self.unit = unit
        self.footnote = footnote
        self.width = width
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            headLayout {
                Image(systemName: systemImage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DS.ink(tint))
                    .frame(height: headIconHeight)
                Text(label)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.dsText2)
                    .lineLimit(textLines)
            }
            valueLayout {
                Text(value)
                    .font(.system(size: valueSize, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.dsText)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(unit)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.dsText2)
                }
            }
            if let footnote {
                Spacer(minLength: 0)
                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(.dsText2)
                    .lineLimit(textLines)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: isLarge ? nil : width, alignment: .topLeading)
        .frame(maxWidth: fills ? CGFloat.infinity : nil, minHeight: minHeight, alignment: .topLeading)
        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var isLarge: Bool { typeSize.isAccessibilitySize }

    /// Fills the offered width when no fixed width is set, and always at
    /// accessibility sizes, where a 148 pt tile would break every word.
    private var fills: Bool { width == nil || isLarge }

    /// Icon beside the label, or above it at accessibility sizes.
    private var headLayout: AnyLayout {
        isLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(spacing: 6))
    }

    /// Unit beside the value, or on its own line under it at accessibility
    /// sizes.
    private var valueLayout: AnyLayout {
        isLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 4))
    }

    /// The footnote band's height is reserved only when there is a footnote.
    private var minHeight: CGFloat? { footnote == nil ? nil : 112 }

    /// One line in the tile; no limit at accessibility sizes rather than
    /// truncating.
    private var textLines: Int? { isLarge ? nil : 1 }
}
