import SwiftUI

/// Reusable species artwork. Shows the bundled per-species illustration
/// (asset `fish_<id>`, populated by the dataset pipeline) when available,
/// otherwise a stylised fish silhouette.
///
/// When `caught == false` the artwork is desaturated + dimmed, exactly like
/// a not-yet-collected Pokédex entry; it snaps to full colour once caught.
/// Used across the collection grid, species guide and species detail so the
/// grey→colour language is consistent everywhere.
struct SpeciesArtworkView: View {
    let species: Species
    var caught: Bool
    var size: CGFloat = 72
    /// When true the art fits within `size` *height* but may use the full width
    /// offered by the parent. Long species (marlin, gar, sturgeon, whale shark)
    /// are drawn on a square canvas, so a fixed square frame letterboxes them
    /// into a thin sliver; letting them fill the available width renders them at
    /// a natural size instead of looking "squished". Used in grid cells.
    var fillWidth: Bool = false

    private var hasBundledArt: Bool {
        UIImage(named: species.artworkAssetName) != nil
    }

    var body: some View {
        ZStack {
            if hasBundledArt {
                Image(species.artworkAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: fillWidth ? .infinity : size, maxHeight: size)
                    .frame(height: size)
            } else {
                // Silhouette fallback until bundled art ships
                Image(systemName: "fish.fill")
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(
                        caught ? AnyShapeStyle(species.rarity.color.gradient)
                               : AnyShapeStyle(Color.secondary)
                    )
                    .frame(width: size, height: size)
            }
        }
        .saturation(caught ? 1 : 0)
        .opacity(caught ? 1 : 0.4)
        .animation(.easeInOut(duration: 0.3), value: caught)
    }
}
