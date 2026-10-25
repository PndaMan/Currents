import SwiftUI

/// Offline knot reference. Knots that have a real, openly-licensed
/// diagram or photo (bundled from Wikimedia Commons, with attribution) show it;
/// the rest show accurate numbered steps only. No invented diagrams, which are
/// misleading. Entries come from `KnotCatalog`, so new sources plug in there.
struct KnotLibraryView: View {
    private let catalog = KnotCatalog.shared
    @State private var search = ""
    @State private var category: KnotEntry.Category?
    @AppStorage("favouriteKnots") private var favouritesRaw = ""

    private var favourites: Set<String> {
        KnotFeatures.personalTools ? KnotFavourites.decode(favouritesRaw) : []
    }

    private var query: String { search.trimmingCharacters(in: .whitespaces) }

    private var filtered: [KnotEntry] {
        let matches = catalog.entries.filter { entry in
            (category == nil || entry.category == category)
            && (query.isEmpty
                || entry.name.localizedCaseInsensitiveContains(query)
                || entry.useCase.localizedCaseInsensitiveContains(query))
        }
        guard KnotFeatures.personalTools else { return matches }
        let saved = favourites
        return matches.sorted { KnotFavourites.contains($0, in: saved) && !KnotFavourites.contains($1, in: saved) }
    }

    /// Groups that have at least one entry, so a group with nothing in it
    /// (Rigs, for now) never shows as a dead chip.
    private var categories: [KnotEntry.Category?] {
        let present = KnotEntry.Category.allCases.filter { c in catalog.entries.contains { $0.category == c } }
        return [nil] + present.map { Optional($0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DetailHeader(title: "Knots", subtitle: "Step by step. Works offline.")
                PFSearchField(prompt: "Knot name or use", text: $search)
                    .padding(.top, DS.Space.s4)
                FilterChips(categories, selection: $category) { $0?.rawValue ?? "All" }
                    .padding(.top, DS.Space.s3)
                    .padding(.bottom, DS.Space.s2)
                if filtered.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { knot in
                            NavigationLink(value: KnotRoute(id: knot.id)) {
                                knotRow(knot)
                            }
                            .buttonStyle(.dsRow)
                        }
                    }
                }
            }
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
        }
        .scrollDismissesKeyboard(.interactively)
        .detailTint(nil)
        .pageTitleFade("Knots")
        .navigationDestination(for: KnotRoute.self) { route in
            if let knot = catalog.entry(id: route.id) {
                KnotDetailView(knot: knot)
            } else {
                ContentUnavailableView("Knot not found", systemImage: "questionmark.circle",
                                       description: Text("It may have been removed."))
            }
        }
    }

    /// Nothing matches the search, or the chosen group has no knots yet.
    @ViewBuilder
    private var emptyState: some View {
        if !query.isEmpty {
            InlineEmpty(systemImage: "magnifyingglass",
                        text: "No knots match \u{201C}\(query)\u{201D}. Try another name or what it is for.",
                        actionTitle: "Clear search") { search = "" }
                .padding(.top, DS.Space.s2)
        } else {
            InlineEmpty(systemImage: category?.icon ?? "point.topleft.down.to.point.bottomright.curvepath",
                        text: "No \(category?.rawValue.lowercased() ?? "knots") in the library yet. Pick another group.",
                        actionTitle: "Show all knots") { category = nil }
                .padding(.top, DS.Space.s2)
        }
    }

    private func knotRow(_ knot: KnotEntry) -> some View {
        let saved = KnotFavourites.contains(knot, in: favourites)
        let steps = knot.steps.count == 1 ? "1 step" : "\(knot.steps.count) steps"
        return ArtRow(over: "\(knot.category.rawValue), \(steps)", title: knot.name,
                      subtitle: knot.useCase, chevron: true) {
            KnotThumb(knot: knot, size: 64)
        } trailing: {
            if saved {
                Image(systemName: "star.fill")
                    .font(.footnote)
                    .foregroundStyle(DS.ink(.dsScoreFair))
                    .accessibilityLabel("Saved")
            }
        }
    }
}

struct KnotRoute: Hashable {
    let id: String
}

/// Switches for knot features that are built but not shown yet.
enum KnotFeatures {
    /// Save, the saved badge, saved-first sorting and Share. Off until knot
    /// sharing ships, so the library reads as a clean reference meanwhile.
    static let personalTools = false
}

