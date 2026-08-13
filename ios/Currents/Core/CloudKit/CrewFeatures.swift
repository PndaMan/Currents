import Foundation
import CloudKit
import UIKit

// MARK: - Crew roles

/// Crew hierarchy. Captain is the creator (implicit, immutable); Mates have
/// every power including identity and role management; Admins moderate
/// (delete posts, remove members). Enforced in-app — CloudKit grants are
/// opened to signed-in users to make moderation possible at all.
enum CrewRole: String, Codable, CaseIterable, Identifiable {
    case captain, mate, admin, member
    var id: String { rawValue }

    var label: String {
        switch self {
        case .captain: "Captain"
        case .mate:    "Mate"
        case .admin:   "Admin"
        case .member:  "Member"
        }
    }
    var icon: String {
        switch self {
        case .captain: "crown.fill"
        case .mate:    "star.fill"
        case .admin:   "shield.fill"
        case .member:  "person.fill"
        }
    }
    /// Delete others' posts, remove members.
    var canModerate: Bool { self != .member }
    /// Rename crew, change emoji/photo/banner, promote & demote.
    var canManage: Bool { self == .captain || self == .mate }
    /// Start tournaments.
    var canRunTournaments: Bool { self != .member }
}

extension CommunityService {

    /// This crew's role for an arbitrary member code.
    func role(of memberCode: String, in crew: Crew) -> CrewRole {
        if memberCode == crew.createdByCode { return .captain }
        if crew.mates.contains(memberCode) { return .mate }
        if crew.admins.contains(memberCode) { return .admin }
        return .member
    }

    func myRole(in crew: Crew) -> CrewRole { role(of: friendCode, in: crew) }

    /// Promote/demote a member. Captain may set any role; Mates may only
    /// grant/revoke Admin. Writes the role lists onto the Crew record.
    func setRole(_ newRole: CrewRole, for memberCode: String, in crew: Crew) async -> Crew? {
        let mine = myRole(in: crew)
        guard memberCode != crew.createdByCode else { return nil }        // captain immutable
        guard mine == .captain || (mine == .mate && newRole != .mate) else { return nil }

        var mates = crew.mates.filter { $0 != memberCode }
        var admins = crew.admins.filter { $0 != memberCode }
        switch newRole {
        case .mate:  mates.append(memberCode)
        case .admin: admins.append(memberCode)
        default: break
        }
        let id = CKRecord.ID(recordName: "crew-\(crew.code)")
        guard let r = try? await db.record(for: id) else { return nil }
        r["mates"] = encodeCodes(mates) as CKRecordValue
        r["admins"] = encodeCodes(admins) as CKRecordValue
        guard (try? await db.save(r)) != nil else { return nil }
        var updated = crew
        updated.mates = mates
        updated.admins = admins
        return updated
    }

    private func encodeCodes(_ codes: [String]) -> String {
        String(data: (try? JSONEncoder().encode(codes)) ?? Data("[]".utf8), encoding: .utf8) ?? "[]"
    }

    /// Captain only: hand the crew to another member. The old captain stays
    /// aboard as a Mate so nothing they were running breaks mid-trip.
    func transferCaptaincy(to memberCode: String, name: String, in crew: Crew) async -> Crew? {
        guard myRole(in: crew) == .captain, memberCode != friendCode else { return nil }
        let id = CKRecord.ID(recordName: "crew-\(crew.code)")
        guard let r = try? await db.record(for: id) else { return nil }
        var mates = crew.mates.filter { $0 != memberCode }
        let admins = crew.admins.filter { $0 != memberCode }
        mates.append(friendCode)
        r["createdByCode"] = memberCode as CKRecordValue
        r["createdByName"] = name as CKRecordValue
        r["mates"] = encodeCodes(mates) as CKRecordValue
        r["admins"] = encodeCodes(admins) as CKRecordValue
        guard (try? await db.save(r)) != nil else { return nil }
        var updated = crew
        updated.createdByCode = memberCode
        updated.createdByName = name
        updated.mates = mates
        updated.admins = admins
        return updated
    }

