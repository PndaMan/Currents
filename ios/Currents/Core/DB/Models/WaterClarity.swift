import Foundation

/// How far you can see into the water. The strongest single input to lure
/// colour choice: clear water rewards natural, translucent finishes; stained
/// water rewards high-contrast chartreuse/orange; muddy water rewards dark
/// silhouettes and vibration.
enum WaterClarity: String, Codable, CaseIterable, Sendable, Identifiable {
    case clear
    case stained
    case muddy

    var id: String { rawValue }

    var label: String {
        switch self {
        case .clear:   "Clear"
        case .stained: "Stained"
        case .muddy:   "Muddy"
        }
    }

    /// Rough visibility, used in copy and to explain the recommendation.
    var detail: String {
        switch self {
        case .clear:   "See past ~1 m"
        case .stained: "Green / tea coloured"
        case .muddy:   "Under ~30 cm"
        }
    }

    var icon: String {
        switch self {
        case .clear:   "drop"
        case .stained: "drop.halffull"
        case .muddy:   "drop.fill"
        }
    }

    /// Best guess from recent rainfall when the angler hasn't said otherwise.
    /// Deliberately conservative — heavy rain muddies water, a shower stains
    /// it, otherwise assume the water is fishing clear.
    static func inferred(precipMm: Double?) -> WaterClarity {
        guard let mm = precipMm else { return .stained }
        switch mm {
        case 12...:   return .muddy
        case 2..<12:  return .stained
        default:      return .clear
        }
    }
}
