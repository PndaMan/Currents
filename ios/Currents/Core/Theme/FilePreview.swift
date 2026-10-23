import SwiftUI
import QuickLookThumbnailing

/// A stored document drawn as itself, the way Files shows documents: the
/// photo, or the first page of a PDF. QuickLook renders the thumbnail off the
/// main thread and `FileThumbnails` caches it. Shows `systemImage` on a plain
/// fill only when there is no file or it can't be read.
///
/// `.fill` crops to the frame the caller gives (rows); PDFs keep their top,
/// where the heading is. `.fit` shows the whole document at its own shape
/// (detail pages) and holds a `placeholderAspect` box while it loads.
struct FilePreview: View {
    let url: URL?
    var systemImage: String = "doc"
    /// Longest edge to render at, in points.
    var renderSize: CGFloat
    var contentMode: ContentMode = .fill
    /// Documents get a tighter corner than photo thumbnails.
    var cornerRadius: CGFloat = DS.Radius.thumb / 2
    var placeholderAspect: CGFloat = 1

    @State private var image: UIImage?
    @State private var failed = false
    @Environment(\.displayScale) private var displayScale

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var isPDF: Bool { url?.pathExtension.lowercased() == "pdf" }

    var body: some View {
        Group {
            if let image {
                loaded(image)
                    .transition(.opacity)
            } else {
                placeholder
            }
        }
        .task(id: url) { await load() }
    }

    @ViewBuilder
    private func loaded(_ image: UIImage) -> some View {
        if contentMode == .fill {
            Color.dsFill2
                .overlay(alignment: isPDF ? .top : .center) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
                .clipShape(shape)
                .overlay { shape.strokeBorder(Color.dsSeparator, lineWidth: 0.5) }
        } else {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(shape)
                .overlay { shape.strokeBorder(Color.dsSeparator, lineWidth: 0.5) }
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        let box = shape
            .fill(Color.dsFill2)
            .overlay {
                if url == nil || failed {
                    Image(systemName: systemImage)
                        .font(renderSize > 120 ? .largeTitle : .title3)
                        .foregroundStyle(.dsText2)
                }
            }
        if contentMode == .fit {
            box.aspectRatio(placeholderAspect, contentMode: .fit)
        } else {
            box
        }
    }

    private func load() async {
        guard let url else {
            image = nil
            failed = true
            return
        }
        let side = renderSize
        let scale = displayScale
        let rendered = await Task.detached(priority: .userInitiated) {
            await FileThumbnails.thumbnail(for: url, side: side, scale: scale)
        }.value
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: DS.Motion.fast)) {
            image = rendered
            failed = rendered == nil
        }
    }
}

/// Thumbnails of stored documents, keyed by file, size and change date so a
/// replaced document never shows its old picture. Bounded like the catch
/// photo cache in `PhotoManager`.
enum FileThumbnails {
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 120
        return c
    }()

    /// The file fitted inside a `side` by `side` point square. Call off the
    /// main thread; it reads the file's attributes.
    static func thumbnail(for url: URL, side: CGFloat, scale: CGFloat) async -> UIImage? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        let stamp = Int(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)
        let key = "\(url.path)@\(Int(side * scale))@\(stamp)" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side),
                                                   scale: scale, representationTypes: .thumbnail)
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
            return nil
        }
        let image = rep.uiImage
        cache.setObject(image, forKey: key)
        return image
    }
}
