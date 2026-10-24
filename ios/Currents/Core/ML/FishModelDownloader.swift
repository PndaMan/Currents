import CoreML
import Foundation
import Observation
import ZIPFoundation

/// What the species ID model is doing, for the log-catch banner and the
/// species picker. `FishModelDownloader` keeps it up to date; views read
/// `FishModelStatus.shared.phase` and redraw when it changes.
@MainActor
@Observable
final class FishModelStatus {
    static let shared = FishModelStatus()

    enum Phase: Equatable {
        /// Not checked yet this launch.
        case unknown
        /// Downloading now. `progress` runs 0 to 1 once the size is known.
        case downloading(progress: Double?)
        /// On the phone and ready to use.
        case installed
        /// The last attempt couldn't reach the server.
        case needsInternet
        /// The last attempt reached the server but didn't finish.
        case failed
    }

    private(set) var phase: Phase = .unknown

    var isInstalled: Bool { phase == .installed }

    var isDownloading: Bool {
        if case .downloading = phase { return true }
        return false
    }

    fileprivate func update(_ phase: Phase) {
        self.phase = phase
    }

    /// Progress only moves an active download forward, so a late update
    /// can't undo `installed` or `failed`.
    fileprivate func showProgress(_ fraction: Double) {
        guard case .downloading = phase else { return }
        phase = .downloading(progress: min(max(fraction, 0), 1))
    }
}

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
    /// Every outcome is published to `FishModelStatus.shared`.
    func ensureModelDownloaded() async {
        if isModelAvailable {
            await report(.installed)
            return
        }
        guard !isDownloading else { return }
        guard let remote = Self.remoteModelURL else {
            await report(.failed)
            return
        }
        isDownloading = true
        defer { isDownloading = false }
        await report(.downloading(progress: nil))
        let progress = ModelDownloadProgress()
        defer { progress.stop() }
        do {
            let fm = FileManager.default
            let (tempURL, response) = try await URLSession.shared.download(from: remote, delegate: progress)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                await report(.failed)
                return
            }

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
            guard let pkg = contents.first(where: { $0.pathExtension == "mlpackage" }) else {
                await report(.failed)
                return
            }

            let compiled = try await MLModel.compileModel(at: pkg)
            try? fm.removeItem(at: Self.compiledURL)
            try fm.moveItem(at: compiled, to: Self.compiledURL)
            try? fm.removeItem(at: unzipDir)
            await report(.installed)
        } catch {
            // Retried on the next launch or the next catch scan.
            await report(Self.isOffline(error) ? .needsInternet : .failed)
        }
    }

    private func report(_ phase: FishModelStatus.Phase) async {
        await MainActor.run { FishModelStatus.shared.update(phase) }
    }

    /// Errors that mean there was no usable connection, as opposed to a
    /// server or file problem.
    private static func isOffline(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut,
             .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
             .dataNotAllowed, .internationalRoamingOff, .callIsActive:
            return true
        default:
            return false
        }
    }
}

/// Passes the download's progress to `FishModelStatus`, at most once per
/// percent so the banner doesn't redraw for every packet.
private final class ModelDownloadProgress: NSObject, URLSessionTaskDelegate {
    private let lock = NSLock()
    private var observation: NSKeyValueObservation?
    private var lastReported = 0.0

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        let observation = task.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
            self?.report(progress.fractionCompleted)
        }
        lock.lock()
        self.observation = observation
        lock.unlock()
    }

    func stop() {
        lock.lock()
        observation?.invalidate()
        observation = nil
        lock.unlock()
    }

    private func report(_ fraction: Double) {
        guard fraction.isFinite, fraction > 0 else { return }
        lock.lock()
        let isNew = fraction - lastReported >= 0.01 || (fraction >= 1 && lastReported < 1)
        if isNew { lastReported = fraction }
        lock.unlock()
        guard isNew else { return }
        Task { @MainActor in FishModelStatus.shared.showProgress(fraction) }
    }
}
