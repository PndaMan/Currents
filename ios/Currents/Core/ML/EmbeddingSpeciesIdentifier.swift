import CoreML
import Vision
import UIKit

/// Zero-shot fish identifier powered by the BioCLIP image encoder.
///
/// BioCLIP is a real species-classification model (trained on iNaturalist +
/// GBIF + EOL). We run its CoreML image encoder on the catch photo to get a
/// 512-d embedding, then cosine-match it against a bundled text embedding for
/// every app species (`species_embeddings.bin`, produced by
/// `ml/bioclip_to_coreml.py`). The label space is exactly the app's species.
///
/// Everything is optional: if the model hasn't been downloaded or the
/// embeddings aren't bundled, `identify` returns `[]` and the caller falls
/// back to the visual-similarity identifier.
actor EmbeddingSpeciesIdentifier {
    struct Ranked: Sendable {
        let speciesId: Int64
        let confidence: Float
    }

    private var model: MLModel?
    private var imageInputName: String?
    private var outputName: String?
    private var speciesEmbeddings: [(id: Int64, vec: [Float])] = []
    private var loaded = false

    private static var cachedModelURL: URL {
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return cache.appendingPathComponent("MLModels/FishID.mlmodelc")
    }

    var isReady: Bool { model != nil && !speciesEmbeddings.isEmpty }

    /// Load the CoreML encoder + bundled species embeddings if present.
    func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true

        // Species text embeddings (bundled binary).
        if let url = Bundle.main.url(forResource: "species_embeddings", withExtension: "bin"),
           let data = try? Data(contentsOf: url) {
            speciesEmbeddings = Self.parseEmbeddings(data)
        }
        guard !speciesEmbeddings.isEmpty else { return }

        // CoreML encoder: bundled first, else the auto-downloaded cache.
        let modelURL = Bundle.main.url(forResource: "FishID", withExtension: "mlmodelc")
            ?? (FileManager.default.fileExists(atPath: Self.cachedModelURL.path) ? Self.cachedModelURL : nil)
        guard let modelURL, let m = try? MLModel(contentsOf: modelURL) else { return }

        // Discover the image input + embedding output feature names.
        let desc = m.modelDescription
        imageInputName = desc.inputDescriptionsByName.first(where: { $0.value.type == .image })?.key
        outputName = desc.outputDescriptionsByName.first(where: { $0.value.type == .multiArray })?.key
        guard imageInputName != nil, outputName != nil else { return }
        model = m
    }

    /// Identify the most likely species for a catch photo.
    func identify(image: UIImage, top: Int = 6) -> [Ranked] {
        loadIfNeeded()
        guard let model, let imageInputName, let outputName,
              let pixelBuffer = Self.pixelBuffer(from: image, side: 224) else { return [] }

        guard let provider = try? MLDictionaryFeatureProvider(
            dictionary: [imageInputName: MLFeatureValue(pixelBuffer: pixelBuffer)]
        ), let out = try? model.prediction(from: provider),
           let arr = out.featureValue(for: outputName)?.multiArrayValue else { return [] }

        // Read + L2-normalise the image embedding.
        let n = arr.count
        var q = [Float](repeating: 0, count: n)
        for i in 0..<n { q[i] = arr[i].floatValue }
        var norm: Float = 0
        for v in q { norm += v * v }
        norm = max(norm.squareRoot(), 1e-6)
        for i in 0..<n { q[i] /= norm }

        // Cosine similarity against each species text embedding.
        var scored: [(Int64, Float)] = []
        scored.reserveCapacity(speciesEmbeddings.count)
        for (id, vec) in speciesEmbeddings where vec.count == n {
            var dot: Float = 0
            for i in 0..<n { dot += q[i] * vec[i] }
            scored.append((id, dot))
        }
        scored.sort { $0.1 > $1.1 }

        // Softmax-ish confidence from the top cosine scores.
        return scored.prefix(top).map { id, sim in
            Ranked(speciesId: id, confidence: max(0.05, min(0.99, (sim + 1) / 2)))
        }
    }

    // MARK: - Helpers

    private static func parseEmbeddings(_ data: Data) -> [(Int64, [Float])] {
        guard data.count >= 8 else { return [] }
        return data.withUnsafeBytes { raw -> [(Int64, [Float])] in
            let count = raw.loadUnaligned(fromByteOffset: 0, as: UInt32.self)
            let dim = Int(raw.loadUnaligned(fromByteOffset: 4, as: UInt32.self))
            guard dim > 0, count > 0 else { return [] }
            var result: [(Int64, [Float])] = []
            result.reserveCapacity(Int(count))
            var offset = 8
            let stride = 4 + dim * 4
            for _ in 0..<Int(count) {
                guard offset + stride <= data.count else { break }
                let sid = Int64(raw.loadUnaligned(fromByteOffset: offset, as: Int32.self))
                var vec = [Float](repeating: 0, count: dim)
                for d in 0..<dim {
                    vec[d] = raw.loadUnaligned(fromByteOffset: offset + 4 + d * 4, as: Float32.self)
                }
                result.append((sid, vec))
                offset += stride
            }
            return result
        }
    }

    private static func pixelBuffer(from image: UIImage, side: Int) -> CVPixelBuffer? {
        let size = CGSize(width: side, height: side)
        UIGraphicsBeginImageContextWithOptions(size, true, 1)
        image.draw(in: CGRect(origin: .zero, size: size))
        let scaled = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        guard let cg = scaled?.cgImage else { return nil }

        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, side, side,
                            kCVPixelFormatType_32ARGB, attrs as CFDictionary, &pb)
        guard let buffer = pb else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: side, height: side, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        return buffer
    }
}
