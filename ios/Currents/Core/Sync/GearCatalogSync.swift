import Foundation
import GRDB

/// Keeps the gear catalog fresh from the hosted catalog file.
///
/// The catalog lives in the repo (`data/gear_catalog.json`) and is fetched
/// from raw GitHub, so new gear can be published without shipping an app
/// update. Every fetched item is upserted into the local GRDB store, which
/// means the whole catalog — and anything the user adds to their gear from
/// it — stays fully available offline; the network is only needed to pick
/// up NEW items.
enum GearCatalogSync {
    static let remoteURL = URL(
        string: "https://raw.githubusercontent.com/PndaMan/Currents/master/data/gear_catalog.json"
    )!
    private static let lastSyncKey = "gearCatalogLastSync"
    private static let refreshInterval: TimeInterval = 24 * 60 * 60

    /// Refresh from the remote catalog unless it was refreshed recently.
    /// Silent no-op when offline — the local copy keeps working.
    /// Returns the number of newly added items.
    @discardableResult
    static func syncIfDue(db: AppDatabase, force: Bool = false) async -> Int {
        let last = UserDefaults.standard.double(forKey: lastSyncKey)
        guard force || Date().timeIntervalSince1970 - last >= refreshInterval else { return 0 }
        do {
            var request = URLRequest(url: remoteURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return 0 }
            let items = try JSONDecoder().decode([GearItem].self, from: data)
            guard !items.isEmpty else { return 0 }
            let added = try await db.db.write { db in
                let before = try GearItem.fetchCount(db)
                for var item in items {
                    // Upsert by primary key — updates existing entries, adds
                    // new ones, never deletes rows the user's gear points at.
                    try item.save(db)
                }
                return try GearItem.fetchCount(db) - before
            }
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastSyncKey)
            print("[Currents] Gear catalog synced: \(items.count) items (\(added) new)")
            return added
        } catch {
            print("[Currents] Gear catalog sync skipped: \(error.localizedDescription)")
            return 0
        }
    }
}
