import Foundation

extension String {
    /// Parse a user-typed measurement (weight, length) into a Double.
    ///
    /// The numeric keypad shows the user's *locale* decimal separator, which in
    /// much of the world is a comma — but `Double("0,5")` returns nil, so any
    /// decimal entry like 0.5 kg was silently dropped. This accepts either
    /// separator (and trims whitespace) so decimals always parse. Returns nil
    /// for empty/blank input so an untouched field stays unset rather than 0.
    var measurementValue: Double? {
        let trimmed = trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }
}