    /// Remove a member from the crew (moderator power).
    func removeMember(_ memberCode: String, fromCrew crew: Crew) async -> Bool {
        guard myRole(in: crew).canModerate, memberCode != crew.createdByCode else { return false }
        let id = CKRecord.ID(recordName: "crewmember-\(crew.code)-\(memberCode)")
        return (try? await db.deleteRecord(withID: id)) != nil
    }

    /// Delete a post — the author always may; moderators may for anyone.
    func deleteCrewPost(_ post: CrewPost, in crew: Crew) async -> Bool {
        guard post.authorCode == friendCode || myRole(in: crew).canModerate else { return false }
        let ok = (try? await db.deleteRecord(withID: CKRecord.ID(recordName: post.id))) != nil
        if ok {
            var cached = CommunityDiskCache.loadFeed(crew.code)
            cached.removeAll { $0.id == post.id }
            CommunityDiskCache.saveFeed(cached, for: crew.code)
        }
        return ok
    }

    // MARK: - Crew identity (name / emoji / photo icon / banner)

    /// Update the crew's identity. Captain/Mates only. Pass nil to leave a
    /// field unchanged; pass `removeBanner`/`removeIcon` to clear assets.
    func updateCrewIdentity(_ crew: Crew, name: String? = nil, emoji: String? = nil,
                            banner: UIImage? = nil, iconPhoto: UIImage? = nil,
                            removeBanner: Bool = false, removeIcon: Bool = false) async -> Bool {
        guard myRole(in: crew).canManage else { return false }
        let id = CKRecord.ID(recordName: "crew-\(crew.code)")
        guard let r = try? await db.record(for: id) else { return false }
        if let name { r["name"] = name as CKRecordValue }
        if let emoji { r["emoji"] = emoji as CKRecordValue }
        if removeBanner { r["banner"] = nil }
        else if let banner { r["banner"] = Self.asset(banner, maxSide: 1400) }
        if removeIcon { r["iconPhoto"] = nil }
        else if let iconPhoto { r["iconPhoto"] = Self.asset(iconPhoto, maxSide: 400) }
        let ok = (try? await db.save(r)) != nil
        if ok {
            if let banner { CommunityDiskCache.saveImage(banner, key: "crewbanner-\(crew.code)") }
            if removeBanner { CommunityDiskCache.deleteImage(key: "crewbanner-\(crew.code)") }
            if let iconPhoto { CommunityDiskCache.saveImage(iconPhoto, key: "crewicon-\(crew.code)") }
            if removeIcon { CommunityDiskCache.deleteImage(key: "crewicon-\(crew.code)") }
        }
        return ok
    }

