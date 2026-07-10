import Foundation

/// Turns a scanned barcode into a real product where possible. Two stages:
/// 1. Validate the code is a well-formed EAN-13 / UPC-A / EAN-8 (check digit).
/// 2. Best-effort online lookup (UPCitemdb's keyless trial endpoint) to resolve
///    a product title + brand. Falls back gracefully when offline or unknown —
///    the barcode is still saved so the user can fill in the rest or re-order.
enum GearProductLookup {

    struct Product {
        var title: String
        var brand: String?
        var category: String?
    }

    enum LookupError: Error { case invalidBarcode, notFound, network }

    /// EAN-13 / UPC-A (12→13) / EAN-8 check-digit validation.
    static func isValid(_ raw: String) -> Bool {
        let digits = raw.filter(\.isNumber)
        guard [8, 12, 13, 14].contains(digits.count) else { return false }
        let nums = digits.compactMap { $0.wholeNumberValue }
        guard nums.count == digits.count else { return false }
        let check = nums.last!
        let body = nums.dropLast().reversed()
        var sum = 0
        for (i, d) in body.enumerated() {
            sum += (i % 2 == 0) ? d * 3 : d
        }
        let computed = (10 - (sum % 10)) % 10
        return computed == check
    }

    /// Normalise to the digits we send to the lookup API.
    static func normalized(_ raw: String) -> String {
        raw.filter(\.isNumber)
    }

    /// Look up a product by barcode. Throws on invalid/unknown/network failure
    /// so callers can decide how loudly to surface it.
    static func lookup(_ raw: String) async throws -> Product {
        guard isValid(raw) else { throw LookupError.invalidBarcode }
        let code = normalized(raw)
        guard let url = URL(string: "https://api.upcitemdb.com/prod/trial/lookup?upc=\(code)") else {
            throw LookupError.network
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw LookupError.network
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LookupError.network
        }
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let items = json["items"] as? [[String: Any]],
            let first = items.first,
            let title = (first["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !title.isEmpty
        else {
            throw LookupError.notFound
        }
        let brand = (first["brand"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = first["category"] as? String
        return Product(
            title: title,
            brand: brand?.isEmpty == false ? brand : nil,
            category: category
        )
    }
}
