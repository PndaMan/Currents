import SwiftUI

/// The catch actions shared by the Logbook list, its long-press menu and the
/// catch detail page, so every entry point deletes, favourites, edits and
/// shares a catch the same way.
@MainActor
enum CatchActions {

    /// Removes the catch, its photos and any shared copies.
    static func delete(_ detail: CatchDetail, appState: AppState) {
        let id = detail.catchRecord.id
        PhotoManager.deleteAll(detail.catchRecord.allPhotoPaths)
        try? appState.catchRepository.delete(detail.catchRecord)
        // Pull it from the shared leaderboard and any group feed too.
        Task { await CommunityService.shared.removeCatch(id: id) }
        ToastCenter.shared.show("Catch deleted", style: .info, icon: "trash")
    }

    /// Flips the favourite flag and returns the saved record.
    @discardableResult
    static func toggleFavourite(_ detail: CatchDetail, appState: AppState) -> Catch {
        var record = detail.catchRecord
        record.isFavorite.toggle()
        try? appState.catchRepository.save(&record)
        return record
    }

    /// Saves an edit from the log catch composer and re-publishes it: the edit is how a
    /// quick-logged catch gets its species and size, and the public record
    /// must follow.
    @discardableResult
    static func saveEdit(_ updated: Catch, appState: AppState) -> Catch {
        var record = updated
        try? appState.catchRepository.save(&record)
        let published = record
        let name = record.speciesId.flatMap { try? appState.speciesRepository.fetch(id: $0) }?.commonName
        Task { await CommunityService.shared.publishLoggedCatch(published, speciesName: name) }
        return record
    }

    /// Rebuilds the joined detail for a saved record.
    static func reloadDetail(_ record: Catch, appState: AppState) -> CatchDetail {
        CatchDetail(
            catchRecord: record,
            species: record.speciesId.flatMap { try? appState.speciesRepository.fetch(id: $0) },
            spot: record.spotId.flatMap { id in
                (try? appState.spotRepository.fetchAll())?.first { $0.id == id }
            },
            gearLoadout: record.gearLoadoutId.flatMap { id in
                (try? appState.gearRepository.fetchAll())?.first { $0.id == id }
            }
        )
    }

    /// Renders the share card for a catch. Uses the photo at `photoIndex`, or
    /// the species art when the catch has no photo.
    static func shareImage(for detail: CatchDetail, photoIndex: Int = 0) async -> UIImage? {
        let paths = detail.catchRecord.allPhotoPaths
        let index = paths.indices.contains(photoIndex) ? photoIndex : 0
        if paths.indices.contains(index), let photo = PhotoManager.load(paths[index]) {
            return await CatchShareCard.render(detail: detail, photo: photo)
        }
        guard let species = detail.species,
              let art = UIImage(named: species.artworkAssetName) else { return nil }
        return await CatchShareCard.render(detail: detail, photo: art, isArtwork: true)
    }

    static func shareFilename(for detail: CatchDetail) -> String {
        "Currents-\(detail.species?.commonName ?? "Catch")"
    }
}

/// A rendered share image, presented with `.sheet(item:)`.
struct CatchShareItem: Identifiable {
    let id = UUID()
    let image: UIImage
    let filename: String
}
