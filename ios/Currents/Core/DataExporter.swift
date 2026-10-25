import Foundation
import SwiftUI
import GRDB
import ZIPFoundation

/// Exports all user data (catches, spots, gear) to a CSV zip bundle for
/// sharing, and imports catches back from that bundle or a catches CSV.
@MainActor
struct DataExporter {
    let appState: AppState

    /// What an import did: catches added, and rows skipped because a catch
    /// with the same id is already in the Logbook.
    struct ImportResult: Sendable {
        var imported = 0
        var skipped = 0
    }

    enum ImportError: Error {
        /// The zip has no catches.csv in it.
        case noCatchesFile
    }

    /// Export all data to a temporary directory and return the zip URL. The
    /// reads run on the database queue and the files are written off the
    /// main actor, so a long logbook doesn't stall the page.
    func exportAll() async throws -> URL {
        let database = appState.db
        let catches = try await database.db.read { db in
            try CatchDetail.fetchAll(db, Catch
                .including(optional: Catch.species)
                .including(optional: Catch.spot)
                .including(optional: Catch.gearLoadout)
                .order(Column("caughtAt").desc))
        }
        let spots = try await database.db.read { db in
            try Spot.order(Column("createdAt").desc).fetchAll(db)
        }
        let gear = try await database.db.read { db in
            try GearLoadout.order(Column("createdAt").desc).fetchAll(db)
        }
        return try await Task.detached(priority: .userInitiated) {
            try ExportFiles.writeBundle(catches: catches, spots: spots, gear: gear)
        }.value
    }

    // MARK: - Import

