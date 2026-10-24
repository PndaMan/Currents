import SwiftUI
import MapKit

// The parts a catch page is made of, shared by your own catch and a friend's
// public catch: the photo hero that runs up under the navigation bar, the
// line of facts under the title, the stat grid for the measurements, and the
// map render of where it was caught.

// MARK: - Hero

/// The catch's photos edge to edge, running up under the navigation bar.
/// Several photos swipe, tapping one opens the full-screen viewer, and pulling
/// the page down stretches the picture. With no photo, the species art sits on
/// its own colour, with an optional "Add a photo" button.
struct CatchHero: View {
    let photos: [UIImage]
    @Binding var index: Int
    let species: Species?
    /// Whether the catch has photos at all, which sets the hero's height
    /// before they have loaded, so the page does not jump.
    let showsPhotos: Bool
    /// Photos exist but are still loading: a plain fill, not the species art.
    var isLoading = false
    let open: () -> Void
    var addPhoto: (() -> Void)? = nil

    /// The status and navigation bars the hero runs up under, read at rest.
    @State private var barHeight: CGFloat?
    /// How far the page is pulled down past the top.
    @State private var pull: CGFloat = 0
    /// The hero's own height below the bars.
    @State private var height: CGFloat = 0
    @Environment(\.colorScheme) private var scheme

    /// Hero height as a share of the page width, below the navigation bar.
    /// Low enough that the Share, Edit and Favourite tiles clear the tab bar
    /// on a 6.1 inch phone when the page opens.
    static func factor(hasPhoto: Bool) -> CGFloat { hasPhoto ? 0.75 : 0.7 }

    private var reach: CGFloat { barHeight ?? 0 }

    /// Grows the backdrop from its bottom edge as the page is pulled down.
    private var stretch: CGFloat {
        let full = height + reach
        return full > 0 ? 1 + pull / full : 1
    }

    var body: some View {
        Color.clear
            .aspectRatio(1 / Self.factor(hasPhoto: showsPhotos), contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottom) {
                backdrop
                    .padding(.top, -reach)
                    .scaleEffect(stretch, anchor: .bottom)
            }
            .overlay { foreground }
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                measure(frame)
            }
    }

    private func measure(_ frame: CGRect) {
        let h = frame.height.rounded()
        if h != height { height = h }
        let top = max(0, frame.minY.rounded())
        if barHeight == nil, top > 0 { barHeight = top }
        let extra = max(0, top - (barHeight ?? top))
        if extra != pull { pull = extra }
    }

    // MARK: Backdrop

    @ViewBuilder private var backdrop: some View {
        if !photos.isEmpty {
            pager
        } else if isLoading {
            Color.dsFill
        } else {
            ZStack {
                Color.dsBackground
                (species?.artTint ?? Color.gray).opacity(DS.thumbTintOpacity(scheme))
            }
        }
    }

    private var pager: some View {
        TabView(selection: $index) {
            ForEach(Array(photos.enumerated()), id: \.offset) { i, image in
                CatchHeroPhoto(image: image, number: i + 1, count: photos.count, open: open)
                    .tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .always : .never))
    }

    // MARK: Foreground

    /// Only the placeholder draws over the hero; the photos are the backdrop.
    @ViewBuilder private var foreground: some View {
        if photos.isEmpty && !isLoading {
            ZStack(alignment: .bottomTrailing) {
                placeholderArt
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(true)
                if let addPhoto {
                    Button(action: addPhoto) {
                        Label("Add a photo", systemImage: "camera")
                    }
                    .buttonStyle(TonalButtonStyle(fullWidth: false))
                    .padding(.horizontal, DS.gutter)
                    .padding(.bottom, DS.Space.s4)
                }
            }
        }
    }

    @ViewBuilder private var placeholderArt: some View {
        let side = max(120, height * 0.72)
        if let species {
            SpeciesArtworkView(species: species, caught: true, size: side)
        } else {
            ThumbSymbol(systemImage: "fish.fill", tint: .dsText3, size: side)
        }
    }
}

/// One photo in the hero, filling its page and opening the viewer on tap.
private struct CatchHeroPhoto: View {
    let image: UIImage
    let number: Int
    let count: Int
    let open: () -> Void

    var body: some View {
        Color.clear
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { open() }
            .accessibilityElement()
            .accessibilityLabel(count > 1 ? "Photo \(number) of \(count)" : "Photo of the catch")
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens the photo full screen")
    }
}

// MARK: - Chrome

/// The navigation bar over the hero: clear while the hero is under it, then
/// the hard edge and the inline title once the hero and the title block have
/// scrolled away. Apply to the page's ScrollView after `detailTint`.
struct CatchHeroChrome: ViewModifier {
    let title: String
    /// `CatchHero.factor(hasPhoto:)` for the hero on the page.
    let heroFactor: CGFloat
    /// 0 with the hero under the bar, 1 once it has gone, 2 once the title has.
    @State private var stage = 0

    func body(content: Content) -> some View {
        content
            .scrollEdgeEffectHidden(stage == 0, for: .top)
            .onScrollGeometryChange(for: Int.self) { geo in
                let y = geo.contentOffset.y + geo.contentInsets.top
                let hero = geo.containerSize.width * heroFactor
                if y > hero + 72 { return 2 }
                return y > hero - 2 ? 1 : 0
            } action: { _, new in
                stage = new
            }
            // Keeps the clock legible over a bright photo, as on the map.
            .statusBarScrim()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                        .opacity(stage == 2 ? 1 : 0)
                        .animation(.easeOut(duration: DS.Motion.fast), value: stage)
                        .accessibilityHidden(stage != 2)
                }
            }
    }
}

