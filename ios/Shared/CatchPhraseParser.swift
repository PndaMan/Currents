import Foundation

/// What a dictated logging phrase meant. Pure text in, structured fields out —
/// species RESOLUTION (matching "bass" to a Species row) happens on the phone;
/// this type is shared with the watch so it can preview the parse live under
/// the dictation field.
public struct ParsedCatchPhrase: Equatable {
    /// The leftover words presumed to name the species ("largemouth bass").
    public var speciesText = ""
    public var weightKg: Double?
    public var lengthCm: Double?
    /// nil = not mentioned; the caller keeps its default.
    public var released: Bool?
    /// The measurements as spoken ("3½ lb", "45 cm") for confirmations.
    public var weightLabel = ""
    public var lengthLabel = ""

    public init() {}

    public var hasDetails: Bool { weightKg != nil || lengthCm != nil || released != nil }

    /// "3½ lb · 45 cm · released" — the live preview line.
    public var summary: String {
        var parts: [String] = []
        if !weightLabel.isEmpty { parts.append(weightLabel) }
        if !lengthLabel.isEmpty { parts.append(lengthLabel) }
        if let released { parts.append(released ? "released" : "kept") }
        return parts.joined(separator: " · ")
    }
}

/// Understands phrases like:
///   "three and a half pound largemouth bass, released"
///   "45 cm dusky kob kept"
///   "caught a rainbow trout about 2 kilos"
/// Weight accepts kg/kilos/pounds/lb; length accepts cm/centimetres/inches.
/// Number words (one…twenty, plus "half") are understood.
public enum CatchPhraseParser {

    public static func parse(_ phrase: String) -> ParsedCatchPhrase {
        var out = ParsedCatchPhrase()
        var text = " " + phrase.lowercased()
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: "-", with: " ") + " "

        // Release / keep intent — longest phrases first so "let it go" wins
        // before a bare "go" could ever be considered.
        let releasedPhrases = ["catch and release", "let it go", "let her go", "let him go",
                               "threw it back", "throw it back", "put it back", "released", "release"]
        let keptPhrases = ["in the cooler", "for dinner", "for the table", "harvested",
                           "keeper", "keeping", "kept", "keep it", "keep"]
        for p in releasedPhrases where text.contains(" \(p) ") {
            out.released = true
            text = text.replacingOccurrences(of: " \(p) ", with: " ")
            break
        }
        if out.released == nil {
            for p in keptPhrases where text.contains(" \(p) ") {
                out.released = false
                text = text.replacingOccurrences(of: " \(p) ", with: " ")
                break
            }
        }

        // Number words → digits ("three pound" → "3 pound").
        let numberWords: [(String, String)] = [
            ("twenty", "20"), ("nineteen", "19"), ("eighteen", "18"), ("seventeen", "17"),
            ("sixteen", "16"), ("fifteen", "15"), ("fourteen", "14"), ("thirteen", "13"),
            ("twelve", "12"), ("eleven", "11"), ("ten", "10"), ("nine", "9"), ("eight", "8"),
            ("seven", "7"), ("six", "6"), ("five", "5"), ("four", "4"), ("three", "3"),
            ("two", "2"), ("one", "1")
        ]
        for (word, digit) in numberWords {
            text = text.replacingOccurrences(of: " \(word) ", with: " \(digit) ")
        }
        // "3 and a half" → "3.5"; "half a pound" → "0.5 pound".
        text = regexReplace(text, #"(\d+)\s+and\s+a\s+half"#) { "\($0[0]).5" }
        text = regexReplace(text, #"half\s+an?\s+"#) { _ in "0.5 " }

        // Weight — "3.5 lb", "2 kilos", "a 3 pounder".
        let weightUnits = #"(kilograms|kilogram|kilos|kilo|kgs|kg|pounds|pounder|pound|lbs|lb)"#
        if let m = regexFirst(text, #"(\d+(?:\.\d+)?)\s*"# + weightUnits) {
            let value = Double(m.groups[0]) ?? 0
            let unit = m.groups[1]
            let metric = unit.hasPrefix("k")
            if value > 0 {
                out.weightKg = metric ? value : value * 0.45359237
                out.weightLabel = "\(trim(value)) \(metric ? "kg" : "lb")"
                text = text.replacingOccurrences(of: m.whole, with: " ")
            }
        }

        // Length — "45 cm", "18 inches" ("in" alone is too ambiguous).
        let lengthUnits = #"(centimetres|centimeters|centimetre|centimeter|cms|cm|inches|inch)"#
        if let m = regexFirst(text, #"(\d+(?:\.\d+)?)\s*"# + lengthUnits) {
            let value = Double(m.groups[0]) ?? 0
            let metric = m.groups[1].hasPrefix("c")
            if value > 0 {
                out.lengthCm = metric ? value : value * 2.54
                out.lengthLabel = "\(trim(value)) \(metric ? "cm" : "in")"
                text = text.replacingOccurrences(of: m.whole, with: " ")
            }
        }

        // Whatever's left, minus filler, is the species.
        let filler: Set<String> = ["caught", "landed", "got", "just", "logged", "log",
                                   "a", "an", "the", "at", "about", "around", "roughly",
                                   "it", "was", "and", "big", "nice", "huge", "little"]
        out.speciesText = text.split(separator: " ")
            .map(String.init)
            .filter { !filler.contains($0) && Double($0) == nil }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return out
    }

    // MARK: - Small regex helpers (NSRegularExpression under the hood)

    private struct Match { var whole: String; var groups: [String] }

    private static func regexFirst(_ text: String, _ pattern: String) -> Match? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let groups = (1..<m.numberOfRanges).map { i -> String in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
        return Match(whole: ns.substring(with: m.range), groups: groups)
    }

    private static func regexReplace(_ text: String, _ pattern: String,
                                     _ replacement: ([String]) -> String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text
        while true {
            let ns = result as NSString
            guard let m = re.firstMatch(in: result, range: NSRange(location: 0, length: ns.length)) else { break }
            let groups = (1..<m.numberOfRanges).map { i -> String in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
            result = ns.replacingCharacters(in: m.range, with: replacement(groups))
        }
        return result
    }

    private static func trim(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.1f", v)
    }
}