    /// Import catches from a CSV file (matching the export format). A row
    /// whose id is already in the Logbook is skipped, never overwritten, so
    /// importing the same file twice adds nothing the second time.
    func importCatches(from url: URL) throws -> ImportResult {
        let csvString = try String(contentsOf: url, encoding: .utf8)
        let lines = csvString.components(separatedBy: .newlines).filter { !$0.isEmpty }
        var result = ImportResult()
        guard lines.count > 1 else { return result }

        let formatter = ISO8601DateFormatter()
        let allSpecies = try appState.speciesRepository.fetchAll()
        let allSpots = try appState.spotRepository.fetchAll()
        let allGear = try appState.gearRepository.fetchAll()
        let existingIds = try appState.db.db.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM \"catch\"")
        }
        var knownIds = Set(existingIds)

        for line in lines.dropFirst() {
            let fields = parseCSVLine(line)
            // Expected: id,species,spot,date,latitude,longitude,length_cm,weight_kg,released,gear,forecast_score,notes
            guard fields.count >= 6 else { continue }

            let dateStr = fields.count > 3 ? fields[3] : ""
            guard let caughtAt = formatter.date(from: dateStr) else { continue }

            // Keep the exported id, so a catch that is already here is found
            // and skipped rather than added a second time.
            let csvId = fields[0].trimmingCharacters(in: .whitespaces)
            if !csvId.isEmpty, knownIds.contains(csvId) {
                result.skipped += 1
                continue
            }

            let speciesName = fields.count > 1 ? fields[1] : ""
            let speciesId = allSpecies.first { $0.commonName.caseInsensitiveCompare(speciesName) == .orderedSame }?.id

            let spotName = fields.count > 2 ? fields[2] : ""
            let spotId = allSpots.first { $0.name.caseInsensitiveCompare(spotName) == .orderedSame }?.id

            let gearName = fields.count > 9 ? fields[9] : ""
            let gearId = allGear.first { $0.name.caseInsensitiveCompare(gearName) == .orderedSame }?.id

            let lat = fields.count > 4 ? Double(fields[4]) ?? 0 : 0
            let lon = fields.count > 5 ? Double(fields[5]) ?? 0 : 0

            var catchRecord = Catch(
                id: csvId.isEmpty ? UUID().uuidString : csvId,
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
            knownIds.insert(catchRecord.id)
            result.imported += 1
        }
        return result
    }

    /// Import from a zip export: unzips it into a temporary folder and
    /// imports the catches.csv inside. Spots and gear are not imported.
    func importFromZip(at url: URL) throws -> ImportResult {
        let fm = FileManager.default
        let importDir = fm.temporaryDirectory
            .appendingPathComponent("currents_import_\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: importDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: importDir) }

        try fm.unzipItem(at: url, to: importDir)

        // The export zips its folder, so catches.csv sits one level down.
        let files = fm.enumerator(at: importDir, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL } ?? []
        guard let catchesFile = files.first(where: { $0.lastPathComponent.lowercased() == "catches.csv" }) else {
            throw ImportError.noCatchesFile
        }
        return try importCatches(from: catchesFile)
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
}

/// Writes the export CSVs and zips them. Plain functions on no actor, so
/// `DataExporter.exportAll` can run them off the main thread.
private enum ExportFiles {
    static func writeBundle(catches: [CatchDetail], spots: [Spot], gear: [GearLoadout]) throws -> URL {
        let fm = FileManager.default
        let stamp = dateStamp()
        let exportDir = fm.temporaryDirectory
            .appendingPathComponent("currents_export_\(stamp)", isDirectory: true)
        try fm.createDirectory(at: exportDir, withIntermediateDirectories: true)

        try catchesCSV(catches).write(to: exportDir.appendingPathComponent("catches.csv"), atomically: true, encoding: .utf8)
        try spotsCSV(spots).write(to: exportDir.appendingPathComponent("spots.csv"), atomically: true, encoding: .utf8)
        try gearCSV(gear).write(to: exportDir.appendingPathComponent("gear.csv"), atomically: true, encoding: .utf8)

        // Create a zip archive
        let zipURL = fm.temporaryDirectory
            .appendingPathComponent("currents_export_\(stamp).zip")
        try? fm.removeItem(at: zipURL)

        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var copyError: Error?
        coordinator.coordinate(readingItemAt: exportDir, options: [.forUploading], error: &coordinationError) { tempZipURL in
            do {
                try fm.copyItem(at: tempZipURL, to: zipURL)
            } catch {
                copyError = error
            }
        }
        try? fm.removeItem(at: exportDir)
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
        return zipURL
    }

    private static func catchesCSV(_ catches: [CatchDetail]) -> String {
        let formatter = ISO8601DateFormatter()
        var csv = "id,species,spot,date,latitude,longitude,length_cm,weight_kg,released,gear,forecast_score,notes\n"
        for detail in catches {
            let c = detail.catchRecord
            let fields: [String] = [
                c.id,
                csvEscape(detail.species?.commonName ?? ""),
                csvEscape(detail.spot?.name ?? ""),
                formatter.string(from: c.caughtAt),
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
        return csv
    }

    private static func spotsCSV(_ spots: [Spot]) -> String {
        let formatter = ISO8601DateFormatter()
        var csv = "id,name,latitude,longitude,private,notes,created\n"
        for s in spots {
            let fields: [String] = [
                s.id,
                csvEscape(s.name),
                String(s.latitude),
                String(s.longitude),
                s.isPrivate ? "yes" : "no",
                csvEscape(s.notes ?? ""),
                formatter.string(from: s.createdAt),
            ]
            csv += fields.joined(separator: ",") + "\n"
        }
        return csv
    }

    private static func gearCSV(_ gear: [GearLoadout]) -> String {
        let formatter = ISO8601DateFormatter()
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
                formatter.string(from: g.createdAt),
            ]
            csv += fields.joined(separator: ",") + "\n"
        }
        return csv
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    private static func dateStamp() -> String {
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
///
/// Shares a real JPEG file URL rather than a raw `UIImage` — several share
/// targets (WhatsApp, Telegram, Messenger) silently reject in-memory image
/// activity items while accepting image files. Save Image keeps working.
struct ImageShareSheet: UIViewControllerRepresentable {
    let image: UIImage
    var filename: String = "Currents-Catch"
    /// Optional text shared alongside the image — e.g. a maps link that apps
    /// like WhatsApp attach as the message/caption.
    var caption: String? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        var items: [Any] = [image]
        if let data = image.jpegData(compressionQuality: 0.92) {
            let safeName = filename.replacingOccurrences(of: "/", with: "-")
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(safeName).jpg")
            if (try? data.write(to: url, options: .atomic)) != nil {
                items = [url]
            }
        }
        if let caption { items.append(caption) }
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
