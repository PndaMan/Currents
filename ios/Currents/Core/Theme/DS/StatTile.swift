import SwiftUI

/// A Logbook top card: icon and label, big bold number with optional unit,
/// and a footnote pinned to the bottom. 148 pt wide by default (pass nil to
/// fill), fill background, card radius.
struct StatTile: View {
    let label: String
    let systemImage: String
    var tint: Color
    let value: String
    var unit: String? = nil
    var footnote: String? = nil
    var width: CGFloat? = 148
    @ScaledMetric(relativeTo: .title) private var valueSize: CGFloat = 28
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
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(tint)
                Text(label)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.dsText2)
                    .lineLimit(textLines)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
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
            Spacer(minLength: 0)
            if let footnote {
                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(.dsText2)
                    .lineLimit(textLines)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: width, alignment: .topLeading)
        .frame(maxWidth: width == nil ? CGFloat.infinity : nil, minHeight: 112, alignment: .topLeading)
        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// One line in the tile, two at accessibility sizes rather than truncating.
    private var textLines: Int { typeSize.isAccessibilitySize ? 2 : 1 }
}
