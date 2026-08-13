import SwiftUI

/// One weekly crew challenge, with live progress measured from the crew's
/// feed. Deterministic per crew per ISO week — every member's device derives
/// the exact same set with no server round-trip.
struct CrewChallenge: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let target: Int
    var progress: Int = 0

    var done: Bool { progress >= target }
    var fraction: Double { target == 0 ? 0 : min(1, Double(progress) / Double(target)) }
}

/// Builds the week's challenges. Everything scales with how many anglers the
/// crew actually has (a 3-person crew gets "land 6 fish", not 50), and the
/// species challenge targets fish the crew has genuinely caught before — the
/// best available signal for what swims in their water.
enum CrewChallengeEngine {

    /// SplitMix64 — tiny, stable, and identical on every device for the same
    /// seed, which is all a deterministic weekly shuffle needs.
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    /// The Monday-anchored interval of the current ISO week.
    static func currentWeek(now: Date = .now) -> DateInterval {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        let start = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        return DateInterval(start: start, duration: 7 * 86_400)
    }

    /// "Resets Sunday night" — the countdown line under the card header.
    static func weekLabel(now: Date = .now) -> String {
        let end = currentWeek(now: now).end
        let days = max(0, Int(end.timeIntervalSince(now) / 86_400))
        switch days {
        case 0: return "Last day — resets tonight"
        case 1: return "1 day left"
        default: return "\(days) days left"
        }
    }

    /// THE challenge of the week — one per crew, so it's a shared goal rather
    /// than a checklist. Picked deterministically from the whole pool, so the
    /// flavour rotates week to week and every member sees the same one.
    static func weeklyChallenge(crewCode: String,
                                memberCount: Int,
                                memberCodes: [String],
                                posts: [CommunityService.CrewPost],
                                now: Date = .now) -> CrewChallenge? {
        var rng = seededRNG(crewCode: crewCode, now: now)
        let all = allChallenges(crewCode: crewCode, memberCount: memberCount,
                                memberCodes: memberCodes, posts: posts, now: now)
        return all.randomElement(using: &rng)
    }

    private static func seededRNG(crewCode: String, now: Date) -> SeededGenerator {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        let weekOfYear = cal.component(.weekOfYear, from: now)
        let year = cal.component(.yearForWeekOfYear, from: now)
        var seed: UInt64 = 5381
        for u in "\(crewCode)-\(year)-\(weekOfYear)".unicodeScalars {
            seed = (seed &* 33) &+ UInt64(u.value)
        }
        return SeededGenerator(state: seed)
    }

