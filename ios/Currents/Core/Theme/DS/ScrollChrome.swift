import SwiftUI

extension View {
    /// For a tab root whose ScrollView starts with `LargeTitleHeader`. Hides
    /// the system navigation bar and, as soon as content scrolls, puts an
    /// opaque backdrop behind the status bar; once the large title has
    /// scrolled away, a centred inline `title` slides in under it, like
    /// Luma and the App Store Today tab. Apply to the root ScrollView itself,
    /// in place of `.toolbar(.hidden, for: .navigationBar)`.
    func largeTitleChrome(_ title: String) -> some View {
        modifier(LargeTitleChrome(title: title))
    }

    /// Pins a vertical scroll page's content to the scroll view's width, so
    /// one over-wide child can never make the whole page scroll sideways.
    /// Apply to the content stack inside the ScrollView. It is a guard, not a
    /// fix: the over-wide child still needs fixing (it will be clipped).
    func pageWidth() -> some View {
        containerRelativeFrame(.horizontal, alignment: .topLeading)
    }

    /// For a full-bleed map root: a soft fade of the page background behind
    /// the status bar, so the clock stays legible over bright map tiles.
    /// Apply to the root stack that holds the map.
    func statusBarScrim() -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 0)
                .background {
                    LinearGradient(colors: [Color.dsBackground.opacity(0.7), Color.dsBackground.opacity(0)],
                                   startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea(edges: .top)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct LargeTitleChrome: ViewModifier {
    let title: String
    /// 0 at rest, 1 once content is under the status bar, 2 once the large
    /// title has scrolled out of view.
    @State private var stage = 0
    @ScaledMetric(relativeTo: .largeTitle) private var headerHeight: CGFloat = 52
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .navigationBar)
            .onScrollGeometryChange(for: Int.self) { geo in
                let y = geo.contentOffset.y + geo.contentInsets.top
                if y > headerHeight { return 2 }
                return y > 1 ? 1 : 0
            } action: { _, new in
                withAnimation(.easeOut(duration: DS.Motion.fast)) { stage = new }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                StatusBarBackdrop(title: title, stage: stage, reduceMotion: reduceMotion)
            }
    }
}

/// A zero-height bar at the top safe-area edge: its background reaches up
/// under the status bar, and its overlay draws the inline title below it, so
/// showing either never moves the content.
private struct StatusBarBackdrop: View {
    let title: String
    let stage: Int
    let reduceMotion: Bool

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 0)
            .background {
                Color.dsBackground
                    .ignoresSafeArea(edges: .top)
                    .opacity(stage >= 1 ? 1 : 0)
            }
            .overlay(alignment: .top) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.dsText)
                    .lineLimit(1)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .padding(.horizontal, 64)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.dsBackground)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.dsSeparator)
                            .frame(height: 0.5)
                    }
                    .offset(y: stage == 2 || reduceMotion ? 0 : -6)
                    .opacity(stage == 2 ? 1 : 0)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
