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
/// A ranked species match shown in the AI Fish ID card.
struct SpeciesMatch: Sendable {
    let species: Species
    let confidence: Float
}

actor EmbeddingSpeciesIdentifier {
    struct Ranked: Sendable {
        let speciesId: Int64
        let confidence: Float
    }

    private var model: MLModel?
    private var imageInputName: String?
    private var outputName: String?
    private var speciesEmbeddings: [(id: Int64, vec: [Float])] = []
    private var embeddingsLoaded = false

    private static var cachedModelURL: URL {
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return cache.appendingPathComponent("MLModels/FishID.mlmodelc")
    }

    var isReady: Bool { model != nil && !speciesEmbeddings.isEmpty }

    /// Load the bundled species embeddings (once) and the CoreML encoder.
    ///
    /// The encoder is auto-downloaded in the background on first launch, so it
    /// may not exist yet on the first catch. We therefore RETRY the model load
    /// on every call until it appears — otherwise the accurate tier would stay
    /// dark until the next app restart.
    func loadIfNeeded() {
        if !embeddingsLoaded {
            embeddingsLoaded = true
            // The embeddings ship inside the Resources/Data FOLDER REFERENCE,
            // so they live under "Data/" in the bundle — a root-level lookup
            // returns nil, which silently killed this whole tier (the app then
            // fell back to matching photos against the cartoon artwork).
            if let url = Bundle.main.url(forResource: "species_embeddings", withExtension: "bin", subdirectory: "Data")
                ?? Bundle.main.url(forResource: "species_embeddings", withExtension: "bin"),
               let data = try? Data(contentsOf: url) {
                speciesEmbeddings = Self.parseEmbeddings(data)
            }
        }
        guard model == nil, !speciesEmbeddings.isEmpty else { return }

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
    ///
    /// `prior` is an optional per-species multiplier (species id → factor, ~0.5…1)
    /// applied to each match's probability weight — a gentle location/season
    /// nudge, never a hard filter. Species not in the map keep weight 1.
    func identify(image: UIImage, prior: [Int64: Float] = [:], top: Int = 6) -> [Ranked] {
        loadIfNeeded()
        guard model != nil, imageInputName != nil, outputName != nil else { return [] }

        // Crop to the fish (saliency) so the angler / grass / sky don't dominate
        // the embedding.
        let subject = Self.croppedToSubject(image) ?? image

        // Test-time augmentation: average the embedding of the fish and its
        // mirror image. A horizontal flip shouldn't change the species, so
        // averaging the two smooths out pose/lighting quirks and measurably
        // steadies borderline IDs — for the cost of one extra encoder pass.
        guard var q = embed(subject) else { return [] }
        if let mirror = Self.mirrored(subject), let q2 = embed(mirror) {
            let n = q.count
            for i in 0..<n { q[i] += q2[i] }
            var norm: Float = 0
            for v in q { norm += v * v }
            norm = max(norm.squareRoot(), 1e-6)
            for i in 0..<n { q[i] /= norm }
        }
        let n = q.count

        // Cosine similarity against each species text embedding.
        var scored: [(id: Int64, sim: Float)] = []
        scored.reserveCapacity(speciesEmbeddings.count)
        for (id, vec) in speciesEmbeddings where vec.count == n {
            var dot: Float = 0
            for i in 0..<n { dot += q[i] * vec[i] }
            scored.append((id, dot))
        }
        guard !scored.isEmpty else { return [] }

        // HONEST confidence: a proper temperature-scaled softmax over ALL species
        // (CLIP's logit scale ≈ 100). When the match is clear the top probability
        // is high; when the model is unsure everything comes out low — instead of
        // the old formula that mapped every near-equal cosine to a fake ~98%.
        let scale: Float = 100
        let maxSim = scored.max(by: { $0.sim < $1.sim })!.sim
        var sum: Float = 0
        var exps: [(id: Int64, e: Float)] = []
        exps.reserveCapacity(scored.count)
        for s in scored {
            // Gentle region/season prior: scales this species' probability mass
            // (0.5…1). Because it multiplies the softmax weight rather than the
            // cosine logit, an implausible species is nudged down, not vetoed —
            // a strong visual match still wins.
            let e = expf((s.sim - maxSim) * scale) * (prior[s.id] ?? 1.0)
            sum += e
            exps.append((s.id, e))
        }
        exps.sort { $0.e > $1.e }
        let denom = max(sum, 1e-6)
        return exps.prefix(top).map { item in
            Ranked(speciesId: item.id, confidence: max(0.001, min(0.999, item.e / denom)))
        }
    }

    /// Run the encoder on one image → its L2-normalised embedding.
    private func embed(_ image: UIImage) -> [Float]? {
        guard let model, let imageInputName, let outputName,
              let pixelBuffer = Self.pixelBuffer(from: image, side: 224),
              let provider = try? MLDictionaryFeatureProvider(
                  dictionary: [imageInputName: MLFeatureValue(pixelBuffer: pixelBuffer)]),
              let out = try? model.prediction(from: provider),
              let arr = out.featureValue(for: outputName)?.multiArrayValue else { return nil }
        let n = arr.count
        var q = [Float](repeating: 0, count: n)
        for i in 0..<n { q[i] = arr[i].floatValue }
        var norm: Float = 0
        for v in q { norm += v * v }
        norm = max(norm.squareRoot(), 1e-6)
        for i in 0..<n { q[i] /= norm }
        return q
    }

    /// A horizontally-mirrored copy (baked into pixels) for test-time augmentation.
    private static func mirrored(_ image: UIImage) -> UIImage? {
        guard image.cgImage != nil else { return nil }
        let size = image.size
        UIGraphicsBeginImageContextWithOptions(size, false, 1)
        defer { UIGraphicsEndImageContext() }
        guard let ctx = UIGraphicsGetCurrentContext() else { return nil }
        ctx.translateBy(x: size.width, y: 0)
        ctx.scaleBy(x: -1, y: 1)
        image.draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }

    /// Crop to the most salient region (the held-up fish) so the background
    /// doesn't swamp the embedding. Falls back to the whole image.
    private static func croppedToSubject(_ image: UIImage) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        try? handler.perform([request])
        guard let obs = request.results?.first as? VNSaliencyImageObservation,
              let salient = obs.salientObjects?.first else {
            return image
        }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        var box = salient.boundingBox.insetBy(dx: -salient.boundingBox.width * 0.08,
                                              dy: -salient.boundingBox.height * 0.08)
        box = box.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        let rect = CGRect(x: box.minX * w, y: (1 - box.maxY) * h,
                          width: box.width * w, height: box.height * h).integral
        guard rect.width > 40, rect.height > 40, let cropped = cg.cropping(to: rect) else { return image }
        return UIImage(cgImage: cropped)
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
        // Aspect-fill + centre-crop to a square (CLIP's own preprocessing),
        // instead of stretching. Stretching squished long fish and skewed the
        // embedding; filling keeps true proportions.
        let src = image.size
        if src.width > 0, src.height > 0 {
            let scale = max(size.width / src.width, size.height / src.height)
            let dw = src.width * scale, dh = src.height * scale
            image.draw(in: CGRect(x: (size.width - dw) / 2, y: (size.height - dh) / 2, width: dw, height: dh))
        } else {
            image.draw(in: CGRect(origin: .zero, size: size))
        }
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
