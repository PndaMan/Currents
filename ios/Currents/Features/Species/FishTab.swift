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
    }

    @AppStorage("fishTabSection") private var section: Segment = .collection

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $section) {
                    ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 6)

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
