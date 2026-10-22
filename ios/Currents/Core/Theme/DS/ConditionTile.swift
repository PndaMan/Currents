import SwiftUI

/// An Apple Weather style condition tile (forecast grid): icon and label
/// head, big value with unit, a slot for a small visual (gauge, arrow, curve),
/// and a footnote. Fill background, card radius, at least 138 pt tall.
struct ConditionTile<Visual: View>: View {
    let label: String
    let systemImage: String
    var iconTint: Color = .dsText2
    let value: String
    var unit: String? = nil
    var footnote: String? = nil
    private let visual: Visual
    @ScaledMetric(relativeTo: .title) private var valueSize: CGFloat = 28

    init(_ label: String, systemImage: String, iconTint: Color = .dsText2,
         value: String, unit: String? = nil, footnote: String? = nil,
         @ViewBuilder visual: () -> Visual) {
        self.label = label
        self.systemImage = systemImage
        self.iconTint = iconTint
        self.value = value
        self.unit = unit
        self.footnote = footnote
        self.visual = visual()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(iconTint)
                Text(label)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.dsText2)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: valueSize, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.dsText)
                    .contentTransition(.numericText())
                if let unit {
                    Text(unit)
                        .font(.subheadline)
                        .foregroundStyle(.dsText2)
                }
            }
            .padding(.top, 4)
            visual
                .frame(maxWidth: .infinity, minHeight: 34, maxHeight: .infinity, alignment: .leading)
            if let footnote {
                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(.dsText2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 13)
        .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

extension ConditionTile where Visual == EmptyView {
    init(_ label: String, systemImage: String, iconTint: Color = .dsText2,
         value: String, unit: String? = nil, footnote: String? = nil) {
        self.init(label, systemImage: systemImage, iconTint: iconTint,
                  value: value, unit: unit, footnote: footnote) { EmptyView() }
    }
}