    /// Banner + photo icon, served from disk instantly and refreshed from the
    /// server at most once per hour.
    func crewArt(code: String, forceRefresh: Bool = false) async -> (banner: UIImage?, icon: UIImage?) {
        let cachedBanner = CommunityDiskCache.loadImage(key: "crewbanner-\(code)")
        let cachedIcon = CommunityDiskCache.loadImage(key: "crewicon-\(code)")
        let fresh = CommunityDiskCache.isFresh(key: "crewart-\(code)", maxAge: 3600)
        if !forceRefresh, fresh, cachedBanner != nil || cachedIcon != nil {
            return (cachedBanner, cachedIcon)
        }
        guard let r = try? await db.record(for: CKRecord.ID(recordName: "crew-\(code)")) else {
            return (cachedBanner, cachedIcon)
        }
        var banner = cachedBanner, icon = cachedIcon
        if let a = r["banner"] as? CKAsset, let url = a.fileURL,
           let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
            banner = img
            CommunityDiskCache.saveImage(img, key: "crewbanner-\(code)")
        }
        if let a = r["iconPhoto"] as? CKAsset, let url = a.fileURL,
           let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
            icon = img
            CommunityDiskCache.saveImage(img, key: "crewicon-\(code)")
        }
        CommunityDiskCache.touch(key: "crewart-\(code)")
        return (banner, icon)
    }

    static func asset(_ image: UIImage, maxSide: CGFloat) -> CKAsset? {
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let data = resized.jpegData(compressionQuality: 0.82) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ck-\(UUID().uuidString).jpg")
        try? data.write(to: url)
        return CKAsset(fileURL: url)
    }

    // MARK: - Paginated crew feed

    /// One page of the crew feed, newest first. Pass the oldest date you have
    /// as `before` to load the next page — no more loading 1,000 posts to
    /// show the first screen.
    func crewFeedPage(code: String, before: Date? = nil, limit: Int = 30) async -> [CrewPost] {
        var predicate = NSPredicate(format: "crewCode == %@", code)
        if let before {
            predicate = NSPredicate(format: "crewCode == %@ AND caughtAt < %@", code, before as NSDate)
        }
        let query = CKQuery(recordType: crewPostType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "caughtAt", ascending: false)]
        guard let results = try? await db.records(
            matching: query,
            desiredKeys: ["crewCode", "authorCode", "authorName", "species", "weightKg",
                          "lengthCm", "caughtAt", "caption", "hasPhoto", "tripName"],
            resultsLimit: limit) else {
            // Offline: first page comes from disk so the crew still opens.
            return before == nil ? CommunityDiskCache.loadFeed(code) : []
        }
        var posts = results.matchResults.compactMap { id, res -> CrewPost? in
            guard let r = try? res.get() else { return nil }
            return CrewPost(
                id: id.recordName,
                crewCode: code,
                authorCode: r["authorCode"] as? String ?? "",
                authorName: r["authorName"] as? String ?? "Angler",
                species: r["species"] as? String ?? "Fish",
                weightKg: r["weightKg"] as? Double,
                lengthCm: r["lengthCm"] as? Double,
                caughtAt: r["caughtAt"] as? Date ?? .distantPast,
                caption: r["caption"] as? String ?? "",
                hasPhoto: (r["hasPhoto"] as? Int64 ?? 0) == 1,
                tripName: r["tripName"] as? String ?? "")
        }
        // Reactions for this crew (single indexed query, grouped per post).
        let rq = CKQuery(recordType: crewReactionType,
                         predicate: NSPredicate(format: "crewCode == %@", code))
        if let rr = try? await db.records(matching: rq, resultsLimit: 400) {
            var byPost: [String: [CrewReaction]] = [:]
            for (_, res) in rr.matchResults {
                guard let r = try? res.get(),
                      let postId = r["postId"] as? String,
                      let emoji = r["emoji"] as? String else { continue }
                byPost[postId, default: []].append(
                    CrewReaction(id: r.recordID.recordName,
                                 reactorCode: r["reactorCode"] as? String ?? "",
                                 reactorName: r["reactorName"] as? String ?? "",
                                 emoji: emoji))
            }
            for i in posts.indices { posts[i].reactions = byPost[posts[i].id] ?? [] }
        }
        // Comment counts for the 💬 badge — one indexed query for the crew.
        let counts = await commentCounts(crewCode: code)
        if !counts.isEmpty {
            for i in posts.indices { posts[i].commentCount = counts[posts[i].id] ?? 0 }
        }
        if before == nil {
            CommunityDiskCache.saveFeed(posts, for: code)
        }
        return posts
    }

    // MARK: - Post comments

    struct CrewComment: Identifiable, Equatable, Codable {
        let id: String            // crewcomment-<postId suffix>-<uuid>
        let postId: String
        let crewCode: String
        let authorCode: String
        let authorName: String
        var text: String
        let createdAt: Date
    }

    var crewCommentType: String { "CrewComment" }

    /// All comments on one post, oldest first (conversation order).
    func comments(postId: String) async -> [CrewComment] {
        let q = CKQuery(recordType: crewCommentType,
                        predicate: NSPredicate(format: "postId == %@", postId))
        guard let res = try? await db.records(matching: q, resultsLimit: 200) else {
            return CommunityDiskCache.load([CrewComment].self, key: "comments-\(postId)") ?? []
        }
        let list: [CrewComment] = res.matchResults.compactMap { id, r in
            guard let rec = try? r.get() else { return nil }
            return CrewComment(id: id.recordName,
                               postId: postId,
                               crewCode: rec["crewCode"] as? String ?? "",
                               authorCode: rec["authorCode"] as? String ?? "",
                               authorName: rec["authorName"] as? String ?? "Angler",
                               text: rec["text"] as? String ?? "",
                               createdAt: rec["createdAt"] as? Date ?? .distantPast)
        }.sorted { $0.createdAt < $1.createdAt }
        CommunityDiskCache.save(list, key: "comments-\(postId)")
        return list
    }

    /// Comment counts for a whole crew in one indexed query, keyed by postId —
    /// powers the 💬 badge on feed cards without per-post fetches.
    func commentCounts(crewCode: String) async -> [String: Int] {
        let q = CKQuery(recordType: crewCommentType,
                        predicate: NSPredicate(format: "crewCode == %@", crewCode))
        guard let res = try? await db.records(matching: q, desiredKeys: ["postId"],
                                              resultsLimit: 800) else { return [:] }
        var counts: [String: Int] = [:]
        for (_, r) in res.matchResults {
            if let rec = try? r.get(), let pid = rec["postId"] as? String {
                counts[pid, default: 0] += 1
            }
        }
        return counts
    }

    @discardableResult
    func addComment(_ text: String, post: CrewPost) async -> CrewComment? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cloudAllowed, !clean.isEmpty else { return nil }
        let name = "crewcomment-\(UUID().uuidString)"
        let record = CKRecord(recordType: crewCommentType,
                              recordID: CKRecord.ID(recordName: name))
        record["postId"] = post.id as CKRecordValue
        record["crewCode"] = post.crewCode as CKRecordValue
        record["authorCode"] = friendCode as CKRecordValue
        record["authorName"] = myName as CKRecordValue
        record["text"] = clean as CKRecordValue
        record["createdAt"] = Date() as CKRecordValue
        guard (try? await db.save(record)) != nil else { return nil }
        return CrewComment(id: name, postId: post.id, crewCode: post.crewCode,
                           authorCode: friendCode, authorName: myName,
                           text: clean, createdAt: .now)
    }

    /// Delete a comment — the author always may; moderators may for anyone.
    func deleteComment(_ comment: CrewComment, in crew: Crew?) async -> Bool {
        let mayModerate = crew.map { myRole(in: $0).canModerate } ?? false
        guard comment.authorCode == friendCode || mayModerate else { return false }
        return (try? await db.deleteRecord(withID: CKRecord.ID(recordName: comment.id))) != nil
    }

    /// A crew-post photo, cached to disk so scrolling back through the feed
    /// never re-downloads assets.
    func crewPostImage(recordName: String) async -> UIImage? {
        if let cached = CommunityDiskCache.loadImage(key: "post-\(recordName)") { return cached }
        guard let img = await crewPostPhoto(recordName: recordName) else { return nil }
        CommunityDiskCache.saveImage(img, key: "post-\(recordName)")
        return img
    }

    /// Batch profile fetch: disk-fresh entries return instantly, the rest load
    /// concurrently (the old paths fetched one at a time, sequentially).
    func profiles(for codes: [String], maxAge: TimeInterval = 1800) async -> [String: Profile] {
        var out: [String: Profile] = [:]
        var toFetch: [String] = []
        for code in codes {
            if CommunityDiskCache.isFresh(key: "profile-\(code)", maxAge: maxAge),
               let cached = cachedProfiles(for: [code]).first {
                out[code] = cached
            } else {
                toFetch.append(code)
            }
        }
        await withTaskGroup(of: (String, Profile?).self) { group in
            for code in toFetch {
                group.addTask { (code, await self.fetchProfile(code: code)) }
            }
            for await (code, p) in group {
                if let p {
                    out[code] = p
                    CommunityDiskCache.touch(key: "profile-\(code)")
                } else if let stale = cachedProfiles(for: [code]).first {
                    out[code] = stale
                }
            }
        }
        return out
    }
}

