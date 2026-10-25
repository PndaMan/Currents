import SwiftUI
import UIKit

// MARK: - Metrics

/// Catch pins follow the Photos app's Places map: the catch's photo in a
/// white frame with a small pointer at the spot, and a fanned stack with a
/// count when catches merge on zoom out. Shared by the SwiftUI map and the
/// UIKit offline map so both draw the same pin.
enum CatchPinMetrics {
    /// Edge of the photo inside the frame.
    static let photo: CGFloat = 44
    /// White frame around the photo.
    static let border: CGFloat = 3
    static let card: CGFloat = photo + border * 2
    /// Outer corner of the frame; the photo's corner follows it inside.
    static let radius: CGFloat = DS.Radius.thumb
    static let photoRadius: CGFloat = radius - border
    static let pointerWidth: CGFloat = 14
    static let pointerHeight: CGFloat = 7
    /// The pointer tucks one point under the frame.
    static let pointerOverlap: CGFloat = 1
    /// Frame plus pointer. The pointer's tip is the bottom edge.
    static let height: CGFloat = card + pointerHeight - pointerOverlap
    /// Where the count badge sits past the top trailing corner.
    static let badgeOffset: CGFloat = 9
    static let badgeHeight: CGFloat = 22
    /// The top photo, then the ones fanned behind it: degrees and points.
    static let fan: [(angle: Double, x: CGFloat, y: CGFloat)] = [(0, 0, 0), (-9, -7, -2), (8, 7, -4)]
    /// Thumbnails decode at 3x, which covers every iPhone screen.
    static let decodeScale: CGFloat = 3
}

// MARK: - Photo loading

/// Pin-sized catch photos. Decoded off the main thread through
/// `PhotoManager.thumbnail` (the same downsampling the Logbook uses) and kept
/// in memory by filename, so a map with hundreds of catches redraws without
/// touching the disk. New photos always get new filenames, so a cached entry
/// never goes stale.
enum CatchPinPhotos {
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 300
        return c
    }()

    /// First photo per photo list, so redrawing hundreds of pins does not
    /// decode each catch's JSON list every time.
    private static let firstPaths: NSCache<NSString, NSString> = {
        let c = NSCache<NSString, NSString>()
        c.countLimit = 2000
        return c
    }()

    /// The photo a pin shows: the catch's first.
    static func path(for record: Catch) -> String? {
        guard let list = record.photoPaths else { return record.photoPath }
        if let hit = firstPaths.object(forKey: list as NSString) { return hit as String }
        let first = record.allPhotoPaths.first
        if let first { firstPaths.setObject(first as NSString, forKey: list as NSString) }
        return first
    }

    /// Cheap check that skips decoding the photo list.
    static func hasPhoto(_ detail: CatchDetail) -> Bool {
        detail.catchRecord.photoPath != nil || detail.catchRecord.photoPaths != nil
    }

    /// A photo already in memory, for drawing without a placeholder frame.
    static func cached(_ path: String) -> UIImage? {
        cache.object(forKey: path as NSString)
    }

    static func load(_ path: String) async -> UIImage? {
        if let hit = cached(path) { return hit }
        let px = CatchPinMetrics.photo * CatchPinMetrics.decodeScale
        let scale = CatchPinMetrics.decodeScale
        let image = await Task.detached(priority: .utility) {
            PhotoManager.thumbnail(path, maxPixel: px, scale: scale)
        }.value
        if let image { cache.setObject(image, forKey: path as NSString) }
        return image
    }

    /// The catches a stack draws, top first: ones with photos lead, newest
    /// first within each group (the order clustering hands them over in).
    static func stackTop(_ catches: [CatchDetail], limit: Int = CatchPinMetrics.fan.count) -> [CatchDetail] {
        var picked = Array(catches.lazy.filter { hasPhoto($0) }.prefix(limit))
        if picked.count < limit {
            picked += catches.lazy.filter { !hasPhoto($0) }.prefix(limit - picked.count)
        }
        return picked
    }
}

/// VoiceOver text for catch pins.
enum CatchPinText {
    /// "Largemouth bass catch, 12 March"; the year is added when it is not
    /// this year.
    static func label(_ detail: CatchDetail) -> String {
        let date = detail.catchRecord.caughtAt
        let thisYear = Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
        let f = DateFormatter()
        f.dateFormat = thisYear ? "d MMMM" : "d MMMM yyyy"
        let day = f.string(from: date)
        if let name = detail.species?.commonName { return "\(name) catch, \(day)" }
        return "Catch, \(day)"
    }

    static func stack(_ count: Int) -> String {
        "Stack of \(count) catches"
    }

    static func badge(_ count: Int) -> String {
        count > 99 ? "99+" : "\(count)"
    }
}

// MARK: - SwiftUI pins

/// What fills a catch pin's frame: the catch's first photo, else its species
/// art on the art colour, else a fish on the accent. A photo already in
/// memory shows at once, so a stack that re-forms while zooming never
/// flashes its placeholder; otherwise it cross-fades in when decoded.
struct CatchPinFace: View {
    let detail: CatchDetail
    var size: CGFloat = CatchPinMetrics.photo
    var cornerRadius: CGFloat = CatchPinMetrics.photoRadius

    private struct LoadedPhoto {
        let path: String
        let image: UIImage
    }

    @State private var loaded: LoadedPhoto?

