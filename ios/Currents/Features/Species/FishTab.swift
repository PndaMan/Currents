import SwiftUI

/// Formerly the Fish tab. The species guide is now reached from Explore and
/// the Fishdex from Logbook (`AppRoute.fishdex`), so this is no longer in the
/// tab bar. It shows the species guide in its own stack for any caller that
/// still presents it on its own.
struct FishTab: View {
    var body: some View {
        NavigationStack {
            SpeciesBrowserView()
        }
    }
}