// MARK: - Disk cache

/// Small JSON + image cache in Caches/ so every community screen renders
/// instantly from the last-seen state and refreshes in the background.
/// The system may evict it under pressure — everything here is re-fetchable.
enum CommunityDiskCache {
    private static var dir: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("community", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: dir.appendingPathComponent("\(key).json"))
        touch(key: key)
    }
    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("\(key).json")) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func saveImage(_ image: UIImage, key: String) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        try? data.write(to: dir.appendingPathComponent("\(key).jpg"))
    }
    static func loadImage(key: String) -> UIImage? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("\(key).jpg")) else { return nil }
        return UIImage(data: data)
    }
    static func deleteImage(key: String) {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(key).jpg"))
    }

    // Freshness stamps, so callers can serve cache-and-refresh with a TTL.
    static func touch(key: String) {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "cdc-\(key)")
    }
    static func isFresh(key: String, maxAge: TimeInterval) -> Bool {
        Date().timeIntervalSince1970 - UserDefaults.standard.double(forKey: "cdc-\(key)") < maxAge
    }

    // Typed helpers for the crew feed.
    static func saveFeed(_ posts: [CommunityService.CrewPost], for code: String) {
        save(Array(posts.prefix(30)), key: "feed-\(code)")
    }
    static func loadFeed(_ code: String) -> [CommunityService.CrewPost] {
        load([CommunityService.CrewPost].self, key: "feed-\(code)") ?? []
    }
}

