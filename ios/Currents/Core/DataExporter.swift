import Foundation
import SwiftUI
import GRDB

/// Exports all user data (catches, spots, gear) to a CSV zip bundle for sharing.
@MainActor
struct DataExporter {
    let appState: AppState

    /// Export all data to a temporary directory and return the zip URL.
    func exportAll() throws -> URL {
        let exportDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("currents_export_\(dateStamp())", isDirectory: true)
        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)

        try exportCatches(to: exportDir)
        try exportSpots(to: exportDir)
        try exportGear(to: exportDir)

        // Create a zip archive
        let zipURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("currents_export_\(dateStamp()).zip")
        try? FileManager.default.removeItem(at: zipURL)

        let coordinator = NSFileCoordinator()
        var error: NSError?
        coordinator.coordinate(readingItemAt: exportDir, options: [.forUploading], error: &error) { tempZipURL in
            try? FileManager.default.copyItem(at: tempZipURL, to: zipURL)
        }
        if let error { throw error }

        try? FileManager.default.removeItem(at: exportDir)
        return zipURL
    }

    private func exportCatches(to dir: URL) throws {
        let catches = try appState.catchRepository.fetchAll()
        var csv = "id,species,spot,date,latitude,longitude,length_cm,weight_kg,released,gear,forecast_score,notes\n"
        for detail in catches {
            let c = detail.catchRecord
            let fields: [String] = [
                c.id,
                csvEscape(detail.species?.commonName ?? ""),
                csvEscape(detail.spot?.name ?? ""),
                ISO8601DateFormatter().string(from: c.caughtAt),
                String(c.latitude),
                String(c.longitude),
                c.lengthCm.map { String($0) } ?? "",
                c.weightKg.map { String($0) } ?? "",
                c.released ? "yes" : "no",
                csvEscape(detail.gearLoadout?.name ?? ""),
                c.forecastScoreAtCapture.map { String($0) } ?? "",
                csvEscape(c.notes ?? ""),
            ]
            csv += fields.joined(separator: ",") + "\n"
        }
        try csv.write(to: dir.appendingPathComponent("catches.csv"), atomically: true, encoding: .utf8)
    }

    private func exportSpots(to dir: URL) throws {
        let spots = try appState.spotRepository.fetchAll()
        var csv = "id,name,latitude,longitude,private,notes,created\n"
        for s in spots {
            let fields: [String] = [
                s.id,
                csvEscape(s.name),
                String(s.latitude),
                String(s.longitude),
                s.isPrivate ? "yes" : "no",
                csvEscape(s.notes ?? ""),
                ISO8601DateFormatter().string(from: s.createdAt),
            ]
            csv += fields.joined(separator: ",") + "\n"
        }
        try csv.write(to: dir.appendingPathComponent("spots.csv"), atomically: true, encoding: .utf8)
    }

    private func exportGear(to dir: URL) throws {
        let gear = try appState.gearRepository.fetchAll()
        var csv = "id,name,rod,reel,line_lb,leader_lb,lure,lure_color,lure_weight_g,technique,created\n"
        for g in gear {
            let fields: [String] = [
                g.id,
                csvEscape(g.name),
                csvEscape(g.rod ?? ""),
                csvEscape(g.reel ?? ""),
                g.lineLb.map { String($0) } ?? "",
                g.leaderLb.map { String($0) } ?? "",
                csvEscape(g.lure ?? ""),
                csvEscape(g.lureColor ?? ""),
                g.lureWeightG.map { String($0) } ?? "",
                csvEscape(g.technique ?? ""),
                ISO8601DateFormatter().string(from: g.createdAt),
            ]
            csv += fields.joined(separator: ",") + "\n"
        }
        try csv.write(to: dir.appendingPathComponent("gear.csv"), atomically: true, encoding: .utf8)
    }

    // MARK: - Import

    /// Import catches from a CSV file (matching the export format).
    /// Returns the number of successfully imported catches.
    func importCatches(from url: URL) throws -> Int {
        let csvString = try String(contentsOf: url, encoding: .utf8)
        let lines = csvString.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count > 1 else { return 0 }

        let formatter = ISO8601DateFormatter()
        let allSpecies = try appState.speciesRepository.fetchAll()
        let allSpots = try appState.spotRepository.fetchAll()
        let allGear = try appState.gearRepository.fetchAll()
        var imported = 0

        for line in lines.dropFirst() {
            let fields = parseCSVLine(line)
            // Expected: id,species,spot,date,latitude,longitude,length_cm,weight_kg,released,gear,forecast_score,notes
            guard fields.count >= 6 else { continue }

            let dateStr = fields.count > 3 ? fields[3] : ""
            guard let caughtAt = formatter.date(from: dateStr) else { continue }

            let speciesName = fields.count > 1 ? fields[1] : ""
            let speciesId = allSpecies.first { $0.commonName.caseInsensitiveCompare(speciesName) == .orderedSame }?.id

            let spotName = fields.count > 2 ? fields[2] : ""
            let spotId = allSpots.first { $0.name.caseInsensitiveCompare(spotName) == .orderedSame }?.id

            let gearName = fields.count > 9 ? fields[9] : ""
            let gearId = allGear.first { $0.name.caseInsensitiveCompare(gearName) == .orderedSame }?.id

            let lat = fields.count > 4 ? Double(fields[4]) ?? 0 : 0
            let lon = fields.count > 5 ? Double(fields[5]) ?? 0 : 0

            var catchRecord = Catch(
                speciesId: speciesId,
                spotId: spotId,
                caughtAt: caughtAt,
                latitude: lat,
                longitude: lon,
                lengthCm: fields.count > 6 ? Double(fields[6]) : nil,
                weightKg: fields.count > 7 ? Double(fields[7]) : nil,
                released: fields.count > 8 ? fields[8].lowercased() == "yes" : true,
                forecastScoreAtCapture: fields.count > 10 ? Int(fields[10]) : nil,
                gearLoadoutId: gearId,
                notes: fields.count > 11 && !fields[11].isEmpty ? fields[11] : nil
            )

            try appState.catchRepository.save(&catchRecord)
            imported += 1
        }
        return imported
    }

    /// Import from a zip export (multiple CSVs).
    func importFromZip(at url: URL) throws -> Int {
        // Unzip to temp directory
        let importDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("currents_import_\(UUID().uuidString)", isDirectory: true)

        let coordinator = NSFileCoordinator()
        var error: NSError?
        var unzippedURL: URL?

        coordinator.coordinate(readingItemAt: url, options: [.withoutChanges], error: &error) { coordURL in
            // Try to decompress the zip
            if let archive = try? FileManager.default.contentsOfDirectory(at: coordURL, includingPropertiesForKeys: nil) {
                unzippedURL = coordURL
            }
        }

        // Fall back to treating as a single CSV
        if unzippedURL == nil {
            return try importCatches(from: url)
        }

        // Look for catches.csv inside the extracted dir
        let catchesFile = importDir.appendingPathComponent("catches.csv")
        if FileManager.default.fileExists(atPath: catchesFile.path) {
            return try importCatches(from: catchesFile)
        }

        // If it's a single CSV
        return try importCatches(from: url)
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current)
        return fields
    }

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    private func dateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}

/// UIKit share sheet wrapped for SwiftUI.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Share sheet for images (catch share cards).
struct ImageShareSheet: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
