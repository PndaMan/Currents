import Foundation
import GRDB

@MainActor
final class LicenseRepository: ObservableObject {
    private let db: AppDatabase

    init(db: AppDatabase) {
        self.db = db
    }

    func save(_ license: inout FishingLicense) throws {
        try db.db.write { db in try license.save(db) }
    }

    func delete(_ license: FishingLicense) throws {
        // Remove the stored document too.
        if let name = license.fileName {
            LicenseFileStore.delete(name)
        }
        _ = try db.db.write { db in try license.delete(db) }
    }

    func fetchAll() throws -> [FishingLicense] {
        let all = try db.db.read { db in try FishingLicense.fetchAll(db) }
        // Soonest expiry first; undated licences last.
        return all.sorted {
            switch ($0.expiryDate, $1.expiryDate) {
            case let (a?, b?): return a < b
            case (_?, nil): return true
            case (nil, _?): return false
            default: return $0.createdAt > $1.createdAt
            }
        }
    }
}

/// Stores licence documents (PDF/images) in Documents/licenses.
enum LicenseFileStore {
    static var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("licenses", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for name: String) -> URL { directory.appendingPathComponent(name) }

    /// Copy/write incoming document data, returns the stored relative name.
    static func store(data: Data, ext: String, id: String) -> String? {
        let name = "\(id).\(ext)"
        do {
            try data.write(to: url(for: name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    static func delete(_ name: String) {
        try? FileManager.default.removeItem(at: url(for: name))
    }
}
