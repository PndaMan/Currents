import SwiftUI

/// The title block of a pushed detail page: over line (subhead, secondary),
/// large title, subtitle (callout, secondary). Left aligned in the gutter.
struct DetailHeader: View {
    var over: String? = nil
    let title: String
    var subtitle: String? = nil

    init(over: String? = nil, title: String, subtitle: String? = nil) {
        self.over = over
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let over, !over.isEmpty {
                Text(over)
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
            }
            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(.dsText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.dsText2)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.gutter)
    }
}
