import Foundation

/// Maps a raw classifier label (scientific or common name) onto a concrete
/// `Species` record in the local database.
///
/// The accurate on-device model (FishNet) emits scientific names such as
/// `Cyprinus carpio`; Apple's Vision fallback emits loose common labels such
/// as `common carp`. Both are resolved here so the log-catch flow can
/// AUTO-SELECT a species instead of showing the user raw keyword strings.
enum SpeciesMatcher {
    struct Match: Sendable {
        let species: Species
        let confidence: Float
    }

    /// Resolve a single label to the best-matching species, if any.
    static func match(label: String, in species: [Species]) -> Species? {
        let needle = normalize(label)
        guard !needle.isEmpty else { return nil }

        // 1. Exact scientific-name match (what FishNet emits).
        if let hit = species.first(where: { normalize($0.scientificName) == needle }) {
            return hit
        }
        // 2. Exact common-name match.
        if let hit = species.first(where: { normalize($0.commonName) == needle }) {
            return hit
        }
        // 3. Genus match on scientific name (first token).
        let genus = needle.split(separator: " ").first.map(String.init) ?? needle
        if genus.count > 3,
           let hit = species.first(where: { normalize($0.scientificName).hasPrefix(genus) }) {
            return hit
        }
        // 4. Token overlap on common name — handles "largemouth" ↔ "Largemouth Bass".
        let tokens = Set(needle.split(separator: " ").map(String.init).filter { $0.count > 3 })
        if !tokens.isEmpty {
            let scored = species.compactMap { sp -> (Species, Int)? in
                let spTokens = Set(normalize(sp.commonName).split(separator: " ").map(String.init))
                let overlap = tokens.intersection(spTokens).count
                return overlap > 0 ? (sp, overlap) : nil
            }
            if let best = scored.max(by: { $0.1 < $1.1 }) {
                return best.0
            }
        }
        return nil
    }

    /// Resolve a ranked list of classifier predictions into de-duplicated
    /// species matches, preserving confidence and order.
    static func matches(
        for predictions: [FishClassifier.Prediction],
        in species: [Species]
    ) -> [Match] {
        var seen = Set<Int64>()
        var out: [Match] = []
        for p in predictions {
            guard let sp = match(label: p.species, in: species), !seen.contains(sp.id) else { continue }
            seen.insert(sp.id)
            out.append(Match(species: sp, confidence: p.confidence))
        }
        return out
    }

    private static func normalize(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
