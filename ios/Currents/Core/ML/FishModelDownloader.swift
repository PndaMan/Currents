import CoreML
import Foundation
import ZIPFoundation

/// Downloads and compiles the BioCLIP image encoder used by
/// `EmbeddingSpeciesIdentifier`. This is the ONLY fish-ID brain in the app —
/// the old Vision/artwork-similarity fallbacks produced junk guesses and were
/// removed. Until the model is on disk, AI Fish ID simply reports that it's
/// still downloading instead of guessing.
actor FishModelDownloader {
    /// Release-hosted CoreML model produced by the `ml/` build pipeline
    /// (see .github/workflows/fish-model.yml). Override via the `FishModelURL`
    /// Info.plist key so the URL can change without an app update.
    private static var remoteModelURL: URL? {
        if let s = Bundle.main.object(forInfoDictionaryKey: "FishModelURL") as? String,
           let url = URL(string: s), !s.isEmpty {
            return url
        }
        // A zipped .mlpackage (unzipped + compiled on-device). Pinned to the
        // `fish-model` release tag (published by fish-model.yml).
        return URL(string: "https://github.com/PndaMan/Currents/releases/download/fish-model/FishID.mlpackage.zip")
    }

    /// Where the compiled model is cached (read by EmbeddingSpeciesIdentifier).
    private static var modelCacheURL: URL {
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return cache.appendingPathComponent("MLModels", isDirectory: true)
    }

    private static var compiledURL: URL {
        modelCacheURL.appendingPathComponent("FishID.mlmodelc")
    }

    private var isDownloading = false

    var isModelAvailable: Bool {
        Bundle.main.url(forResource: "FishID", withExtension: "mlmodelc") != nil
            || FileManager.default.fileExists(atPath: Self.compiledURL.path)
    }

    /// Download + compile the model if it isn't on disk yet. Safe to call
    /// repeatedly (no-ops while a download is running or once cached).
    func ensureModelDownloaded() async {
        guard !isModelAvailable, !isDownloading, let remote = Self.remoteModelURL else { return }
        isDownloading = true
        defer { isDownloading = false }
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

            let contents = (try? fm.contentsOfDirectory(at: unzipDir, includingPropertiesForKeys: nil)) ?? []
            guard let pkg = contents.first(where: { $0.pathExtension == "mlpackage" }) else { return }

            let compiled = try await MLModel.compileModel(at: pkg)
            try? fm.removeItem(at: Self.compiledURL)
            try fm.moveItem(at: compiled, to: Self.compiledURL)
            try? fm.removeItem(at: unzipDir)
        } catch {
            // Offline — retried on the next launch / next catch scan.
        }
    }
}
