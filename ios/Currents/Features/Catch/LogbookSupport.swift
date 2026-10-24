import SwiftUI
import MapKit

// MARK: - Routes

/// Pages the Logbook stack pushes. Registered once on the Logbook root
/// (CatchesTab). Records travel by id and are read fresh on push.
enum LogbookRoute: Hashable {
    case catchDetail(String)
    case session(String)
    case plan(String)
    case streak
    case achievements
    case stats
}

// MARK: - Formatting

enum LogbookFormat {
    /// "Today", "Yesterday", a weekday within the last week, else "12 Oct",
    /// or "12 Oct 2025" for an earlier year. Day before month, as on Today.
    static func relativeDay(_ date: Date, now: Date = .now) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day ?? 99
        if days > 0 && days < 7 {
            return format(date, "EEEE")
        }
        if cal.component(.year, from: date) == cal.component(.year, from: now) {
            return format(date, "d MMM")
        }
        return format(date, "d MMM yyyy")
    }

    /// "Saturday 12 October"
    static func longDay(_ date: Date) -> String {
        ForecastFormat.longDate(date)
    }

    /// "12 Oct"
    static func shortDay(_ date: Date) -> String {
        format(date, "d MMM")
    }

    /// "12 October 2026", for when a badge was earned and on the share card.
    static func fullDate(_ date: Date) -> String {
        format(date, "d MMMM yyyy")
    }

    /// "06:40" or "6:40 am", following the 24-hour setting. Views pass their
    /// own `@AppStorage("use24HourTime")` value so they redraw when it changes.
    static func time(_ date: Date, use24: Bool = ForecastFormat.use24) -> String {
        ForecastFormat.time(date, use24: use24)
    }

    /// Fixed day-first patterns, the same way `ForecastFormat` writes dates.
    private static func format(_ date: Date, _ pattern: String) -> String {
        let f = DateFormatter()
        f.dateFormat = pattern
        return f.string(from: date)
    }

    /// "62 cm, 3.4 kg" from whatever was measured, or nil.
    static func size(_ record: Catch) -> String? {
        var parts: [String] = []
        if let l = record.lengthCm { parts.append(Units.length(cm: l)) }
        if let w = record.weightKg { parts.append(Units.weight(kg: w)) }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// "2 h 5 min" for durations on detail pages.
    static func duration(_ seconds: TimeInterval) -> String {
        ForecastFormat.elapsed(seconds)
    }
}

// MARK: - Page title

/// TodayPage's inline title for a pushed page that draws its own header (a
/// count or a hero rather than the page name): hidden at rest, faded in once
/// the header has scrolled away. Apply to the page's ScrollView.
private struct LogbookTitleFade: ViewModifier {
    let title: String
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top > 60
            } action: { _, past in
                shown = past
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                        .opacity(shown ? 1 : 0)
                        .animation(.easeOut(duration: DS.Motion.fast), value: shown)
                        .accessibilityHidden(!shown)
                }
            }
    }
}

extension View {
    /// The inline title of a Logbook page, shown only once its header has
    /// scrolled away, as on TodayPage.
    func logbookPageTitle(_ title: String) -> some View {
        modifier(LogbookTitleFade(title: title))
    }
}

// MARK: - Catch thumbnail

/// A catch's square thumbnail: its first photo, else the species art on its
/// art colour, else a fish symbol. Photos decode off the main thread.
struct CatchThumb: View {
    let detail: CatchDetail
    var size: CGFloat = 64
    @Environment(\.displayScale) private var displayScale
    @State private var photo: UIImage?

    var body: some View {
        Group {
            if let photo {
                ThumbView(image: photo, tint: detail.species?.artTint ?? .gray, size: size)
            } else if let species = detail.species {
                ThumbView(species: species, size: size)
            } else {
                ThumbView(systemImage: "fish.fill", tint: DS.accent, size: size)
            }
        }
        .task(id: detail.catchRecord.allPhotoPaths.first) {
            guard let path = detail.catchRecord.allPhotoPaths.first else { photo = nil; return }
            let px = size * displayScale
            let scale = displayScale
            photo = await Task.detached { PhotoManager.thumbnail(path, maxPixel: px, scale: scale) }.value
        }
    }
}