    init(detail: CatchDetail, size: CGFloat = CatchPinMetrics.photo,
         cornerRadius: CGFloat = CatchPinMetrics.photoRadius) {
        self.detail = detail
        self.size = size
        self.cornerRadius = cornerRadius
        if let path = CatchPinPhotos.path(for: detail.catchRecord),
           let image = CatchPinPhotos.cached(path) {
            _loaded = State(initialValue: LoadedPhoto(path: path, image: image))
        }
    }

    private var path: String? { CatchPinPhotos.path(for: detail.catchRecord) }

    var body: some View {
        ZStack {
            if let loaded, loaded.path == path {
                Image(uiImage: loaded.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .transition(.opacity)
            } else if let species = detail.species {
                ThumbView(species: species, size: size)
            } else {
                ThumbView(systemImage: "fish.fill", tint: DS.accent, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: path) {
            guard let path, loaded?.path != path else { return }
            guard let image = await CatchPinPhotos.load(path), !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: DS.Motion.fast)) {
                loaded = LoadedPhoto(path: path, image: image)
            }
        }
    }
}

/// One catch in its white frame.
struct CatchPhotoCard: View {
    let detail: CatchDetail

    var body: some View {
        CatchPinFace(detail: detail)
            .padding(CatchPinMetrics.border)
            .background(Color.white, in: RoundedRectangle(cornerRadius: CatchPinMetrics.radius, style: .continuous))
    }
}

/// The small triangle under a pin, its tip on the spot. Slightly rounded at
/// the tip, as Apple's callout pointers are.
struct CatchPinPointer: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let tip = rect.width * 0.12
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX + tip, y: rect.maxY - tip))
        p.addQuadCurve(to: CGPoint(x: rect.midX - tip, y: rect.maxY - tip),
                       control: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

private struct CatchPinPointerView: View {
    var body: some View {
        CatchPinPointer()
            .fill(Color.white)
            .frame(width: CatchPinMetrics.pointerWidth, height: CatchPinMetrics.pointerHeight)
    }
}

/// A single catch on the map. Place it with a bottom anchor: the pointer's
/// tip is the bottom edge.
struct CatchPhotoPin: View {
    let detail: CatchDetail

    var body: some View {
        VStack(spacing: -CatchPinMetrics.pointerOverlap) {
            CatchPhotoCard(detail: detail)
            CatchPinPointerView()
        }
        // One shadow for frame and pointer together.
        .compositingGroup()
        .mapPinShadow()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CatchPinText.label(detail))
    }
}

/// Catches merged on zoom out: the top photo with one or two more fanned
/// behind it, slightly turned, and a badge with how many the stack holds.
/// The fan opens with a spring as the stack forms, and the count rolls when
/// it changes. Reduce Motion shows it open and still.
struct CatchPhotoStack: View {
    /// Top first, as `CatchPinPhotos.stackTop` orders them.
    let catches: [CatchDetail]
    let count: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var open = false

    private struct Layer: Identifiable {
        let index: Int
        let detail: CatchDetail
        var id: String { detail.id }
    }

    /// The photos behind the top one, farthest first so it draws first.
    private var behind: [Layer] {
        let shown = catches.prefix(CatchPinMetrics.fan.count).enumerated()
            .map { Layer(index: $0.offset, detail: $0.element) }
            .filter { $0.index > 0 }
        return Array(shown.reversed())
    }

    private var fanned: Bool { open || reduceMotion }

    var body: some View {
        ZStack(alignment: .top) {
            ForEach(behind) { layer in
                let fan = CatchPinMetrics.fan[layer.index]
                // Each frame casts its own shadow so white edges stay apart
                // where they overlap.
                CatchPhotoCard(detail: layer.detail)
                    .mapPinShadow()
                    .rotationEffect(.degrees(fanned ? fan.angle : 0))
                    .offset(x: fanned ? fan.x : 0, y: fanned ? fan.y : 0)
            }
            if let top = catches.first {
                VStack(spacing: -CatchPinMetrics.pointerOverlap) {
                    CatchPhotoCard(detail: top)
                    CatchPinPointerView()
                }
                .compositingGroup()
                .mapPinShadow()
                .id(top.id)
            }
        }
        .overlay(alignment: .topTrailing) { badge }
        .scaleEffect(fanned ? 1 : 0.85, anchor: .bottom)
        .animation(reduceMotion ? nil : DS.Motion.spring, value: count)
        .animation(reduceMotion ? nil : DS.Motion.softSpring, value: catches.map(\.id))
        .onAppear {
            guard !open else { return }
            withAnimation(reduceMotion ? nil : DS.Motion.spring) { open = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CatchPinText.stack(count))
    }

    private var badge: some View {
        Text(CatchPinText.badge(count))
            .font(.caption2.weight(.bold))
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(count)))
            .foregroundStyle(.dsOnPrimary)
            .padding(.horizontal, 6)
            .frame(minWidth: CatchPinMetrics.badgeHeight, minHeight: CatchPinMetrics.badgeHeight)
            .background(Color.dsPrimaryButton, in: Capsule())
            .overlay(Capsule().stroke(Color.dsBackground, lineWidth: 1.5))
            .fixedSize()
            .offset(x: CatchPinMetrics.badgeOffset, y: -CatchPinMetrics.badgeOffset)
    }
}
