import UIKit

/// Handles saving catch photos to app's Documents directory with EXIF stripped.
enum PhotoManager {
    private static var photosDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let photos = docs.appendingPathComponent("catch_photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
        return photos
    }

    /// Save a photo with EXIF GPS stripped, returns the relative path.
    static func save(_ image: UIImage, id: String) throws -> String {
        // Re-encode as JPEG to strip all EXIF metadata (including GPS)
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw PhotoError.compressionFailed
        }

        let filename = "\(id).jpg"
        let url = photosDirectory.appendingPathComponent(filename)
        try data.write(to: url)
        return filename
    }

    /// Load a photo by its relative filename.
    static func load(_ filename: String) -> UIImage? {
        let url = photosDirectory.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Delete a photo.
    static func delete(_ filename: String) {
        let url = photosDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }

    enum PhotoError: Error {
        case compressionFailed
    }
}
