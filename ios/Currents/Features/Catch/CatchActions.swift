import SwiftUI

/// The catch actions shared by the Logbook list, its long-press menu and the
/// catch detail page, so every entry point deletes, favourites, edits and
/// shares a catch the same way.
@MainActor
enum CatchActions {

    /// Removes the catch, its photos and any shared copies. The database row
    /// goes first; when that fails nothing else is touched, an error toast
    /// shows and the result is false.
    @discardableResult
    static func delete(_ detail: CatchDetail, appState: AppState) -> Bool {
        let id = detail.catchRecord.id
        do {
            try appState.catchRepository.delete(detail.catchRecord)
        } catch {
            ToastCenter.shared.show("Couldn't delete the catch", style: .error)
            return false
        }
        PhotoManager.deleteAll(detail.catchRecord.allPhotoPaths)
        // Pull it from the shared leaderboard and any group feed too.
        Task { await CommunityService.shared.removeCatch(id: id) }
        ToastCenter.shared.show("Catch deleted", style: .info, icon: "trash")
        return true
    }

    /// Flips the favourite flag and returns the saved record. When the save
    /// fails an error toast shows and the original record comes back.
    @discardableResult
    static func toggleFavourite(_ detail: CatchDetail, appState: AppState) -> Catch {
        var record = detail.catchRecord
        record.isFavorite.toggle()
        do {
            try appState.catchRepository.save(&record)
        } catch {
            ToastCenter.shared.show("Couldn't update the catch", style: .error)
            return detail.catchRecord
        }
        return record
    }

    /// Saves an edit from the log catch composer and re-publishes it: the edit is how a
    /// quick-logged catch gets its species and size, and the public record
    /// must follow. Falls back to the edit as passed when the save fails;
    /// `saveEditChecked` tells the caller about that.
    @discardableResult
    static func saveEdit(_ updated: Catch, appState: AppState) -> Catch {
        saveEditChecked(updated, appState: appState) ?? updated
    }

    /// `saveEdit` that returns nil, and publishes nothing, when the save fails.
    static func saveEditChecked(_ updated: Catch, appState: AppState) -> Catch? {
        var record = updated
        do {
            try appState.catchRepository.save(&record)
        } catch {
            return nil
        }
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

    /// Renders the share card for a catch. Uses the photo at `photoIndex`,
    /// the species art when the catch has no photo, and the fish symbol
    /// cover when it has neither.
    static func shareImage(for detail: CatchDetail, photoIndex: Int = 0) async -> UIImage? {
        let paths = detail.catchRecord.allPhotoPaths
        let index = paths.indices.contains(photoIndex) ? photoIndex : 0
        if paths.indices.contains(index) {
            let path = paths[index]
            // Decode the full-size photo off the main actor.
            let photo = await Task.detached { PhotoManager.load(path) }.value
            if let photo {
                return await CatchShareCard.render(detail: detail, photo: photo)
            }
        }
        if let species = detail.species, let art = UIImage(named: species.artworkAssetName) {
            return await CatchShareCard.render(detail: detail, photo: art, isArtwork: true)
        }
        return await CatchShareCard.render(detail: detail)
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
