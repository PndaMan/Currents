import Foundation
import CloudKit
import GRDB

/// Backs up and restores the local SQLite database to iCloud Drive.
/// This is a simple file-level backup, not real-time sync — keeps
/// the offline-first architecture intact while persisting data across
/// reinstalls.
actor CloudBackup {
    static let shared = CloudBackup()

    private let containerID = "iCloud.com.currents.app"
    private let backupFileName = "currents_backup.sqlite"

    enum BackupError: Error, LocalizedError {
        case iCloudUnavailable
        case noBackupFound
        case backupFailed(Error)
        case restoreFailed(Error)

        var errorDescription: String? {
            switch self {
            case .iCloudUnavailable: "iCloud is not available. Sign in to iCloud in Settings."
            case .noBackupFound: "No backup found in iCloud."
            case .backupFailed(let e): "Backup failed: \(e.localizedDescription)"
            case .restoreFailed(let e): "Restore failed: \(e.localizedDescription)"
            }
        }
    }

    /// The iCloud Documents directory for this app's container.
    private var iCloudDocsURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: containerID)?
            .appendingPathComponent("Documents", isDirectory: true)
    }

    /// Whether iCloud is available on this device.
    var isAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    /// Last backup date, if any.
    var lastBackupDate: Date? {
        guard let url = iCloudDocsURL?.appendingPathComponent(backupFileName) else { return nil }
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate
    }

    /// Back up the current database to iCloud Drive.
    func backup(db: AppDatabase) async throws {
        guard let docsURL = iCloudDocsURL else {
            throw BackupError.iCloudUnavailable
        }

        try FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)

        let backupURL = docsURL.appendingPathComponent(backupFileName)

        // Export a clean copy of the database
        do {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("backup_\(UUID().uuidString).sqlite")

            try db.db.read { sourceDb in
                try sourceDb.backup(to: DatabaseQueue(path: tempURL.path))
            }

            // Move to iCloud (replaces existing)
            if FileManager.default.fileExists(atPath: backupURL.path) {
                try FileManager.default.removeItem(at: backupURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: backupURL)
        } catch {
            throw BackupError.backupFailed(error)
        }

        // Also save settings
        let settings: [String: Any] = [
            "units": UserDefaults.standard.string(forKey: "units") ?? "metric",
            "privacyRadiusKm": UserDefaults.standard.double(forKey: "privacyRadiusKm"),
            "backupDate": Date().timeIntervalSince1970,
        ]
        let kvStore = NSUbiquitousKeyValueStore.default
        for (key, value) in settings {
            kvStore.set(value, forKey: "currents_\(key)")
        }
        kvStore.synchronize()
    }

    /// Restore the database from iCloud Drive backup.
    func restore(db: AppDatabase) async throws {
        guard let docsURL = iCloudDocsURL else {
            throw BackupError.iCloudUnavailable
        }

        let backupURL = docsURL.appendingPathComponent(backupFileName)

        // Start downloading if needed
        try FileManager.default.startDownloadingUbiquitousItem(at: backupURL)

        // Wait for download (simple polling — file is small)
        for _ in 0..<30 {
            if FileManager.default.isUbiquitousItem(at: backupURL) {
                let values = try? backupURL.resourceValues(forKeys: [.ubiquitousItemIsDownloadedKey])
                if values?.ubiquitousItemIsDownloaded == true {
                    break
                }
            }
            try await Task.sleep(for: .seconds(1))
        }

        guard FileManager.default.fileExists(atPath: backupURL.path) else {
            throw BackupError.noBackupFound
        }

        // Restore by reading from backup and writing to local db
        do {
            let backupDb = try DatabaseQueue(path: backupURL.path)
            try backupDb.read { sourceDb in
                try sourceDb.backup(to: db.db)
            }
        } catch {
            throw BackupError.restoreFailed(error)
        }

        // Restore settings
        let kvStore = NSUbiquitousKeyValueStore.default
        if let units = kvStore.string(forKey: "currents_units") {
            UserDefaults.standard.set(units, forKey: "units")
        }
        let radius = kvStore.double(forKey: "currents_privacyRadiusKm")
        if radius > 0 {
            UserDefaults.standard.set(radius, forKey: "privacyRadiusKm")
        }
    }

    /// Check if a backup exists in iCloud.
    func hasBackup() -> Bool {
        guard let url = iCloudDocsURL?.appendingPathComponent(backupFileName) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
}
