import SwiftUI

/// A catch/photo thumbnail that decodes a downsampled image off the main thread
/// (via `PhotoManager.thumbnail`) and caches it, so scrolling a long list never
/// blocks on full-resolution JPEG decoding. Shows a light placeholder until the
/// thumbnail is ready, then cross-fades it in.
struct PhotoThumbnail<Placeholder: View>: View {
    let path: String?
    /// The rendered size in points; the decode target is scaled for this.
    let size: CGFloat
    let cornerRadius: CGFloat
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    init(path: String?, size: CGFloat, cornerRadius: CGFloat = 12,
         @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.path = path
        self.size = size
        self.cornerRadius = cornerRadius
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    .transition(.opacity)
            } else {
                placeholder()
                    .frame(width: size, height: size)
            }
        }
        .task(id: path) { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        guard let path else { image = nil; return }
        let px = size * displayScale
        let scale = displayScale
        // Decode off the main thread; the cache makes repeat scrolls instant.
        let decoded = await Task.detached(priority: .userInitiated) {
            PhotoManager.thumbnail(path, maxPixel: px, scale: scale)
        }.value
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.15)) { image = decoded }
    }
}
