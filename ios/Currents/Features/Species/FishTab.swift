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
    @Environment(AppState.self) private var appState

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
            // The two segments are neighbours in the swipe continuum, with
            // Catches to the guide's left and Community to the seasons' right.
            .smartSwipe(section == .guide ? .fishGuide : .fishSeasons)
            .navigationTitle(section.rawValue)
            // Inline title: the large title stacked a tall empty band between
            // the top of the screen and the search bar; the segment pills
            // already name the surface, so the big heading was pure air.
            .navigationBarTitleDisplayMode(.inline)
            .sensoryFeedback(.selection, trigger: section)
            .onChange(of: appState.swipePage) { _, page in applySwipe(page) }
            .onAppear { applySwipe(appState.swipePage) }
        }
    }

    /// A cross-tab swipe landed here: pick the segment nearest the direction
    /// of travel (guide when coming from Catches, seasons from Community),
    /// overriding whatever segment was last open.
    private func applySwipe(_ page: SwipePage?) {
        switch page {
        case .fishGuide: section = .guide
        case .fishSeasons: section = .seasons
        default: return
        }
        appState.swipePage = nil
    }

    private var pills: some View {
        SegmentedPills(options: Segment.allCases, selection: $section,
                       title: { $0.rawValue }, icon: { $0.icon })
            .padding(.bottom, 2)
    }
}
