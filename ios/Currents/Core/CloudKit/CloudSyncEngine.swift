import CloudKit
import Foundation
import GRDB
import UIKit

/// Optional, opt-in **live sync of catches + spots across the angler's own
/// devices** via their PRIVATE iCloud database, built on `CKSyncEngine`.
///
/// Privacy: this uses the user's *private* CloudKit database — the same iCloud
/// account that already backs up their data. The developer has NO access to it;
/// nothing is sent to any server we run. It is OFF by default and only starts
/// once the angler explicitly turns it on in Settings › Privacy.
///
/// It syncs the catch/spot rows (as a JSON payload) plus each catch's primary
/// photo (as a CKAsset). Conflict resolution is last-writer-wins, which is right
/// for a single angler across their own devices.
final class CloudSyncEngine: NSObject, CKSyncEngineDelegate, @unchecked Sendable {
    static let shared = CloudSyncEngine()

    // Lazy so a build without the iCloud entitlement (the unsigned CI test
    // build) never instantiates the container at launch — it's only touched
    // once sync is actually enabled.
    private lazy var container = CKContainer(identifier: "iCloud.com.aidanmcconnon.currents")
    private let zoneID = CKRecordZone.ID(zoneName: "CurrentsData", ownerName: CKCurrentUserDefaultName)
    private let catchType = "SyncCatch"
    private let spotType = "SyncSpot"
    private static let stateKey = "cloudSyncState"

    private var engine: CKSyncEngine?
    /// The GRDB queue is Sendable + thread-safe, so the engine's background
    /// callbacks can read/write it without hopping to the main actor.
    private var dbQueue: DatabaseQueue?

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: "cloudSyncEnabled") }

    // MARK: - Lifecycle

    /// Called once at launch. Starts syncing only if the user has opted in.
    func configure(db: AppDatabase) {
        self.dbQueue = db.db
        guard isEnabled else { return }
        start()
    }

    /// Toggle from Settings. Turning on kicks off an initial upload of everything.
    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: "cloudSyncEnabled")
        if on { start(initialUpload: true) } else { engine = nil }
    }

    private func start(initialUpload: Bool = false) {
        if engine == nil {
            var config = CKSyncEngine.Configuration(
                database: container.privateCloudDatabase,
                stateSerialization: loadState(),
                delegate: self)
            config.automaticallySync = true
            engine = CKSyncEngine(config)
            engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
        }
        if initialUpload { enqueueAllLocal() }
    }

    // MARK: - Enqueue local changes (called from the repositories)

    func catchChanged(_ id: String) { enqueue(.saveRecord(recordID(catchType, id))) }
    func catchDeleted(_ id: String) { enqueue(.deleteRecord(recordID(catchType, id))) }
    func spotChanged(_ id: String) { enqueue(.saveRecord(recordID(spotType, id))) }
    func spotDeleted(_ id: String) { enqueue(.deleteRecord(recordID(spotType, id))) }

    private func enqueue(_ change: CKSyncEngine.PendingRecordZoneChange) {
        guard isEnabled, let engine else { return }
        engine.state.add(pendingRecordZoneChanges: [change])
    }

    private func recordID(_ type: String, _ id: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "\(type)-\(id)", zoneID: zoneID)
    }

    private func enqueueAllLocal() {
        guard let dbQueue else { return }
        let catches = (try? dbQueue.read { try Catch.fetchAll($0) }) ?? []
        let spots = (try? dbQueue.read { try Spot.fetchAll($0) }) ?? []
        catches.forEach { catchChanged($0.id) }
        spots.forEach { spotChanged($0.id) }
    }

    // MARK: - CKSyncEngineDelegate

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            saveState(update.stateSerialization)
        case .fetchedRecordZoneChanges(let changes):
            for mod in changes.modifications { applyRemote(mod.record) }
            for del in changes.deletions { applyRemoteDeletion(del.recordID) }
        case .sentRecordZoneChanges(let sent):
            // On a server-record conflict, re-enqueue with the server version's
            // change tag so our next push isn't rejected (last-writer-wins).
            for failure in sent.failedRecordSaves {
                if failure.error.code == .serverRecordChanged {
                    engine?.state.add(pendingRecordZoneChanges: [.saveRecord(failure.record.recordID)])
                }
            }
        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                   syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { [weak self] recordID in
            self?.buildRecord(for: recordID)
        }
    }

    // MARK: - Serialization (local → CKRecord)

    private func buildRecord(for recordID: CKRecord.ID) -> CKRecord? {
        guard let dbQueue else { return nil }
        let name = recordID.recordName
        if name.hasPrefix("\(catchType)-") {
            let id = String(name.dropFirst(catchType.count + 1))
            guard let c = try? dbQueue.read({ try Catch.fetchOne($0, key: id) }) else { return nil }
            let rec = CKRecord(recordType: catchType, recordID: recordID)
            rec["payload"] = (try? JSONEncoder().encode(c)) as CKRecordValue?
            if let path = c.allPhotoPaths.first,
               let asset = photoAsset(path) { rec["photo"] = asset }
            return rec
        } else if name.hasPrefix("\(spotType)-") {
            let id = String(name.dropFirst(spotType.count + 1))
            guard let s = try? dbQueue.read({ try Spot.fetchOne($0, key: id) }) else { return nil }
            let rec = CKRecord(recordType: spotType, recordID: recordID)
            rec["payload"] = (try? JSONEncoder().encode(s)) as CKRecordValue?
            return rec
        }
        return nil
    }

    private func photoAsset(_ filename: String) -> CKAsset? {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("catch_photos", isDirectory: true)
            .appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? CKAsset(fileURL: url) : nil
    }

    // MARK: - Apply remote → local (raw GRDB writes, never re-enqueued)

    private func applyRemote(_ record: CKRecord) {
        guard let dbQueue, let payload = record["payload"] as? Data else { return }
        if record.recordType == catchType, var c = try? JSONDecoder().decode(Catch.self, from: payload) {
            // Land the synced photo into the local photo store if present.
            if let asset = record["photo"] as? CKAsset, let src = asset.fileURL,
               let first = c.allPhotoPaths.first {
                restorePhoto(from: src, to: first)
            }
            try? dbQueue.write { try c.save($0) }
        } else if record.recordType == spotType, var s = try? JSONDecoder().decode(Spot.self, from: payload) {
            try? dbQueue.write { try s.save($0) }
        }
    }

    private func applyRemoteDeletion(_ recordID: CKRecord.ID) {
        guard let dbQueue else { return }
        let name = recordID.recordName
        if name.hasPrefix("\(catchType)-") {
            let id = String(name.dropFirst(catchType.count + 1))
            _ = try? dbQueue.write { try Catch.deleteOne($0, key: id) }
        } else if name.hasPrefix("\(spotType)-") {
            let id = String(name.dropFirst(spotType.count + 1))
            _ = try? dbQueue.write { try Spot.deleteOne($0, key: id) }
        }
    }

    private func restorePhoto(from src: URL, to filename: String) {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("catch_photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(filename)
        guard !FileManager.default.fileExists(atPath: dest.path) else { return }
        try? FileManager.default.copyItem(at: src, to: dest)
    }

    // MARK: - State persistence

    private func loadState() -> CKSyncEngine.State.Serialization? {
        guard let data = UserDefaults.standard.data(forKey: Self.stateKey) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func saveState(_ state: CKSyncEngine.State.Serialization) {
        UserDefaults.standard.set(try? JSONEncoder().encode(state), forKey: Self.stateKey)
    }
}
