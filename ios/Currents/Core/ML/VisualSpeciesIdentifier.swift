import Vision
import UIKit

/// On-device species identification by **visual similarity** to the bundled
/// species reference photos.
///
/// Apple's generic `VNClassifyImageRequest` can't tell gamefish apart (it
/// called a largemouth bass a brook trout). Instead we:
///   1. Crop the catch photo to the fish (saliency) so the background —
///      angler, grass, sky — doesn't dominate.
///   2. Compute a neural feature print (`VNGenerateImageFeaturePrintRequest`).
///   3. Compare it against feature prints of every species' reference image
///      (`fish_<id>` collection artwork) and rank by distance.
///
/// The label space is therefore exactly the app's ~1500 species, and the
/// nearest reference wins — a bass photo matches the bass reference, not a
/// trout. Fully offline; the gallery is computed once and cached to disk.
actor VisualSpeciesIdentifier {
    struct Ranked: Sendable {
        let speciesId: Int64
        let distance: Float          // lower = more similar
        var confidence: Float        // 0…1, derived from distance
    }

    private var gallery: [(id: Int64, print: VNFeaturePrintObservation)] = []
    private var isBuilt = false

    private static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("SpeciesFeaturePrints.v1.archive")
    }

    /// Build the reference gallery from bundled artwork. Cached across launches.
    /// Call once in the background at startup.
    func build(species: [Species]) {
        guard !isBuilt else { return }
        let withArt = species.filter { UIImage(named: $0.artworkAssetName) != nil }
        guard !withArt.isEmpty else { isBuilt = true; return }

        if loadCache(expectedIds: withArt.map(\.id)) {
            isBuilt = true
            return
        }

        var built: [(Int64, VNFeaturePrintObservation)] = []
        for sp in withArt {
            guard let cg = UIImage(named: sp.artworkAssetName)?.cgImage,
                  let fp = Self.featurePrint(cgImage: cg) else { continue }
            built.append((sp.id, fp))
        }
        gallery = built
        isBuilt = true
        saveCache()
    }

    /// Rank the most visually similar species for a catch photo.
    func identify(image: UIImage, top: Int = 6) -> [Ranked] {
        guard !gallery.isEmpty else { return [] }
        let cg = Self.croppedToSubject(image) ?? image.cgImage
        guard let cg, let query = Self.featurePrint(cgImage: cg) else { return [] }

        var scored: [Ranked] = []
        scored.reserveCapacity(gallery.count)
        for (id, fp) in gallery {
            var distance: Float = 0
            do {
                try fp.computeDistance(&distance, to: query)
            } catch {
                continue
            }
            scored.append(Ranked(speciesId: id, distance: distance, confidence: 0))
        }
        scored.sort { $0.distance < $1.distance }

        // Map distance → a friendly confidence. Feature-print distances are
        // typically ~18–30; closer is better. Normalise against the spread of
        // the top results so the UI shows a sensible percentage.
        let best = scored.first?.distance ?? 0
        return scored.prefix(top).map { r in
            let conf = max(0.05, min(0.99, 1.0 - (r.distance - best) / 22.0 - best / 60.0))
            return Ranked(speciesId: r.speciesId, distance: r.distance, confidence: conf)
        }
    }

    // MARK: - Vision helpers

    private static func featurePrint(cgImage: CGImage) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        request.imageCropAndScaleOption = .centerCrop
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        return request.results?.first as? VNFeaturePrintObservation
    }

    /// Crop to the most salient region (the held-up fish) so the background
    /// doesn't swamp the embedding. Falls back to the whole image.
    private static func croppedToSubject(_ image: UIImage) -> CGImage? {
        guard let cg = image.cgImage else { return nil }
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        try? handler.perform([request])
        guard let obs = request.results?.first as? VNSaliencyImageObservation,
              let salient = obs.salientObjects?.first else {
            return cg
        }
        // boundingBox is normalised with origin at bottom-left; pad a little.
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        var box = salient.boundingBox
        box = box.insetBy(dx: -box.width * 0.08, dy: -box.height * 0.08)
        let rect = CGRect(
            x: max(0, box.minX * w),
            y: max(0, (1 - box.maxY) * h),
            width: min(w, box.width * w),
            height: min(h, box.height * h)
        ).integral
        guard rect.width > 40, rect.height > 40 else { return cg }
        return cg.cropping(to: rect) ?? cg
    }

    // MARK: - Disk cache

    private func loadCache(expectedIds: [Int64]) -> Bool {
        guard let data = try? Data(contentsOf: Self.cacheURL) else { return false }
        guard let root = try? NSKeyedUnarchiver.unarchivedObject(
            ofClasses: [NSDictionary.self, NSArray.self, NSNumber.self, VNFeaturePrintObservation.self],
            from: data
        ) as? [NSNumber: VNFeaturePrintObservation] else { return false }
        // Invalidate if the species set changed size.
        guard root.count == expectedIds.count else { return false }
        gallery = root.map { ($0.key.int64Value, $0.value) }
        return !gallery.isEmpty
    }

    private func saveCache() {
        var dict: [NSNumber: VNFeaturePrintObservation] = [:]
        for (id, fp) in gallery { dict[NSNumber(value: id)] = fp }
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: dict, requiringSecureCoding: true) {
            try? data.write(to: Self.cacheURL, options: .atomic)
        }
    }
}