// MARK: - Tournaments

extension CommunityService {
    static let tournamentType = "Tournament"

    struct Tournament: Identifiable, Equatable, Codable {
        let id: String            // 6-char code
        var name: String
        var crewCode: String
        var hostCode: String
        var hostName: String
        var createdAt: Date
        var endsAt: Date?
        var endedAt: Date?
        var winnerTeam: String?
        /// Custom scoring set by the admin at creation. Nil (older records and
        /// caches) falls back to the standard rates.
        var pointsPerFish: Int?
        var pointsPerKg: Int?
        var speciesBonus: Int?
        var isEnded: Bool { endedAt != nil }
        var rates: TournamentPoints.Rates {
            .init(perFish: pointsPerFish ?? TournamentPoints.standard.perFish,
                  perKg: pointsPerKg ?? TournamentPoints.standard.perKg,
                  newSpeciesBonus: speciesBonus ?? TournamentPoints.standard.newSpeciesBonus)
        }
    }

    /// A team = one live session inside the tournament, plus its tally.
    struct TeamStanding: Identifiable {
        let id: String            // the team session's group code
        var teamName: String
        var points: Int
        var fishCount: Int
        var totalWeightKg: Double
        var speciesCount: Int
        var memberCodes: [String]
        var isEnded: Bool
        /// Who started the team's session — shown on the team card.
        var hostCode: String = ""
        var hostName: String = ""
        /// Every catch the team has logged, newest first — powers the
        /// tournament highlights without a second fetch.
        var catches: [GroupCatch] = []
    }

    /// A headline moment (most fish / biggest / first), computed from every
    /// team's catches for the tournament page.
    struct TournamentHighlight: Identifiable {
        let id: String
        let title: String
        let icon: String
        let anglerCode: String
        let anglerName: String
        let teamName: String
        let detail: String
    }

    /// The three headline moments, when there are catches to headline.
    static func tournamentHighlights(from standings: [TeamStanding]) -> [TournamentHighlight] {
        let all: [(team: String, c: GroupCatch)] = standings.flatMap { s in
            s.catches.map { (s.teamName, $0) }
        }
        guard !all.isEmpty else { return [] }
        var out: [TournamentHighlight] = []
        let byAngler = Dictionary(grouping: all, by: { $0.c.friendCode })
        if let top = byAngler.values.max(by: { $0.count < $1.count }), let first = top.first {
            out.append(.init(id: "most-fish", title: "Most fish", icon: "fish.fill",
                             anglerCode: first.c.friendCode, anglerName: first.c.anglerName,
                             teamName: first.team, detail: "\(top.count) fish"))
        }
        if let big = all.max(by: { ($0.c.weightKg ?? 0) < ($1.c.weightKg ?? 0) }),
           let kg = big.c.weightKg, kg > 0 {
            out.append(.init(id: "biggest", title: "Biggest fish", icon: "scalemass.fill",
                             anglerCode: big.c.friendCode, anglerName: big.c.anglerName,
                             teamName: big.team, detail: "\(big.c.species) · \(Units.weight(kg: kg))"))
        }
        if let first = all.min(by: { $0.c.date < $1.c.date }) {
            out.append(.init(id: "first", title: "First fish", icon: "bolt.fill",
                             anglerCode: first.c.friendCode, anglerName: first.c.anglerName,
                             teamName: first.team,
                             detail: "\(first.c.species) · \(first.c.date.formatted(date: .omitted, time: .shortened))"))
        }
        return out
    }

