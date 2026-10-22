import SwiftUI
import UIKit

/// The art colour of a species: the alpha-weighted average of its bundled
/// artwork, cached per species. Falls back to the rarity colour when a
/// species has no art yet. Drives thumbnail backgrounds and detail tints.
enum SpeciesTint {
    private static let cache = NSCache<NSNumber, UIColor>()

    static func color(for species: Species) -> Color {
        let key = NSNumber(value: species.id)
        if let cached = cache.object(forKey: key) { return Color(uiColor: cached) }
        guard let image = UIImage(named: species.artworkAssetName),
              let average = averageColor(of: image) else {
            return species.rarity.color
        }
        cache.setObject(average, forKey: key)
        return Color(uiColor: average)
    }

    /// Draws the image into a 12 x 12 bitmap and averages it, weighting each
    /// pixel by its alpha so the transparent background does not grey it out.
    private static func averageColor(of image: UIImage) -> UIColor? {
        let side = 12
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            UIGraphicsPushContext(context)
            image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
            UIGraphicsPopContext()
            return true
        }
        guard drawn else { return nil }

        var r = 0.0, g = 0.0, b = 0.0, a = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            r += Double(pixels[i])
            g += Double(pixels[i + 1])
            b += Double(pixels[i + 2])
            a += Double(pixels[i + 3])
        }
        guard a > 0 else { return nil }
        // Premultiplied channels summed over summed alpha = alpha-weighted mean.
        return UIColor(red: r / a, green: g / a, blue: b / a, alpha: 1)
    }
}

extension Species {
    /// See `SpeciesTint`.
    var artTint: Color { SpeciesTint.color(for: self) }
}
