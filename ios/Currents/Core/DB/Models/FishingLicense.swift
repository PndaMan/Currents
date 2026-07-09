import Foundation
import GRDB

/// A stored fishing licence / permit — its document (PDF or image) plus the
/// details we OCR out of it (expiry, holder, number…). Expiry drives reminder
/// notifications so it never lapses unnoticed.
struct FishingLicense: Codable, Identifiable, Sendable, Hashable {
    var id: String
    var title: String
    var licenseType: String?
    var holderName: String?
    var licenseNumber: String?
    var region: String?
    var issueDate: Date?
    var expiryDate: Date?
    var fileName: String?          // relative name in Documents/licenses
    var fileKind: String?          // "pdf" | "image"
    var notes: String?
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        title: String,
        licenseType: String? = nil,
        holderName: String? = nil,
        licenseNumber: String? = nil,
        region: String? = nil,
        issueDate: Date? = nil,
        expiryDate: Date? = nil,
        fileName: String? = nil,
        fileKind: String? = nil,
        notes: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.licenseType = licenseType
        self.holderName = holderName
        self.licenseNumber = licenseNumber
        self.region = region
        self.issueDate = issueDate
        self.expiryDate = expiryDate
        self.fileName = fileName
        self.fileKind = fileKind
        self.notes = notes
        self.createdAt = createdAt
    }

    /// Days until expiry (negative if already expired).
    var daysUntilExpiry: Int? {
        guard let expiryDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now),
                                               to: Calendar.current.startOfDay(for: expiryDate)).day
    }

    var isExpired: Bool { (daysUntilExpiry ?? 1) < 0 }
}

extension FishingLicense: FetchableRecord, PersistableRecord {
    static let databaseTableName = "fishingLicense"
}
