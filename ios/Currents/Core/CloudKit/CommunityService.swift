import Foundation
import CloudKit
import CoreLocation

/// Serverless multiplayer via CloudKit's PUBLIC database — no backend to run.
/// Opt-in: nothing is published until the angler joins the community. Powers a
/// friends/regional/global leaderboard and a friend-code system.
///
/// Runtime-only (CloudKit needs a device + iCloud account); the app degrades
/// gracefully to an empty state when unavailable or not joined.
@MainActor
final class CommunityService: ObservableObject {
    static let shared = CommunityService()

    private let container = CKContainer(identifier: "iCloud.com.aidanmcconnon.currents")
    private var db: CKDatabase { container.publicCloudDatabase }

    // Record types & fields
    private let profileType = "AnglerProfile"
    private let catchType = "LeaderCatch"

    @Published var joined = UserDefaults.standard.bool(forKey: "communityJoined")
    @Published var isBusy = false

    /// Stable per-user friend code (6 chars), persisted locally + published.
    var friendCode: String {
        if let c = UserDefaults.standard.string(forKey: "communityFriendCode") { return c }
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let code = String((0..<6).map { _ in chars[Int.random(in: 0..<chars.count)] })
        UserDefaults.standard.set(code, forKey: "communityFriendCode")
        return code
    }

    var friends: [String] {
        get { UserDefaults.standard.stringArray(forKey: "communityFriends") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "communityFriends") }
    }

    var displayName: String {
        UserDefaults.standard.string(forKey: "communityName") ?? "Angler \(friendCode)"
    }

    // MARK: - Types

    struct LeaderRow: Identifiable {
        let id: String
        let anglerName: String
        let friendCode: String
        let species: String
        let weightKg: Double?
        let lengthCm: Double?
        let region: String
        let date: Date
    }

    struct Profile: Identifiable {
        let id: String        // friend code
        let name: String
        let region: String
        let bestWeightKg: Double
        let speciesCount: Int
    }

    enum Scope { case global, region, friends }
    enum Metric { case weight, length }

    // MARK: - Join / profile

    func join(name: String, region: String) async {
        let clean = name.trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(clean.isEmpty ? "Angler \(friendCode)" : clean, forKey: "communityName")
        UserDefaults.standard.set(region, forKey: "communityRegion")
        UserDefaults.standard.set(true, forKey: "communityJoined")
        joined = true
        await upsertProfile(region: region)
    }

    func leave() {
        UserDefaults.standard.set(false, forKey: "communityJoined")
        joined = false
    }

    private func upsertProfile(region: String, bestWeightKg: Double = 0, speciesCount: Int = 0) async {
        let id = CKRecord.ID(recordName: "profile-\(friendCode)")
        let record = (try? await db.record(for: id)) ?? CKRecord(recordType: profileType, recordID: id)
        record["displayName"] = displayName as CKRecordValue
        record["friendCode"] = friendCode as CKRecordValue
        record["region"] = region as CKRecordValue
        if bestWeightKg > 0 { record["bestWeightKg"] = bestWeightKg as CKRecordValue }
        if speciesCount > 0 { record["speciesCount"] = speciesCount as CKRecordValue }
        record["updatedAt"] = Date() as CKRecordValue
        _ = try? await db.save(record)
    }

    // MARK: - Publishing catches

    /// Publish a notable catch to the leaderboard (opt-in). Location is coarsened
    /// to the region only — exact coordinates never leave the device.
    func publish(catchRecord: Catch, speciesName: String, region: String) async {
        guard joined else { return }
        let id = CKRecord.ID(recordName: "catch-\(friendCode)-\(catchRecord.id)")
        let record = CKRecord(recordType: catchType, recordID: id)
        record["anglerName"] = displayName as CKRecordValue
        record["friendCode"] = friendCode as CKRecordValue
        record["species"] = speciesName as CKRecordValue
        if let w = catchRecord.weightKg { record["weightKg"] = w as CKRecordValue }
        if let l = catchRecord.lengthCm { record["lengthCm"] = l as CKRecordValue }
        record["region"] = region as CKRecordValue
        record["caughtAt"] = catchRecord.caughtAt as CKRecordValue
        _ = try? await db.save(record)
    }

    // MARK: - Leaderboard

    func leaderboard(scope: Scope, metric: Metric, region: String, limit: Int = 50) async -> [LeaderRow] {
        let field = metric == .weight ? "weightKg" : "lengthCm"
        var predicate = NSPredicate(format: "%K > 0", field)
        switch scope {
        case .global: break
        case .region: predicate = NSPredicate(format: "region == %@ AND %K > 0", region, field)
        case .friends:
            let codes = friends + [friendCode]
            predicate = NSPredicate(format: "friendCode IN %@ AND %K > 0", codes, field)
        }
        let query = CKQuery(recordType: catchType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: field, ascending: false)]
        guard let results = try? await db.records(matching: query, resultsLimit: limit) else { return [] }
        return results.matchResults.compactMap { _, res -> LeaderRow? in
            guard let r = try? res.get() else { return nil }
            return LeaderRow(
                id: r.recordID.recordName,
                anglerName: r["anglerName"] as? String ?? "Angler",
                friendCode: r["friendCode"] as? String ?? "",
                species: r["species"] as? String ?? "Fish",
                weightKg: r["weightKg"] as? Double,
                lengthCm: r["lengthCm"] as? Double,
                region: r["region"] as? String ?? "",
                date: r["caughtAt"] as? Date ?? .now
            )
        }
    }

    // MARK: - Friends

    func addFriend(code raw: String) async -> Profile? {
        let code = raw.uppercased().trimmingCharacters(in: .whitespaces)
        guard code.count == 6, code != friendCode else { return nil }
        let id = CKRecord.ID(recordName: "profile-\(code)")
        guard let r = try? await db.record(for: id) else { return nil }
        if !friends.contains(code) { friends.append(code) }
        return Profile(
            id: code,
            name: r["displayName"] as? String ?? "Angler",
            region: r["region"] as? String ?? "",
            bestWeightKg: r["bestWeightKg"] as? Double ?? 0,
            speciesCount: r["speciesCount"] as? Int ?? 0
        )
    }

    func removeFriend(_ code: String) { friends.removeAll { $0 == code } }

    func fetchFriendProfiles() async -> [Profile] {
        guard !friends.isEmpty else { return [] }
        let ids = friends.map { CKRecord.ID(recordName: "profile-\($0)") }
        guard let results = try? await db.records(for: ids) else { return [] }
        return results.compactMap { _, res -> Profile? in
            guard let r = try? res.get() else { return nil }
            return Profile(
                id: r["friendCode"] as? String ?? "",
                name: r["displayName"] as? String ?? "Angler",
                region: r["region"] as? String ?? "",
                bestWeightKg: r["bestWeightKg"] as? Double ?? 0,
                speciesCount: r["speciesCount"] as? Int ?? 0
            )
        }
    }
}
