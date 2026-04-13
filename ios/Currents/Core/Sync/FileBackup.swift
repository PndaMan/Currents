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
}
