import Foundation
// ActivityKit is unavailable on watchOS — this type is only used by the iOS app
// and its widget extension, so guard the whole file for those platforms.
#if canImport(ActivityKit)
import ActivityKit

/// Live Activity descriptor for a crew tournament you're competing in: your
/// team's score and rank against the nearest rival, updating live as catches
/// land. Static attributes carry the identity; ContentState the scoreboard.
public struct TournamentActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var myTeamName: String
        public var myPoints: Int
        public var myRank: Int
        public var myFish: Int
        /// The team to beat — the leader when you're chasing, second place
        /// when you're on top. Nil while yours is the only team.
        public var rivalName: String?
        public var rivalPoints: Int?
        public var teamsCount: Int
        public var endsAt: Date?
        /// When the tournament began — drives the count-UP clock when the
        /// admin didn't set an end time (endsAt drives the countdown).
        public var startedAt: Date
        /// The live bite score at your location, mirrored from the session so
        /// the tournament card can replace the session one outright.
        public var biteScore: Int?

        public init(myTeamName: String, myPoints: Int, myRank: Int, myFish: Int,
                    rivalName: String?, rivalPoints: Int?, teamsCount: Int, endsAt: Date?,
                    startedAt: Date = .now, biteScore: Int? = nil) {
            self.myTeamName = myTeamName
            self.myPoints = myPoints
            self.myRank = myRank
            self.myFish = myFish
            self.rivalName = rivalName
            self.rivalPoints = rivalPoints
            self.teamsCount = teamsCount
            self.endsAt = endsAt
            self.startedAt = startedAt
            self.biteScore = biteScore
        }
    }

    public var tournamentName: String
    public var tournamentCode: String

    public init(tournamentName: String, tournamentCode: String) {
        self.tournamentName = tournamentName
        self.tournamentCode = tournamentCode
    }
}
#endif