/// Saved knots, stored as a newline-separated list of knot ids.
enum KnotFavourites {
    static func decode(_ raw: String) -> Set<String> {
        Set(raw.split(separator: "\n").map(String.init))
    }

    static func encode(_ set: Set<String>) -> String {
        set.sorted().joined(separator: "\n")
    }

    /// Older builds saved by name, so a name match still counts.
    static func contains(_ knot: KnotEntry, in set: Set<String>) -> Bool {
        set.contains(knot.id) || set.contains(knot.name)
    }
}


/// The knot's bundled line art drawn in the text colour on the cyan tint,
/// or its category symbol. The whole drawing fits inside the tile, as on the
/// knot's page: filling the square cut tall plates to meaningless slices.
/// The blank paper and the page shading round the drawing are trimmed and
/// the padding is slight, so the drawing gets most of the tile.
struct KnotThumb: View {
    let knot: KnotEntry
    var size: CGFloat = 64

    var body: some View {
        if let art = KnotImageStore.thumbArt(knot.imageName) {
            ThumbView(tint: .cyan, size: size) {
                Image(uiImage: art)
                    .renderingMode(.template)
                    .resizable().scaledToFit()
                    .foregroundStyle(Color.dsText)
                    .padding(size * 0.06)
                    .frame(width: size, height: size)
            }
            .accessibilityHidden(true)
        } else {
            ThumbView(systemImage: knot.category.icon, tint: .cyan, size: size)
        }
    }
}

struct KnotDetailView: View {
    let knot: KnotEntry
    @AppStorage("favouriteKnots") private var favouritesRaw = ""
    @State private var stepping: Int?
    @State private var showsDiagram = false
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Half height leaves no room for a step at accessibility sizes.
    private var stepDetents: Set<PresentationDetent> {
        typeSize.isAccessibilitySize ? [.large] : [.medium, .large]
    }

    private var isFavourite: Bool { KnotFavourites.contains(knot, in: KnotFavourites.decode(favouritesRaw)) }
    private var diagram: UIImage? { KnotImageStore.lineArt(knot.imageName) }

    private var shareText: String {
        let steps = knot.steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        return "\(knot.name)\n\(knot.useCase)\n\n\(steps)" + (knot.tip.isEmpty ? "" : "\n\nTip: \(knot.tip)")
    }

    private var facts: [(String, String)] {
        // A percentage is a strength; the rest describe what the knot suits.
        let strengthLabel = knot.strength.contains("%") ? "Strength" : "Good for"
        var rows = [(strengthLabel, knot.strength), ("Type", knot.category.rawValue)]
        if knot.source == .community, let author = knot.author {
            rows.append(("Shared by", author))
        }
        return rows
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                VStack(alignment: .leading, spacing: DS.Space.s4) {
                    DetailHeader(over: knot.category.rawValue, title: knot.name, subtitle: knot.useCase)
                    actions
                }

                if let img = diagram {
                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        Button { showsDiagram = true } label: {
                            Image(uiImage: img)
                                .renderingMode(.template)
                                .resizable().scaledToFit()
                                .foregroundStyle(Color.dsText)
                                .frame(maxWidth: .infinity)
                                .padding(DS.Space.s3)
                                .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                        }
                        .buttonStyle(.dim)
                        .accessibilityLabel("Diagram of the \(knot.name.lowercased())")
                        .accessibilityHint("Opens the diagram full screen")
                        if let credit = knot.attribution {
                            Text(credit)
                                .font(.caption2)
                                .foregroundStyle(.dsText3)
                        }
                    }
                    .padding(.horizontal, DS.gutter)
                }

                KeyValueList(rows: facts)

                stepsSection

