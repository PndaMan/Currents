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
