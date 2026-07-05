import CoreML
import Vision
import UIKit
import ZIPFoundation

/// On-device fish species identification using CoreML.
///
/// Resolution order:
/// 1. Custom FishNet model (`FishID.mlmodelc`) — 17k species, most accurate
/// 2. Downloaded model from cache (auto-downloaded on first classify if network available)
/// 3. Vision framework `VNClassifyImageRequest` + `VNRecognizeAnimalsRequest` combined
///
/// The Vision fallback uses Apple's on-device neural networks (not keyword
/// filtering) — these are real classifiers that run inference on the image.
actor FishClassifier {
    struct Prediction: Sendable {
        let species: String
        let confidence: Float
    }

    private var model: VNCoreMLModel?
    private(set) var isCustomModel = false
    private var isLoaded = false

    /// Release-hosted CoreML model produced by the `ml/` build pipeline
    /// (see .github/workflows/fish-model.yml). Auto-downloaded on first use
    /// when the model isn't bundled. Override via the `FishModelURL` Info.plist
    /// key so the URL can change without an app update.
    private static var remoteModelURL: URL? {
        if let s = Bundle.main.object(forInfoDictionaryKey: "FishModelURL") as? String,
           let url = URL(string: s), !s.isEmpty {
            return url
        }
        // A zipped .mlpackage (unzipped + compiled on-device). Pinned to the
        // `fish-model` release tag (published by fish-model.yml); `latest` can
        // resolve to an IPA release that has no model asset.
        return URL(string: "https://github.com/PndaMan/Currents/releases/download/fish-model/FishID.mlpackage.zip")
    }

    /// Where downloaded models are cached
    private static var modelCacheURL: URL {
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return cache.appendingPathComponent("MLModels", isDirectory: true)
    }

    /// Load the CoreML model. Call once at app startup.
    func loadModel() {
        // 1. Try bundled model
        if let modelURL = Bundle.main.url(forResource: "FishID", withExtension: "mlmodelc"),
           let mlModel = try? MLModel(contentsOf: modelURL),
           let vnModel = try? VNCoreMLModel(for: mlModel) {
            self.model = vnModel
            self.isCustomModel = true
            self.isLoaded = true
            return
        }

        // 2. Try cached (previously downloaded) compiled model
        if loadCachedModel() {
            return
        }

        // 3. No custom model yet — Vision framework fallback for now, and kick
        //    off a background download of the accurate model for next time.
        self.isLoaded = true
        Task { await downloadModelIfNeeded() }
    }

    @discardableResult
    private func loadCachedModel() -> Bool {
        let cachedModelURL = Self.modelCacheURL.appendingPathComponent("FishID.mlmodelc")
        guard FileManager.default.fileExists(atPath: cachedModelURL.path),
              let mlModel = try? MLModel(contentsOf: cachedModelURL) else {
            return false
        }
        // The downloaded asset is the BioCLIP ENCODER (embedding output) used
        // by EmbeddingSpeciesIdentifier — it is NOT a classifier. Only adopt
        // it here when it actually predicts class labels; otherwise this
        // classifier sticks to the Vision fallback and the encoder does its
        // job in the embedding tier.
        guard mlModel.modelDescription.predictedFeatureName != nil,
              let vnModel = try? VNCoreMLModel(for: mlModel) else {
            return false
        }
        self.model = vnModel
        self.isCustomModel = true
        self.isLoaded = true
        return true
    }

    /// Download + compile the accurate model in the background if we don't
    /// already have it. Safe to call repeatedly; no-ops once loaded.
    func downloadModelIfNeeded() async {
        guard model == nil, let remote = Self.remoteModelURL else { return }
        // Already compiled from a previous launch? Don't re-download — even
        // when it's the encoder (unusable as a classifier here), the
        // embedding identifier is the consumer of that file.
        let compiledURL = Self.modelCacheURL.appendingPathComponent("FishID.mlmodelc")
        if FileManager.default.fileExists(atPath: compiledURL.path) {
            _ = loadCachedModel()
            return
        }
        do {
            let fm = FileManager.default
            let (tempURL, response) = try await URLSession.shared.download(from: remote)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }

            try fm.createDirectory(at: Self.modelCacheURL, withIntermediateDirectories: true)

            // The asset is a zipped .mlpackage. Unzip it, then compile the
            // package to the .mlmodelc directory MLModel(contentsOf:) loads.
            let zipURL = Self.modelCacheURL.appendingPathComponent("FishID.mlpackage.zip")
            try? fm.removeItem(at: zipURL)
            try fm.moveItem(at: tempURL, to: zipURL)

            let unzipDir = Self.modelCacheURL.appendingPathComponent("unzipped", isDirectory: true)
            try? fm.removeItem(at: unzipDir)
            try fm.createDirectory(at: unzipDir, withIntermediateDirectories: true)
            try fm.unzipItem(at: zipURL, to: unzipDir)
            try? fm.removeItem(at: zipURL)

            // Find the .mlpackage inside the unzipped output.
            let contents = (try? fm.contentsOfDirectory(at: unzipDir, includingPropertiesForKeys: nil)) ?? []
            guard let pkg = contents.first(where: { $0.pathExtension == "mlpackage" }) else { return }

            let compiled = try await MLModel.compileModel(at: pkg)
            let dest = Self.modelCacheURL.appendingPathComponent("FishID.mlmodelc")
            try? fm.removeItem(at: dest)
            try fm.moveItem(at: compiled, to: dest)
            try? fm.removeItem(at: unzipDir)

            _ = loadCachedModel()
        } catch {
            // Offline or asset not published yet — keep using Vision fallback.
        }
    }

    /// Classify a fish in the given image. Returns top-N predictions.
    /// Combines custom model OR Vision's classify + animal recognition.
    func classify(image: UIImage, maxResults: Int = 5) async throws -> [Prediction] {
        guard let cgImage = image.cgImage else {
            return []
        }

        if let model {
            // Custom CoreML model — single-pass classification
            return try await runCoreMLClassification(cgImage: cgImage, model: model, maxResults: maxResults)
        } else {
            // Vision fallback — run both classifiers in parallel for best coverage
            async let classifyResults = runVisionClassification(cgImage: cgImage, maxResults: maxResults)
            async let animalResults = runAnimalRecognition(cgImage: cgImage)

            let classify = try await classifyResults
            let animals = try await animalResults

            // Merge: animal detections first (higher specificity), then classifications
            var seen = Set<String>()
            var merged: [Prediction] = []
            for p in (animals + classify) {
                let key = p.species.lowercased()
                if !seen.contains(key) {
                    seen.insert(key)
                    merged.append(p)
                }
            }
            return Array(merged.prefix(maxResults))
        }
    }

    // MARK: - Custom CoreML Model

    private func runCoreMLClassification(cgImage: CGImage, model: VNCoreMLModel, maxResults: Int) async throws -> [Prediction] {
        try await withCheckedThrowingContinuation { continuation in
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            let request = VNCoreMLRequest(model: model) { req, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let results = req.results as? [VNClassificationObservation] else {
                    continuation.resume(returning: [])
                    return
                }
                let predictions = results.prefix(maxResults).map { obs in
                    Prediction(species: Self.cleanSpeciesName(obs.identifier), confidence: obs.confidence)
                }
                continuation.resume(returning: predictions)
            }
            request.imageCropAndScaleOption = .centerCrop

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Vision Classification (Neural Network)

    private func runVisionClassification(cgImage: CGImage, maxResults: Int) async throws -> [Prediction] {
        try await withCheckedThrowingContinuation { continuation in
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            let request = VNClassifyImageRequest { req, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let results = req.results as? [VNClassificationObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                // Vision's VNClassifyImageRequest uses a real neural network.
                // Filter for animal/fish-related classifications with meaningful confidence.
                let fishKeywords: Set<String> = [
                    "fish", "bass", "trout", "carp", "salmon", "tuna", "catfish",
                    "perch", "pike", "walleye", "snapper", "grouper", "tilapia",
                    "barramundi", "marlin", "swordfish", "mahi", "dorado",
                    "bream", "yellowtail", "kingfish", "mackerel", "cod",
                    "haddock", "halibut", "flounder", "sole", "ray", "shark",
                    "sturgeon", "eel", "anchovy", "sardine", "herring",
                    "goldfish", "koi", "cichlid", "coho", "chinook",
                    "largemouth", "smallmouth", "striped", "spotted",
                    "animal", "aquatic", "underwater",
                ]

                let relevant = results.filter { obs in
                    let id = obs.identifier.lowercased()
                    return obs.confidence > 0.05 && fishKeywords.contains(where: { id.contains($0) })
                }

                let source = relevant.isEmpty ? Array(results.prefix(maxResults)) : Array(relevant.prefix(maxResults))
                let predictions = source.map { obs in
                    Prediction(species: Self.cleanSpeciesName(obs.identifier), confidence: obs.confidence)
                }
                continuation.resume(returning: predictions)
            }

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Animal Recognition (Neural Network)

    private func runAnimalRecognition(cgImage: CGImage) async throws -> [Prediction] {
        try await withCheckedThrowingContinuation { continuation in
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            let request = VNRecognizeAnimalsRequest { req, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let results = req.results as? [VNRecognizedObjectObservation] else {
                    continuation.resume(returning: [])
                    return
                }
                let predictions = results.flatMap { obs in
                    obs.labels.map { label in
                        Prediction(
                            species: Self.cleanSpeciesName(label.identifier),
                            confidence: label.confidence
                        )
                    }
                }
                continuation.resume(returning: predictions)
            }

            do {
                try handler.perform([request])
            } catch {
                // VNRecognizeAnimalsRequest may not be available on all devices
                continuation.resume(returning: [])
            }
        }
    }

    /// Clean up Vision's identifier format (e.g. "largemouth_bass" → "Largemouth Bass")
    private static func cleanSpeciesName(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ")
           .split(separator: " ")
           .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
           .joined(separator: " ")
    }
}