    private static func tournament(from rec: CKRecord, crewCode: String) -> Tournament? {
        guard let code = rec["code"] as? String else { return nil }
        return Tournament(id: code,
                          name: rec["name"] as? String ?? "Tournament",
                          crewCode: crewCode,
                          hostCode: rec["hostCode"] as? String ?? "",
                          hostName: rec["hostName"] as? String ?? "",
                          createdAt: rec["createdAt"] as? Date ?? .distantPast,
                          endsAt: rec["endsAt"] as? Date,
                          endedAt: rec["endedAt"] as? Date,
                          winnerTeam: rec["winnerTeam"] as? String,
                          pointsPerFish: (rec["pointsPerFish"] as? Int64).map(Int.init),
                          pointsPerKg: (rec["pointsPerKg"] as? Int64).map(Int.init),
                          speciesBonus: (rec["speciesBonus"] as? Int64).map(Int.init))
    }

    /// Every tournament the crew has run, newest first — the history hub, so
    /// the crew page itself only ever carries the active one. Client-sorted
    /// (the record type has no sortable index) and disk-cached.
    func tournaments(crewCode: String, limit: Int = 200) async -> [Tournament] {
        let q = CKQuery(recordType: Self.tournamentType,
                        predicate: NSPredicate(format: "crewCode == %@", crewCode))
        guard let res = try? await db.records(matching: q, resultsLimit: limit) else {
            return CommunityDiskCache.load([Tournament].self, key: "tournaments-\(crewCode)") ?? []
        }
        let list: [Tournament] = res.matchResults.compactMap { _, r in
            guard let rec = try? r.get() else { return nil }
            return Self.tournament(from: rec, crewCode: crewCode)
        }.sorted { $0.createdAt > $1.createdAt }
        CommunityDiskCache.save(list, key: "tournaments-\(crewCode)")
        return list
    }

    /// Admins only. Teams are created as members join. Scoring rates default
    /// to the standard rules; admins can tune them in the setup sheet.
    func createTournament(name: String, crew: Crew, endsAt: Date?,
                          rates: TournamentPoints.Rates = TournamentPoints.standard) async -> Tournament? {
        guard cloudAllowed, myRole(in: crew).canRunTournaments else { return nil }
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let code = String((0..<6).map { _ in chars[Int.random(in: 0..<chars.count)] })
        let record = CKRecord(recordType: Self.tournamentType,
                              recordID: CKRecord.ID(recordName: "tournament-\(code)"))
        record["code"] = code as CKRecordValue
        record["name"] = name as CKRecordValue
        record["crewCode"] = crew.code as CKRecordValue
        record["hostCode"] = friendCode as CKRecordValue
        record["hostName"] = myName as CKRecordValue
        record["createdAt"] = Date() as CKRecordValue
        if let endsAt { record["endsAt"] = endsAt as CKRecordValue }
        record["pointsPerFish"] = rates.perFish as CKRecordValue
        record["pointsPerKg"] = rates.perKg as CKRecordValue
        record["speciesBonus"] = rates.newSpeciesBonus as CKRecordValue
        var saved = rates
        if (try? await db.save(record)) == nil {
            // Production rejects undeclared fields until the schema import
            // deploys the scoring columns — fall back to standard rates so
            // starting a tournament never silently fails.
            record["pointsPerFish"] = nil
            record["pointsPerKg"] = nil
            record["speciesBonus"] = nil
            guard (try? await db.save(record)) != nil else { return nil }
            saved = TournamentPoints.standard
        }
        return Tournament(id: code, name: name, crewCode: crew.code,
                          hostCode: friendCode, hostName: myName,
                          createdAt: .now, endsAt: endsAt, endedAt: nil, winnerTeam: nil,
                          pointsPerFish: saved.perFish, pointsPerKg: saved.perKg,
                          speciesBonus: saved.newSpeciesBonus)
    }