// MARK: - Facts line

/// A short fact under the title: kept or released, a personal best, where.
struct CatchFact: Identifiable {
    let systemImage: String
    let text: String
    var tint: Color = .dsText2
    var id: String { text }
}

/// The facts as icon and text pairs on one line, stacked when they do not fit.
struct CatchFactsLine: View {
    let facts: [CatchFact]

    var body: some View {
        if !facts.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DS.Space.s4) { items }
                VStack(alignment: .leading, spacing: DS.Space.s2) { items }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.gutter)
        }
    }

    private var items: some View {
        ForEach(facts) { fact in
            Label {
                Text(fact.text)
                    .foregroundStyle(.dsText2)
            } icon: {
                Image(systemName: fact.systemImage)
                    .foregroundStyle(fact.tint)
            }
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
        }
    }
}

// MARK: - Stat grid

/// One measurement in the stat grid: a label over a large value and its unit.
struct CatchStat: Identifiable {
    let label: String
    let value: String
    var unit: String? = nil
    var id: String { label }

    init(_ label: String, value: String, unit: String? = nil) {
        self.label = label
        self.value = value
        self.unit = unit
    }

    /// From a formatted measurement such as "2.4 kg": the number large, the
    /// unit small. A value with no trailing unit word ("1′ 4″") stays whole.
    init(_ label: String, measured text: String) {
        let parts = text.split(separator: " ")
        if parts.count >= 2, let last = parts.last, last.contains(where: \.isLetter) {
            self.init(label, value: parts.dropLast().joined(separator: " "), unit: String(last))
        } else {
            self.init(label, value: text)
        }
    }
}

/// Strava's stat block: label over value, left aligned, in up to three
/// columns (two for four stats, one at accessibility sizes). No tiles.
struct CatchStatGrid: View {
    let stats: [CatchStat]
    @Environment(\.dynamicTypeSize) private var typeSize

    private var columnCount: Int {
        if typeSize.isAccessibilitySize { return 1 }
        if stats.count == 4 { return 2 }
        return min(3, max(1, stats.count))
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: DS.Space.s4, alignment: .topLeading),
              count: columnCount)
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: DS.Space.s4) {
            ForEach(stats) { stat in
                CatchStatCell(stat: stat)
            }
        }
        .padding(.horizontal, DS.gutter)
    }
}

private struct CatchStatCell: View {
    let stat: CatchStat

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(stat.label)
                .font(.subheadline)
                .foregroundStyle(.dsText2)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(stat.value)
                    .font(.title.bold())
                    .monospacedDigit()
                    .foregroundStyle(.dsText)
                    .contentTransition(.numericText())
                if let unit = stat.unit {
                    Text(unit)
                        .font(.headline)
                        .foregroundStyle(.dsText2)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Map render

/// A wide still of the map around a catch, from the same renderer and cache
/// as the place thumbnails, with a pin in the species colour. Offline with no
/// render cached, it says so instead of showing blank tiles.
struct CatchMapRender: View {
    static let height: CGFloat = 180

    let id: String
    let coordinate: CLLocationCoordinate2D
    let tint: Color
    /// Metres across the full render; about half of that shows top to bottom.
    var span: CLLocationDistance = 1200

    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale
    @AppStorage("mapStyleOption") private var mapStyleRaw = MapTab.MapStyleOption.standard.rawValue
    @State private var width: CGFloat = 0
    @State private var image: UIImage?
    @State private var finished = false

    /// Satellite when the map shows imagery, the plain map otherwise.
    private var satellite: Bool {
        switch MapTab.MapStyleOption(rawValue: mapStyleRaw) ?? .standard {
        case .standard, .fishing: false
        case .offline, .imagery, .hybrid: true
        }
    }

    /// A square render as wide as the card; the card shows its middle band.
    private var request: PlaceSnapshots.Request {
        PlaceSnapshots.Request(id: id, coordinate: coordinate, span: span, satellite: satellite,
                               dark: scheme == .dark, size: width, scale: displayScale)
    }

    var body: some View {
        ZStack {
            Color.dsFill
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
                pin
            } else if finished {
                offline
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .animation(.easeOut(duration: DS.Motion.fast), value: image != nil)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width.rounded()
        } action: { new in
            width = new
        }
        .task(id: width > 0 ? request.key : "") { await load() }
    }

    private func load() async {
        guard width > 0 else { return }
        let req = self.request
        image = PlaceSnapshots.cached(req.key)
        if image == nil {
            image = await PlaceSnapshots.image(for: req)
        }
        finished = true
    }

    private var pin: some View {
        Circle()
            .fill(tint)
            .frame(width: 16, height: 16)
            .overlay(Circle().stroke(.white, lineWidth: 2.5))
            .mapPinShadow()
    }

    private var offline: some View {
        VStack(spacing: DS.Space.s2) {
            Image(systemName: "map")
                .font(.title2)
                .foregroundStyle(.dsText3)
            Text("The map shows next time you're online.")
                .font(.footnote)
                .foregroundStyle(.dsText2)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, DS.Space.s4)
    }
}
