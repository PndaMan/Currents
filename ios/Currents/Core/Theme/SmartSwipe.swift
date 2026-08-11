import SwiftUI

/// The single left-to-right continuum of top-level screens that edge swipes
/// travel through — the tab bar and each tab's inner segments flattened into
/// one order:
///
///   Today · Explore · Catches · Field Guide · Seasons · Feed · Crews · Friends
///
/// Standard paging physics: drag LEFT to travel right through the order, drag
/// RIGHT to travel back. The gesture only arms in narrow strips on the screen
/// edges (extra narrow on the map) so it never fights vertical scrolling,
/// swipe-to-delete on rows, horizontal pill rows, or panning the map.
enum SwipePage: Int, CaseIterable {
    case today, map, catches, fishGuide, fishSeasons
    case communityFeed, communityCrews, communityFriends

    var tab: ContentView.Tab {
        switch self {
        case .today: .today
        case .map: .map
        case .catches: .catches
        case .fishGuide, .fishSeasons: .fish
        case .communityFeed, .communityCrews, .communityFriends: .community
        }
    }

    /// Pages whose tab has no inner segments — ContentView consumes these
    /// itself; segmented tabs (Fish, Community) apply their segment first.
    var isPlainTab: Bool {
        switch self {
        case .today, .map, .catches: true
        default: false
        }
    }
}

private struct SmartSwipeModifier: ViewModifier {
    @Environment(AppState.self) private var appState
    let page: SwipePage
    var edgeWidth: CGFloat

    func body(content: Content) -> some View {
        content.overlay {
            HStack(spacing: 0) {
                if page.rawValue > 0 {
                    strip(direction: -1)
                }
                Spacer(minLength: 0)
                if page.rawValue < SwipePage.allCases.count - 1 {
                    strip(direction: +1)
                }
            }
        }
    }

    /// A transparent edge strip that recognises a horizontal drag. Touches
    /// that start here are owned by the strip (the cost of any edge gesture),
    /// so the width stays narrow — mostly over content padding.
    private func strip(direction: Int) -> some View {
        Color.clear
            .frame(width: edgeWidth)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onEnded { value in
                        let w = value.translation.width
                        let h = value.translation.height
                        // Deliberate, horizontal-dominant drag only.
                        guard abs(w) > 36, abs(w) > abs(h) * 1.2 else { return }
                        // Content follows the finger: dragging right (w > 0)
                        // reveals the page on the LEFT.
                        let travelled = w > 0 ? -1 : 1
                        guard travelled == direction else { return }
                        appState.smartSwipe(from: page, toward: direction)
                    }
            )
    }
}

extension View {
    /// Arms edge-swipe navigation on a tab's ROOT screen. Attach inside the
    /// NavigationStack so pushed detail views cover the strips (and keep the
    /// system back-swipe to themselves).
    func smartSwipe(_ page: SwipePage, edgeWidth: CGFloat = 22) -> some View {
        modifier(SmartSwipeModifier(page: page, edgeWidth: edgeWidth))
    }
}
