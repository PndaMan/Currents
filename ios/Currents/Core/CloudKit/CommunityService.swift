import Foundation
import CloudKit
import CoreLocation
import UIKit
import UserNotifications

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

    /// Bumped whenever the local profile (name/bio/avatar) or friend list
    /// changes, so SwiftUI views observing this service refresh immediately —
    /// the underlying values live in UserDefaults/files and aren't observable
    /// on their own.
    @Published private(set) var revision = 0
    func bumpRevision() { revision &+= 1 }

    // MARK: - Identity

    var friendCode: String {
        if let c = UserDefaults.standard.string(forKey: "communityFriendCode") { return c }
        let code = Self.randomCode()
        UserDefaults.standard.set(code, forKey: "communityFriendCode")
        return code
    }

    // 6 chars from a 31-symbol alphabet (ambiguous 0/O/1/I excluded) ≈ 887M
    // combinations. Random alone would collide by the birthday bound at tens of
    // thousands of users, so we reserve the code (below) rather than trust luck.
    private static func randomCode() -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in chars[Int.random(in: 0..<chars.count)] })
    }

    /// Guarantee this device's friend code is unique. CloudKit's public DB
    /// enforces record-name uniqueness, so the first angler to save
    /// "codeclaim-<code>" owns it; a collision fails the save and we pick a new
    /// code and retry. Runs once (until claimed); the code is stable afterwards,
    /// so already-shared codes never change out from under a friend.
    func claimFriendCode(maxAttempts: Int = 6) async {
        guard !UserDefaults.standard.bool(forKey: "friendCodeClaimed") else { return }
        for _ in 0..<maxAttempts {
            let code = friendCode
            let id = CKRecord.ID(recordName: "codeclaim-\(code)")
            let record = CKRecord(recordType: "CodeClaim", recordID: id)
            record["claimedAt"] = Date() as CKRecordValue
            do {
                _ = try await db.save(record)
                UserDefaults.standard.set(true, forKey: "friendCodeClaimed")
                return
            } catch let ckError as CKError where ckError.code == .serverRecordChanged {
                // Code is taken — regenerate and try again (only safe because we
                // haven't claimed/shared it yet).
                UserDefaults.standard.set(Self.randomCode(), forKey: "communityFriendCode")
            } catch {
                // Network/other: leave unclaimed and retry on a later join/open.
                return
            }
        }
    }

    var friends: [String] {
        get { UserDefaults.standard.stringArray(forKey: "communityFriends") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "communityFriends"); bumpRevision() }
    }

    /// Whether to attach an (obfuscated) location to catches I publish, so
    /// friends see a map on my catches. Off by default — coordinates never leave
    /// the device unless the angler explicitly turns this on.
    var shareCatchLocations: Bool {
        get { UserDefaults.standard.bool(forKey: "shareCatchLocations") }
        set { UserDefaults.standard.set(newValue, forKey: "shareCatchLocations") }
    }

    /// Global social-sharing preferences (previously per-friend, now managed
    /// centrally in Settings › Privacy). `bool(forKey:)` defaults to false, so
    /// preferences that should default ON are read through `boolDefaultTrue`.
    private func boolDefaultTrue(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil ? true : UserDefaults.standard.bool(forKey: key)
    }

    /// Let friends see my individual catch history (leaderboard bests are always
    /// visible; the full per-catch list is friends-only and gated by this). On by default.
    var shareCatchesWithFriends: Bool {
        get { boolDefaultTrue("shareCatchesWithFriends") }
        set { UserDefaults.standard.set(newValue, forKey: "shareCatchesWithFriends") }
    }

    /// Share my saved spots with my friends. Off by default (spot-protective).
    var shareSpotsWithFriends: Bool {
        get { UserDefaults.standard.bool(forKey: "shareSpotsWithFriends") }
        set { UserDefaults.standard.set(newValue, forKey: "shareSpotsWithFriends") }
    }

    /// Include exact GPS in shared spots (otherwise they're shared as an
    /// approximate area). Off by default.
    var shareSpotExactLocations: Bool {
        get { UserDefaults.standard.bool(forKey: "shareSpotExactLocations") }
        set { UserDefaults.standard.set(newValue, forKey: "shareSpotExactLocations") }
    }

    /// Re-apply the global catch-sharing preference to every friend as grant
    /// records (so they can/can't see my catch history). Call after the toggle
    /// flips or a new friend is added.
    func syncCatchGrants() async {
        guard joined else { return }
        for code in friends where code.uppercased() != Self.demoCode {
            await updateCatchGrant(for: code, share: shareCatchesWithFriends)
        }
    }

    /// The honey-hole radius (km) the angler set in Privacy settings; used to
    /// offset shared catch coordinates. 0 = off (share exact).
    private var privacyRadiusKm: Double {
        max(0, UserDefaults.standard.double(forKey: "privacyRadiusKm"))
    }

    /// Deterministically offset a coordinate by up to the honey-hole radius, so
    /// a shared catch shows the right general area without giving up the exact
    /// spot. Deterministic per catch id so it doesn't jump around between syncs.
    private func obfuscated(_ lat: Double, _ lon: Double, seed: String, radiusKm: Double? = nil) -> (Double, Double) {
        let radius = radiusKm ?? privacyRadiusKm
        guard radius > 0 else { return (lat, lon) }
        // Stable FNV-1a hash so the same catch always offsets the same way
        // (Swift's String.hashValue is per-process seeded and would jump around).
        var hash: UInt64 = 1469598103934665603
        for byte in seed.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        let h = Int(hash % 100000)
        let angle = Double(h % 360) * .pi / 180
        // 30–100% of the radius, so points don't cluster on a ring.
        let frac = 0.3 + Double((h / 360) % 71) / 100.0
        let distKm = radius * frac
        let dLat = (distKm / 111.0) * cos(angle)
        let dLon = (distKm / (111.0 * cos(lat * .pi / 180))) * sin(angle)
        return (lat + dLat, lon + dLon)
    }

    /// Minimum fuzz applied to an "approximate" shared spot, so it's genuinely
    /// vague even when the angler's honey-hole radius (for catches) is 0.
    private var spotApproxRadiusKm: Double { max(privacyRadiusKm, 4) }

    /// Base URL of the web smart-link page (hosted on GitHub Pages from /docs).
    /// A real https:// link that previews nicely in Messages and bounces into
    /// the app via the currents:// scheme (see docs/open.html).
    static let webBase = "https://pndaman.github.io/Currents/open.html"

    /// Tappable https link that opens the app on an "Add friend" confirmation.
    func friendLink() -> URL { URL(string: "\(Self.webBase)?f=\(friendCode)")! }

    func friendInviteMessage() -> String {
        """
        Add me on Currents 🎣
        \(friendLink().absoluteString)
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
        var localPhotoPath: String? = nil   // set for your own catches (local)
        /// A friend published a photo with this catch (fetched on demand by id).
        var hasRemotePhoto: Bool = false
        /// Present only when the angler opted into sharing catch locations
        /// (already offset by their honey-hole radius).
        var coordinate: CLLocationCoordinate2D? = nil
    }

    struct SharedSpot: Identifiable {
        let id: String
        let ownerCode: String
        let name: String
        let type: String
        let notes: String
        /// The coordinate to display. When `isApproximate` is true this is an
        /// obfuscated point (offset by the owner's honey-hole radius), not the
        /// real spot. Nil only for legacy records shared without any location.
        let coordinate: CLLocationCoordinate2D?
        /// True when the owner shared only an approximate area, not exact GPS.
        var isApproximate: Bool = false
    }

    /// What YOU share with a specific friend. Spot-protective defaults.
    struct FriendPrivacy: Codable, Equatable {
        var shareCatches = true
        var shareSpots = false
        var shareExactLocations = false
        var nickname = ""
    }

    enum Metric { case count, weight, length }

    // MARK: - Join / leave

    func join(name: String, region: String) async {
        // Settle on a unique friend code before anything is saved or shared.
        await claimFriendCode()
        let clean = name.trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(clean.isEmpty ? "Angler \(friendCode)" : clean, forKey: "communityName")
        UserDefaults.standard.set(region, forKey: "communityRegion")
        if UserDefaults.standard.object(forKey: "communityMemberSince") == nil {
            UserDefaults.standard.set(Date(), forKey: "communityMemberSince")
        }
        UserDefaults.standard.set(true, forKey: "communityJoined")
        joined = true
        await saveMyProfile(stats: nil)
        await enablePush()
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
        bumpRevision()
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
        bumpRevision()
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
        attachPhoto(catchRecord.photoPath, to: record)
        attachLocation(lat: catchRecord.latitude, lon: catchRecord.longitude,
                       seed: catchRecord.id, to: record)
        // Tag the catch to a shared trip so the whole group sees it in real time.
        if let groupCode { record["groupCode"] = groupCode as CKRecordValue }
        if (try? await db.save(record)) != nil, joined {
            // Remember we've sent it so the full-history sync doesn't re-upload it.
            var published = Set(UserDefaults.standard.stringArray(forKey: "publishedCatchIds") ?? [])
            published.insert(catchRecord.id)
            UserDefaults.standard.set(Array(published), forKey: "publishedCatchIds")
        }
    }

    /// Attach a catch photo as a CKAsset (and a `hasPhoto` flag so leaderboard
    /// queries can tell there's a photo without downloading the asset).
    private func attachPhoto(_ photoPath: String?, to record: CKRecord) {
        guard let photoPath, let image = PhotoManager.load(photoPath),
              let data = image.jpegData(compressionQuality: 0.7) else {
            record["hasPhoto"] = 0 as CKRecordValue
            return
        }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ck-\(UUID().uuidString).jpg")
        do {
            try data.write(to: tmp, options: .atomic)
            record["photo"] = CKAsset(fileURL: tmp)
            record["hasPhoto"] = 1 as CKRecordValue
        } catch {
            record["hasPhoto"] = 0 as CKRecordValue
        }
    }

    /// Attach an obfuscated catch location, but only if the angler opted in.
    private func attachLocation(lat: Double, lon: Double, seed: String, to record: CKRecord) {
        guard shareCatchLocations, lat != 0 || lon != 0 else {
            record["lat"] = nil
            record["lon"] = nil
            return
        }
        let (oLat, oLon) = obfuscated(lat, lon, seed: seed)
        record["lat"] = oLat as CKRecordValue
        record["lon"] = oLon as CKRecordValue
    }

    /// A leaderboard: the visible top rows PLUS your own standing (rank + row)
    /// so you can always see where you sit even if you're outside the top.
    /// We fetch catches with a system-field sort and rank on-device, so no
    /// custom CloudKit indexes need configuring for it to work.
    /// `myRows` are the caller's own catches built from the LOCAL database, so
    /// you always see yourself and your full history even if the CloudKit query
    /// returns nothing (e.g. indexes not yet configured, or backfill pending).
    /// The leaderboard is scoped to friends (and yourself) only — there are no
    /// global or regional boards.
    func board(metric: Metric, myRows: [LeaderRow] = [])
        async -> (rows: [LeaderRow], mine: (rank: Int, row: LeaderRow)?) {
        let ranked = await rankedRows(metric: metric, myRows: myRows)
        let cap = metric == .count ? 50 : 20
        let top = Array(ranked.prefix(cap))
        var mine: (rank: Int, row: LeaderRow)?
        if let idx = ranked.firstIndex(where: { $0.friendCode == friendCode }) {
            mine = (idx + 1, ranked[idx])
        }
        return (top, mine)
    }

    /// The full ranked list for a board (no truncation), among friends + me.
    private func rankedRows(metric: Metric, myRows: [LeaderRow]) async -> [LeaderRow] {
        var catches = await fetchAllLeaderCatches()
        // Local catches are authoritative for me: drop any remote copies of my
        // own catches and use the local ones so I always appear.
        catches.removeAll { $0.friendCode == friendCode }
        catches += myRows

        // Friends-only: keep just my friends and me.
        let codes = Set(friends + [friendCode])
        catches = catches.filter { codes.contains($0.friendCode) }

        // Fold in the demo angler (if added) so there's always something to see.
        catches += demoLeaderCatches()

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

    /// All published catches. No server-side sort (we rank client-side), so the
    /// query needs no custom Sortable index — one less CloudKit setup step.
    private func fetchAllLeaderCatches(limit: Int = 400) async -> [LeaderRow] {
        let query = CKQuery(recordType: catchType, predicate: NSPredicate(value: true))
        // Fetch everything EXCEPT the photo asset — the leaderboard only needs to
        // know a photo exists (`hasPhoto`); the asset itself is downloaded on
        // demand when a catch is opened, so lists stay fast.
        let keys = ["anglerName", "friendCode", "species", "weightKg", "lengthCm",
                    "region", "caughtAt", "groupCode", "hasPhoto", "lat", "lon"]
        guard let results = try? await db.records(
            matching: query, desiredKeys: keys, resultsLimit: limit) else { return [] }
        return results.matchResults.compactMap { _, res -> LeaderRow? in
            guard let r = try? res.get() else { return nil }
            var coord: CLLocationCoordinate2D?
            if let lat = r["lat"] as? Double, let lon = r["lon"] as? Double {
                coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
            return LeaderRow(
                id: r.recordID.recordName,
                anglerName: r["anglerName"] as? String ?? "Angler",
                friendCode: r["friendCode"] as? String ?? "",
                species: r["species"] as? String ?? "Fish",
                weightKg: r["weightKg"] as? Double,
                lengthCm: r["lengthCm"] as? Double,
                catchCount: nil,
                region: r["region"] as? String ?? "",
                date: r["caughtAt"] as? Date ?? .now,
                hasRemotePhoto: (r["hasPhoto"] as? Int ?? 0) == 1,
                coordinate: coord
            )
        }
    }

    /// Download a single published catch's photo asset by its record id. Cached
    /// in memory so re-opening a catch (or scrolling a friend's list) is instant.
    private let photoCache = NSCache<NSString, UIImage>()
    func catchPhoto(recordName: String) async -> UIImage? {
        if let cached = photoCache.object(forKey: recordName as NSString) { return cached }
        let id = CKRecord.ID(recordName: recordName)
        guard let r = try? await db.record(for: id),
              let asset = r["photo"] as? CKAsset, let url = asset.fileURL,
              let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return nil }
        photoCache.setObject(image, forKey: recordName as NSString)
        return image
    }

    /// Publish every past catch so the leaderboards reflect the full history,
    /// not just catches logged after joining. Idempotent (deterministic record
    /// ids, force-overwrite) and throttled so it isn't re-run constantly.
    func syncAllCatches(_ details: [(id: String, species: String, weightKg: Double?, lengthCm: Double?, caughtAt: Date, latitude: Double, longitude: Double, photoPath: String?)]) async {
        guard joined else { return }
        await claimFriendCode()   // no-op once claimed; retries if a prior claim failed offline
        // Re-run when the location-sharing preference flips, not just on a timer,
        // so turning it on/off updates existing catches promptly.
        let last = UserDefaults.standard.object(forKey: "lastCatchSync") as? Date ?? .distantPast
        let lastLocPref = UserDefaults.standard.object(forKey: "lastCatchSyncLocPref") as? Bool
        let prefChanged = lastLocPref != shareCatchLocations
        guard prefChanged || Date().timeIntervalSince(last) > 1800 else { return }

        // Only re-upload everything (photos + coords) when the location-sharing
        // preference flips. Otherwise publish just catches we haven't sent yet,
        // so routine syncs don't re-upload every photo each time.
        var published = Set(UserDefaults.standard.stringArray(forKey: "publishedCatchIds") ?? [])
        let toPublish = prefChanged ? details : details.filter { !published.contains($0.id) }
        guard !toPublish.isEmpty else {
            UserDefaults.standard.set(Date(), forKey: "lastCatchSync")
            UserDefaults.standard.set(shareCatchLocations, forKey: "lastCatchSyncLocPref")
            return
        }
        UserDefaults.standard.set(Date(), forKey: "lastCatchSync")
        UserDefaults.standard.set(shareCatchLocations, forKey: "lastCatchSyncLocPref")

        let region = myRegion
        let records: [CKRecord] = toPublish.map { d in
            let id = CKRecord.ID(recordName: "catch-\(friendCode)-\(d.id)")
            let record = CKRecord(recordType: catchType, recordID: id)
            record["anglerName"] = myName as CKRecordValue
            record["friendCode"] = friendCode as CKRecordValue
            record["species"] = d.species as CKRecordValue
            if let w = d.weightKg { record["weightKg"] = w as CKRecordValue }
            if let l = d.lengthCm { record["lengthCm"] = l as CKRecordValue }
            record["region"] = region as CKRecordValue
            record["caughtAt"] = d.caughtAt as CKRecordValue
            attachPhoto(d.photoPath, to: record)
            attachLocation(lat: d.latitude, lon: d.longitude, seed: d.id, to: record)
            return record
        }
        // Batch (CloudKit caps ~400/op); force-overwrite so re-runs are safe.
        for chunk in stride(from: 0, to: records.count, by: 300).map({ Array(records[$0..<min($0 + 300, records.count)]) }) {
            _ = try? await db.modifyRecords(saving: chunk, deleting: [], savePolicy: .allKeys, atomically: false)
        }
        published.formUnion(toPublish.map(\.id))
        UserDefaults.standard.set(Array(published), forKey: "publishedCatchIds")
    }

    /// Remove a catch from the shared leaderboard + any group feed when it's
    /// deleted locally, so friends and group standings stop showing it. Safe to
    /// call even if the catch was never published. The record name is shared by
    /// the leaderboard and group feed, so a single delete covers both.
    func removeCatch(id catchId: String) async {
        guard joined else { return }
        let recordID = CKRecord.ID(recordName: "catch-\(friendCode)-\(catchId)")
        _ = try? await db.deleteRecord(withID: recordID)
        // Forget it locally so a same-id re-log would re-publish, and refresh
        // any open community/leaderboard view.
        var published = Set(UserDefaults.standard.stringArray(forKey: "publishedCatchIds") ?? [])
        published.remove(catchId)
        UserDefaults.standard.set(Array(published), forKey: "publishedCatchIds")
        bumpRevision()
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

    /// Per-friend privacy. Sharing is now controlled globally (Settings ›
    /// Privacy); only the nickname stays per-friend. The share* fields are
    /// filled from the global preferences so existing publish logic keeps working.
    func privacy(for code: String) -> FriendPrivacy {
        var p = FriendPrivacy()
        if let data = UserDefaults.standard.data(forKey: "friendPrivacy-\(code)"),
           let stored = try? JSONDecoder().decode(FriendPrivacy.self, from: data) {
            p.nickname = stored.nickname
        }
        p.shareCatches = shareCatchesWithFriends
        p.shareSpots = shareSpotsWithFriends
        p.shareExactLocations = shareSpotExactLocations
        return p
    }

    /// Persist only the per-friend nickname (sharing is global now).
    func setNickname(_ nickname: String, for code: String) {
        var p = FriendPrivacy()
        p.nickname = nickname
        if let data = try? JSONEncoder().encode(p) {
            UserDefaults.standard.set(data, forKey: "friendPrivacy-\(code)")
        }
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
                    record["approx"] = 0 as CKRecordValue
                } else {
                    // Share an obfuscated area instead of nothing, so the friend
                    // still sees roughly where it is — never the exact honey hole.
                    let (oLat, oLon) = obfuscated(spot.latitude, spot.longitude, seed: spot.id,
                                                  radiusKm: spotApproxRadiusKm)
                    record["lat"] = oLat as CKRecordValue
                    record["lon"] = oLon as CKRecordValue
                    record["approx"] = 1 as CKRecordValue
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
                coordinate: coord,
                isApproximate: (r["approx"] as? Int ?? 0) == 1
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

    private func demoLeaderCatches() -> [LeaderRow] {
        guard demoAdded else { return [] }
        return demoCatchRows
    }

    /// The demo angler's individual catches (used for their profile + boards).
    var demoCatchRows: [LeaderRow] {
        Self.demoCatchSeeds.enumerated().map { i, s in
            // Scatter demo catches around Theewaterskloof so the location-sharing
            // map preview has something to show.
            let coord = CLLocationCoordinate2D(
                latitude: -34.055 + Double((i % 5)) * 0.006 - 0.012,
                longitude: 19.290 + Double((i % 4)) * 0.007 - 0.010)
            return LeaderRow(
                id: "demo-\(i)", anglerName: "Sasha Rivers", friendCode: Self.demoCode,
                species: s.species, weightKg: s.weightKg, lengthCm: s.lengthCm,
                catchCount: nil, region: myRegion,
                date: Date().addingTimeInterval(-Double(i) * 3.2 * 24 * 3600),
                coordinate: coord
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
                       coordinate: CLLocationCoordinate2D(latitude: -34.038, longitude: 19.315),
                       isApproximate: true),
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

    // Last-seen group feed/members, so reopening a trip shows content instantly
    // instead of a blank page while the network refresh runs.
    private var groupCatchCache: [String: [GroupCatch]] = [:]
    private var groupMemberCache: [String: [GroupMember]] = [:]
    func cachedGroupCatches(_ code: String) -> [GroupCatch] { groupCatchCache[code] ?? [] }
    func cachedGroupMembers(_ code: String) -> [GroupMember] { groupMemberCache[code] ?? [] }

    struct GroupTrip: Identifiable, Equatable {
        let id: String          // 6-char join code
        let name: String
        let hostCode: String
        let hostName: String
        let createdAt: Date
        var isHost: Bool = false
        /// Set when the host ends the trip for everyone. Members' own GPS
        /// sessions are unaffected — only the shared trip is closed.
        var endedAt: Date?
        var isEnded: Bool { endedAt != nil }
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

    /// A group trip I'm part of, persisted locally so it shows up reliably (and
    /// offline) for BOTH host and joiner — the same list drives both.
    struct GroupRef: Codable, Identifiable, Equatable {
        let code: String
        var name: String
        var hostName: String
        var isHost: Bool
        var joinedAt: Date
        /// Cached "trip ended" marker so the group list can show finished trips
        /// (they stay as history until you leave the group). Optional so old
        /// stored refs decode fine.
        var endedAt: Date? = nil
        var id: String { code }
    }

    /// All group trips I host or have joined, newest first.
    var myGroups: [GroupRef] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "myGroupTrips"),
                  let refs = try? JSONDecoder().decode([GroupRef].self, from: data) else { return [] }
            return refs.sorted { $0.joinedAt > $1.joinedAt }
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "myGroupTrips")
            }
            bumpRevision()
        }
    }

    private func rememberGroup(_ ref: GroupRef) {
        var groups = myGroups
        if let i = groups.firstIndex(where: { $0.code == ref.code }) {
            groups[i].name = ref.name
            groups[i].hostName = ref.hostName
        } else {
            groups.append(ref)
        }
        myGroups = groups
    }

    private func forgetGroup(code: String) {
        myGroups = myGroups.filter { $0.code != code }
    }

    // Local trip.id → group code mapping so a trip stays linked to its group
    // across launches (no DB migration needed).
    func groupCode(forTripId id: String) -> String? {
        (UserDefaults.standard.dictionary(forKey: "tripGroupCodes") as? [String: String])?[id]
    }

    /// Reverse lookup: the local trip linked to a group code (if any).
    func tripId(forGroupCode code: String) -> String? {
        (UserDefaults.standard.dictionary(forKey: "tripGroupCodes") as? [String: String])?
            .first(where: { $0.value == code })?.key
    }

    func setGroupCode(_ code: String?, forTripId id: String) {
        var m = (UserDefaults.standard.dictionary(forKey: "tripGroupCodes") as? [String: String]) ?? [:]
        m[id] = code
        UserDefaults.standard.set(m, forKey: "tripGroupCodes")
    }

    /// Tappable https link that opens the app straight into the join flow.
    func inviteLink(forGroup code: String, tripName: String = "") -> URL {
        var comps = URLComponents(string: Self.webBase)!
        comps.queryItems = [URLQueryItem(name: "t", value: code)]
        if !tripName.isEmpty { comps.queryItems?.append(URLQueryItem(name: "n", value: tripName)) }
        return comps.url!
    }

    func inviteMessage(forGroup code: String, tripName: String) -> String {
        """
        Join my fishing trip “\(tripName)” on Currents 🎣
        \(inviteLink(forGroup: code, tripName: tripName).absoluteString)
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
        rememberGroup(GroupRef(code: code, name: name, hostName: myName, isHost: true, joinedAt: Date()))
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
        rememberGroup(GroupRef(code: code, name: trip.name, hostName: trip.hostName,
                               isHost: trip.isHost, joinedAt: Date()))
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
        let endedAt = r["endedAt"] as? Date
        // Keep the locally-cached ref in step so the group list shows "Ended"
        // for every member, not just whoever tapped End.
        if let endedAt { markGroupEnded(code: code, at: endedAt) }
        return GroupTrip(
            id: r["code"] as? String ?? code,
            name: r["name"] as? String ?? "Group Trip",
            hostCode: hostCode,
            hostName: r["hostName"] as? String ?? "Host",
            createdAt: r["createdAt"] as? Date ?? .now,
            isHost: hostCode == friendCode,
            endedAt: endedAt
        )
    }

    /// Host-only: end the shared trip for everyone. Marks the group record ended
    /// so members see it as finished on their next poll. Does NOT stop anyone's
    /// personal GPS session — each angler ends their own. No-op for non-hosts.
    func endGroupTrip(code: String) async {
        let id = CKRecord.ID(recordName: "grouptrip-\(code)")
        guard let r = try? await db.record(for: id),
              (r["hostCode"] as? String) == friendCode else { return }
        r["endedAt"] = Date() as CKRecordValue
        _ = try? await db.save(r)
        markGroupEnded(code: code, at: Date())
    }

    /// Update the locally-cached group ref so the list shows it as ended.
    private func markGroupEnded(code: String, at date: Date) {
        var groups = myGroups
        if let i = groups.firstIndex(where: { $0.code == code }), groups[i].endedAt == nil {
            groups[i].endedAt = date
            myGroups = groups
        }
    }

    func groupMembers(code: String) async -> [GroupMember] {
        // Server-side filter on the indexed `groupCode` so every member is found
        // regardless of how many group members exist across the whole public DB.
        let query = CKQuery(recordType: groupMemberType,
                            predicate: NSPredicate(format: "groupCode == %@", code))
        guard let results = try? await db.records(matching: query, resultsLimit: 300) else {
            return groupMemberCache[code] ?? []
        }
        let members = results.matchResults.compactMap { _, res -> GroupMember? in
            guard let r = try? res.get() else { return nil }
            return GroupMember(
                id: r["memberCode"] as? String ?? "",
                name: r["memberName"] as? String ?? "Angler",
                joinedAt: r["joinedAt"] as? Date ?? .now
            )
        }.sorted { $0.joinedAt < $1.joinedAt }
        groupMemberCache[code] = members
        return members
    }

    /// Every catch shared into the group, newest first. Server-side filter on the
    /// indexed `groupCode` so the whole group's feed is reliable at any scale.
    func groupCatches(code: String) async -> [GroupCatch] {
        let query = CKQuery(recordType: catchType,
                            predicate: NSPredicate(format: "groupCode == %@", code))
        guard let results = try? await db.records(matching: query, resultsLimit: 400) else {
            return groupCatchCache[code] ?? []
        }
        let catches = results.matchResults.compactMap { _, res -> GroupCatch? in
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
        }.sorted { $0.date > $1.date }
        groupCatchCache[code] = catches
        return catches
    }

    func leaveGroupTrip(code: String, tripId: String?) async {
        let wasHost = myGroups.first(where: { $0.code == code })?.isHost ?? false
        let id = CKRecord.ID(recordName: "member-\(code)-\(friendCode)")
        _ = try? await db.deleteRecord(withID: id)
        // When the HOST leaves, the trip no longer exists — delete the group
        // record so members detect it's gone and any pending invites to it drop
        // (invitees clean those up in pendingInvites()).
        if wasHost {
            _ = try? await db.deleteRecord(withID: CKRecord.ID(recordName: "grouptrip-\(code)"))
        }
        groupCatchCache[code] = nil
        groupMemberCache[code] = nil
        let linked = tripId ?? self.tripId(forGroupCode: code)
        if let linked { setGroupCode(nil, forTripId: linked) }
        forgetGroup(code: code)
    }

    /// Publish a catch straight into a group's live feed even when it isn't tied
    /// to a local tracked session — used by the "Log to trip" action so a
    /// member's catch always reaches the group.
    func publishGroupCatch(species: String, weightKg: Double?, lengthCm: Double?,
                           catchId: String, groupCode: String) async {
        await ensureJoined()
        let id = CKRecord.ID(recordName: "catch-\(friendCode)-\(catchId)")
        // Update the existing catch record (adding the group tag) if it's already
        // been published to the leaderboard, so its photo/fields are preserved;
        // otherwise create it fresh.
        let record = (try? await db.record(for: id)) ?? CKRecord(recordType: catchType, recordID: id)
        if record["groupCode"] as? String == groupCode { return } // already tagged
        record["anglerName"] = myName as CKRecordValue
        record["friendCode"] = friendCode as CKRecordValue
        if record["species"] == nil { record["species"] = species as CKRecordValue }
        if record["weightKg"] == nil, let weightKg { record["weightKg"] = weightKg as CKRecordValue }
        if record["lengthCm"] == nil, let lengthCm { record["lengthCm"] = lengthCm as CKRecordValue }
        if record["region"] == nil { record["region"] = myRegion as CKRecordValue }
        if record["caughtAt"] == nil { record["caughtAt"] = Date() as CKRecordValue }
        record["groupCode"] = groupCode as CKRecordValue
        _ = try? await db.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys, atomically: false)
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
        // Server-side filter on the indexed `toCode` so invites addressed to me
        // are found even as the public DB grows past a single query page.
        let query = CKQuery(recordType: inviteType,
                            predicate: NSPredicate(format: "toCode == %@", friendCode))
        guard let results = try? await db.records(matching: query, resultsLimit: 200) else { return [] }
        let raw = results.matchResults.compactMap { _, res -> (TripInvite, CKRecord.ID)? in
            guard let r = try? res.get() else { return nil }
            let inv = TripInvite(
                id: r.recordID.recordName,
                groupCode: r["groupCode"] as? String ?? "",
                tripName: r["tripName"] as? String ?? "Group Trip",
                fromName: r["fromName"] as? String ?? "A friend",
                fromCode: r["fromCode"] as? String ?? "",
                date: r["createdAt"] as? Date ?? .now
            )
            return (inv, r.recordID)
        }
        // Drop invites whose group no longer exists (host left) or has already
        // ended, cleaning up the stale invite record so it never shows again.
        var live: [TripInvite] = []
        for (inv, recID) in raw {
            let group = await groupTrip(code: inv.groupCode)
            if let group, !group.isEnded {
                live.append(inv)
            } else {
                _ = try? await db.deleteRecord(withID: recID)
            }
        }
        return live.sorted { $0.date > $1.date }
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
    /// Refresh the in-app trip-invite list. Alerts themselves arrive as instant
    /// push (CloudKit subscription) — no local "on open" notification.
    @discardableResult
    func refreshTripInvites() async -> [TripInvite] {
        guard joined else { return [] }
        return await pendingInvites()
    }

    // MARK: - Friend requests (mutual add + accept)

    private let friendReqType = "FriendRequest"

    struct FriendRequest: Identifiable {
        let id: String
        let fromCode: String
        let fromName: String
        let date: Date
    }

    /// Send a friend request. The recipient gets a notification + an in-app
    /// Accept/Decline, and both become friends on accept. The demo angler
    /// auto-accepts. Returns false on a bad code.
    @discardableResult
    func sendFriendRequest(to raw: String) async -> Bool {
        let toCode = raw.uppercased().trimmingCharacters(in: .whitespaces)
        guard toCode.count == 6, toCode != friendCode else { return false }
        if toCode == Self.demoCode {
            if !friends.contains(toCode) { friends.append(toCode) }
            UserDefaults.standard.set(true, forKey: "communityDemoAdded")
            return true
        }
        if friends.contains(toCode) { return true } // already friends
        let id = CKRecord.ID(recordName: "friendreq-\(friendCode)-\(toCode)")
        let rec = (try? await db.record(for: id)) ?? CKRecord(recordType: friendReqType, recordID: id)
        rec["fromCode"] = friendCode as CKRecordValue
        rec["fromName"] = myName as CKRecordValue
        rec["toCode"] = toCode as CKRecordValue
        rec["status"] = "pending" as CKRecordValue
        rec["createdAt"] = Date() as CKRecordValue
        return (try? await db.save(rec)) != nil
    }

    /// Requests addressed to me and still pending. Queries server-side on the
    /// indexed `toCode` field — a TRUEPREDICATE scan capped at 200 could miss my
    /// request once the public DB has more than 200 requests across all users.
    func pendingFriendRequests() async -> [FriendRequest] {
        let query = CKQuery(recordType: friendReqType,
                            predicate: NSPredicate(format: "toCode == %@", friendCode))
        guard let results = try? await db.records(matching: query, resultsLimit: 200) else { return [] }
        return results.matchResults.compactMap { _, res -> FriendRequest? in
            guard let r = try? res.get(),
                  (r["status"] as? String ?? "pending") == "pending" else { return nil }
            return FriendRequest(
                id: r.recordID.recordName,
                fromCode: r["fromCode"] as? String ?? "",
                fromName: r["fromName"] as? String ?? "An angler",
                date: r["createdAt"] as? Date ?? .now
            )
        }
    }

    func acceptFriendRequest(_ req: FriendRequest) async {
        if !friends.contains(req.fromCode) { friends.append(req.fromCode) }
        // Apply my global sharing prefs to the new friend.
        await updateCatchGrant(for: req.fromCode, share: shareCatchesWithFriends)
        // Mark accepted so the sender's app adds me back and cleans up.
        let id = CKRecord.ID(recordName: "friendreq-\(req.fromCode)-\(friendCode)")
        if let rec = try? await db.record(for: id) {
            rec["status"] = "accepted" as CKRecordValue
            _ = try? await db.save(rec)
        }
    }

    func declineFriendRequest(_ req: FriendRequest) async {
        _ = try? await db.deleteRecord(withID: CKRecord.ID(recordName: req.id))
    }

    /// Add friends who accepted a request I sent, then delete those records.
    private func reconcileSentRequests() async {
        let query = CKQuery(recordType: friendReqType,
                            predicate: NSPredicate(format: "fromCode == %@", friendCode))
        guard let results = try? await db.records(matching: query, resultsLimit: 200) else { return }
        for (_, res) in results.matchResults {
            guard let r = try? res.get(),
                  (r["status"] as? String) == "accepted" else { continue }
            if let toCode = r["toCode"] as? String, !friends.contains(toCode) {
                friends.append(toCode)
                await updateCatchGrant(for: toCode, share: shareCatchesWithFriends)
            }
            _ = try? await db.deleteRecord(withID: r.recordID)
        }
    }

    /// Poll incoming requests (fire a one-time notification for new ones) and
    /// reconcile ones I sent that were accepted. Returns pending incoming.
    /// Refresh the in-app friend-request list and reconcile ones I sent that
    /// were accepted. Alerts arrive as instant push (CloudKit subscription).
    @discardableResult
    func refreshFriendRequests() async -> [FriendRequest] {
        guard joined else { return [] }
        await reconcileSentRequests()
        return await pendingFriendRequests()
    }

    // MARK: - Push notifications (instant, via CloudKit subscriptions)

    /// Register for APNs and create the CloudKit subscriptions that deliver
    /// friend requests / trip invites / request-accepted as real push — instant,
    /// even when the app is closed (not "when you next open the app").
    func enablePush() async {
        guard joined else { return }
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        UserDefaults.standard.set(granted, forKey: "notifAuthorized")
        guard granted else { return }
        UIApplication.shared.registerForRemoteNotifications()
        await registerPushSubscriptions()
    }

    /// Whether APNs registration succeeded on this build (proves the aps-
    /// environment entitlement is present). Set by the app delegate.
    var apnsRegistered: Bool { UserDefaults.standard.bool(forKey: "apnsRegistered") }
    var apnsRegisterError: String? { UserDefaults.standard.string(forKey: "apnsRegisterError") }
    var pushSubscriptionsCreated: Bool {
        UserDefaults.standard.string(forKey: "pushSubsForCode") == friendCode
    }

    /// Force a full re-registration (clears the guard) — used by the in-app
    /// "Re-enable notifications" action after granting permission or deploying
    /// the CloudKit schema.
    func forcePushReenable() async {
        UserDefaults.standard.removeObject(forKey: "pushSubsForCode")
        await enablePush()
    }

    /// Whether the CKQuerySubscriptions could be created (a quick probe that also
    /// tells us if the schema/indexes are deployed to this environment).
    func verifyPushSubscriptions() async -> Bool {
        await registerPushSubscriptions(force: true)
        return pushSubscriptionsCreated
    }

    @discardableResult
    private func registerPushSubscriptions(force: Bool = false) async -> Bool {
        // Only rebuild subscriptions when the friend code changes (cheap guard).
        if !force, UserDefaults.standard.string(forKey: "pushSubsForCode") == friendCode { return true }

        func info(_ title: String, key: String, args: [String]) -> CKSubscription.NotificationInfo {
            let n = CKSubscription.NotificationInfo()
            n.title = title
            n.alertLocalizationKey = key
            n.alertLocalizationArgs = args
            n.soundName = "default"
            n.shouldBadge = true
            return n
        }

        // Incoming friend requests.
        let frSub = CKQuerySubscription(
            recordType: friendReqType,
            predicate: NSPredicate(format: "toCode == %@", friendCode),
            subscriptionID: "friendreq-in-\(friendCode)",
            options: [.firesOnRecordCreation])
        frSub.notificationInfo = info("New friend request",
                                      key: "%1$@ wants to be friends on Currents 🎣",
                                      args: ["fromName"])

        // Incoming trip invites.
        let tiSub = CKQuerySubscription(
            recordType: inviteType,
            predicate: NSPredicate(format: "toCode == %@", friendCode),
            subscriptionID: "tripinvite-in-\(friendCode)",
            options: [.firesOnRecordCreation])
        tiSub.notificationInfo = info("Trip invite",
                                      key: "%1$@ invited you to “%2$@” on Currents",
                                      args: ["fromName", "tripName"])

        // A request I sent got accepted.
        let acSub = CKQuerySubscription(
            recordType: friendReqType,
            predicate: NSPredicate(format: "fromCode == %@ AND status == %@", friendCode, "accepted"),
            subscriptionID: "friendreq-accepted-\(friendCode)",
            options: [.firesOnRecordCreation, .firesOnRecordUpdate])
        let acInfo = CKSubscription.NotificationInfo()
        acInfo.title = "Friend request accepted"
        acInfo.alertBody = "You've got a new fishing friend on Currents 🎣"
        acInfo.soundName = "default"
        acInfo.shouldBadge = true
        acSub.notificationInfo = acInfo

        do {
            _ = try await db.modifySubscriptions(saving: [frSub, tiSub, acSub], deleting: [])
            UserDefaults.standard.set(friendCode, forKey: "pushSubsForCode")
            UserDefaults.standard.removeObject(forKey: "pushSubsError")
            return true
        } catch {
            // Schema not deployed yet / offline — retried next foreground.
            UserDefaults.standard.set(error.localizedDescription, forKey: "pushSubsError")
            return false
        }
    }

    var pushSubsError: String? { UserDefaults.standard.string(forKey: "pushSubsError") }
}
