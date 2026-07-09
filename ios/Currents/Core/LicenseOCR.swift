import Foundation
import Vision
import UIKit
import PDFKit

/// Extracts licence details (expiry, issue date, number, holder) from a photo
/// or PDF using on-device Vision text recognition. All heuristic — the user can
/// always correct the fields before saving.
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
        let scale: CGFloat = 2
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
            DispatchQueue.global(qos: .userInitiated).async {
                try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
            }
        }
    }

    // MARK: - Parsing

    private static func parse(_ lines: [String]) -> Result {
        var result = Result()
        result.rawText = lines.joined(separator: "\n")
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

        func firstDate(in s: String) -> Date? {
            guard let detector else { return nil }
            let range = NSRange(s.startIndex..., in: s)
            return detector.firstMatch(in: s, range: range)?.date
        }

        var allDates: [Date] = []
        if let detector {
            let full = result.rawText
            detector.enumerateMatches(in: full, range: NSRange(full.startIndex..., in: full)) { m, _, _ in
                if let d = m?.date { allDates.append(d) }
            }
        }

        for (i, line) in lines.enumerated() {
            let l = line.lowercased()
            let nextLine = i + 1 < lines.count ? lines[i + 1] : ""

            if result.expiry == nil,
               l.contains("expir") || l.contains("valid until") || l.contains("valid to")
                || l.contains("valid thru") || l.contains("expiry") || l.contains("renew") {
                result.expiry = firstDate(in: line) ?? firstDate(in: nextLine)
            }
            if result.issue == nil, l.contains("issue") || l.contains("valid from") || l.contains("date of issue") {
                result.issue = firstDate(in: line) ?? firstDate(in: nextLine)
            }
            if result.number == nil,
               l.contains("licence no") || l.contains("license no") || l.contains("permit no")
                || l.contains("number") || l.contains("licence number") || l.contains("license number") {
                result.number = alnumToken(from: line) ?? alnumToken(from: nextLine)
            }
            if result.holder == nil, l.contains("name") || l.contains("holder") || l.contains("issued to") {
                result.holder = valueAfterColon(line) ?? (nextLine.isEmpty ? nil : nextLine)
            }
        }

        // Fallbacks: latest date is most likely the expiry, earliest the issue.
        let sorted = allDates.sorted()
        if result.expiry == nil { result.expiry = sorted.last }
        if result.issue == nil, sorted.count > 1 { result.issue = sorted.first }
        return result
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
