import SwiftUI

extension View {
    /// Luma's art-colour fade at the top of a pushed detail page: the tint at
    /// 17 percent in dark (10 percent in light) fading into the page
    /// background over `height` points. Apply to the page's ScrollView or
    /// List. Pass nil for a plain background. Pass a smaller height when the
    /// first card sits high on the page, so the wash ends above it.
    ///
    /// It also puts an opaque backdrop behind the navigation bar, as Today
    /// does behind its status bar: text that scrolls up is hidden under the
    /// bar instead of showing through it. The backdrop is a copy of the
    /// page's own top, wash included, so it cannot be seen at rest and the
    /// bar never cuts a band across the tint. The hard scroll edge effect
    /// stays on under it.
    func detailTint(_ color: Color?, height: CGFloat = 560) -> some View {
        modifier(DetailTint(color: color, height: height))
    }

    /// The same opaque bar and hard top edge without the tint, for pushed
    /// pages and sheets on the plain background.
    func detailScrollEdge() -> some View {
        reviewScrollAnchor()
            .modifier(NavBarBackdrop(color: nil, height: 0))
            .scrollEdgeEffectStyle(.hard, for: .top)
    }

    /// Turns the bar backdrop of `detailTint` and `detailScrollEdge` on or
    /// off. A page whose hero runs under the bar uses `statusBarScrim`,
    /// which turns the backdrop off; it passes true here once the hero has
    /// scrolled away. Apply outside `detailTint` or `detailScrollEdge`.
    func pageBarBackdrop(_ shown: Bool) -> some View {
        environment(\.pageBarBackdropShown, shown)
    }
}

/// The fade behind `detailTint`. In light mode a 17 percent wash matched the
/// `dsFill` of the first card and swallowed it, so light uses 10 percent.
private struct DetailTint: ViewModifier {
    let color: Color?
    let height: CGFloat

    func body(content: Content) -> some View {
        content
            .reviewScrollAnchor()
            .background {
                DetailWash(color: color, height: height)
                    .ignoresSafeArea()
            }
            .modifier(NavBarBackdrop(color: color, height: height))
            .scrollEdgeEffectStyle(.hard, for: .top)
    }
}

/// The page background `detailTint` draws: the plain background with the
/// tint's fade from its top edge. Both the page and the bar backdrop draw
/// it, so they meet without a seam.
private struct DetailWash: View {
    let color: Color?
    let height: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .top) {
            Color.dsBackground
            if let color {
                LinearGradient(colors: [color.opacity(scheme == .dark ? 0.17 : 0.10), color.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: height)
                    .animation(.easeInOut(duration: DS.Motion.slow), value: color)
            }
        }
    }
}

/// A zero-height bar at the top safe-area edge whose background reaches up
/// behind the navigation bar, like Today's status bar backdrop. It draws the
/// page's own top (`DetailWash`, clipped to the bar), so it is always on:
/// nothing changes at rest, and whatever scrolls under the bar is covered.
///
/// When pages stack these (a page title modifier that adds
/// `detailScrollEdge` around a `detailTint` page), only the innermost draws,
/// so a plain bar never covers a tinted one.
private struct NavBarBackdrop: ViewModifier {
    let color: Color?
    let height: CGFloat
    @Environment(\.pageHasStatusBarScrim) private var hasScrim
    @Environment(\.pageBarBackdropShown) private var shownOverride
    /// This backdrop plus any inside it; 0 until the first layout reports.
    @State private var depth = 0

    private var visible: Bool { depth == 1 && (shownOverride ?? !hasScrim) }

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 0)
                    .background {
                        DetailWash(color: color, height: height)
                            .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
                            .clipped()
                            .ignoresSafeArea(edges: .top)
                            .opacity(visible ? 1 : 0)
                            .animation(.easeOut(duration: DS.Motion.fast), value: visible)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .transformPreference(NavBarBackdropDepthKey.self) { $0 += 1 }
            .onPreferenceChange(NavBarBackdropDepthKey.self) { depth = $0 }
    }
}

/// Counts the bar backdrops in a view and the views inside it.
private struct NavBarBackdropDepthKey: PreferenceKey {
    static let defaultValue = 0

    static func reduce(value: inout Int, nextValue: () -> Int) {
        value += nextValue()
    }
}

private struct PageHasStatusBarScrimKey: EnvironmentKey {
    static let defaultValue = false
}

private struct PageBarBackdropShownKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    /// Set by `statusBarScrim`: the page runs a hero or a map under the bar,
    /// so the bar backdrop stays off unless `pageBarBackdrop(_:)` turns it on.
    var pageHasStatusBarScrim: Bool {
        get { self[PageHasStatusBarScrimKey.self] }
        set { self[PageHasStatusBarScrimKey.self] = newValue }
    }

    /// Set by `pageBarBackdrop(_:)`; nil leaves the backdrop to the scrim rule.
    fileprivate var pageBarBackdropShown: Bool? {
        get { self[PageBarBackdropShownKey.self] }
        set { self[PageBarBackdropShownKey.self] = newValue }
    }
}
