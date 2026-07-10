import Foundation
import CloudKit
import CoreLocation
import UIKit

/// Serverless multiplayer via CloudKit's PUBLIC database — no backend to run.
///
/// Privacy model (spot-protective by default):
/// - Nothing is published until the angler joins the community.
/// - Leaderboard entries carry species + size + broad region only — never
///   coordinates.
/// - Spots are NEVER shared globally. A spot is visible to a friend only if the
///   owner explicitly shares it with that specific friend (per-friend opt-in),
///   and exact coordinates are shared only if the owner also enables it.
///
/// Runtime-only (CloudKit needs a device + iCloud account); the app degrades
/// gracefully when unavailable or not joined.
@MainActor
final class CommunityService: ObservableObject {
    static let shared = CommunityService()

    private let container = CKContainer(identifier: "iCloud.com.aidanmcconnon.currents")
    private var db: CKDatabase { container.publicCloudDatabase }

    private let profileType = "AnglerProfile"
    private let catchType = "LeaderCatch"
    private let sharedSpotType = "SharedSpot"

    @Published var joined = UserDefaults.standard.bool(forKey: "communityJoined")

    // MARK: - Identity

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

    // MARK: - Models

    struct Profile: Identifiable, Equatable {
        var id: String        // friend code
        var name: String
        var bio: String
        var region: String
        var homeWater: String
        var avatar: UIImage?
        var memberSince: Date
        var totalCatches: Int
        var speciesCount: Int
        var bestWeightKg: Double
        var bestLengthCm: Double
        var favoriteSpecies: String
    }

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

    struct SharedSpot: Identifiable {
        let id: String
        let ownerCode: String
        let name: String
        let type: String
        let notes: String
        /// Nil when the owner shared the spot without exact coordinates.
        let coordinate: CLLocationCoordinate2D?
    }

    /// What YOU share with a specific friend. Spot-protective defaults.
    struct FriendPrivacy: Codable, Equatable {
        var shareCatches = true
        var shareSpots = false
        var shareExactLocations = false
        var nickname = ""
    }

    enum Scope { case global, region, friends }
    enum Metric { case weight, length }

    // MARK: - Join / leave

    func join(name: String, region: String) async {
        let clean = name.trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(clean.isEmpty ? "Angler \(friendCode)" : clean, forKey: "communityName")
        UserDefaults.standard.set(region, forKey: "communityRegion")
        if UserDefaults.standard.object(forKey: "communityMemberSince") == nil {
            UserDefaults.standard.set(Date(), forKey: "communityMemberSince")
        }
        UserDefaults.standard.set(true, forKey: "communityJoined")
        joined = true
        await saveMyProfile(stats: nil)
    }

    func leave() {
        UserDefaults.standard.set(false, forKey: "communityJoined")
        joined = false
    }

    // MARK: - My profile

    struct MyStats { var totalCatches: Int; var speciesCount: Int; var bestWeightKg: Double; var bestLengthCm: Double; var favoriteSpecies: String }

    var myName: String { UserDefaults.standard.string(forKey: "communityName") ?? "Angler \(friendCode)" }
    var myBio: String { UserDefaults.standard.string(forKey: "communityBio") ?? "" }
    var myHomeWater: String { UserDefaults.standard.string(forKey: "communityHomeWater") ?? "" }
    var myRegion: String { UserDefaults.standard.string(forKey: "communityRegion") ?? (Locale.current.region?.identifier ?? "Global") }
    var memberSince: Date { UserDefaults.standard.object(forKey: "communityMemberSince") as? Date ?? .now }