    /// The crew's current tournament (newest un-ended), or its most recent
    /// finished one within a day — so the result screen sticks around.
    func activeTournament(crewCode: String) async -> Tournament? {
        let q = CKQuery(recordType: Self.tournamentType,
                        predicate: NSPredicate(format: "crewCode == %@", crewCode))
        guard let res = try? await db.records(matching: q, resultsLimit: 20) else {
            return CommunityDiskCache.load(Tournament.self, key: "tournament-\(crewCode)")
        }
        let all: [Tournament] = res.matchResults.compactMap { _, r in
            guard let rec = try? r.get() else { return nil }
            return Self.tournament(from: rec, crewCode: crewCode)
        }
        let live = all.filter { !$0.isEnded }.max { $0.createdAt < $1.createdAt }
        let recent = all.filter { $0.isEnded && ($0.endedAt ?? .distantPast) > Date().addingTimeInterval(-86_400) }
            .max { ($0.endedAt ?? .distantPast) < ($1.endedAt ?? .distantPast) }
        let result = live ?? recent
        if let result { CommunityDiskCache.save(result, key: "tournament-\(crewCode)") }
        return result
    }

    /// Start a NEW team in the tournament: a live session carrying the team
    /// name, which teammates then join like any group trip.
    @discardableResult
    func createTeam(named teamName: String, tournament: Tournament, localTripId: String) async -> String? {
        guard let code = await createGroupTrip(name: teamName, tripId: localTripId,
                                               crewCode: tournament.crewCode) else { return nil }
        let id = CKRecord.ID(recordName: "grouptrip-\(code)")
        if let r = try? await db.record(for: id) {
            r["tournamentCode"] = tournament.id as CKRecordValue
            r["teamName"] = teamName as CKRecordValue
            _ = try? await db.save(r)
        }
        markGroupTeam(code: code, teamName: teamName)
        return code
    }

    /// Admin: put a crewmate on a team by creating their membership record.
    /// Their device rebuilds its trip list from memberCode on the next
    /// reconcile, so the assignment shows up without them doing anything.
    func assignMember(code memberCode: String, name: String, toTeam groupCode: String) async -> Bool {
        let id = CKRecord.ID(recordName: "member-\(groupCode)-\(memberCode)")
        let record = CKRecord(recordType: groupMemberType, recordID: id)
        record["groupCode"] = groupCode as CKRecordValue
        record["memberCode"] = memberCode as CKRecordValue
        record["memberName"] = name as CKRecordValue
        record["joinedAt"] = Date() as CKRecordValue
        let ok = (try? await db.modifyRecords(saving: [record], deleting: [],
                                              savePolicy: .allKeys, atomically: false)) != nil
        // Assigning yourself registers locally right away (real trip name and
        // host via the normal join path — the membership save is idempotent).
        if ok, memberCode == friendCode {
            _ = await joinGroupTrip(code: groupCode)
        }
        return ok
    }

    /// All the tournament's teams with live points. One query for the teams,
    /// then their catches concurrently.
    func teamStandings(tournament: Tournament) async -> [TeamStanding] {
        let q = CKQuery(recordType: groupTripType,
                        predicate: NSPredicate(format: "tournamentCode == %@", tournament.id))
        guard let res = try? await db.records(matching: q, resultsLimit: 50) else { return [] }
        let teams: [(code: String, name: String, ended: Bool, hostCode: String, hostName: String)] = res.matchResults.compactMap { _, r in
            guard let rec = try? r.get(), let code = rec["code"] as? String else { return nil }
            return (code,
                    rec["teamName"] as? String ?? (rec["name"] as? String ?? "Team"),
                    rec["endedAt"] != nil,
                    rec["hostCode"] as? String ?? "",
                    rec["hostName"] as? String ?? "")
        }
        var out: [TeamStanding] = []
        await withTaskGroup(of: TeamStanding.self) { group in
            for team in teams {
                group.addTask {
                    let catches = await self.groupCatches(code: team.code)
                    let members = await self.groupMembers(code: team.code).map(\.id)
                    let score = TournamentPoints.score(
                        catches.map { (species: $0.species, weightKg: $0.weightKg) },
                        rates: tournament.rates)
                    return TeamStanding(id: team.code, teamName: team.name,
                                        points: score.points, fishCount: score.fish,
                                        totalWeightKg: score.weightKg,
                                        speciesCount: score.species,
                                        memberCodes: members, isEnded: team.ended,
                                        hostCode: team.hostCode, hostName: team.hostName,
                                        catches: catches)
                }
            }
            for await standing in group { out.append(standing) }
        }
        return out.sorted { $0.points > $1.points }
    }

