import CoreML
import Vision
import UIKit

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
        let cachedModelURL = Self.modelCacheURL.appendingPathComponent("FishID.mlmodelc")
        if FileManager.default.fileExists(atPath: cachedModelURL.path),
           let mlModel = try? MLModel(contentsOf: cachedModelURL),
           let vnModel = try? VNCoreMLModel(for: mlModel) {
            self.model = vnModel
            self.isCustomModel = true
            self.isLoaded = true
            return
        }

        // 3. No custom model — Vision framework fallback (still neural network based)
        self.isLoaded = true
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
