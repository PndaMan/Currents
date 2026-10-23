import SwiftUI
import PhotosUI

/// A spot's own picture, which its thumbnail shows in place of the map.
struct SpotCover: Equatable {
    let spotId: String
    let style: Spot.Cover
    let photoPath: String?

    /// Nil when the spot shows the map.
    init?(_ spot: Spot) {
        guard spot.cover != .map else { return nil }
        spotId = spot.id
        style = spot.cover
        photoPath = spot.coverPhotoPath
    }

    var id: String { "\(style.rawValue)-\(photoPath ?? "")" }
}

/// Loads, renders and caches spot pictures. A photo is a downsampled copy of
/// the file in PhotoManager's store; a collage is drawn from the latest catch
/// photos at the spot and kept in Caches under the spot id and those photos,
/// so a new catch photo draws a new one. Decoding and drawing happen off the
/// main thread.
@MainActor
enum SpotCovers {
    /// Pictures are drawn once at this size and scaled down for every row.
    static let side: CGFloat = 128

    private static let memory = NSCache<NSString, UIImage>()
    /// The last collage drawn per spot, shown on the first frame while the
    /// catch photos are checked again.
    private static var latestCollage: [String: String] = [:]
    private static var running: [String: Task<UIImage?, Never>] = [:]

    nonisolated private static let folder: URL? = {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = caches.appendingPathComponent("SpotCovers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// A picture already in memory. Anything else loads through `image(for:scale:)`.
    static func cached(_ cover: SpotCover, scale: CGFloat) -> UIImage? {
        let key: String?
        switch cover.style {
        case .photo: key = cover.photoPath.map { photoKey($0, scale: scale) }
        case .collage: key = latestCollage[collageSlot(cover.spotId, scale: scale)]
        case .map: key = nil
        }
        return key.flatMap { memory.object(forKey: $0 as NSString) }
    }

    /// Nil when the photo is gone or there are no catch photos, so the
    /// thumbnail falls back to the map.
    static func image(for cover: SpotCover, scale: CGFloat) async -> UIImage? {
        switch cover.style {
        case .photo: return await photo(cover.photoPath, scale: scale)
        case .collage: return await collage(spotId: cover.spotId, scale: scale)
        case .map: return nil
        }
    }

    /// The latest catch photos at a spot, one per catch, newest first.
    static func collagePhotos(spotId: String, limit: Int = 4) -> [String] {
        let catches = (try? AppState.shared?.catchRepository.fetchForSpot(spotId)) ?? []
        return Array(catches.compactMap { $0.catchRecord.allPhotoPaths.first }.prefix(limit))
    }

    /// Keeps a library photo as a spot's picture: scaled to 1600 pixels on
    /// its long edge and saved through PhotoManager, which drops its
    /// location. Returns the filename.
    static func store(_ item: PhotosPickerItem, spotId: String) async -> String? {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        let name = "spot_\(spotId)_\(UUID().uuidString.prefix(8))"
        return await Task.detached(priority: .userInitiated) { () -> String? in
            guard let image = UIImage(data: data) else { return nil }
            let long = max(image.size.width, image.size.height, 1)
            let ratio = min(1, 1600 / long)
            let target = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
            let small = image.preparingThumbnail(of: target) ?? image
            return try? PhotoManager.save(small, id: name)
        }.value
    }

    // MARK: Loading

    private static func photoKey(_ path: String, scale: CGFloat) -> String {
        "photo-\(path)@\(Int(scale))"
    }

    private static func collageSlot(_ spotId: String, scale: CGFloat) -> String {
        "\(spotId)@\(Int(scale))"
    }

    private static func photo(_ path: String?, scale: CGFloat) async -> UIImage? {
        guard let path else { return nil }
        let key = photoKey(path, scale: scale)
        if let hit = memory.object(forKey: key as NSString) { return hit }
        let pixels = side * scale
        let image = await Task.detached(priority: .utility) {
            PhotoManager.thumbnail(path, maxPixel: pixels, scale: scale)
        }.value
        if let image { memory.setObject(image, forKey: key as NSString) }
        return image
    }

    private static func collage(spotId: String, scale: CGFloat) async -> UIImage? {
        let photos = collagePhotos(spotId: spotId)
        guard !photos.isEmpty else { return nil }
        let key = "collage-\(spotId)-\(fingerprint(photos))@\(Int(scale))"
        if let hit = memory.object(forKey: key as NSString) {
            latestCollage[collageSlot(spotId, scale: scale)] = key
            return hit
        }
        if let task = running[key] { return await task.value }

        let edge = side
        let task = Task.detached(priority: .utility) { () -> UIImage? in
            if let stored = readFile(key) { return stored }
            guard let drawn = drawCollage(photos, side: edge, scale: scale) else { return nil }
            writeFile(drawn, key: key, replacing: "collage-\(spotId)-")
            return drawn
        }
        running[key] = task
        let image = await task.value
        running[key] = nil

        if let image {
            memory.setObject(image, forKey: key as NSString)
            latestCollage[collageSlot(spotId, scale: scale)] = key
        }
        return image
    }

    // MARK: Drawing and files

    /// Stable across launches, unlike `hashValue`.
    nonisolated private static func fingerprint(_ photos: [String]) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in photos.joined(separator: "|").utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    /// One photo fills the square, two sit side by side, three are one tall
    /// on the left and two stacked on the right, four make a 2 by 2 grid. The
    /// gaps stay clear so the thumbnail's own background shows through.
    nonisolated private static func drawCollage(_ photos: [String], side: CGFloat, scale: CGFloat) -> UIImage? {
        let images = photos.compactMap { PhotoManager.thumbnail($0, maxPixel: side * scale, scale: scale) }
        guard !images.isEmpty else { return nil }
        let rects = tiles(count: images.count, side: side, gap: 3)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        return renderer.image { context in
            for (image, rect) in zip(images, rects) {
                context.cgContext.saveGState()
                context.cgContext.clip(to: rect)
                image.draw(in: filling(image.size, into: rect))
                context.cgContext.restoreGState()
            }
        }
    }

    nonisolated private static func tiles(count: Int, side: CGFloat, gap: CGFloat) -> [CGRect] {
        let half = (side - gap) / 2
        let far = half + gap
        let left = CGRect(x: 0, y: 0, width: half, height: side)
        let right = CGRect(x: far, y: 0, width: half, height: side)
        let topLeft = CGRect(x: 0, y: 0, width: half, height: half)
        let topRight = CGRect(x: far, y: 0, width: half, height: half)
        let bottomLeft = CGRect(x: 0, y: far, width: half, height: half)
        let bottomRight = CGRect(x: far, y: far, width: half, height: half)
        switch count {
        case 1: return [CGRect(x: 0, y: 0, width: side, height: side)]
        case 2: return [left, right]
        case 3: return [left, topRight, bottomRight]
        default: return [topLeft, topRight, bottomLeft, bottomRight]
        }
    }

    /// Where to draw an image of `size` so it fills `rect`, cropped evenly.
    nonisolated private static func filling(_ size: CGSize, into rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let factor = max(rect.width / size.width, rect.height / size.height)
        let width = size.width * factor
        let height = size.height * factor
        return CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
    }

    nonisolated private static func readFile(_ key: String) -> UIImage? {
        guard let url = folder?.appendingPathComponent("\(key).png"),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        return image.preparingForDisplay() ?? image
    }

    /// Saves a collage and drops the spot's older ones.
    nonisolated private static func writeFile(_ image: UIImage, key: String, replacing prefix: String) {
        guard let folder, let data = image.pngData() else { return }
        let fm = FileManager.default
        let stale = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in stale where name.hasPrefix(prefix) && name != "\(key).png" {
            try? fm.removeItem(at: folder.appendingPathComponent(name))
        }
        try? data.write(to: folder.appendingPathComponent("\(key).png"), options: .atomic)
    }
}

// MARK: - Choosing

/// The picture choices, shared by the edit form's menu and a spot row's
/// context menu: the map, the angler's own photo, or a collage of the
/// catches there.
struct SpotPictureMenu: View {
    @Binding var cover: Spot.Cover
    let hasPhoto: Bool
    /// Catch photos at the spot; none leaves the collage off with a reason.
    let catchPhotos: Int
    let onChoosePhoto: () -> Void

    var body: some View {
        Picker("Picture", selection: $cover.haptic()) {
            Label("Map", systemImage: "map").tag(Spot.Cover.map)
            if hasPhoto {
                Label("Your photo", systemImage: "photo").tag(Spot.Cover.photo)
            }
            if catchPhotos > 0 {
                Label("Catch collage", systemImage: "square.grid.2x2").tag(Spot.Cover.collage)
            }
        }
        .pickerStyle(.inline)
        if catchPhotos == 0 {
            Button {} label: {
                Text("Catch collage")
                Text("No catch photos here yet")
                Image(systemName: "square.grid.2x2")
            }
            .disabled(true)
        }
        Button(action: onChoosePhoto) {
            Label(hasPhoto ? "Choose another photo" : "Choose a photo", systemImage: "photo.on.rectangle")
        }
    }
}

/// The edit form's picture row: what the spot shows and a menu to change it.
/// A photo picked here is stored straight away and listed in `pickedPaths`,
/// so the sheet can keep it on save or remove it on cancel.
struct SpotPictureField: View {
    let spot: Spot
    @Binding var cover: Spot.Cover
    @Binding var photoPath: String?
    @Binding var pickedPaths: [String]

    @State private var catchPhotos = 0
    @State private var choosingPhoto = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var storing = false

    /// The spot as it would look with the choice made here.
    private var draft: Spot {
        var s = spot
        s.coverPhotoPath = photoPath
        s.cover = cover
        return s
    }

    private var title: String {
        switch draft.cover {
        case .map: "Map"
        case .photo: "Your photo"
        case .collage: catchPhotos == 0 ? "Map" : "Catch collage"
        }
    }

    private var detail: String {
        switch draft.cover {
        case .map: "Where the spot is"
        case .photo: "From your library"
        case .collage:
            switch catchPhotos {
            case 0: "Turns into a collage of your catch photos here"
            case 1: "Your catch photo here"
            default: "Your latest \(min(catchPhotos, 4)) catch photos here"
            }
        }
    }

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            PlaceSnapshotThumb(spot: draft, size: 64)
                .overlay { if storing { ProgressView() } }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.dsText)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.dsText2)
            }
            Spacer(minLength: 0)
            menu
        }
        .padding(.horizontal, DS.gutter)
        .photosPicker(isPresented: $choosingPhoto, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            pickerItem = nil
            usePhoto(item)
        }
        .task { catchPhotos = SpotCovers.collagePhotos(spotId: spot.id).count }
    }

    private var menu: some View {
        Menu {
            SpotPictureMenu(cover: $cover, hasPhoto: photoPath != nil, catchPhotos: catchPhotos) {
                choosingPhoto = true
            }
        } label: {
            HStack(spacing: 6) {
                Text("Change")
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.dsText2)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.dsText)
            .padding(.horizontal, DS.Space.s3)
            .padding(.vertical, 6)
            .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
        }
        .accessibilityLabel("Picture")
        .accessibilityValue(title)
        .disabled(storing)
    }

    private func usePhoto(_ item: PhotosPickerItem) {
        storing = true
        Task {
            let path = await SpotCovers.store(item, spotId: spot.id)
            storing = false
            guard let path else {
                ToastCenter.shared.show("Could not use that photo", style: .error)
                return
            }
            pickedPaths.append(path)
            photoPath = path
            cover = .photo
        }
    }
}