    func updateProfile(name: String, bio: String, homeWater: String, region: String, avatar: UIImage?, stats: MyStats?) async {
        UserDefaults.standard.set(name, forKey: "communityName")
        UserDefaults.standard.set(bio, forKey: "communityBio")
        UserDefaults.standard.set(homeWater, forKey: "communityHomeWater")
        UserDefaults.standard.set(region, forKey: "communityRegion")
        if let avatar, let data = avatar.jpegData(compressionQuality: 0.8) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("avatar-\(friendCode).jpg")
            try? data.write(to: url)
            UserDefaults.standard.set(url.path, forKey: "communityAvatarPath")
        }
        await saveMyProfile(stats: stats)
    }

    private func saveMyProfile(stats: MyStats?) async {
        let id = CKRecord.ID(recordName: "profile-\(friendCode)")
        let record = (try? await db.record(for: id)) ?? CKRecord(recordType: profileType, recordID: id)
        record["displayName"] = myName as CKRecordValue
        record["friendCode"] = friendCode as CKRecordValue
        record["bio"] = myBio as CKRecordValue
        record["homeWater"] = myHomeWater as CKRecordValue
        record["region"] = myRegion as CKRecordValue
        record["memberSince"] = memberSince as CKRecordValue
        if let stats {
            record["totalCatches"] = stats.totalCatches as CKRecordValue
            record["speciesCount"] = stats.speciesCount as CKRecordValue
            record["bestWeightKg"] = stats.bestWeightKg as CKRecordValue
            record["bestLengthCm"] = stats.bestLengthCm as CKRecordValue
            record["favoriteSpecies"] = stats.favoriteSpecies as CKRecordValue
        }
        if let path = UserDefaults.standard.string(forKey: "communityAvatarPath") {
            record["avatar"] = CKAsset(fileURL: URL(fileURLWithPath: path))
        }
        record["updatedAt"] = Date() as CKRecordValue
        _ = try? await db.save(record)
    }

    func fetchProfile(code: String) async -> Profile? {
        let id = CKRecord.ID(recordName: "profile-\(code)")
        guard let r = try? await db.record(for: id) else { return nil }
        return profile(from: r)
    }

    private func profile(from r: CKRecord) -> Profile {
        var avatar: UIImage?
        if let asset = r["avatar"] as? CKAsset, let url = asset.fileURL, let data = try? Data(contentsOf: url) {
            avatar = UIImage(data: data)
        }
        return Profile(
            id: r["friendCode"] as? String ?? r.recordID.recordName,
            name: r["displayName"] as? String ?? "Angler",
            bio: r["bio"] as? String ?? "",
            region: r["region"] as? String ?? "",
            homeWater: r["homeWater"] as? String ?? "",
            avatar: avatar,
            memberSince: r["memberSince"] as? Date ?? .now,
            totalCatches: r["totalCatches"] as? Int ?? 0,
            speciesCount: r["speciesCount"] as? Int ?? 0,
            bestWeightKg: r["bestWeightKg"] as? Double ?? 0,
            bestLengthCm: r["bestLengthCm"] as? Double ?? 0,
            favoriteSpecies: r["favoriteSpecies"] as? String ?? ""
        )
    }

    // MARK: - Leaderboard

    func publish(catchRecord: Catch, speciesName: String, region: String, groupCode: String? = nil) async {
        guard joined || groupCode != nil else { return }
        let id = CKRecord.ID(recordName: "catch-\(friendCode)-\(catchRecord.id)")
        let record = CKRecord(recordType: catchType, recordID: id)
        record["anglerName"] = myName as CKRecordValue
        record["friendCode"] = friendCode as CKRecordValue
        record["species"] = speciesName as CKRecordValue
        if let w = catchRecord.weightKg { record["weightKg"] = w as CKRecordValue }
        if let l = catchRecord.lengthCm { record["lengthCm"] = l as CKRecordValue }
        record["region"] = region as CKRecordValue
        record["caughtAt"] = catchRecord.caughtAt as CKRecordValue
        // Tag the catch to a shared trip so the whole group sees it in real time.
        if let groupCode { record["groupCode"] = groupCode as CKRecordValue }
        _ = try? await db.save(record)
    }

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
        guard let profile = await fetchProfile(code: code) else { return nil }
        if !friends.contains(code) { friends.append(code) }
        return profile
    }

    func removeFriend(_ code: String) {
        friends.removeAll { $0 == code }
        UserDefaults.standard.removeObject(forKey: "friendPrivacy-\(code)")
    }

    // MARK: - Per-friend privacy

    func privacy(for code: String) -> FriendPrivacy {
        guard let data = UserDefaults.standard.data(forKey: "friendPrivacy-\(code)"),
              let p = try? JSONDecoder().decode(FriendPrivacy.self, from: data) else { return FriendPrivacy() }
        return p
    }

    func setPrivacy(_ p: FriendPrivacy, for code: String) {
        if let data = try? JSONEncoder().encode(p) {
            UserDefaults.standard.set(data, forKey: "friendPrivacy-\(code)")
        }
        Task { await republishSharedSpots() }
    }

    // MARK: - Shared spots (per-friend, spot-protective)

    /// Republish the caller's shared spots so each carries the current set of
    /// friends allowed to see it (only friends with shareSpots enabled), and
    /// strips coordinates for friends without shareExactLocations.
    func republishSharedSpots(spots: [Spot] = []) async {
        // Callers pass their spots; without them this is a no-op placeholder
        // that the profile screen invokes with the live spot list.
        guard joined, !spots.isEmpty else { return }
        let allowed = friends.filter { privacy(for: $0).shareSpots }
        let exactAllowed = Set(friends.filter { privacy(for: $0).shareExactLocations })
        for spot in spots {
            let id = CKRecord.ID(recordName: "spot-\(friendCode)-\(spot.id)")
            if allowed.isEmpty {
                _ = try? await db.deleteRecord(withID: id)
                continue
            }
            let record = (try? await db.record(for: id)) ?? CKRecord(recordType: sharedSpotType, recordID: id)
            record["ownerCode"] = friendCode as CKRecordValue
            record["name"] = spot.name as CKRecordValue
            record["type"] = (spot.spotType ?? "General") as CKRecordValue
            record["notes"] = (spot.notes ?? "") as CKRecordValue
            record["allowedCodes"] = allowed as CKRecordValue
            // Share exact coords only with friends allowed exact locations.
            if !exactAllowed.isDisjoint(with: Set(allowed)) {
                record["lat"] = spot.latitude as CKRecordValue
                record["lon"] = spot.longitude as CKRecordValue
                record["exactAllowedCodes"] = Array(exactAllowed) as CKRecordValue
            } else {
                record["lat"] = nil
                record["lon"] = nil
            }
            _ = try? await db.save(record)
        }
    }

    /// Spots a friend has shared with me (respecting their exact-location rule).
    func sharedSpots(fromFriend code: String) async -> [SharedSpot] {
        let predicate = NSPredicate(format: "ownerCode == %@ AND allowedCodes CONTAINS %@", code, friendCode)
        let query = CKQuery(recordType: sharedSpotType, predicate: predicate)
        guard let results = try? await db.records(matching: query, resultsLimit: 100) else { return [] }
        return results.matchResults.compactMap { _, res -> SharedSpot? in
            guard let r = try? res.get() else { return nil }
            var coord: CLLocationCoordinate2D?
            if let lat = r["lat"] as? Double, let lon = r["lon"] as? Double,
               let exact = r["exactAllowedCodes"] as? [String], exact.contains(friendCode) {
                coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
            return SharedSpot(
                id: r.recordID.recordName,
                ownerCode: code,
                name: r["name"] as? String ?? "Spot",
                type: r["type"] as? String ?? "General",
                notes: r["notes"] as? String ?? "",
                coordinate: coord
            )
        }
    }

    // MARK: - Group trips (serverless, invite by link)

    private let groupTripType = "GroupTrip"
    private let groupMemberType = "GroupMember"

    struct GroupTrip: Identifiable, Equatable {
        let id: String          // 6-char join code
        let name: String
        let hostCode: String
        let hostName: String
        let createdAt: Date
        var isHost: Bool = false
    }

    struct GroupMember: Identifiable {
        let id: String          // member friend code
        let name: String
        let joinedAt: Date
    }

    struct GroupCatch: Identifiable {
        let id: String
        let anglerName: String
        let friendCode: String
        let species: String
        let weightKg: Double?
        let lengthCm: Double?
        let date: Date
    }

    // Local trip.id → group code mapping so a trip stays linked to its group
    // across launches (no DB migration needed).
    func groupCode(forTripId id: String) -> String? {
        (UserDefaults.standard.dictionary(forKey: "tripGroupCodes") as? [String: String])?[id]
    }

    private func setGroupCode(_ code: String?, forTripId id: String) {
        var m = (UserDefaults.standard.dictionary(forKey: "tripGroupCodes") as? [String: String]) ?? [:]
        m[id] = code
        UserDefaults.standard.set(m, forKey: "tripGroupCodes")
    }

    /// Tappable deep link that opens the app straight into the join flow.
    func inviteLink(forGroup code: String) -> URL {
        URL(string: "currents://trip/\(code)")!
    }

    func inviteMessage(forGroup code: String, tripName: String) -> String {
        """
        Join my fishing trip “\(tripName)” on Currents 🎣
        Tap to join: currents://trip/\(code)
        …or open Currents › Community › Join a Trip and enter code \(code).
        """
    }

    /// Ensure the angler has a community identity so group records carry a name.
    private func ensureJoined() async {
        guard !joined else { return }
        await join(name: myName, region: myRegion)
    }

    /// Host creates a shared trip and returns its join code.
    @discardableResult
    func createGroupTrip(name: String, tripId: String) async -> String? {
        await ensureJoined()
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let code = String((0..<6).map { _ in chars[Int.random(in: 0..<chars.count)] })
        let id = CKRecord.ID(recordName: "grouptrip-\(code)")
        let record = CKRecord(recordType: groupTripType, recordID: id)
        record["code"] = code as CKRecordValue
        record["name"] = name as CKRecordValue
        record["hostCode"] = friendCode as CKRecordValue
        record["hostName"] = myName as CKRecordValue
        record["createdAt"] = Date() as CKRecordValue
        guard (try? await db.save(record)) != nil else { return nil }
        await addMembership(code: code)
        setGroupCode(code, forTripId: tripId)
        return code
    }

    /// Join a shared trip by code (from a link or manual entry). Returns the
    /// trip if it exists. Optionally links it to a local trip id.
    @discardableResult
    func joinGroupTrip(code raw: String, tripId: String? = nil) async -> GroupTrip? {
        await ensureJoined()
        let code = raw.uppercased().trimmingCharacters(in: .whitespaces)
        guard code.count == 6, let trip = await groupTrip(code: code) else { return nil }
        await addMembership(code: code)
        if let tripId { setGroupCode(code, forTripId: tripId) }
        return trip
    }

    private func addMembership(code: String) async {
        let id = CKRecord.ID(recordName: "member-\(code)-\(friendCode)")
        let record = (try? await db.record(for: id)) ?? CKRecord(recordType: groupMemberType, recordID: id)
        record["groupCode"] = code as CKRecordValue
        record["memberCode"] = friendCode as CKRecordValue
        record["memberName"] = myName as CKRecordValue
        record["joinedAt"] = Date() as CKRecordValue
        _ = try? await db.save(record)
    }

    func groupTrip(code: String) async -> GroupTrip? {
        let id = CKRecord.ID(recordName: "grouptrip-\(code)")
        guard let r = try? await db.record(for: id) else { return nil }
        let hostCode = r["hostCode"] as? String ?? ""
        return GroupTrip(
            id: r["code"] as? String ?? code,
            name: r["name"] as? String ?? "Group Trip",
            hostCode: hostCode,
            hostName: r["hostName"] as? String ?? "Host",
            createdAt: r["createdAt"] as? Date ?? .now,
            isHost: hostCode == friendCode
        )
    }

    func groupMembers(code: String) async -> [GroupMember] {
        let predicate = NSPredicate(format: "groupCode == %@", code)
        let query = CKQuery(recordType: groupMemberType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "joinedAt", ascending: true)]
        guard let results = try? await db.records(matching: query, resultsLimit: 100) else { return [] }
        return results.matchResults.compactMap { _, res -> GroupMember? in
            guard let r = try? res.get() else { return nil }
            return GroupMember(
                id: r["memberCode"] as? String ?? "",
                name: r["memberName"] as? String ?? "Angler",
                joinedAt: r["joinedAt"] as? Date ?? .now
            )
        }
    }

    /// Every catch shared into the group, newest first.
    func groupCatches(code: String) async -> [GroupCatch] {
        let predicate = NSPredicate(format: "groupCode == %@", code)
        let query = CKQuery(recordType: catchType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "caughtAt", ascending: false)]
        guard let results = try? await db.records(matching: query, resultsLimit: 200) else { return [] }
        return results.matchResults.compactMap { _, res -> GroupCatch? in
            guard let r = try? res.get() else { return nil }
            return GroupCatch(
                id: r.recordID.recordName,
                anglerName: r["anglerName"] as? String ?? "Angler",
                friendCode: r["friendCode"] as? String ?? "",
                species: r["species"] as? String ?? "Fish",
                weightKg: r["weightKg"] as? Double,
                lengthCm: r["lengthCm"] as? Double,
                date: r["caughtAt"] as? Date ?? .now
            )
        }
    }

    func leaveGroupTrip(code: String, tripId: String?) async {
        let id = CKRecord.ID(recordName: "member-\(code)-\(friendCode)")
        _ = try? await db.deleteRecord(withID: id)
        if let tripId { setGroupCode(nil, forTripId: tripId) }
    }
}