                if !knot.tip.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionTitle("Tip")
                        Label(knot.tip, systemImage: "lightbulb")
                            .foregroundStyle(.dsText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, DS.Space.s4)
                            .padding(.vertical, 13)
                            .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                            .padding(.horizontal, DS.gutter)
                    }
                }
            }
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
        }
        .detailTint(nil)
        .pageTitleFade(knot.name)
        .sheet(isPresented: Binding(get: { stepping != nil }, set: { if !$0 { stepping = nil } })) {
            KnotStepSheet(knot: knot, step: stepping ?? 0)
                .dsSheet(stepDetents)
        }
        .fullScreenCover(isPresented: $showsDiagram) {
            if diagram != nil {
                KnotDiagramViewer(title: knot.name, imageName: knot.imageName)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if KnotFeatures.personalTools {
            ActionTriple {
                stepThroughButton
                Button { toggleFavourite() } label: {
                    Label(isFavourite ? "Saved" : "Save", systemImage: isFavourite ? "star.fill" : "star")
                }
                .buttonStyle(ActionTileStyle())
                .buttonHaptic(.toggle)
                ShareLink(item: shareText) {
                    ActionTileLabel("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.dim)
            }
        } else {
            ActionTriple {
                stepThroughButton
                if diagram != nil {
                    Button { showsDiagram = true } label: {
                        Label("Diagram", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(ActionTileStyle())
                }
            }
        }
    }

    /// The steps as rows on one card, like the facts above. Each opens the
    /// step-by-step sheet at that step.
    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Steps", detail: "\(knot.steps.count)")
            VStack(spacing: 0) {
                ForEach(Array(knot.steps.enumerated()), id: \.offset) { i, step in
                    Button { stepping = i } label: {
                        stepRow(number: i + 1, text: step)
                    }
                    .buttonStyle(.dim)
                    .accessibilityLabel("Step \(i + 1). \(step)")
                    .accessibilityHint("Opens this step on its own")
                    if i < knot.steps.count - 1 {
                        PFDivider(inset: 56)
                    }
                }
            }
            .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .padding(.horizontal, DS.gutter)
            SectionFootnote("Tap a step to go through them one at a time.")
        }
    }

    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.dsText)
                .frame(minWidth: 28, minHeight: 28)
                .background(Color.dsFill2, in: Circle())
            Text(text)
                .foregroundStyle(.dsText)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var stepThroughButton: some View {
        Button { stepping = 0 } label: {
            Label("Step through", systemImage: "play.fill")
        }
        .buttonStyle(ActionTileStyle(.primary))
    }

    private func toggleFavourite() {
        var set = KnotFavourites.decode(favouritesRaw)
        if KnotFavourites.contains(knot, in: set) {
            set.remove(knot.id)
            set.remove(knot.name)
        } else {
            set.insert(knot.id)
            ToastCenter.shared.show("Saved to your knots", haptic: false)
        }
        favouritesRaw = KnotFavourites.encode(set)
    }
}

/// One step at a time, with Back and Next, for tying at the water. The step
/// scrolls when large text needs more room; Back and Next stay pinned.
private struct KnotStepSheet: View {
    let knot: KnotEntry
    @State private var step: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    init(knot: KnotEntry, step: Int) {
        self.knot = knot
        _step = State(initialValue: min(max(step, 0), max(knot.steps.count - 1, 0)))
    }

    private var isLast: Bool { step >= knot.steps.count - 1 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Space.s4) {
                    if let art = KnotImageStore.lineArt(knot.imageName) {
                        Image(uiImage: art)
                            .renderingMode(.template)
                            .resizable().scaledToFit()
                            .foregroundStyle(Color.dsText)
                            .frame(maxHeight: 180)
                            .padding(DS.Space.s3)
                            .frame(maxWidth: .infinity)
                            .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                            .accessibilityHidden(true)
                    }
                    HStack(spacing: 6) {
                        ForEach(knot.steps.indices, id: \.self) { i in
                            Circle()
                                .fill(i == step ? Color.dsText : Color.dsFill2)
                                .frame(width: 7, height: 7)
                        }
                    }
                    .accessibilityHidden(true)
                    Text("Step \(step + 1) of \(knot.steps.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.dsText2)
                    Text(knot.steps.indices.contains(step) ? knot.steps[step] : "")
                        .font(.title3)
                        .foregroundStyle(.dsText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .id(step)
                        .transition(reduceMotion ? .opacity : .push(from: .trailing))
                }
                .padding(DS.gutter)
            }
            .safeAreaInset(edge: .bottom) { controls }
            .dsScreenBackground()
            .navigationTitle(knot.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var controls: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: DS.Space.s3))
            : AnyLayout(HStackLayout(spacing: DS.Space.s3))
        return layout {
            Button {
                withAnimation(reduceMotion ? nil : DS.Motion.spring) { step -= 1 }
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(.dsTonal)
            .disabled(step == 0)
            Button {
                if isLast { dismiss() } else {
                    withAnimation(reduceMotion ? nil : DS.Motion.spring) { step += 1 }
                }
            } label: {
                Label(isLast ? "Done" : "Next", systemImage: isLast ? "checkmark" : "chevron.right")
            }
            .buttonStyle(.dsPrimary)
        }
        .padding(.horizontal, DS.gutter)
        .padding(.top, DS.Space.s3)
        .padding(.bottom, DS.Space.s2)
        .background(Color.dsBackground.ignoresSafeArea())
    }
}

/// The diagram on its own, pinch or double-tap to zoom, for reading the
/// wraps at the water. Zooming reuses the photo viewer's `ZoomableImage`,
/// a UIKit view that ignores SwiftUI's foreground style, so it gets the line
/// art already drawn in the text colour for the current appearance.
private struct KnotDiagramViewer: View {
    let title: String
    let imageName: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationStack {
            Group {
                if let art = KnotImageStore.lineArt(imageName, scheme: scheme) {
                    ZoomableImage(image: art)
                } else {
                    Color.clear
                }
            }
                .background(Color.dsFill)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                .padding(DS.gutter)
                .dsScreenBackground()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Diagram of the \(title.lowercased())")
                .accessibilityAddTraits(.isImage)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

/// Loads bundled knot images from the Resources/Knots folder reference.
enum KnotImageStore {
    private static var cache: [String: UIImage] = [:]
    private static var artCache: [String: UIImage] = [:]
    static func image(_ name: String?) -> UIImage? {
        guard let name else { return nil }
        if let cached = cache[name] { return cached }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        guard let url = Bundle.main.url(forResource: base, withExtension: ext, subdirectory: "Knots")
            ?? Bundle.main.url(forResource: base, withExtension: ext),
              let img = UIImage(contentsOfFile: url.path) else { return nil }
        cache[name] = img
        return img
    }

    /// The diagram with its paper taken out, as a template image. The
    /// engravings are dark lines on white paper with no transparency, which
    /// glares in dark mode, so each pixel's darkness becomes its opacity and
    /// the lines then draw in any colour on any tint.
    static func lineArt(_ name: String?) -> UIImage? {
        guard let name else { return nil }
        if let cached = artCache[name] { return cached }
        guard let source = image(name), let art = removingPaper(from: source) else { return nil }
        artCache[name] = art
        return art
    }

    /// The line art trimmed to its ink, for thumbnails. The blank paper round
    /// the drawing and the faint page shading at a plate's edges go; every
    /// inked line stays. Falls back to the whole plate.
    static func thumbArt(_ name: String?) -> UIImage? {
        guard let name, let art = lineArt(name) else { return nil }
        let key = "\(name)|thumb"
        if let cached = artCache[key] { return cached }
        guard let cg = art.cgImage, let box = inkBounds(of: cg),
              let cropped = cg.cropping(to: box) else { return art }
        let trimmed = UIImage(cgImage: cropped, scale: art.scale, orientation: art.imageOrientation)
            .withRenderingMode(.alwaysTemplate)
        artCache[key] = trimmed
        return trimmed
    }

    /// The box, in pixels from the top left, round every pixel inked at
    /// least 30 percent, with a small margin. Page shading stays under that
    /// level. Nil when nothing is inked.
    private static func inkBounds(of cg: CGImage) -> CGRect? {
        let width = cg.width
        let height = cg.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = y * width * 4
            for x in 0..<width where pixels[row + x * 4 + 3] >= 77 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let margin = max(width, height) / 50
        let left = max(0, minX - margin)
        let top = max(0, minY - margin)
        let right = min(width, maxX + 1 + margin)
        let bottom = min(height, maxY + 1 + margin)
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    /// The line art drawn in the text colour for one appearance, for UIKit
    /// views. Cached, so the zoom view keeps the same image between updates.
    @MainActor static func lineArt(_ name: String?, scheme: ColorScheme) -> UIImage? {
        guard let name, let art = lineArt(name) else { return nil }
        let key = "\(name)|\(scheme == .dark ? "dark" : "light")"
        if let cached = artCache[key] { return cached }
        let renderer = ImageRenderer(content: Image(uiImage: art)
            .renderingMode(.template)
            .foregroundStyle(Color.dsText)
            .environment(\.colorScheme, scheme))
        renderer.scale = art.scale
        guard let drawn = renderer.uiImage else { return nil }
        artCache[key] = drawn
        return drawn
    }

    /// Turns paper white into clear and ink into opaque white. A contrast
    /// step around mid grey drops the paper (about 90 percent white) to
    /// nothing while the inked lines stay solid.
    private static func removingPaper(from image: UIImage) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let width = cg.width
        let height = cg.height
        guard width > 0, height > 0 else { return nil }
        let ink: [UInt8] = (0..<256).map { level in
            let boosted = (Double(level) / 255 - 0.5) * 1.6 + 0.5
            return UInt8(((1 - min(1, max(0, boosted))) * 255).rounded())
        }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let output: CGImage? = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            // Premultiplied white: every channel equals the alpha.
            for i in stride(from: 0, to: buffer.count, by: 4) {
                let alpha = ink[Int(buffer[i])]
                buffer[i] = alpha
                buffer[i + 1] = alpha
                buffer[i + 2] = alpha
                buffer[i + 3] = alpha
            }
            return context.makeImage()
        }
        guard let output else { return nil }
        return UIImage(cgImage: output, scale: image.scale, orientation: image.imageOrientation)
            .withRenderingMode(.alwaysTemplate)
    }
}

// MARK: - Catalog

/// The one place screens read knots from. Today it holds the built-in set;
/// knots shared by other anglers will be passed in as `community` once
/// sharing exists, and every screen picks them up unchanged.
struct KnotCatalog {
    let entries: [KnotEntry]

    init(builtIn: [KnotEntry] = KnotEntry.builtIn, community: [KnotEntry] = []) {
        // A shared knot can never replace one that ships with the app.
        let shipped = Set(builtIn.map(\.id))
        entries = builtIn + community.filter { !shipped.contains($0.id) }
    }

    static let shared = KnotCatalog()

    func entry(id: String) -> KnotEntry? {
        entries.first { $0.id == id }
    }

    func entries(from source: KnotSource) -> [KnotEntry] {
        entries.filter { $0.source == source }
    }
}

/// Where a knot entry came from.
enum KnotSource: String, Hashable {
    case builtIn
    case community
}

// MARK: - Data

struct KnotEntry: Identifiable, Hashable {
    /// Stable across app versions and devices, so saves and shared links survive renames.
    let id: String
    let name: String
    let category: Category
    let useCase: String
    let strength: String
    let steps: [String]
    let tip: String
    let imageName: String?     // bundled Resources/Knots file, if a real diagram exists
    let attribution: String?
    var source: KnotSource = .builtIn
    /// The angler who shared it. Nil for built-in knots.
    var author: String? = nil

    enum Category: String, CaseIterable {
        case terminal = "Line to hook"
        case loop = "Loops"
        case join = "Line to line"
        case rig = "Rigs"

        var icon: String {
            switch self {
            case .terminal: "link"
            case .loop: "circle"
            case .join: "arrow.triangle.merge"
            case .rig: "fish"
            }
        }
    }

    // Uniform diagram set: all illustrations are vintage line-engravings from
    // the Freshwater and Marine Image Bank (public domain), so the whole
    // library reads as one consistent style.
    private static let credit = "Illustration: Freshwater and Marine Image Bank (public domain)"

    /// The knots that ship with the app. Read them through `KnotCatalog`.
    static let builtIn: [KnotEntry] = [
        KnotEntry(
            id: "clinch",
            name: "Clinch knot",
            category: .terminal,
            useCase: "The classic tie to an eyed hook, swivel or lure.",
            strength: "About 85% of line strength",
            steps: [
                "Pass the tag end through the hook eye.",
                "Wrap the tag around the standing line 5 to 7 times.",
                "Pass the tag back through the small loop next to the eye.",
                "Wet the knot and pull the standing line to seat the coils, then trim.",
            ],
            tip: "Always wet the knot before cinching. Friction heat weakens line.",
            imageName: "clinch_down.jpeg",
            attribution: credit
        ),
        KnotEntry(
            id: "improved-jam",
            name: "Improved jam knot",
            category: .terminal,
            useCase: "A more secure clinch that tucks the tag for extra grip.",
            strength: "About 90% of line strength",
            steps: [
                "Pass the tag through the eye and wrap it around the standing line 5 or 6 times.",
                "Pass the tag back through the loop by the eye.",
                "Then tuck it through the big loop you just formed.",
                "Wet and pull to seat, then trim the tag.",
            ],
            tip: "The extra tuck stops the tag slipping under load.",
            imageName: "improved_jam.jpeg",
            attribution: credit
        ),
        KnotEntry(
            id: "fishing-gazette",
            name: "Fishing Gazette knot",
            category: .terminal,
            useCase: "A neat loop-and-jam tie for eyed hooks and flies.",
            strength: "Reliable on eyed hooks",
            steps: [
                "Double the line and pass the loop through the hook eye.",
                "Bring the loop back over the hook.",
                "Draw the standing line to slide the loop up and jam it at the eye.",
                "Wet, snug down and trim.",
            ],
            tip: "A tidy traditional knot for turned-up or turned-down eyes.",
            imageName: "gazette.jpeg",
            attribution: credit
        ),
        KnotEntry(
            id: "pennell-jam",
            name: "Jam knot (Pennell)",
            category: .terminal,
            useCase: "A simple, strong jam knot for eyed hooks.",
            strength: "Strong on the eye",
            steps: [
                "Pass the tag through the eye and form a loop against the shank.",
                "Wrap the tag around the shank and standing line a few turns.",
                "Feed the tag back through the loop.",
                "Wet and pull the standing line to jam the wraps against the eye.",
            ],
            tip: "Good for bait hooks where you want the pull in line with the shank.",
            imageName: "pennell_jam.jpeg",
            attribution: credit
        ),
        KnotEntry(
            id: "turle",
            name: "Turle knot",
            category: .terminal,
            useCase: "Seats a fly or eyed hook so it rides in line with the leader.",
            strength: "Classic fly knot",
            steps: [
                "Pass the tippet through the hook eye and slide the fly up out of the way.",
                "Make a simple loop and tie an overhand knot in the tippet.",
                "Pass the fly through the loop.",
                "Draw up so the loop seats behind the eye, then trim.",
            ],
            tip: "Keeps small flies aligned straight for a natural drift.",
            imageName: "turle.jpeg",
            attribution: credit
        ),
        KnotEntry(
            id: "snell",
            name: "Whipping a hook (snell)",
            category: .terminal,
            useCase: "Binds the line along the hook shank for a straight-line hookset.",
            strength: "Very strong on the shank",
            steps: [
                "Lay the line along the shank with a loop hanging below.",
                "Wrap the loop neatly around the shank and line toward the eye 6 to 8 turns.",
                "Hold the wraps and draw the standing line through to tighten.",
                "Seat firmly and trim.",
            ],
            tip: "Ideal for bait and octopus hooks in bottom fishing.",
            imageName: "whipping.jpeg",
            attribution: credit
        ),
        KnotEntry(
            id: "dropper-loop",
            name: "Dropper loop",
            category: .loop,
            useCase: "A standing loop for a dropper fly, second hook or sinker.",
            strength: "Strong mid-line loop",
            steps: [
                "Form a loop in the line where you want the dropper.",
                "Make several twists through the centre of the loop.",
                "Open a gap in the middle twists and pass the loop through.",
                "Wet and pull both ends so the twists gather and the loop stands out.",
            ],
            tip: "The backbone of a two-hook paternoster rig.",
            imageName: "loop_dropper.jpeg",
            attribution: credit
        ),
        KnotEntry(
            id: "double-loop",
            name: "Double loop knot",
            category: .loop,
            useCase: "A strong fixed loop at the line's end for a lure or spinning bait.",
            strength: "Strong end loop",
            steps: [
                "Double the end of the line to make a bight.",
                "Tie an overhand knot with the doubled line, passing it through twice.",
                "Keep the loop the size you want.",
                "Wet and pull all parts evenly to seat.",
            ],
            tip: "A free loop lets a bait or lure swing naturally.",
            imageName: "double_loop.jpeg",
            attribution: credit
        ),
        KnotEntry(
            id: "water-knot",
            name: "Joining two lines (water knot)",
            category: .join,
            useCase: "Join two lengths of line or a leader to the main line.",
            strength: "About 90% of line strength",
            steps: [
                "Overlap the two lines by about \(Units.length(cm: 20)).",
                "Form a loop with both lines together.",
                "Pass both ends through the loop twice to make a double overhand.",
                "Wet and pull all four strands evenly to seat, then trim the tags.",
            ],
            tip: "Simple and strong for lines of similar diameter.",
            imageName: "gut_join.jpeg",
            attribution: credit
        ),
    ]
}