    /// End the tournament and declare the winner (admins only). Also ends any
    /// team sessions still running.
    func endTournament(_ tournament: Tournament, winnerTeam: String, crew: Crew) async -> Bool {
        guard myRole(in: crew).canRunTournaments else { return false }
        let id = CKRecord.ID(recordName: "tournament-\(tournament.id)")
        guard let r = try? await db.record(for: id) else { return false }
        r["endedAt"] = Date() as CKRecordValue
        r["winnerTeam"] = winnerTeam as CKRecordValue
        guard (try? await db.save(r)) != nil else { return false }
        let q = CKQuery(recordType: groupTripType,
                        predicate: NSPredicate(format: "tournamentCode == %@", tournament.id))
        if let res = try? await db.records(matching: q, resultsLimit: 50) {
            for (_, rr) in res.matchResults {
                if let rec = try? rr.get(), rec["endedAt"] == nil {
                    rec["endedAt"] = Date() as CKRecordValue
                    _ = try? await db.save(rec)
                }
            }
        }
        CommunityDiskCache.save(
            Tournament(id: tournament.id, name: tournament.name, crewCode: tournament.crewCode,
                       hostCode: tournament.hostCode, hostName: tournament.hostName,
                       createdAt: tournament.createdAt, endsAt: tournament.endsAt,
                       endedAt: .now, winnerTeam: winnerTeam),
            key: "tournament-\(tournament.crewCode)")
        return true
    }

    /// All live, NON-tournament sessions in a crew — multiple can run at once;
    /// tournament team sessions live under the tournament hero instead.
    func liveCrewTrips(crewCode: String) async -> [GroupTrip] {
        let q = CKQuery(recordType: groupTripType,
                        predicate: NSPredicate(format: "crewCode == %@", crewCode))
        guard let res = try? await db.records(matching: q, resultsLimit: 50) else { return [] }
        return res.matchResults.compactMap { _, r -> GroupTrip? in
            guard let rec = try? r.get(), let code = rec["code"] as? String,
                  rec["endedAt"] == nil, rec["tournamentCode"] == nil else { return nil }
            return GroupTrip(id: code,
                             name: rec["name"] as? String ?? "Group Trip",
                             hostCode: rec["hostCode"] as? String ?? "",
                             hostName: rec["hostName"] as? String ?? "",
                             createdAt: rec["createdAt"] as? Date ?? .distantPast,
                             isHost: (rec["hostCode"] as? String) == friendCode,
                             endedAt: nil,
                             crewCode: crewCode)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }
}

// MARK: - Tournament points

/// Three rules, explained in the in-app info sheet. The standard rates are
/// the defaults; each tournament may carry its own (admin sets them at
/// creation and every device scores with the tournament's rates).
enum TournamentPoints {
    struct Rates: Equatable {
        var perFish: Int
        var perKg: Int
        var newSpeciesBonus: Int
    }
    static let standard = Rates(perFish: 10, perKg: 1, newSpeciesBonus: 5)

    static func score(_ catches: [(species: String, weightKg: Double?)],
                      rates: Rates = standard)
        -> (points: Int, fish: Int, weightKg: Double, species: Int) {
        var points = 0, seen = Set<String>(), weight = 0.0
        for c in catches {
            points += rates.perFish
            if let w = c.weightKg {
                points += Int(w.rounded()) * rates.perKg
                weight += w
            }
            if seen.insert(c.species.lowercased()).inserted {
                points += rates.newSpeciesBonus
            }
        }
        return (points, catches.count, weight, seen.count)
    }

    static func explanation(rates: Rates = standard) -> String {
        var out = """
        How points work:
        • \(rates.perFish) points for every fish landed
        • +\(rates.perKg) point\(rates.perKg == 1 ? "" : "s") per kilogram of each fish (rounded)
        • +\(rates.newSpeciesBonus) points the first time your team lands a new species

        Points update live as catches are logged. When the tournament ends, an \
        admin confirms the winner — the top team is highlighted, but the call is \
        theirs.
        """
        if rates != standard {
            out += "\n\nThis tournament uses custom scoring set by its host."
        }
        return out
    }
}
