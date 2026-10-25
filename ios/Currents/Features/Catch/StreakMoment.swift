import Foundation

/// Decides whether a catch just saved earns the streak moment: it is the
/// first catch of this week, and this week extends a run, so the streak
/// goes from N-1 to N with N of 2 or more. A first week on its own (N of 1)
/// gets nothing. Worked out with the same week calendar and streak count
/// as the Logbook's Streak card.
enum StreakMomentJudge {
    /// Weeks shown in the moment's row, this week last.
    static let rowLength = 7

    /// `log` is the whole catch log read after the save, holding the new
    /// catch; the log before the save is the same without it. Only a new
    /// catch is judged: editing a catch never gets here.
    static func judge(savedCatchId: String, log: [CatchDetail]) -> Celebration? {
        let cal = BadgeDefinition.weekCalendar
        guard let saved = log.first(where: { $0.catchRecord.id == savedCatchId }) else { return nil }
        let thisWeek = BadgeDefinition.weekStart(of: .now, calendar: cal)
        // A catch dated in an earlier week doesn't make this week count.
        guard BadgeDefinition.weekStart(of: saved.catchRecord.caughtAt, calendar: cal) == thisWeek else { return nil }
        let before = log.filter { $0.catchRecord.id != savedCatchId }
        // This week already counted before this catch.
        let countedBefore = before.contains {
            BadgeDefinition.weekStart(of: $0.catchRecord.caughtAt, calendar: cal) == thisWeek
        }
        guard !countedBefore else { return nil }
        let after = BadgeDefinition.streakWeeks(from: log)
        guard after >= 2, BadgeDefinition.streakWeeks(from: before) == after - 1 else { return nil }
        return celebration(weeks: after, log: before)
    }

    /// The streak moment for a run of `weeks` that this week has just
    /// extended. `before` is the log without this week's catches, so this
    /// week's marker fills in as the number rolls on. Screenshot mode builds
    /// it straight from the demo log.
    static func celebration(weeks: Int, log before: [CatchDetail]) -> Celebration {
        let cal = BadgeDefinition.weekCalendar
        let thisWeek = BadgeDefinition.weekStart(of: .now, calendar: cal)
        let row: [Date] = (0..<rowLength).reversed().compactMap {
            BadgeDefinition.adjacentWeek(-$0, to: thisWeek, calendar: cal)
        }
        let fished = Set(before.map { BadgeDefinition.weekStart(of: $0.catchRecord.caughtAt, calendar: cal) })
            .subtracting([thisWeek])
        return Celebration(headline: "\(weeks)-week streak",
                           detail: "You've fished \(weeks) weeks in a row.",
                           icon: "flame.fill",
                           moment: .streak,
                           streak: StreakMoment(weeks: weeks, rowWeeks: row,
                                                fishedBefore: fished.intersection(row)))
    }
}
