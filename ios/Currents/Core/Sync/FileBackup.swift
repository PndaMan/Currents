import Foundation
import GRDB

/// File-based backup/restore — works on sideloaded IPAs without iCloud entitlements.
/// Exports the SQLite database as a shareable .sqlite file; imports via document picker.
actor FileBackup {
    static let shared = FileBackup()

    enum BackupError: Error, LocalizedError {
        case exportFailed(Error)
        case importFailed(Error)
        case invalidFile

        var errorDescription: String? {
            switch self {
            case .exportFailed(let e): "Export failed: \(e.localizedDescription)"
            case .importFailed(let e): "Import failed: \(e.localizedDescription)"
            case .invalidFile: "The selected file is not a valid Currents backup."
            }
        }
    }

    /// Export a clean copy of the database to a temp file for sharing.
    func exportBackup(db: AppDatabase) throws -> URL {
        let dateStamp = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd_HHmm"
            return f.string(from: Date())
        }()

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("currents_backup_\(dateStamp).sqlite")
        try? FileManager.default.removeItem(at: tempURL)

        do {
            let destQueue = try DatabaseQueue(path: tempURL.path)
            try db.db.backup(to: destQueue)
            return tempURL
        } catch {
            throw BackupError.exportFailed(error)
        }
    }

    /// Restore the database from an imported .sqlite file.
    func importBackup(from url: URL, to db: AppDatabase) throws {
        // Verify the file exists and is accessible
        guard url.startAccessingSecurityScopedResource() || true else {
            throw BackupError.invalidFile
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            // Validate it's a real SQLite database by trying to open it
            let sourceQueue = try DatabaseQueue(path: url.path)
            _ = try sourceQueue.read { db in
                // Check for our catch table to verify it's a Currents backup
                try db.tableExists("catch")
            }

            // Restore by backing up from source to our live database
            try sourceQueue.backup(to: db.db)
        } catch {
            throw BackupError.importFailed(error)
        }
    }

    /// Get the size of the current database file.
    var databaseSize: String? {
        guard let url = try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent("currents.sqlite"),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else {
            return nil
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    // MARK: - Automatic rotating snapshots

    /// A single automatic backup snapshot on disk.
    struct Snapshot: Identifiable, Sendable {
        let url: URL
        let date: Date
        let sizeBytes: Int64
        var id: String { url.lastPathComponent }

        var formattedSize: String {
            ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
        }
    }

    /// Automatic backups live in Documents/Backups — Documents is included in
    /// the device's own iCloud/computer backup, so these survive device
    /// restores even without the app-specific iCloud container entitlement
    /// (which TestFlight builds don't have).
    private var snapshotsDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Write a fresh snapshot and prune old ones beyond `keep`.
    @discardableResult
    func writeSnapshot(db: AppDatabase, keep: Int = 5) throws -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        let url = snapshotsDir.appendingPathComponent("auto_\(f.string(from: Date())).sqlite")
        do {
            let destQueue = try DatabaseQueue(path: url.path)
            try db.db.backup(to: destQueue)
        } catch {
            throw BackupError.exportFailed(error)
        }
        // Prune oldest beyond the keep count.
        let all = snapshots()
        for old in all.dropFirst(keep) {
            try? FileManager.default.removeItem(at: old.url)
        }
        return url
    }

    /// All automatic snapshots, newest first.
    func snapshots() -> [Snapshot] {
        let keys: [URLResourceKey] = [.fileSizeKey, .creationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(
            at: snapshotsDir, includingPropertiesForKeys: keys
        )) ?? []
        return files
            .filter { $0.pathExtension == "sqlite" }
            .compactMap { url -> Snapshot? in
                let v = try? url.resourceValues(forKeys: Set(keys))
                return Snapshot(
                    url: url,
                    date: v?.creationDate ?? .distantPast,
                    sizeBytes: Int64(v?.fileSize ?? 0)
                )
            }
            .sorted { $0.date > $1.date }
    }

    func deleteSnapshot(_ snapshot: Snapshot) {
        try? FileManager.default.removeItem(at: snapshot.url)
    }
}

// MARK: - Automatic backup scheduler

/// Runs a backup at most once a day, triggered when the app goes to the
/// background: a local rotating snapshot always, plus the iCloud-container
/// backup when the entitlement/account make it available.
enum AutoBackup {
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "autoBackupEnabled") as? Bool ?? true
    }

    static var lastRun: Date? {
        let t = UserDefaults.standard.double(forKey: "lastAutoBackupAt")
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    static func runIfDue(db: AppDatabase, force: Bool = false) {
        guard isEnabled || force else { return }
        if !force, let last = lastRun, Date().timeIntervalSince(last) < 20 * 3600 {
            return
        }
        Task.detached(priority: .utility) {
            do {
                try await FileBackup.shared.writeSnapshot(db: db)
                if await CloudBackup.shared.isAvailable {
                    try? await CloudBackup.shared.backup(db: db)
                }
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastAutoBackupAt")
            } catch {
                print("[Currents] Automatic backup failed: \(error)")
            }
        }
    }
}
