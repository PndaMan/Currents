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
            await updateCatchGrant(for: code, share: privacy(for: code).shareCatches)
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

    /// The EFFECTIVE (resolved) sharing for a specific friend — what the publish
    /// logic reads. Produced by `privacy(for:)` from the global settings plus any
    /// per-friend overrides.
    struct FriendPrivacy: Codable, Equatable {
        var shareCatches = true
        var shareSpots = false
        var shareExactLocations = false
        var nickname = ""
    }

    /// Per-friend OVERRIDES. Each share flag is a tri-state: `nil` follows the
    /// global Privacy setting; `true`/`false` overrides it just for this friend
    /// (e.g. share your exact spots with a trusted friend while everyone else
    /// only sees an approximate area). The honey-hole obfuscation radius is
    /// deliberately NOT overridable — it stays a single global setting.
    struct FriendPrivacyOverride: Codable, Equatable {
        var shareCatches: Bool?
        var shareSpots: Bool?
        var shareExactLocations: Bool?
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
        // Stop community push for a user who left — the subscriptions would
        // happily keep delivering crew/friend alerts forever otherwise. The
        // published records stay (rejoining restores them); the UI says so.
        Task {
            if let subs = try? await db.allSubscriptions() {
                let mine = subs.map(\.subscriptionID).filter {
                    $0.hasPrefix("ev-") || $0.hasPrefix("friendreq-") || $0.hasPrefix("tripinvite-")
                }
                if !mine.isEmpty {
                    _ = try? await db.modifySubscriptions(saving: [], deleting: mine)
                }
            }
            UserDefaults.standard.removeObject(forKey: "pushSubsForCode")
            UserDefaults.standard.removeObject(forKey: "eventSubsFingerprint")
        }
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
        let p = profile(from: r)
        cache(profile: p, code: code)
        return p
    }

    // MARK: - Local profile cache (instant friend rendering)

    /// A Codable snapshot of a friend's profile so the Friends list can render
    /// immediately on launch instead of blocking on a CloudKit round-trip. The
    /// (small) avatar is stored inline as JPEG data.
    private struct ProfileDTO: Codable {
        var id, name, bio, region, homeWater: String
        var memberSince: Date
        var totalCatches, speciesCount: Int
        var bestWeightKg, bestLengthCm: Double
        var favoriteSpecies: String
        var avatarData: Data?

        init(_ p: Profile) {
            id = p.id; name = p.name; bio = p.bio; region = p.region
            homeWater = p.homeWater; memberSince = p.memberSince
            totalCatches = p.totalCatches; speciesCount = p.speciesCount
            bestWeightKg = p.bestWeightKg; bestLengthCm = p.bestLengthCm
            favoriteSpecies = p.favoriteSpecies
            avatarData = p.avatar?.jpegData(compressionQuality: 0.6)
        }

        var profile: Profile {
            Profile(id: id, name: name, bio: bio, region: region, homeWater: homeWater,
                    avatar: avatarData.flatMap(UIImage.init(data:)), memberSince: memberSince,
                    totalCatches: totalCatches, speciesCount: speciesCount,
                    bestWeightKg: bestWeightKg, bestLengthCm: bestLengthCm,
                    favoriteSpecies: favoriteSpecies)
        }
    }

    private static let profileCacheKey = "cachedFriendProfiles"

    private var profileCache: [String: ProfileDTO] {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.profileCacheKey) else { return [:] }
            return (try? JSONDecoder().decode([String: ProfileDTO].self, from: data)) ?? [:]
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: Self.profileCacheKey) }
    }

    private func cache(profile p: Profile, code: String) {
        var c = profileCache
        c[code.uppercased()] = ProfileDTO(p)
        profileCache = c
    }

    /// Last-known profiles for these friend codes, in the same order, for
    /// instant display while the network refresh runs.
    func cachedProfiles(for codes: [String]) -> [Profile] {
        let c = profileCache
        return codes.compactMap { c[$0.uppercased()]?.profile }
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
        // .allKeys so re-publishing after an edit overwrites the existing
        // record instead of failing on the change tag.
        let saved = (try? await db.modifyRecords(saving: [record], deleting: [],
                                                 savePolicy: .allKeys, atomically: false)) != nil
        if saved, joined {
            // Remember we've sent it so the full-history sync doesn't re-upload it.
            var published = Set(UserDefaults.standard.stringArray(forKey: "publishedCatchIds") ?? [])
            published.insert(catchRecord.id)
            UserDefaults.standard.set(Array(published), forKey: "publishedCatchIds")
        }
    }

    /// One entry point for "a catch was saved outside the log sheet" — the
    /// watch, Siri, and the edit screen. Mirrors the log sheet's contract:
    /// measured catches go to the leaderboard (and the live group trip if the
    /// catch's trip is linked to one); every catch auto-posts to crews. The
    /// leaderboard write is idempotent, so edits simply overwrite.
    func publishLoggedCatch(_ c: Catch, speciesName: String?) async {
        guard joined else { return }
        let name = speciesName ?? "Fish"
        if c.weightKg != nil || c.lengthCm != nil {
            let group = c.tripId.flatMap { groupCode(forTripId: $0) }
            await publish(catchRecord: c, speciesName: name, region: myRegion, groupCode: group)
        }
        await autoPostCatch(c, speciesName: name)
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
        // Never publish the exact spot: at the default honey-hole radius (0)
        // the offset was a no-op while the viewer UI promised "Approximate
        // area". Floor of 3 km keeps the promise without the user configuring
        // anything.
        let (oLat, oLon) = obfuscated(lat, lon, seed: seed,
                                      radiusKm: max(privacyRadiusKm, 3))
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
        // Server-side filter on the indexed friendCode: a TRUEPREDICATE scan
        // capped at `limit` would silently drop friends' catches once the
        // whole public DB outgrew it.
        let codes = friends + [friendCode]
        let query = CKQuery(recordType: catchType,
                            predicate: NSPredicate(format: "friendCode IN %@", codes))
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
        // Deliberately NOT gated on `joined` — deleting a catch must retract
        // it even if the user has since left the community.
        let recordID = CKRecord.ID(recordName: "catch-\(friendCode)-\(catchId)")
        _ = try? await db.deleteRecord(withID: recordID)
        // Crew posts are separate records; take them down too so the photo
        // doesn't outlive the catch in every crew feed.
        for crew in myCrews {
            let postID = CKRecord.ID(recordName: "crewpost-\(crew.code)-\(catchId)")
            _ = try? await db.deleteRecord(withID: postID)
        }
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

    /// The stored per-friend overrides (nil flags = follow global).
    func override(for code: String) -> FriendPrivacyOverride {
        if let data = UserDefaults.standard.data(forKey: "friendPrivacyV2-\(code)"),
           let o = try? JSONDecoder().decode(FriendPrivacyOverride.self, from: data) {
            return o
        }
        // Back-compat: pull a nickname saved under the old key, if any.
        var o = FriendPrivacyOverride()
        if let data = UserDefaults.standard.data(forKey: "friendPrivacy-\(code)"),
           let old = try? JSONDecoder().decode(FriendPrivacy.self, from: data) {
            o.nickname = old.nickname
        }
        return o
    }

    /// Effective per-friend sharing: each setting is the friend's override if
    /// set, otherwise the global Privacy setting.
    func privacy(for code: String) -> FriendPrivacy {
        let o = override(for: code)
        var p = FriendPrivacy()
        p.shareCatches = o.shareCatches ?? shareCatchesWithFriends
        p.shareSpots = o.shareSpots ?? shareSpotsWithFriends
        p.shareExactLocations = o.shareExactLocations ?? shareSpotExactLocations
        p.nickname = o.nickname
        return p
    }

    func setOverride(_ o: FriendPrivacyOverride, for code: String) {
        if let data = try? JSONEncoder().encode(o) {
            UserDefaults.standard.set(data, forKey: "friendPrivacyV2-\(code)")
        }
        bumpRevision()
    }

    /// Re-apply this friend's effective sharing after their overrides change, so
    /// grants + shared spots reflect the new choice immediately.
    func applyPrivacy(for code: String, spots: [Spot]) async {
        guard joined else { return }
        await updateCatchGrant(for: code, share: privacy(for: code).shareCatches)
        await republishSharedSpots(spots: spots)
    }

    func setNickname(_ nickname: String, for code: String) {
        var o = override(for: code)
        o.nickname = nickname
        setOverride(o, for: code)
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
        // No isEmpty guard: with zero spots the retraction pass below must
        // still run, or deleting your last spot would leave it shared forever.
        guard joined else { return }
        var live = Set<String>()
        for spot in spots {
            for code in friends {
                let p = privacy(for: code)
                let id = CKRecord.ID(recordName: "spot-\(friendCode)-\(spot.id)-\(code)")
                if !p.shareSpots {
                    _ = try? await db.deleteRecord(withID: id)
                    continue
                }
                live.insert("\(spot.id)|\(code)")
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
        // Retract shares whose spot was deleted (or whose friend was removed)
        // since the last pass — the loop above only sees spots that still exist.
        let previous = Set(UserDefaults.standard.stringArray(forKey: "publishedSpotShares") ?? [])
        for stale in previous.subtracting(live) {
            guard let sep = stale.lastIndex(of: "|") else { continue }
            let spotId = String(stale[..<sep]), code = String(stale[stale.index(after: sep)...])
            let id = CKRecord.ID(recordName: "spot-\(friendCode)-\(spotId)-\(code)")
            _ = try? await db.deleteRecord(withID: id)
        }
        UserDefaults.standard.set(Array(live), forKey: "publishedSpotShares")
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

    // MARK: - Crews (persistent shared catch-feeds for a circle of friends)

    private let crewType = "Crew"
    private let crewMemberType = "CrewMember"
    private let crewPostType = "CrewPost"
    private let crewReactionType = "CrewReaction"

    /// Emoji offered as one-tap reactions in a crew feed.
    static let crewReactionEmojis = ["🔥", "🎣", "👏", "😮", "🐟"]

    struct Crew: Codable, Identifiable, Equatable {
        let code: String
        var name: String
        var emoji: String
        var createdByCode: String
        var createdByName: String
        var joinedAt: Date
        /// Per-crew, per-device: auto-post my new catches into this crew's feed.
        var autoPost: Bool = true
        var id: String { code }
    }

    struct CrewReaction: Identifiable, Equatable {
        let id: String            // crewreact-<postId>-<reactorCode>
        let reactorCode: String
        let reactorName: String
        let emoji: String
    }

    struct CrewPost: Identifiable, Equatable {
        let id: String            // crewpost-<crewCode>-<catchId>
        let crewCode: String
        let authorCode: String
        let authorName: String
        let species: String
        let weightKg: Double?
        let lengthCm: Double?
        let caughtAt: Date
        var caption: String
        let hasPhoto: Bool
        /// Set when the catch was logged during a live trip run by this crew, so
        /// the feed can badge it "on <trip>".
        var tripName: String = ""
        var reactions: [CrewReaction] = []
    }

    /// The crew's currently-live trip, if any (a linked group trip not yet ended).
    func activeTrip(forCrew code: String) -> GroupRef? {
        myGroups.first { $0.crewCode == code && $0.endedAt == nil }
    }

    /// Crews I'm in — persisted locally so the list is instant + offline, and so
    /// each crew's auto-post preference lives on-device.
    var myCrews: [Crew] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "myCrews"),
                  let list = try? JSONDecoder().decode([Crew].self, from: data) else { return [] }
            return list.sorted { $0.joinedAt > $1.joinedAt }
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "myCrews")
            }
            bumpRevision()
        }
    }

    func crew(withCode code: String) -> Crew? { myCrews.first { $0.code == code } }

    private func rememberCrew(_ crew: Crew) {
        var list = myCrews
        if let i = list.firstIndex(where: { $0.code == crew.code }) {
            list[i].name = crew.name
            list[i].emoji = crew.emoji
            list[i].createdByName = crew.createdByName
        } else {
            list.append(crew)
        }
        myCrews = list
        scheduleEventSubSync()
    }

    private func forgetCrew(code: String) {
        myCrews = myCrews.filter { $0.code != code }
        scheduleEventSubSync()
    }

    func setAutoPost(_ on: Bool, forCrew code: String) {
        var list = myCrews
        guard let i = list.firstIndex(where: { $0.code == code }) else { return }
        list[i].autoPost = on
        myCrews = list
    }

    // Last-seen feed/members so reopening a crew shows content instantly.
    private var crewFeedCache: [String: [CrewPost]] = [:]
    private var crewMemberCacheStore: [String: [GroupMember]] = [:]
    func cachedCrewFeed(_ code: String) -> [CrewPost] { crewFeedCache[code] ?? [] }
    func cachedCrewMembers(_ code: String) -> [GroupMember] { crewMemberCacheStore[code] ?? [] }

    @discardableResult
    func createCrew(name: String, emoji: String) async -> Crew? {
        guard joined else { return nil }
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let code = String((0..<6).map { _ in chars[Int.random(in: 0..<chars.count)] })
        let id = CKRecord.ID(recordName: "crew-\(code)")
        let record = CKRecord(recordType: crewType, recordID: id)
        record["code"] = code as CKRecordValue
        record["name"] = name as CKRecordValue
        record["emoji"] = emoji as CKRecordValue
        record["createdByCode"] = friendCode as CKRecordValue
        record["createdByName"] = myName as CKRecordValue
        record["createdAt"] = Date() as CKRecordValue
        guard (try? await db.save(record)) != nil else { return nil }
        await addCrewMembership(code: code)
        let crew = Crew(code: code, name: name, emoji: emoji, createdByCode: friendCode,
                        createdByName: myName, joinedAt: Date(), autoPost: true)
        rememberCrew(crew)
        return crew
    }

    @discardableResult
    func joinCrew(code raw: String) async -> Crew? {
        guard joined else { return nil }
        let code = raw.uppercased().trimmingCharacters(in: .whitespaces)
        guard code.count == 6, let crew = await fetchCrew(code: code) else { return nil }
        await addCrewMembership(code: code)
        rememberCrew(crew)
        return crew
    }

    private func addCrewMembership(code: String) async {
        let id = CKRecord.ID(recordName: "crewmember-\(code)-\(friendCode)")
        let record = (try? await db.record(for: id)) ?? CKRecord(recordType: crewMemberType, recordID: id)
        record["crewCode"] = code as CKRecordValue
        record["memberCode"] = friendCode as CKRecordValue
        record["memberName"] = myName as CKRecordValue
        record["joinedAt"] = Date() as CKRecordValue
        _ = try? await db.save(record)
    }

    func fetchCrew(code: String) async -> Crew? {
        let id = CKRecord.ID(recordName: "crew-\(code)")
        guard let r = try? await db.record(for: id) else { return nil }
        let existing = crew(withCode: code)
        return Crew(
            code: r["code"] as? String ?? code,
            name: r["name"] as? String ?? "Crew",
            emoji: r["emoji"] as? String ?? "🎣",
            createdByCode: r["createdByCode"] as? String ?? "",
            createdByName: r["createdByName"] as? String ?? "Angler",
            joinedAt: existing?.joinedAt ?? Date(),
            autoPost: existing?.autoPost ?? true)
    }

    func leaveCrew(code: String) async {
        let id = CKRecord.ID(recordName: "crewmember-\(code)-\(friendCode)")
        _ = try? await db.deleteRecord(withID: id)
        crewFeedCache[code] = nil
        crewMemberCacheStore[code] = nil
        forgetCrew(code: code)
    }

    func crewMembers(code: String) async -> [GroupMember] {
        let query = CKQuery(recordType: crewMemberType,
                            predicate: NSPredicate(format: "crewCode == %@", code))
        guard let results = try? await db.records(matching: query, resultsLimit: 300) else {
            return crewMemberCacheStore[code] ?? []
        }
        let members = results.matchResults.compactMap { _, res -> GroupMember? in
            guard let r = try? res.get() else { return nil }
            return GroupMember(id: r["memberCode"] as? String ?? "",
                               name: r["memberName"] as? String ?? "Angler",
                               joinedAt: r["joinedAt"] as? Date ?? .now)
        }.sorted { $0.joinedAt < $1.joinedAt }
        crewMemberCacheStore[code] = members
        return members
    }

    /// The crew's catch feed (newest first) with each post's reactions attached.
    func crewFeed(code: String) async -> [CrewPost] {
        let postQuery = CKQuery(recordType: crewPostType,
                                predicate: NSPredicate(format: "crewCode == %@", code))
        guard let results = try? await db.records(matching: postQuery, resultsLimit: 300) else {
            return crewFeedCache[code] ?? []
        }
        var posts = results.matchResults.compactMap { _, res -> CrewPost? in
            guard let r = try? res.get() else { return nil }
            return CrewPost(
                id: r.recordID.recordName,
                crewCode: code,
                authorCode: r["authorCode"] as? String ?? "",
                authorName: r["authorName"] as? String ?? "Angler",
                species: r["species"] as? String ?? "Fish",
                weightKg: r["weightKg"] as? Double,
                lengthCm: r["lengthCm"] as? Double,
                caughtAt: r["caughtAt"] as? Date ?? .now,
                caption: r["caption"] as? String ?? "",
                hasPhoto: (r["hasPhoto"] as? Int ?? 0) == 1,
                tripName: r["tripName"] as? String ?? "")
        }
        // Fold in reactions for the whole crew in one query.
        let reactQuery = CKQuery(recordType: crewReactionType,
                                 predicate: NSPredicate(format: "crewCode == %@", code))
        if let rr = try? await db.records(matching: reactQuery, resultsLimit: 800) {
            let all = rr.matchResults.compactMap { _, res -> (String, CrewReaction)? in
                guard let r = try? res.get() else { return nil }
                return (r["postId"] as? String ?? "",
                        CrewReaction(id: r.recordID.recordName,
                                     reactorCode: r["reactorCode"] as? String ?? "",
                                     reactorName: r["reactorName"] as? String ?? "",
                                     emoji: r["emoji"] as? String ?? "🔥"))
            }
            let byPost = Dictionary(grouping: all, by: { $0.0 })
            posts = posts.map { post in
                var post = post
                post.reactions = (byPost[post.id] ?? []).map { $0.1 }
                return post
            }
        }
        posts.sort { $0.caughtAt > $1.caughtAt }
        crewFeedCache[code] = posts
        return posts
    }

    func crewPostPhoto(recordName: String) async -> UIImage? {
        let id = CKRecord.ID(recordName: recordName)
        guard let r = try? await db.record(for: id),
              let asset = r["photo"] as? CKAsset, let url = asset.fileURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Auto-post a freshly-logged catch into every crew that has auto-post on.
    func autoPostCatch(_ c: Catch, speciesName: String) async {
        let targets = myCrews.filter { $0.autoPost }
        guard !targets.isEmpty, joined else { return }
        for crew in targets {
            // Tag the post with the crew's live trip, if one is running.
            let trip = activeTrip(forCrew: crew.code)?.name ?? ""
            await postCatch(c, speciesName: speciesName, toCrew: crew.code, caption: "", tripName: trip)
        }
    }

    /// Create/update a crew post for a catch (used by auto-post and manual share).
    func postCatch(_ c: Catch, speciesName: String, toCrew code: String, caption: String, tripName: String = "") async {
        guard joined else { return }
        let id = CKRecord.ID(recordName: "crewpost-\(code)-\(c.id)")
        let record = (try? await db.record(for: id)) ?? CKRecord(recordType: crewPostType, recordID: id)
        record["crewCode"] = code as CKRecordValue
        record["authorCode"] = friendCode as CKRecordValue
        record["authorName"] = myName as CKRecordValue
        record["species"] = speciesName as CKRecordValue
        if let w = c.weightKg { record["weightKg"] = w as CKRecordValue }
        if let l = c.lengthCm { record["lengthCm"] = l as CKRecordValue }
        record["caughtAt"] = c.caughtAt as CKRecordValue
        record["caption"] = caption as CKRecordValue
        if !tripName.isEmpty { record["tripName"] = tripName as CKRecordValue }
        attachPhoto(c.photoPath, to: record)
        _ = try? await db.save(record)
    }

    /// Set/clear the one-line caption on a post I authored.
    func setCrewCaption(_ caption: String, postId: String) async {
        let id = CKRecord.ID(recordName: postId)
        guard let r = try? await db.record(for: id) else { return }
        r["caption"] = caption as CKRecordValue
        _ = try? await db.save(r)
    }

    /// Toggle my reaction on a post: same emoji removes it, a different emoji
    /// replaces it (one reaction per member per post).
    func toggleCrewReaction(emoji: String, postId: String, crewCode: String,
                            postAuthorCode: String) async {
        let id = CKRecord.ID(recordName: "crewreact-\(postId)-\(friendCode)")
        if let existing = try? await db.record(for: id) {
            if (existing["emoji"] as? String) == emoji {
                _ = try? await db.deleteRecord(withID: id)
                return
            }
            existing["emoji"] = emoji as CKRecordValue
            _ = try? await db.save(existing)
            return
        }
        let record = CKRecord(recordType: crewReactionType, recordID: id)
        record["postId"] = postId as CKRecordValue
        record["crewCode"] = crewCode as CKRecordValue
        // Denormalised so the post owner's "someone reacted to your catch"
        // subscription can match it (CloudKit predicates can't join to the post).
        record["postAuthorCode"] = postAuthorCode as CKRecordValue
        record["reactorCode"] = friendCode as CKRecordValue
        record["reactorName"] = myName as CKRecordValue
        record["emoji"] = emoji as CKRecordValue
        record["createdAt"] = Date() as CKRecordValue
        if (try? await db.save(record)) == nil {
            // Production rejects undeclared fields until the schema import
            // deploys postAuthorCode — retry without it so reacting still
            // works today (only the reaction *push* needs the new field).
            record["postAuthorCode"] = nil
            _ = try? await db.save(record)
        }
    }

    func crewInviteLink(code: String, name: String) -> URL {
        var comps = URLComponents(string: Self.webBase)!
        comps.queryItems = [URLQueryItem(name: "c", value: code)]
        if !name.isEmpty { comps.queryItems?.append(URLQueryItem(name: "n", value: name)) }
        return comps.url!
    }

    func crewInviteMessage(code: String, name: String) -> String {
        """
        Join my crew “\(name)” on Currents 🎣 — we share our catches here.
        \(crewInviteLink(code: code, name: name).absoluteString)
        …or open Currents › Community › New Crew › Join and enter code \(code).
        """
    }

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
        /// The Crew this trip belongs to, if started from one.
        var crewCode: String? = nil
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
        /// The Crew this trip belongs to, if it was started from one. Optional so
        /// old stored refs decode fine and standalone trips stay unlinked.
        var crewCode: String? = nil
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
        scheduleEventSubSync()
    }

    private func forgetGroup(code: String) {
        myGroups = myGroups.filter { $0.code != code }
        scheduleEventSubSync()
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
        …or open Currents › Community › Group Trips › Start or join a trip and enter code \(code).
        """
    }

    /// Ensure the angler has a community identity so group records carry a name.
    /// Host creates a shared trip and returns its join code. Pass `crewCode` to
    /// tie the trip to a Crew (its live banner + trip-tagged feed posts).
    @discardableResult
    func createGroupTrip(name: String, tripId: String, crewCode: String? = nil) async -> String? {
        guard joined else { return nil }
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let code = String((0..<6).map { _ in chars[Int.random(in: 0..<chars.count)] })
        let id = CKRecord.ID(recordName: "grouptrip-\(code)")
        let record = CKRecord(recordType: groupTripType, recordID: id)
        record["code"] = code as CKRecordValue
        record["name"] = name as CKRecordValue
        record["hostCode"] = friendCode as CKRecordValue
        record["hostName"] = myName as CKRecordValue
        record["createdAt"] = Date() as CKRecordValue
        if let crewCode { record["crewCode"] = crewCode as CKRecordValue }
        guard (try? await db.save(record)) != nil else { return nil }
        await addMembership(code: code)
        setGroupCode(code, forTripId: tripId)
        rememberGroup(GroupRef(code: code, name: name, hostName: myName, isHost: true,
                               joinedAt: Date(), crewCode: crewCode))
        return code
    }

    /// Join a shared trip by code (from a link or manual entry). Returns the
    /// trip if it exists. Optionally links it to a local trip id.
    @discardableResult
    func joinGroupTrip(code raw: String, tripId: String? = nil) async -> GroupTrip? {
        guard joined else { return nil }
        let code = raw.uppercased().trimmingCharacters(in: .whitespaces)
        guard code.count == 6, let trip = await groupTrip(code: code) else { return nil }
        await addMembership(code: code)
        if let tripId { setGroupCode(code, forTripId: tripId) }
        rememberGroup(GroupRef(code: code, name: trip.name, hostName: trip.hostName,
                               isHost: trip.isHost, joinedAt: Date(), crewCode: trip.crewCode))
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
            endedAt: endedAt,
            crewCode: r["crewCode"] as? String
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
            // Drops the trip's catch subscription now that it's over.
            scheduleEventSubSync()
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
        // When the HOST leaves, END the trip rather than deleting it. A
        // deleted record left members staring at a live-looking trip that no
        // longer existed and could never resolve (endedAt was only ever set
        // on a record that still exists).
        if wasHost {
            if let r = try? await db.record(for: CKRecord.ID(recordName: "grouptrip-\(code)")) {
                r["endedAt"] = Date() as CKRecordValue
                _ = try? await db.save(r)
            }
        }
        groupCatchCache[code] = nil
        groupMemberCache[code] = nil
        let linked = tripId ?? self.tripId(forGroupCode: code)
        if let linked { setGroupCode(nil, forTripId: linked) }
        forgetGroup(code: code)
    }

    /// The crew's live trip as the SERVER sees it. `activeTrip(forCrew:)` only
    /// knows trips this device joined, so crewmates who hadn't joined yet never
    /// saw the "live" banner — the whole join-mid-trip flow was invisible.
    func liveCrewTrip(crewCode: String) async -> GroupTrip? {
        let q = CKQuery(recordType: groupTripType,
                        predicate: NSPredicate(format: "crewCode == %@", crewCode))
        guard let res = try? await db.records(matching: q, resultsLimit: 25) else { return nil }
        let trips: [GroupTrip] = res.matchResults.compactMap { _, r in
            guard let rec = try? r.get(), let code = rec["code"] as? String else { return nil }
            return GroupTrip(id: code,
                             name: rec["name"] as? String ?? "Group Trip",
                             hostCode: rec["hostCode"] as? String ?? "",
                             hostName: rec["hostName"] as? String ?? "",
                             createdAt: rec["createdAt"] as? Date ?? .distantPast,
                             isHost: (rec["hostCode"] as? String) == friendCode,
                             endedAt: rec["endedAt"] as? Date,
                             crewCode: crewCode)
        }
        return trips.filter { !$0.isEnded }.max { $0.createdAt < $1.createdAt }
    }

    /// If this local session was linked to a group trip I host, end the shared
    /// trip too. Hosts used to have to remember a separate "End trip for
    /// everyone" step that nothing prompted — ending the session is the
    /// natural end of the trip.
    func endLinkedGroupTrip(forLocalTripId id: String) async {
        guard joined,
              let code = groupCode(forTripId: id),
              let ref = myGroups.first(where: { $0.code == code }),
              ref.isHost, ref.endedAt == nil else { return }
        await endGroupTrip(code: code)
    }

    /// Rebuild crew/trip membership from the server. `myCrews`/`myGroups` are
    /// local caches, so a reinstall or new device showed no memberships while
    /// the server still counted (and pushed to) this angler. Once per launch.
    private var reconciledThisLaunch = false
    func reconcileMemberships() async {
        guard joined, !reconciledThisLaunch else { return }
        reconciledThisLaunch = true
        let cq = CKQuery(recordType: crewMemberType,
                         predicate: NSPredicate(format: "memberCode == %@", friendCode))
        if let res = try? await db.records(matching: cq, resultsLimit: 100) {
            for (_, r) in res.matchResults {
                guard let rec = try? r.get(), let code = rec["crewCode"] as? String,
                      !myCrews.contains(where: { $0.code == code }),
                      let crew = await fetchCrew(code: code) else { continue }
                rememberCrew(crew)
            }
        }
        let gq = CKQuery(recordType: groupMemberType,
                         predicate: NSPredicate(format: "memberCode == %@", friendCode))
        if let res = try? await db.records(matching: gq, resultsLimit: 100) {
            for (_, r) in res.matchResults {
                guard let rec = try? r.get(), let code = rec["groupCode"] as? String,
                      !myGroups.contains(where: { $0.code == code }),
                      let trip = await groupTrip(code: code) else { continue }
                rememberGroup(GroupRef(code: code, name: trip.name, hostName: trip.hostName,
                                       isHost: trip.isHost, joinedAt: Date(),
                                       endedAt: trip.endedAt, crewCode: trip.crewCode))
            }
        }
    }

    /// Publish a catch straight into a group's live feed even when it isn't tied
    /// to a local tracked session — used by the "Log to trip" action so a
    /// member's catch always reaches the group.
    func publishGroupCatch(species: String, weightKg: Double?, lengthCm: Double?,
                           catchId: String, groupCode: String) async {
        guard joined else { return }
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
        // Verify the code belongs to a real angler before claiming success —
        // the failure copy promises "Couldn't find that code", so keep it true.
        guard await fetchProfile(code: toCode) != nil else { return false }
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
        // Apply my sharing prefs (global, or this friend's override) to them.
        await updateCatchGrant(for: req.fromCode, share: privacy(for: req.fromCode).shareCatches)
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
                await updateCatchGrant(for: toCode, share: privacy(for: toCode).shareCatches)
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
        // Crew/trip subscriptions — forced so baked-in crew names stay fresh.
        await syncEventSubscriptions(force: true)
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
        await syncEventSubscriptions(force: true)
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
    var eventSubsError: String? { UserDefaults.standard.string(forKey: "eventSubsError") }
    /// True once the crew/trip subscriptions have completed a successful sync.
    var eventSubscriptionsSynced: Bool {
        UserDefaults.standard.string(forKey: "eventSubsFingerprint") != nil && eventSubsError == nil
    }

    // MARK: - Event push subscriptions (crews + live trips)
    //
    // Unlike the friend-request/invite subscriptions above (fixed set, keyed
    // only on my code), these come and go with membership: one per crew for
    // new posts, one per crew for a trip going live, one per still-live group
    // trip for members' catches, and a single one for reactions to my posts.
    // CloudKit sends the APNs push itself when a matching record lands — no
    // server of ours involved. Every one also carries content-available, so
    // delivery quietly wakes the app to pre-warm the crew feed cache.

    /// The dynamic subscriptions this device should hold right now.
    private func desiredEventSubscriptions() -> [CKQuerySubscription] {
        guard joined else { return [] }

        func info(title: String, key: String, args: [String],
                  desiredKeys: [CKRecord.FieldKey]) -> CKSubscription.NotificationInfo {
            let n = CKSubscription.NotificationInfo()
            n.title = title
            n.alertLocalizationKey = key
            n.alertLocalizationArgs = args
            n.soundName = "default"
            n.shouldBadge = true
            // Wake the app in the background as well as showing the alert, so
            // the relevant feed is already fresh when the user opens it.
            n.shouldSendContentAvailable = true
            // Included in the payload so the app can drop self-authored events
            // (CloudKit predicates can't express `authorCode != me`).
            n.desiredKeys = desiredKeys
            return n
        }

        var subs: [CKQuerySubscription] = []

        // Reactions to my posts — one subscription regardless of crew count.
        // Fires on update too, since changing your emoji edits the record.
        let react = CKQuerySubscription(
            recordType: crewReactionType,
            predicate: NSPredicate(format: "postAuthorCode == %@", friendCode),
            subscriptionID: "ev-react-\(friendCode)",
            options: [.firesOnRecordCreation, .firesOnRecordUpdate])
        react.notificationInfo = info(
            title: "Your catch got a reaction",
            key: "%1$@ reacted %2$@ to your catch",
            args: ["reactorName", "emoji"],
            desiredKeys: ["reactorCode", "crewCode"])
        subs.append(react)

        for crew in myCrews {
            // Someone posted a catch to this crew's feed.
            let posts = CKQuerySubscription(
                recordType: crewPostType,
                predicate: NSPredicate(format: "crewCode == %@", crew.code),
                subscriptionID: "ev-posts-\(crew.code)",
                options: [.firesOnRecordCreation])
            posts.notificationInfo = info(
                title: "\(crew.emoji) \(crew.name)",
                key: "%1$@ landed a %2$@ 🎣",
                args: ["authorName", "species"],
                desiredKeys: ["authorCode", "crewCode"])
            subs.append(posts)

            // A live trip just started in this crew.
            let trips = CKQuerySubscription(
                recordType: groupTripType,
                predicate: NSPredicate(format: "crewCode == %@", crew.code),
                subscriptionID: "ev-trip-\(crew.code)",
                options: [.firesOnRecordCreation])
            trips.notificationInfo = info(
                title: "\(crew.emoji) \(crew.name)",
                key: "%1$@ started a live trip — jump in",
                args: ["hostName"],
                desiredKeys: ["hostCode", "crewCode"])
            subs.append(trips)
        }

        // Catches landing on group trips I'm on that are still live. Fires on
        // update too: sharing an already-published catch tags the existing
        // leaderboard record rather than creating one.
        for g in myGroups where g.endedAt == nil {
            let catches = CKQuerySubscription(
                recordType: catchType,
                predicate: NSPredicate(format: "groupCode == %@", g.code),
                subscriptionID: "ev-tripcatch-\(g.code)",
                options: [.firesOnRecordCreation, .firesOnRecordUpdate])
            catches.notificationInfo = info(
                title: g.name,
                key: "%1$@ just landed a %2$@ on the trip!",
                args: ["anglerName", "species"],
                desiredKeys: ["friendCode", "groupCode"])
            subs.append(catches)
        }

        return subs
    }

    /// Reconcile the dynamic subscriptions against the server: create what's
    /// missing, delete what no longer applies (left crew, trip ended). Cheap
    /// no-op when membership hasn't changed since the last successful sync.
    /// `force` rebuilds everything — also refreshes baked-in crew names.
    func syncEventSubscriptions(force: Bool = false) async {
        guard joined else { return }
        let desired = desiredEventSubscriptions()
        let fingerprint = desired.map(\.subscriptionID).sorted().joined(separator: ",")
        if !force, UserDefaults.standard.string(forKey: "eventSubsFingerprint") == fingerprint {
            return
        }
        do {
            let existing = try await db.allSubscriptions()
                .map(\.subscriptionID)
                .filter { $0.hasPrefix("ev-") }
            let desiredIDs = Set(desired.map(\.subscriptionID))
            let stale = existing.filter { !desiredIDs.contains($0) }
            let existingSet = Set(existing)
            let saving = force ? desired : desired.filter { !existingSet.contains($0.subscriptionID) }
            if !saving.isEmpty || !stale.isEmpty {
                _ = try await db.modifySubscriptions(saving: saving, deleting: stale)
            }
            UserDefaults.standard.set(fingerprint, forKey: "eventSubsFingerprint")
            UserDefaults.standard.removeObject(forKey: "eventSubsError")
        } catch {
            // Schema not deployed / offline — retried on the next membership
            // change or push re-enable.
            UserDefaults.standard.set(error.localizedDescription, forKey: "eventSubsError")
        }
    }

    /// Fire-and-forget wrapper for the synchronous membership mutation points.
    private func scheduleEventSubSync() {
        Task { await self.syncEventSubscriptions() }
    }
}
