import SwiftUI

/// Offline knot and rig reference. Knots that have a real, openly-licensed
/// diagram or photo (bundled from Wikimedia Commons, with attribution) show it;
/// the rest show accurate numbered steps only. No invented diagrams, which are
/// misleading. Entries come from `KnotCatalog`, so new sources plug in there.
struct KnotLibraryView: View {
    private let catalog = KnotCatalog.shared
    @State private var search = ""
    @State private var category: KnotEntry.Category?
    @State private var titleShown = false
    @AppStorage("favouriteKnots") private var favouritesRaw = ""

    private var favourites: Set<String> {
        KnotFeatures.personalTools ? KnotFavourites.decode(favouritesRaw) : []
    }

    private var filtered: [KnotEntry] {
        let matches = catalog.entries.filter { entry in
            (category == nil || entry.category == category)
            && (search.isEmpty
                || entry.name.localizedCaseInsensitiveContains(search)
                || entry.useCase.localizedCaseInsensitiveContains(search))
        }
        guard KnotFeatures.personalTools else { return matches }
        let saved = favourites
        return matches.sorted { KnotFavourites.contains($0, in: saved) && !KnotFavourites.contains($1, in: saved) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                DetailHeader(title: "Knots and rigs", subtitle: "Step by step. Works offline.")
                PFSearchField(prompt: "Search knots", text: $search)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Chip("All", isSelected: category == nil) { category = nil }
                        ForEach(KnotEntry.Category.allCases, id: \.self) { c in
                            Chip(c.rawValue, isSelected: category == c) {
                                category = category == c ? nil : c
                            }
                        }
                    }
                    .padding(.horizontal, DS.gutter)
                }

                if filtered.isEmpty {
                    ContentUnavailableView("No knots found", systemImage: "magnifyingglass",
                                           description: Text("Try clinch, loop or snell."))
                        .padding(.top, DS.Space.s6)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { knot in
                            NavigationLink(value: KnotRoute(id: knot.id)) {
                                knotRow(knot)
                            }
                            .buttonStyle(.dim)
                        }
                    }
                }
            }
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
        }
        .detailTint(.cyan)
        .pfTrackScroll($titleShown, threshold: 60)
        .pfScrollTitle("Knots and rigs", shown: titleShown)
        .navigationDestination(for: KnotRoute.self) { route in
            if let knot = catalog.entry(id: route.id) {
                KnotDetailView(knot: knot)
            } else {
                ContentUnavailableView("Knot not found", systemImage: "questionmark.circle",
                                       description: Text("It may have been removed."))
            }
        }
    }

    private func knotRow(_ knot: KnotEntry) -> some View {
        HStack(spacing: 14) {
            KnotThumb(knot: knot, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(knot.name)
                        .foregroundStyle(.dsText)
                        .lineLimit(1)
                    if KnotFavourites.contains(knot, in: favourites) {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("Saved")
                    }
                }
                Text(knot.useCase)
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                    .lineLimit(1)
                Text("\(knot.category.rawValue), \(knot.steps.count) steps")
                    .font(.footnote)
                    .foregroundStyle(.dsText3)
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, DS.gutter)
        .padding(.vertical, DS.Space.s2)
        .contentShape(Rectangle())
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

/// The knot's bundled illustration on white, or its category symbol.
struct KnotThumb: View {
    let knot: KnotEntry
    var size: CGFloat = 56

    var body: some View {
        if let img = KnotImageStore.image(knot.imageName) {
            Image(uiImage: img)
                .resizable().scaledToFill()
                .frame(width: size, height: size)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous))
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
    @State private var titleShown = false

    private var isFavourite: Bool { KnotFavourites.contains(knot, in: KnotFavourites.decode(favouritesRaw)) }
    private var diagram: UIImage? { KnotImageStore.image(knot.imageName) }

    private var shareText: String {
        let steps = knot.steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        return "\(knot.name)\n\(knot.useCase)\n\n\(steps)" + (knot.tip.isEmpty ? "" : "\n\nTip: \(knot.tip)")
    }

    private var facts: [(String, String)] {
        var rows = [("Strength", knot.strength), ("Type", knot.category.rawValue)]
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
                                .resizable().scaledToFit()
                                .frame(maxWidth: .infinity)
                                .padding(DS.Space.s3)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
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

                PFKeyValueCard(rows: facts)

                VStack(alignment: .leading, spacing: 0) {
                    SectionTitle("Steps", detail: "\(knot.steps.count)")
                    VStack(spacing: DS.Space.s2) {
                        ForEach(Array(knot.steps.enumerated()), id: \.offset) { i, step in
                            Button { stepping = i } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Text("\(i + 1)")
                                        .font(.subheadline.weight(.semibold))
                                        .monospacedDigit()
                                        .frame(width: 28, height: 28)
                                        .background(Color.dsFill2, in: Circle())
                                        .foregroundStyle(.dsText)
                                    Text(step)
                                        .foregroundStyle(.dsText)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(DS.Space.s3)
                                .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
                            }
                            .buttonStyle(.dim)
                            .accessibilityLabel("Step \(i + 1). \(step)")
                        }
                    }
                    .padding(.horizontal, DS.gutter)
                }

                if !knot.tip.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionTitle("Tip")
                        Text(knot.tip)
                            .foregroundStyle(.dsText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(DS.Space.s4)
                            .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                            .padding(.horizontal, DS.gutter)
                    }
                }
            }
            .padding(.bottom, DS.Space.s8)
            .pageWidth()
        }
        .detailTint(.cyan)
        .pfTrackScroll($titleShown, threshold: 100)
        .pfScrollTitle(knot.name, shown: titleShown)
        .sheet(isPresented: Binding(get: { stepping != nil }, set: { if !$0 { stepping = nil } })) {
            KnotStepSheet(knot: knot, step: stepping ?? 0)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showsDiagram) {
            if let img = diagram {
                KnotDiagramViewer(title: knot.name, image: img)
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

/// One step at a time, with Back and Next, for tying at the water.
private struct KnotStepSheet: View {
    let knot: KnotEntry
    @State private var step: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(knot: KnotEntry, step: Int) {
        self.knot = knot
        _step = State(initialValue: min(max(step, 0), max(knot.steps.count - 1, 0)))
    }

    private var isLast: Bool { step >= knot.steps.count - 1 }

    var body: some View {
        NavigationStack {
            VStack(spacing: DS.Space.s4) {
                if let img = KnotImageStore.image(knot.imageName) {
                    Image(uiImage: img)
                        .resizable().scaledToFit()
                        .frame(maxHeight: 180)
                        .padding(DS.Space.s3)
                        .frame(maxWidth: .infinity)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
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
                    .frame(maxWidth: .infinity)
                    .id(step)
                    .transition(reduceMotion ? .opacity : .push(from: .trailing))
                Spacer(minLength: 0)
                HStack(spacing: DS.Space.s3) {
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
            }
            .padding(DS.gutter)
            .navigationTitle(knot.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

/// The diagram on its own, pinch or double-tap to zoom, for reading the
/// wraps at the water. Zooming reuses the photo viewer's `ZoomableImage`.
private struct KnotDiagramViewer: View {
    let title: String
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZoomableImage(image: image)
                .background(Color.white)
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
                "Overlap the two lines by about 20 cm.",
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
