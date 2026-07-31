import SwiftUI

/// One home for everything species-related. Collection, the field guide and
/// the seasonal calendar were three separate destinations buried in the old
/// "More" list; they answer the same question — *what fish, and when* — so
/// they're segments of a single tab now.
struct FishTab: View {
    /// Named Segment, not Section — a nested `Section` would shadow
    /// SwiftUI's own inside this file.
    enum Segment: String, CaseIterable, Identifiable {
        case collection = "Collection"
        case guide = "Guide"
        case seasons = "Seasons"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .collection: "checklist"
            case .guide:      "book.fill"
            case .seasons:    "calendar"
            }
        }
    }

    @AppStorage("fishTabSection") private var section: Segment = .collection

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SegmentedPills(options: Segment.allCases, selection: $section,
                               title: { $0.rawValue }, icon: { $0.icon })
                    .padding(.horizontal)
                    .padding(.bottom, 8)

                switch section {
                case .collection: FishCollectionView(embedded: true)
                case .guide:      SpeciesBrowserView()
                case .seasons:    SeasonalCalendarView()
                }
            }
            .navigationTitle("Fish")
            .sensoryFeedback(.selection, trigger: section)
        }
    }
}