/// The gallery tile's art: a square photo or species art filling the width.
struct CatchTileArt: View {
    let detail: CatchDetail
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var scheme
    @State private var photo: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .background {
                ZStack {
                    Color.dsBackground
                    (detail.species?.artTint ?? DS.accent).opacity(DS.thumbTintOpacity(scheme))
                }
            }
            .overlay {
                if let photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                } else if let species = detail.species {
                    SpeciesArtworkView(species: species, caught: true, size: 120)
                        .padding(12)
                } else {
                    Image(systemName: "fish.fill")
                        .font(.largeTitle)
                        .foregroundStyle(DS.accent)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .task(id: detail.catchRecord.allPhotoPaths.first) {
                guard let path = detail.catchRecord.allPhotoPaths.first else { photo = nil; return }
                let px: CGFloat = 400 * displayScale
                let scale = displayScale
                photo = await Task.detached { PhotoManager.thumbnail(path, maxPixel: px, scale: scale) }.value
            }
    }
}

// MARK: - Search

/// Search across every catch by species, spot, notes or gear. Opens a catch
/// by handing its id back to the Logbook, which pushes it. Laid out like the
/// Explore and Today sheets: a section title over catch rows, the field
/// focused as it opens.
struct LogbookSearchSheet: View {
    let catches: [CatchDetail]
    let onOpen: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    private var results: [CatchDetail] {
        let q = trimmedQuery
        guard !q.isEmpty else { return Array(catches.prefix(30)) }
        return catches.filter { d in
            d.species?.commonName.localizedCaseInsensitiveContains(q) == true ||
            d.species?.scientificName.localizedCaseInsensitiveContains(q) == true ||
            d.spot?.name.localizedCaseInsensitiveContains(q) == true ||
            d.catchRecord.notes?.localizedCaseInsensitiveContains(q) == true ||
            d.gearLoadout?.name.localizedCaseInsensitiveContains(q) == true ||
            d.gearLoadout?.lure?.localizedCaseInsensitiveContains(q) == true
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    let found = results
                    if catches.isEmpty {
                        InlineEmpty(systemImage: "fish",
                                    text: "No catches yet. Log your first fish and you can search it here.")
                            .padding(.top, DS.Space.s4)
                    } else if found.isEmpty {
                        InlineEmpty(systemImage: "magnifyingglass",
                                    text: "No catches match. Search by species, spot, lure or notes.")
                            .padding(.top, DS.Space.s4)
                    } else {
                        SectionTitle(trimmedQuery.isEmpty ? "Recent" : "Results",
                                     detail: trimmedQuery.isEmpty ? nil : "\(found.count)")
                            .padding(.top, DS.Space.s4)
                        ForEach(found) { d in
                            Button {
                                dismiss()
                                onOpen(d.catchRecord.id)
                            } label: {
                                row(d)
                            }
                            .buttonStyle(.dsRow)
                        }
                    }
                }
                .padding(.bottom, DS.Space.s6)
            }
            .dsScreenBackground()
            .detailScrollEdge()
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Species, spot or lure")
            .searchFocused($searchFocused)
            .navigationTitle("Search catches")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { SheetDoneButton() }
            }
            .onAppear { searchFocused = true }
        }
        .dsSheet([.large])
    }

    /// The same row as the Logbook list: when and where over the species,
    /// then the size and lure.
    private func row(_ d: CatchDetail) -> some View {
        let over = [LogbookFormat.relativeDay(d.catchRecord.caughtAt), d.spot?.name]
            .compactMap { $0 }.joined(separator: ", ")
        let detail = [LogbookFormat.size(d.catchRecord), d.gearLoadout?.lure]
            .compactMap { $0 }.joined(separator: ", ")
        return ArtRow(over: over,
                      title: d.species?.commonName ?? "Unknown species",
                      subtitle: detail.isEmpty ? nil : detail,
                      chevron: true) {
            CatchThumb(detail: d, size: 52)
        }
    }
}

// MARK: - Track thumbnail

/// A session's GPS track drawn into a square thumbnail, start and end dots
/// included. With no usable track it shows a catch photo from the session
/// when there is one, else a route symbol.
struct TrackThumb: View {
    let points: [Trip.TrackPoint]
    var tint: Color = DS.accent
    var size: CGFloat = 64
    /// A catch photo from the session, for when there is no track to draw.
    var photoPath: String? = nil

