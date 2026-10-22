import SwiftUI

/// A section heading (title3) in the gutter, with an optional dimmed detail
/// ("Windows  3") and an optional chevron when the whole title is a link.
/// Wrap in a NavigationLink or Button with `.buttonStyle(.dim)` to make it tappable.
struct SectionTitle: View {
    let title: String
    var detail: String? = nil
    var showsChevron: Bool = false

    init(_ title: String, detail: String? = nil, chevron: Bool = false) {
        self.title = title
        self.detail = detail
        self.showsChevron = chevron
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.dsText)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.dsText2)
                    .padding(.leading, 4)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.dsText3)
                    .padding(.leading, 2)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .padding(.horizontal, DS.gutter)
        .padding(.bottom, DS.Space.s2)
    }
}
