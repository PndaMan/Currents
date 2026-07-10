import Foundation
import Vision
import UIKit
import PDFKit

/// Extracts licence details (expiry, issue date, number, holder, region) from a
/// photo or PDF using on-device Vision text recognition. All heuristic — the
/// user can always correct the fields before saving.
///
/// Dates are parsed with an explicit day/month order (Settings › Units › Date
/// format) rather than `NSDataDetector`, which defaults to the US month-first
/// reading and silently swaps e.g. 05/11/2025 to 11 May instead of 5 November.
enum LicenseOCR {
    struct Result: Sendable {
        var expiry: Date?
        var issue: Date?
        var number: String?
        var holder: String?
        var region: String?
        var rawText: String = ""
    }

    static func scan(image: UIImage) async -> Result {
        guard let cg = image.cgImage else { return Result() }
        let lines = await recognize(cg)
        return parse(lines)
    }

    static func scan(pdf url: URL) async -> Result {
        guard let doc = PDFDocument(url: url), let page = doc.page(at: 0) else { return Result() }
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 3
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.white.set()
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.cgContext.translateBy(x: 0, y: size.height)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
        return await scan(image: image)
    }

    // MARK: - Vision

    private static func recognize(_ cg: CGImage) async -> [String] {
        await withCheckedContinuation { (cont: CheckedContinuation<[String], Never>) in
            let request = VNRecognizeTextRequest { request, _ in
                let lines = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string } ?? []
                cont.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US", "en-GB"]
            request.minimumTextHeight = 0.008   // catch small print like expiry dates
            DispatchQueue.global(qos: .userInitiated).async {
                try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
            }
        }
    }

    // MARK: - Date parsing (locale-aware)

    /// User's preferred numeric date order. "auto" derives from the device
    /// region (US → month-first, everywhere else → day-first).
    static var dayFirst: Bool {
        switch UserDefaults.standard.string(forKey: "dateOrder") {
        case "monthFirst": return false
        case "dayFirst": return true
        default:
            let region = Locale.current.region?.identifier ?? "ZA"
            return region != "US"   // US is the main month-first outlier
        }
    }