    private static func allChallenges(crewCode: String,
                                      memberCount: Int,
                                      memberCodes: [String],
                                      posts: [CommunityService.CrewPost],
                                      now: Date = .now) -> [CrewChallenge] {
        let members = max(1, memberCount)
        let week = currentWeek(now: now)
        let weekPosts = posts.filter { week.contains($0.caughtAt) }

        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        let weekOfYear = cal.component(.weekOfYear, from: now)
        let year = cal.component(.yearForWeekOfYear, from: now)
        var seed: UInt64 = 5381
        for u in "\(crewCode)-\(year)-\(weekOfYear)".unicodeScalars {
            seed = (seed &* 33) &+ UInt64(u.value)
        }
        var rng = SeededGenerator(state: seed)

        func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int { min(hi, max(lo, v)) }
        func hour(_ d: Date) -> Int { cal.component(.hour, from: d) }

        // The species pool: what this crew has actually landed, ever — the
        // local fish, by definition. Weighted by frequency via plain repetition.
        let speciesHistory = posts.map(\.species).filter { !$0.isEmpty && $0 != "Fish" }

        // Core challenge: one of these anchors every week.
        var core: [CrewChallenge] = [
            CrewChallenge(id: "haul", title: "Crew haul",
                          detail: "Land \(clamp(members * 2, 3, 24)) fish together",
                          icon: "fish.fill",
                          target: clamp(members * 2, 3, 24),
                          progress: weekPosts.count),
            CrewChallenge(id: "variety", title: "Species safari",
                          detail: "Land \(clamp(members + 1, 2, 8)) different species",
                          icon: "sparkles",
                          target: clamp(members + 1, 2, 8),
                          progress: Set(weekPosts.map { $0.species.lowercased() }).count)
        ]
        if members >= 2 {
            let quorum = clamp((members * 2) / 3, 2, members)
            core.append(
                CrewChallenge(id: "everyone", title: "All hands on deck",
                              detail: "\(quorum) different anglers each log a fish",
                              icon: "person.3.fill",
                              target: quorum,
                              progress: Set(weekPosts.map(\.authorCode)).count))
        }

        // Variety pool: two more, different every week.
        var pool: [CrewChallenge] = []
        if let target = speciesHistory.randomElement(using: &rng) {
            let n = clamp(members / 2, 1, 4)
            pool.append(
                CrewChallenge(id: "target", title: "Target: \(target)",
                              detail: "Land \(n) \(target)\(n == 1 ? "" : "s") — a crew favourite",
                              icon: "scope",
                              target: n,
                              progress: weekPosts.filter { $0.species.caseInsensitiveCompare(target) == .orderedSame }.count))
        }
        let bigTiers: [Double] = [1, 2, 3, 5]
        let tier = bigTiers.randomElement(using: &rng) ?? 2
        pool.append(
            CrewChallenge(id: "big", title: "The big one",
                          detail: "Someone lands a fish over \(Units.weight(kg: tier))",
                          icon: "scalemass.fill",
                          target: 1,
                          progress: weekPosts.contains { ($0.weightKg ?? 0) >= tier } ? 1 : 0))
        pool.append(
            CrewChallenge(id: "dawn", title: "Dawn patrol",
                          detail: "\(clamp(members, 2, 6)) fish landed before 8 AM",
                          icon: "sunrise.fill",
                          target: clamp(members, 2, 6),
                          progress: weekPosts.filter { hour($0.caughtAt) < 8 }.count))
        pool.append(
            CrewChallenge(id: "night", title: "Night shift",
                          detail: "\(clamp(members, 2, 6)) fish landed after 8 PM",
                          icon: "moon.stars.fill",
                          target: clamp(members, 2, 6),
                          progress: weekPosts.filter { hour($0.caughtAt) >= 20 }.count))
        pool.append(
            CrewChallenge(id: "photo", title: "Pics or it didn't happen",
                          detail: "\(clamp(members, 2, 10)) catches posted with a photo",
                          icon: "camera.fill",
                          target: clamp(members, 2, 10),
                          progress: weekPosts.filter(\.hasPhoto).count))
        pool.append(
            CrewChallenge(id: "measured", title: "On the board",
                          detail: "\(clamp(members, 2, 10)) catches logged with weight or length",
                          icon: "ruler.fill",
                          target: clamp(members, 2, 10),
                          progress: weekPosts.filter { $0.weightKg != nil || $0.lengthCm != nil }.count))

        return core + pool
    }
}

// MARK: - Row

/// The week's crew challenge as an ordinary list row, so it sits in the crew
/// page's grouped sections looking like it was born there — no floating card.
struct CrewChallengeRow: View {
    let challenge: CrewChallenge

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(challenge.done ? Color.green.opacity(0.15)
                                         : CurrentsTheme.accent.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: challenge.done ? "checkmark" : challenge.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(challenge.done ? .green : CurrentsTheme.accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(challenge.title).font(.subheadline.bold())
                    Spacer()
                    Text(challenge.done ? "Done!"
                         : "\(min(challenge.progress, challenge.target))/\(challenge.target)")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(challenge.done ? .green : .secondary)
                }
                Text(challenge.detail)
                    .font(.caption).foregroundStyle(.secondary)
                ProgressView(value: challenge.fraction)
                    .tint(challenge.done ? .green : CurrentsTheme.accent)
            }
        }
        .padding(.vertical, 2)
    }
}
