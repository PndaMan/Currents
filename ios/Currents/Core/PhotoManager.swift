import UIKit
import ImageIO

/// Handles saving catch photos to app's Documents directory with EXIF stripped.
enum PhotoManager {
    /// In-memory cache of decoded thumbnails, keyed by "filename@maxPixel".
    /// Bounded so a big catch history doesn't balloon memory.
    private static let thumbnailCache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 400
        return c
    }()

    private static var photosDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let photos = docs.appendingPathComponent("catch_photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
        return photos
    }

    /// Save a photo with EXIF GPS stripped, returns the relative path.
    static func save(_ image: UIImage, id: String) throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw PhotoError.compressionFailed
        }

        let filename = "\(id).jpg"
        let url = photosDirectory.appendingPathComponent(filename)
        try data.write(to: url)
        return filename
    }

    /// Save multiple photos, returns array of filenames.
    static func saveMultiple(_ images: [UIImage], catchId: String) throws -> [String] {
        var filenames: [String] = []
        for (index, image) in images.enumerated() {
            let id = index == 0 ? catchId : "\(catchId)_\(index)"
            let filename = try save(image, id: id)
            filenames.append(filename)
        }
        return filenames
    }

    /// Load a photo by its relative filename.
    static func load(_ filename: String) -> UIImage? {
        let url = photosDirectory.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Load all photos for a catch.
    static func loadAll(_ filenames: [String]) -> [UIImage] {
        filenames.compactMap { load($0) }
    }

    /// A downsampled thumbnail decoded straight to `maxPixel` (the longest edge,
    /// in *pixels*) via ImageIO — far cheaper than loading the full-resolution
    /// image and letting the view shrink it. `scale` is baked into the returned
    /// UIImage so it renders crisp at its point size. Cached in memory so
    /// scrolling a list doesn't re-decode. Safe to call off the main thread —
    /// it touches no main-actor API.
    static func thumbnail(_ filename: String, maxPixel: CGFloat, scale: CGFloat = 2) -> UIImage? {
        let pixelSize = max(1, maxPixel.rounded())
        let key = "\(filename)@\(Int(pixelSize))" as NSString
        if let cached = thumbnailCache.object(forKey: key) { return cached }

        let url = photosDirectory.appendingPathComponent(filename)
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: pixelSize,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cg, scale: scale, orientation: .up)
        thumbnailCache.setObject(image, forKey: key)
        return image
    }

    /// Delete a photo.
    static func delete(_ filename: String) {
        let url = photosDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
        // Drop any cached thumbnails for this file (all sizes).
        thumbnailCache.removeAllObjects()
    }

    /// Delete all photos for a catch.
    static func deleteAll(_ filenames: [String]) {
        filenames.forEach { delete($0) }
    }

    enum PhotoError: Error {
        case compressionFailed
    }
}
