import CoreML
import Vision
import UIKit

/// On-device fish species identification using CoreML.
/// Uses a YOLOv8n model converted to CoreML, or falls back to Vision's
/// built-in animal classifier.
actor FishClassifier {
    struct Prediction: Sendable {
        let species: String
        let confidence: Float
    }

    private var model: VNCoreMLModel?
    private var isLoaded = false

    /// Load the CoreML model. Call once at app startup.
    func loadModel() {
        // Try to load our custom fish model first
        if let modelURL = Bundle.main.url(forResource: "FishID", withExtension: "mlmodelc"),
           let mlModel = try? MLModel(contentsOf: modelURL),
           let vnModel = try? VNCoreMLModel(for: mlModel) {
            self.model = vnModel
            self.isLoaded = true
            return
        }

        // No custom model bundled yet — we'll use Vision's built-in classifier
        // as a placeholder. It recognizes some fish species already.
        self.isLoaded = true
    }

    /// Classify a fish in the given image. Returns top-N predictions.
    func classify(image: UIImage, maxResults: Int = 3) async throws -> [Prediction] {
        guard let cgImage = image.cgImage else {
            return []
        }

        return try await withCheckedThrowingContinuation { continuation in
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            let request: VNRequest
            if let model {
                // Custom CoreML model
                let coreMLRequest = VNCoreMLRequest(model: model) { req, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    let predictions = self.parseCoreMLResults(req.results, maxResults: maxResults)
                    continuation.resume(returning: predictions)
                }
                coreMLRequest.imageCropAndScaleOption = .centerCrop
                request = coreMLRequest
            } else {
                // Fallback: Vision's built-in animal classifier
                let classifyRequest = VNClassifyImageRequest { req, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    let predictions = self.parseClassificationResults(req.results, maxResults: maxResults)
                    continuation.resume(returning: predictions)
                }
                request = classifyRequest
            }

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func parseCoreMLResults(_ results: [VNObservation]?, maxResults: Int) -> [Prediction] {
        guard let results = results as? [VNClassificationObservation] else { return [] }
        return results.prefix(maxResults).map { obs in
            Prediction(species: obs.identifier, confidence: obs.confidence)
        }
    }

    private func parseClassificationResults(_ results: [VNObservation]?, maxResults: Int) -> [Prediction] {
        guard let results = results as? [VNClassificationObservation] else { return [] }
        // Filter for fish-related classifications
        let fishRelated = results.filter { obs in
            let id = obs.identifier.lowercased()
            return id.contains("fish") || id.contains("bass") || id.contains("trout") ||
                   id.contains("carp") || id.contains("salmon") || id.contains("tuna") ||
                   id.contains("aquarium") || obs.confidence > 0.3
        }
        let source = fishRelated.isEmpty ? results : fishRelated
        return source.prefix(maxResults).map { obs in
            Prediction(species: obs.identifier, confidence: obs.confidence)
        }
    }
}
