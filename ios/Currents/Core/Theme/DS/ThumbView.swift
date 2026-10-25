import SwiftUI

/// Luma's square rounded thumbnail: content centred on a soft tint of the
/// item's art colour. Species, icon and photo variants. Default 64 pt.
struct ThumbView<Content: View>: View {
    let tint: Color
    var size: CGFloat = 64
    private let content: Content
    @Environment(\.colorScheme) private var scheme

    init(tint: Color, size: CGFloat = 64, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.size = size
        self.content = content()
    }

    private var radius: CGFloat { size < 48 ? size * 0.25 : DS.Radius.thumb }

    var body: some View {
        ZStack {
            Color.dsBackground
            tint.opacity(DS.thumbTintOpacity(scheme))
            content
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension ThumbView where Content == SpeciesThumbArt {
    /// The species' bundled art on its own art colour. `caught: false`
    /// greys it out (Fishdex not-yet-caught state).
    init(species: Species, size: CGFloat = 64, caught: Bool = true) {
        self.init(tint: caught ? species.artTint : Color.dsText3, size: size) {
            SpeciesThumbArt(species: species, size: size, caught: caught)
        }
    }
}

extension ThumbView where Content == ThumbSymbol {
    /// An SF Symbol tinted with `tint` on the same tint (spots, gear, sessions).
    init(systemImage: String, tint: Color, size: CGFloat = 64) {
        self.init(tint: tint, size: size) {
            ThumbSymbol(systemImage: systemImage, tint: tint, size: size)
        }
    }
}

extension ThumbView where Content == ThumbPhoto {
    /// A photo filling the square (catch photos). Falls back to the tint.
    init(image: UIImage?, tint: Color = .gray, size: CGFloat = 64) {
        self.init(tint: tint, size: size) {
            ThumbPhoto(image: image)
        }
    }
}

struct SpeciesThumbArt: View {
    let species: Species
    let size: CGFloat
    let caught: Bool

    var body: some View {
        // The mockup draws the fish at 92 percent width, nudged right 4 percent.
        SpeciesArtworkView(species: species, caught: caught, size: size * 0.92)
            .offset(x: size * 0.04)
    }
}

/// The glyph goes through `DS.ink`, so pale tints (yellow, light blue)
/// still read on the light-mode tile; dark mode keeps the tint as it is.
struct ThumbSymbol: View {
    let systemImage: String
    let tint: Color
    let size: CGFloat

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.4, weight: .medium))
            .foregroundStyle(DS.ink(tint))
    }
}

struct ThumbPhoto: View {
    let image: UIImage?

    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        }
    }
}