    private static let monthNames: [String: Int] = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "sept": 9, "oct": 10, "nov": 11, "dec": 12,
    ]

    /// Parse the first date found in a string, respecting the user's day/month
    /// order for ambiguous numeric dates.
    static func parseDate(in text: String, dayFirst: Bool = dayFirst) -> Date? {
        let lower = text.lowercased()

        // 1) Textual month, e.g. "5 Nov 2025", "Nov 5, 2025", "5 November 2025".
        if let m = firstMatch(#"(\d{1,2})\s*(?:st|nd|rd|th)?\s+([a-z]{3,9})\.?,?\s+(\d{2,4})"#, in: lower),
           let day = Int(m[1]), let mon = monthNames[String(m[2].prefix(3))] {
            return makeDate(day: day, month: mon, year: normalizeYear(m[3]))
        }
        if let m = firstMatch(#"([a-z]{3,9})\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{2,4})"#, in: lower),
           let mon = monthNames[String(m[1].prefix(3))], let day = Int(m[2]) {
            return makeDate(day: day, month: mon, year: normalizeYear(m[3]))
        }

        // 2) ISO, e.g. 2025-11-05.
        if let m = firstMatch(#"(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})"#, in: lower),
           let y = Int(m[1]), let mo = Int(m[2]), let d = Int(m[3]) {
            return makeDate(day: d, month: mo, year: y)
        }

        // 3) Numeric d/m/y or m/d/y — disambiguate by value, else by preference.
        if let m = firstMatch(#"(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})"#, in: lower) {
            let a = Int(m[1]) ?? 0, b = Int(m[2]) ?? 0
            let year = normalizeYear(m[3])
            let (day, month): (Int, Int)
            if a > 12 { (day, month) = (a, b) }        // first can only be a day
            else if b > 12 { (day, month) = (b, a) }   // second can only be a day
            else { (day, month) = dayFirst ? (a, b) : (b, a) }
            return makeDate(day: day, month: month, year: year)
        }
        return nil
    }

    private static func normalizeYear(_ s: Substring) -> Int {
        let y = Int(s) ?? 0
        return y < 100 ? 2000 + y : y
    }

    private static func makeDate(day: Int, month: Int, year: Int) -> Date? {
        guard (1...31).contains(day), (1...12).contains(month), year > 1900 else { return nil }
        var c = DateComponents()
        c.day = day; c.month = month; c.year = year
        c.hour = 12
        return Calendar(identifier: .gregorian).date(from: c)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> [Substring]? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range) else { return nil }
        return (0..<m.numberOfRanges).compactMap { i -> Substring? in
            guard let r = Range(m.range(at: i), in: text) else { return "" }
            return text[r]
        }
    }

    // MARK: - Parsing

    private static func parse(_ lines: [String]) -> Result {
        var result = Result()
        result.rawText = lines.joined(separator: "\n")

        var allDates: [Date] = []
        for line in lines {
            if let d = parseDate(in: line) { allDates.append(d) }
        }

        for (i, line) in lines.enumerated() {
            let l = line.lowercased()
            let nextLine = i + 1 < lines.count ? lines[i + 1] : ""

            if result.expiry == nil,
               l.contains("expir") || l.contains("valid until") || l.contains("valid to")
                || l.contains("valid thru") || l.contains("expiry") || l.contains("renew")
                || l.contains("valid up to") || l.contains("end date") {
                result.expiry = parseDate(in: line) ?? parseDate(in: nextLine)
            }
            if result.issue == nil,
               l.contains("issue") || l.contains("valid from") || l.contains("date of issue")
                || l.contains("start date") || l.contains("issued on") {
                result.issue = parseDate(in: line) ?? parseDate(in: nextLine)
            }
            if result.number == nil,
               l.contains("licence no") || l.contains("license no") || l.contains("permit no")
                || l.contains("number") || l.contains("licence number") || l.contains("license number")
                || l.contains("ref no") || l.contains("reference") || l.contains("permit number") {
                result.number = alnumToken(from: line) ?? alnumToken(from: nextLine)
            }
            if result.holder == nil,
               l.contains("name") || l.contains("holder") || l.contains("issued to")
                || l.contains("surname") || l.contains("full name") {
                result.holder = valueAfterColon(line) ?? (nextLine.isEmpty ? nil : nextLine)
            }
            if result.region == nil,
               l.contains("province") || l.contains("region") || l.contains("state")
                || l.contains("district") || l.contains("municipality") || l.contains("area") {
                result.region = valueAfterColon(line)
            }
        }

        // Region: fall back to a well-known South African province name anywhere.
        if result.region == nil {
            result.region = southAfricanProvince(in: result.rawText)
        }

        // Date fallbacks: latest date is most likely the expiry, earliest the issue.
        let sorted = allDates.sorted()
        if result.expiry == nil { result.expiry = sorted.last }
        if result.issue == nil, sorted.count > 1 { result.issue = sorted.first }
        return result
    }

    private static func southAfricanProvince(in text: String) -> String? {
        let provinces = ["Western Cape", "Eastern Cape", "Northern Cape", "KwaZulu-Natal",
                         "Free State", "Gauteng", "Limpopo", "Mpumalanga", "North West"]
        let lower = text.lowercased()
        return provinces.first { lower.contains($0.lowercased()) }
    }

    /// The value after a "Label: value" colon, trimmed.
    private static func valueAfterColon(_ s: String) -> String? {
        guard let idx = s.firstIndex(of: ":") else { return nil }
        let v = s[s.index(after: idx)...].trimmingCharacters(in: .whitespaces)
        return v.isEmpty ? nil : v
    }

    /// The longest alphanumeric token on a line (likely the licence number).
    private static func alnumToken(from s: String) -> String? {
        let tokens = s.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 5 && $0.contains(where: \.isNumber) }
        return tokens.max(by: { $0.count < $1.count })
    }
}
