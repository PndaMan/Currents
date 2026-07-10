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

    // Lazy so merely constructing the service (e.g. reading `joined`) doesn't
    // reach CloudKit. In the unsigned simulator TEST build there's no iCloud
    // entitlement, and touching CloudKit at launch crashes the app before the
    // test harness connects.
    private lazy var container = CKContainer(identifier: "iCloud.com.aidanmcconnon.currents")
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

    /// Tappable deep link that opens the app on an "Add friend" confirmation.
    func friendLink() -> URL { URL(string: "currents://friend/\(friendCode)")! }

    func friendInviteMessage() -> String {
        """
        Add me on Currents 🎣
        Tap to add me: currents://friend/\(friendCode)
        …or enter my angler code \(friendCode) in Community › Friends.
        """
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
        var catchCount: Int?   // set for the "most fish" board
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
    enum Metric { case count, weight, length }

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
        if let avatar { saveAvatar(avatar) }
        await saveMyProfile(stats: stats)
    }

    // MARK: - Avatar persistence

    /// Avatar lives in Application Support under a fixed name. The previous
    /// version wrote it to the temp directory (which iOS purges) and stored an
    /// absolute path (which breaks when the app container id changes between
    /// launches) — that's why the picture kept vanishing on update. Resolving a
    /// stable path fresh each read fixes it.
    private var avatarURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("community-avatar.jpg")
    }

    func saveAvatar(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        try? data.write(to: avatarURL, options: .atomic)
    }

    var myAvatar: UIImage? { UIImage(contentsOfFile: avatarURL.path) }

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
        if FileManager.default.fileExists(atPath: avatarURL.path) {
            record["avatar"] = CKAsset(fileURL: avatarURL)
        }
        record["updatedAt"] = Date() as CKRecordValue
        _ = try? await db.save(record)
    }

    func fetchProfile(code: String) async -> Profile? {
        if code.uppercased() == Self.demoCode { return demoProfile }
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

    /// A leaderboard: the visible top rows PLUS your own standing (rank + row)
    /// so you can always see where you sit even if you're outside the top.
    /// We fetch catches with a system-field sort and rank on-device, so no
    /// custom CloudKit indexes need configuring for it to work.
    func board(scope: Scope, metric: Metric, region: String)
        async -> (rows: [LeaderRow], mine: (rank: Int, row: LeaderRow)?) {
        let ranked = await rankedRows(scope: scope, metric: metric, region: region)
        let cap = metric == .count ? 50 : 20
        let top = Array(ranked.prefix(cap))
        var mine: (rank: Int, row: LeaderRow)?
        if let idx = ranked.firstIndex(where: { $0.friendCode == friendCode }) {
            mine = (idx + 1, ranked[idx])
        }
        return (top, mine)
    }

    /// The full ranked list for a board (no truncation).
    private func rankedRows(scope: Scope, metric: Metric, region: String) async -> [LeaderRow] {
        var catches = await fetchAllLeaderCatches()

        switch scope {
        case .global: break
        case .region: catches = catches.filter { $0.region == region }
        case .friends:
            let codes = Set(friends + [friendCode])
            catches = catches.filter { codes.contains($0.friendCode) }
        }

        // Fold in the demo angler so there's always something to look at.
        catches += demoLeaderCatches(scope: scope, region: region)

        switch metric {
        case .count:
            // Most fish caught — one row per angler.
            var byCode: [String: LeaderRow] = [:]
            for c in catches {
                if var row = byCode[c.friendCode] {
                    row.catchCount = (row.catchCount ?? 0) + 1
                    byCode[c.friendCode] = row
                } else {
                    byCode[c.friendCode] = LeaderRow(
                        id: "count-\(c.friendCode)", anglerName: c.anglerName,
                        friendCode: c.friendCode, species: "", weightKg: nil, lengthCm: nil,
                        catchCount: 1, region: c.region, date: c.date
                    )
                }
            }
            return byCode.values.sorted { ($0.catchCount ?? 0) > ($1.catchCount ?? 0) }
        case .weight:
            return catches.filter { ($0.weightKg ?? 0) > 0 }
                .sorted { ($0.weightKg ?? 0) > ($1.weightKg ?? 0) }
        case .length:
            return catches.filter { ($0.lengthCm ?? 0) > 0 }
                .sorted { ($0.lengthCm ?? 0) > ($1.lengthCm ?? 0) }
        }
    }

    /// All published catches (client-side ranking avoids custom-index needs).
    private func fetchAllLeaderCatches(limit: Int = 400) async -> [LeaderRow] {
        let query = CKQuery(recordType: catchType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
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
                catchCount: nil,
                region: r["region"] as? String ?? "",
                date: r["caughtAt"] as? Date ?? .now
            )
        }
    }

    /// Publish every past catch so the leaderboards reflect the full history,
    /// not just catches logged after joining. Idempotent (deterministic record
    /// ids, force-overwrite) and throttled so it isn't re-run constantly.
    func syncAllCatches(_ details: [(id: String, species: String, weightKg: Double?, lengthCm: Double?, caughtAt: Date)]) async {
        guard joined else { return }
        let last = UserDefaults.standard.object(forKey: "lastCatchSync") as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 1800 else { return }
        UserDefaults.standard.set(Date(), forKey: "lastCatchSync")

        let region = myRegion
        let records: [CKRecord] = details.map { d in
            let id = CKRecord.ID(recordName: "catch-\(friendCode)-\(d.id)")
            let record = CKRecord(recordType: catchType, recordID: id)
            record["anglerName"] = myName as CKRecordValue
            record["friendCode"] = friendCode as CKRecordValue
            record["species"] = d.species as CKRecordValue
            if let w = d.weightKg { record["weightKg"] = w as CKRecordValue }
            if let l = d.lengthCm { record["lengthCm"] = l as CKRecordValue }
            record["region"] = region as CKRecordValue
            record["caughtAt"] = d.caughtAt as CKRecordValue
            return record
        }
        // Batch (CloudKit caps ~400/op); force-overwrite so re-runs are safe.
        for chunk in stride(from: 0, to: records.count, by: 300).map({ Array(records[$0..<min($0 + 300, records.count)]) }) {
            _ = try? await db.modifyRecords(saving: chunk, deleting: [], savePolicy: .allKeys, atomically: false)
        }
    }

    // MARK: - Friends

    func addFriend(code raw: String) async -> Profile? {
        let code = raw.uppercased().trimmingCharacters(in: .whitespaces)
        guard code.count == 6, code != friendCode else { return nil }
        // Demo angler: auto-accepts with rich sample data so you can see and
        // style the friends + leaderboard experience without a second device.
        if code == Self.demoCode {
            if !friends.contains(code) { friends.append(code) }
            UserDefaults.standard.set(true, forKey: "communityDemoAdded")
            return demoProfile
        }
        guard let profile = await fetchProfile(code: code) else { return nil }
        if !friends.contains(code) { friends.append(code) }
        return profile
    }

    func removeFriend(_ code: String) {
        friends.removeAll { $0 == code }
        if code.uppercased() == Self.demoCode {
            UserDefaults.standard.set(false, forKey: "communityDemoAdded")
        }
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
        Task { await updateCatchGrant(for: code, share: p.shareCatches) }
        // (The profile screen re-runs republishSharedSpots with the live spots.)
    }

    // MARK: - Catch-sharing permission (shareCatches)

    private let catchGrantType = "CatchGrant"

    /// A grant record lets a specific friend see my individual catch history
    /// (leaderboard bests stay public; the full list is friends-only, gated).
    private func updateCatchGrant(for code: String, share: Bool) async {
        let id = CKRecord.ID(recordName: "catchgrant-\(friendCode)-\(code)")
        if share {
            let rec = (try? await db.record(for: id)) ?? CKRecord(recordType: catchGrantType, recordID: id)
            rec["ownerCode"] = friendCode as CKRecordValue
            rec["viewerCode"] = code as CKRecordValue
            _ = try? await db.save(rec)
        } else {
            _ = try? await db.deleteRecord(withID: id)
        }
    }

    /// Whether a given angler has shared their catches with me.
    func hasCatchAccess(to code: String) async -> Bool {
        if code == Self.demoCode { return true }
        let id = CKRecord.ID(recordName: "catchgrant-\(code)-\(friendCode)")
        return (try? await db.record(for: id)) != nil
    }

    var isFriend: (String) -> Bool { { [friends] code in friends.contains(code.uppercased()) } }

    /// A specific angler's individual catches (from the published catch data).
    func anglerCatches(code: String, limit: Int = 60) async -> [LeaderRow] {
        if code == Self.demoCode { return demoCatchRows }
        let all = await fetchAllLeaderCatches(limit: 400)
        return Array(all.filter { $0.friendCode == code }.prefix(limit))
    }

    // MARK: - Shared spots (per-friend, spot-protective)

    /// Republish shared spots as ONE record per (spot, recipient), so a record
    /// only ever contains what that specific friend is allowed to see: no record
    /// for friends without shareSpots, and no coordinates for friends without
    /// shareExactLocations (previously exact coords leaked into a shared record
    /// that non-exact friends could read).
    func republishSharedSpots(spots: [Spot] = []) async {
        guard joined, !spots.isEmpty else { return }
        for spot in spots {
            for code in friends {
                let p = privacy(for: code)
                let id = CKRecord.ID(recordName: "spot-\(friendCode)-\(spot.id)-\(code)")
                if !p.shareSpots {
                    _ = try? await db.deleteRecord(withID: id)
                    continue
                }
                let record = (try? await db.record(for: id)) ?? CKRecord(recordType: sharedSpotType, recordID: id)
                record["ownerCode"] = friendCode as CKRecordValue
                record["toCode"] = code as CKRecordValue
                record["name"] = spot.name as CKRecordValue
                record["type"] = (spot.spotType ?? "General") as CKRecordValue
                record["notes"] = (spot.notes ?? "") as CKRecordValue
                if p.shareExactLocations {
                    record["lat"] = spot.latitude as CKRecordValue
                    record["lon"] = spot.longitude as CKRecordValue
                } else {
                    record["lat"] = nil
                    record["lon"] = nil
                }
                _ = try? await db.save(record)
            }
        }
    }

    /// Spots a friend has shared with me. Coordinates are present only when they
    /// granted exact locations (the record simply won't contain them otherwise).
    func sharedSpots(fromFriend code: String) async -> [SharedSpot] {
        if code == Self.demoCode { return demoSharedSpots }
        let query = CKQuery(recordType: sharedSpotType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        guard let results = try? await db.records(matching: query, resultsLimit: 200) else { return [] }
        return results.matchResults.compactMap { _, res -> SharedSpot? in
            guard let r = try? res.get(),
                  (r["ownerCode"] as? String) == code,
                  (r["toCode"] as? String) == friendCode else { return nil }
            var coord: CLLocationCoordinate2D?
            if let lat = r["lat"] as? Double, let lon = r["lon"] as? Double {
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

    // MARK: - Demo angler (styling / preview without a second device)

    static let demoCode = "MARLIN"
    var demoAdded: Bool { UserDefaults.standard.bool(forKey: "communityDemoAdded") }

    var demoProfile: Profile {
        Profile(
            id: Self.demoCode,
            name: "Sasha Rivers",
            bio: "Kayak & shore angler chasing PBs across the Cape. Mostly catch-and-release. Topwater at first light is my religion 🌅",
            region: myRegion,
            homeWater: "Theewaterskloof Dam",
            avatar: Self.demoAvatar,
            memberSince: Date().addingTimeInterval(-238 * 24 * 3600),
            totalCatches: Self.demoCatchSeeds.count,
            speciesCount: Set(Self.demoCatchSeeds.map(\.species)).count,
            bestWeightKg: Self.demoCatchSeeds.compactMap(\.weightKg).max() ?? 0,
            bestLengthCm: Self.demoCatchSeeds.compactMap(\.lengthCm).max() ?? 0,
            favoriteSpecies: "Largemouth Bass"
        )
    }

    private func demoLeaderCatches(scope: Scope, region: String) -> [LeaderRow] {
        guard demoAdded else { return [] }
        if scope == .region && region != myRegion { return [] }
        return demoCatchRows
    }

    /// The demo angler's individual catches (used for their profile + boards).
    var demoCatchRows: [LeaderRow] {
        Self.demoCatchSeeds.enumerated().map { i, s in
            LeaderRow(
                id: "demo-\(i)", anglerName: "Sasha Rivers", friendCode: Self.demoCode,
                species: s.species, weightKg: s.weightKg, lengthCm: s.lengthCm,
                catchCount: nil, region: myRegion,
                date: Date().addingTimeInterval(-Double(i) * 3.2 * 24 * 3600)
            )
        }
    }

    /// Spots the demo angler "shares" with you — one approximate to show the
    /// exact-location rule in action.
    var demoSharedSpots: [SharedSpot] {
        guard demoAdded else { return [] }
        return [
            SharedSpot(id: "demo-spot-1", ownerCode: Self.demoCode, name: "Sasha's Dawn Point",
                       type: "Bank", notes: "Topwater at first light — big bass patrol the reed line.",
                       coordinate: CLLocationCoordinate2D(latitude: -34.0498, longitude: 19.2830)),
            SharedSpot(id: "demo-spot-2", ownerCode: Self.demoCode, name: "The Deep Channel",
                       type: "Boat", notes: "Drop-off to ~8 m. Slow-roll spinnerbaits when it's overcast.",
                       coordinate: CLLocationCoordinate2D(latitude: -34.0655, longitude: 19.3011)),
            SharedSpot(id: "demo-spot-3", ownerCode: Self.demoCode, name: "Carp Bay",
                       type: "Bank", notes: "Shared as an approximate area — exact spot kept private.",
                       coordinate: nil),
        ]
    }

    private struct DemoCatch { let species: String; let weightKg: Double?; let lengthCm: Double? }
    private static let demoCatchSeeds: [DemoCatch] = [
        .init(species: "Largemouth Bass", weightKg: 6.4, lengthCm: 62),
        .init(species: "Largemouth Bass", weightKg: 4.1, lengthCm: 54),
        .init(species: "Common Carp", weightKg: 8.9, lengthCm: 78),
        .init(species: "Common Carp", weightKg: 5.2, lengthCm: 66),
        .init(species: "Sharptooth Catfish", weightKg: 12.3, lengthCm: 96),
        .init(species: "Rainbow Trout", weightKg: 2.1, lengthCm: 51),
        .init(species: "Rainbow Trout", weightKg: 1.6, lengthCm: 46),
        .init(species: "Smallmouth Bass", weightKg: 2.8, lengthCm: 48),
        .init(species: "Bluegill", weightKg: 0.4, lengthCm: 22),
        .init(species: "Largemouth Bass", weightKg: 3.3, lengthCm: 50),
        .init(species: "Yellowfish", weightKg: 3.9, lengthCm: 58),
        .init(species: "Yellowfish", weightKg: 2.4, lengthCm: 49),
        .init(species: "Common Carp", weightKg: 6.7, lengthCm: 72),
        .init(species: "Tilapia", weightKg: 1.1, lengthCm: 31),
        .init(species: "Largemouth Bass", weightKg: 5.5, lengthCm: 59),
        .init(species: "Sharptooth Catfish", weightKg: 9.4, lengthCm: 88),
    ]

    private static let demoAvatar: UIImage? = {
        let size = CGSize(width: 240, height: 240)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let cg = ctx.cgContext
            let colors = [UIColor(red: 0.13, green: 0.55, blue: 0.95, alpha: 1).cgColor,
                          UIColor(red: 0.04, green: 0.30, blue: 0.55, alpha: 1).cgColor]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors as CFArray, locations: [0, 1]) {
                cg.drawLinearGradient(gradient, start: .zero,
                                      end: CGPoint(x: size.width, y: size.height), options: [])
            }
            let initials = "SR" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 110, weight: .bold),
                .foregroundColor: UIColor.white,
            ]
            let sz = initials.size(withAttributes: attrs)
            initials.draw(at: CGPoint(x: (size.width - sz.width) / 2, y: (size.height - sz.height) / 2),
                          withAttributes: attrs)
        }
    }()

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

    // MARK: - Trip invites (pick a friend → they accept in-app)

    private let inviteType = "GroupInvite"

    struct TripInvite: Identifiable {
        let id: String          // record name
        let groupCode: String
        let tripName: String
        let fromName: String
        let fromCode: String
        let date: Date
    }

    /// Invite one of my friends to a group trip. Creates an invite record the
    /// friend's app picks up (and a local notification when they next open it).
    func inviteFriend(_ toCode: String, toGroup groupCode: String, tripName: String) async {
        let id = CKRecord.ID(recordName: "invite-\(groupCode)-\(toCode)")
        let record = (try? await db.record(for: id)) ?? CKRecord(recordType: inviteType, recordID: id)
        record["groupCode"] = groupCode as CKRecordValue
        record["tripName"] = tripName as CKRecordValue
        record["fromCode"] = friendCode as CKRecordValue
        record["fromName"] = myName as CKRecordValue
        record["toCode"] = toCode as CKRecordValue
        record["createdAt"] = Date() as CKRecordValue
        _ = try? await db.save(record)
    }

    /// Trip invites addressed to me. (Client-side filter so no custom CloudKit
    /// index is required — same approach as the leaderboards.)
    func pendingInvites() async -> [TripInvite] {
        let query = CKQuery(recordType: inviteType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        guard let results = try? await db.records(matching: query, resultsLimit: 200) else { return [] }
        return results.matchResults.compactMap { _, res -> TripInvite? in
            guard let r = try? res.get(), (r["toCode"] as? String) == friendCode else { return nil }
            return TripInvite(
                id: r.recordID.recordName,
                groupCode: r["groupCode"] as? String ?? "",
                tripName: r["tripName"] as? String ?? "Group Trip",
                fromName: r["fromName"] as? String ?? "A friend",
                fromCode: r["fromCode"] as? String ?? "",
                date: r["createdAt"] as? Date ?? .now
            )
        }
    }

    func acceptInvite(_ invite: TripInvite) async {
        _ = await joinGroupTrip(code: invite.groupCode)
        _ = try? await db.deleteRecord(withID: CKRecord.ID(recordName: invite.id))
    }

    func declineInvite(_ invite: TripInvite) async {
        _ = try? await db.deleteRecord(withID: CKRecord.ID(recordName: invite.id))
    }

    /// Poll for invites and fire a one-time local notification for any new ones.
    /// Returns the current pending set for the in-app list.
    @discardableResult
    func refreshTripInvites() async -> [TripInvite] {
        guard joined else { return [] }
        let invites = await pendingInvites()
        var seen = Set(UserDefaults.standard.stringArray(forKey: "seenTripInvites") ?? [])
        for inv in invites where !seen.contains(inv.id) {
            await NotificationManager.shared.scheduleTripInviteAlert(fromName: inv.fromName, tripName: inv.tripName)
            seen.insert(inv.id)
        }
        // Keep only ids that still have live invites, so re-invites re-notify.
        UserDefaults.standard.set(Array(seen.intersection(invites.map(\.id))), forKey: "seenTripInvites")
        return invites
    }
}
