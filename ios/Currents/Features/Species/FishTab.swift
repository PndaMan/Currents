import SwiftUI

/// Everything species-related in one place. The old "Collection" and "Species
/// Guide" were the same 1,568 fish shown twice — one blurred, one not — so
/// they're merged into a single browsable Field Guide, leaving just the guide
/// and the seasonal view.
struct FishTab: View {
    enum Segment: String, CaseIterable, Identifiable {
        case guide = "Field Guide"
        case seasons = "Seasons"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .guide:   "books.vertical.fill"
            case .seasons: "calendar"
            }
        }
    }

    @AppStorage("fishTabSection") private var section: Segment = .guide

    var body: some View {
        NavigationStack {
            Group {
                switch section {
                case .guide:
                    // Pills are handed to the child so they sit inside its
                    // scroll view and travel with the content. Pinned above it
                    // they collided with the large title and the search bar.
                    FishCollectionView(embedded: true, header: AnyView(pills))
                case .seasons:
                    SeasonalCalendarView(header: AnyView(pills))
                }
            }
            .navigationTitle(section.rawValue)
            .sensoryFeedback(.selection, trigger: section)
        }
    }

    private var pills: some View {
        SegmentedPills(options: Segment.allCases, selection: $section,
                       title: { $0.rawValue }, icon: { $0.icon })
            .padding(.bottom, 2)
    }
}
