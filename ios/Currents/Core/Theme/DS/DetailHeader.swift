import SwiftUI

/// The title block of a pushed detail page: over line (subhead, secondary),
/// large title, subtitle (callout, secondary). Left aligned in the gutter.
/// It reports how tall the over line and title are, so `pageTitleFade` on
/// the page knows when they have scrolled away.
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
            }
            .background {
                GeometryReader { geo in
                    Color.clear.preference(key: DetailHeaderTitleHeightKey.self, value: geo.size.height)
                }
            }
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

/// How tall the over line and large title of a page's `DetailHeader` are,
/// so `pageTitleFade` brings the inline title in once that block has gone
/// under the bar. The first header on the page wins.
struct DetailHeaderTitleHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        if value == 0 { value = nextValue() }
    }
}