    var body: some View {
        if points.count > 1 {
            ThumbView(tint: tint, size: size) {
                TrackShape(points: points)
                    .stroke(tint, style: StrokeStyle(lineWidth: max(2, size / 28), lineCap: .round, lineJoin: .round))
                    .padding(size * 0.18)
            }
        } else if let photoPath {
            PhotoThumbnail(path: photoPath, size: size,
                           cornerRadius: size < 48 ? size * 0.25 : DS.Radius.thumb) {
                symbol
            }
        } else {
            symbol
        }
    }

    private var symbol: some View {
        ThumbView(systemImage: "point.topleft.down.to.point.bottomright.curvepath", tint: tint, size: size)
    }
}

/// The track normalised into the shape's rect, keeping its aspect ratio.
struct TrackShape: Shape {
    let points: [Trip.TrackPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count > 1 else { return path }
        // Thin very long tracks so the path stays cheap to draw.
        let step = max(1, points.count / 300)
        let pts = stride(from: 0, to: points.count, by: step).map { points[$0] } + [points[points.count - 1]]
        let lats = pts.map(\.lat), lons = pts.map(\.lon)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return path }
        let w = max(maxLon - minLon, 0.00001), h = max(maxLat - minLat, 0.00001)
        let scale = min(rect.width / w, rect.height / h)
        let ox = rect.minX + (rect.width - w * scale) / 2
        let oy = rect.minY + (rect.height - h * scale) / 2
        func p(_ t: Trip.TrackPoint) -> CGPoint {
            CGPoint(x: ox + (t.lon - minLon) * scale, y: oy + (maxLat - t.lat) * scale)
        }
        path.move(to: p(pts[0]))
        for t in pts.dropFirst() { path.addLine(to: p(t)) }
        return path
    }
}

// MARK: - Key-value rows

/// Plain label and value rows with hairlines between, padded to the gutter.
struct LogbookKeyValueList: View {
    let rows: [(String, String)]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.0)
                        .foregroundStyle(.dsText2)
                    Spacer(minLength: 12)
                    Text(row.1)
                        .foregroundStyle(.dsText)
                        .multilineTextAlignment(.trailing)
                }
                .font(.body)
                .padding(.vertical, 12)
                .accessibilityElement(children: .combine)
                if i < rows.count - 1 {
                    Rectangle()
                        .fill(Color.dsSeparator)
                        .frame(height: 0.5)
                }
            }
        }
        .padding(.horizontal, DS.gutter)
    }
}

/// A short explanatory note under a section. Kept for its callers; it draws
/// the DS `SectionFootnote`, so every note reads in dsText2.
struct SectionFoot: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        SectionFootnote(text)
    }
}

/// A thin rounded progress bar that fills from the leading edge.
struct LogbookProgressBar: View {
    let fraction: Double
    var tint: Color = DS.accent
    var height: CGFloat = 8

    var body: some View {
        Capsule()
            .fill(Color.dsFill2)
            .frame(height: height)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(tint)
                        .frame(width: max(height, geo.size.width * CGFloat(min(1, max(0, fraction)))))
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Directions

/// A full-width tonal "Directions" menu: Waze, Apple Maps or Google Maps,
/// opened the same way as the app's Drive to button.
struct DirectionsButton: View {
    let coordinate: CLLocationCoordinate2D
    var name: String = ""
    @Environment(\.openURL) private var openURL

    var body: some View {
        Menu {
            Button { openWaze() } label: { Label("Waze", systemImage: "car.fill") }
            Button { openAppleMaps() } label: { Label("Apple Maps", systemImage: "map.fill") }
            Button {
                let url = URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(coordinate.latitude),\(coordinate.longitude)&travelmode=driving")
                if let url { Haptics.tap(); openURL(url) }
            } label: { Label("Google Maps", systemImage: "mappin.and.ellipse") }
        } label: {
            Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(.dsText)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Color.dsTonal, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
        }
    }

    private func openWaze() {
        Haptics.tap()
        let lat = coordinate.latitude, lon = coordinate.longitude
        let app = URL(string: "waze://?ll=\(lat),\(lon)&navigate=yes")
        let web = URL(string: "https://waze.com/ul?ll=\(lat)%2C\(lon)&navigate=yes")
        if let app {
            UIApplication.shared.open(app, options: [:]) { opened in
                if !opened, let web { UIApplication.shared.open(web) }
            }
        } else if let web {
            UIApplication.shared.open(web)
        }
    }

    private func openAppleMaps() {
        Haptics.tap()
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = name.isEmpty ? "Destination" : name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}
