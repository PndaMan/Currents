import SwiftUI

/// Offline knot & rig reference. Knots that have a real, openly-licensed
/// diagram/photo (bundled from Wikimedia Commons, with attribution) show it;
/// the rest show accurate numbered steps only — no invented/AI diagrams, which
/// are misleading. Content is data-driven so entries are easy to extend.
struct KnotLibraryView: View {
    @State private var search = ""
    @State private var category: KnotEntry.Category?

    private var filtered: [KnotEntry] {
        KnotEntry.all.filter { entry in
            (category == nil || entry.category == category)
            && (search.isEmpty
                || entry.name.localizedCaseInsensitiveContains(search)
                || entry.useCase.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        FilterChip(title: "All", isSelected: category == nil) { category = nil }
                        ForEach(KnotEntry.Category.allCases, id: \.self) { c in
                            FilterChip(title: c.rawValue, isSelected: category == c) {
                                category = category == c ? nil : c
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
            }

            ForEach(filtered) { knot in
                NavigationLink {
                    KnotDetailView(knot: knot)
                } label: {
                    knotRowLabel(knot)
                }
            }
        }
        .navigationTitle("Knots & Rigs")
        .searchable(text: $search, prompt: "Search knots")
        .sensoryFeedback(.selection, trigger: category)
    }

    @ViewBuilder
    private func knotRowLabel(_ knot: KnotEntry) -> some View {
        HStack(spacing: 12) {
            if let img = KnotImageStore.image(knot.imageName) {
                Image(uiImage: img)
                    .resizable().scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: knot.category.icon)
                    .frame(width: 52, height: 52)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(CurrentsTheme.accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(knot.name).font(.subheadline.bold())
                Text(knot.useCase)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

struct KnotDetailView: View {
    let knot: KnotEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let img = KnotImageStore.image(knot.imageName) {
                    VStack(alignment: .leading, spacing: 4) {
                        Image(uiImage: img)
                            .resizable().scaledToFit()
                            .frame(maxWidth: .infinity)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        if let credit = knot.attribution {
                            Text(credit)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(knot.useCase).font(.subheadline)
                    HStack(spacing: 10) {
                        Label(knot.category.rawValue, systemImage: knot.category.icon)
                        Label(knot.strength, systemImage: "gauge.with.needle")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeaderView(title: "Steps", systemImage: "list.number")
                    ForEach(Array(knot.steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(i + 1)")
                                .font(.caption.bold())
                                .frame(width: 22, height: 22)
                                .background(CurrentsTheme.accent, in: Circle())
                                .foregroundStyle(.white)
                            Text(step).font(.subheadline)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()

                if !knot.tip.isEmpty {
                    Label(knot.tip, systemImage: "lightbulb")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard()
                }
            }
            .padding()
        }
        .navigationTitle(knot.name)
        .navigationBarTitleDisplayMode(.inline)
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

// MARK: - Data

struct KnotEntry: Identifiable {
    let id = UUID()
    let name: String
    let category: Category
    let useCase: String
    let strength: String
    let steps: [String]
    let tip: String
    let imageName: String?     // bundled Resources/Knots file, if a real diagram exists
    let attribution: String?

    enum Category: String, CaseIterable {
        case terminal = "Line to Hook"
        case loop = "Loops"
        case join = "Line to Line"
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

    static let all: [KnotEntry] = [
        KnotEntry(
            name: "Clinch Knot",
            category: .terminal,
            useCase: "The classic tie to an eyed hook, swivel or lure.",
            strength: "~85% line strength",
            steps: [
                "Pass the tag end through the hook eye.",
                "Wrap the tag around the standing line 5–7 times.",
                "Pass the tag back through the small loop next to the eye.",
                "Wet the knot and pull the standing line to seat the coils; trim.",
            ],
            tip: "Always wet the knot before cinching — friction heat weakens line.",
            imageName: "clinch_down.jpeg",
            attribution: credit
        ),
        KnotEntry(
            name: "Improved Jam Knot",
            category: .terminal,
            useCase: "A more secure clinch that tucks the tag for extra grip.",
            strength: "~90% line strength",
            steps: [
                "Pass the tag through the eye and wrap it around the standing line 5–6 times.",
                "Pass the tag back through the loop by the eye.",
                "Then tuck it through the big loop you just formed.",
                "Wet and pull to seat; trim the tag.",
            ],
            tip: "The extra tuck stops the tag slipping under load.",
            imageName: "improved_jam.jpeg",
            attribution: credit
        ),
        KnotEntry(
            name: "Fishing Gazette Knot",
            category: .terminal,
            useCase: "A neat loop-and-jam tie for eyed hooks and flies.",
            strength: "Reliable on eyed hooks",
            steps: [
                "Double the line and pass the loop through the hook eye.",
                "Bring the loop back over the hook.",
                "Draw the standing line to slide the loop up and jam it at the eye.",
                "Wet, snug down, and trim.",
            ],
            tip: "A tidy traditional knot for turned-up or turned-down eyes.",
            imageName: "gazette.jpeg",
            attribution: credit
        ),
        KnotEntry(
            name: "Jam Knot (Pennell)",
            category: .terminal,
            useCase: "A simple, strong jam knot for eyed hooks.",
            strength: "Strong on the eye",
            steps: [
                "Pass the tag through the eye and form a loop against the shank.",
                "Wrap the tag around the shank and standing line a few turns.",
                "Feed the tag back through the loop.",
                "Wet and pull the standing line to jam the wraps against the eye.",
            ],
            tip: "Good for bait hooks where you want the pull inline with the shank.",
            imageName: "pennell_jam.jpeg",
            attribution: credit
        ),
        KnotEntry(
            name: "Turle Knot",
            category: .terminal,
            useCase: "Seats a fly or eyed hook so it rides in line with the leader.",
            strength: "Classic fly knot",
            steps: [
                "Pass the tippet through the hook eye and slide the fly up out of the way.",
                "Make a simple loop and tie an overhand knot in the tippet.",
                "Pass the fly through the loop.",
                "Draw up so the loop seats behind the eye; trim.",
            ],
            tip: "Keeps small flies aligned straight for a natural drift.",
            imageName: "turle.jpeg",
            attribution: credit
        ),
        KnotEntry(
            name: "Whipping a Hook (Snell)",
            category: .terminal,
            useCase: "Binds the line along the hook shank for a straight-line hookset.",
            strength: "Very strong on the shank",
            steps: [
                "Lay the line along the shank with a loop hanging below.",
                "Wrap the loop neatly around the shank and line toward the eye 6–8 turns.",
                "Hold the wraps and draw the standing line through to tighten.",
                "Seat firmly and trim.",
            ],
            tip: "Ideal for bait/octopus hooks in bottom fishing.",
            imageName: "whipping.jpeg",
            attribution: credit
        ),
        KnotEntry(
            name: "Dropper Loop",
            category: .loop,
            useCase: "A standing loop for a dropper fly, second hook or sinker.",
            strength: "Strong mid-line loop",
            steps: [
                "Form a loop in the line where you want the dropper.",
                "Make several twists through the centre of the loop.",
                "Open a gap in the middle twists and pass the loop through.",
                "Wet and pull both ends so the twists gather and the loop stands out.",
            ],
            tip: "The backbone of a paternoster/two-hook bottom rig.",
            imageName: "loop_dropper.jpeg",
            attribution: credit
        ),
        KnotEntry(
            name: "Double Loop Knot",
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
            name: "Joining Two Lines (Water Knot)",
            category: .join,
            useCase: "Join two lengths of line or a leader to the main line.",
            strength: "~90% line strength",
            steps: [
                "Overlap the two lines by ~20 cm.",
                "Form a loop with both lines together.",
                "Pass both ends through the loop twice (a double overhand).",
                "Wet and pull all four strands evenly to seat; trim the tags.",
            ],
            tip: "Simple and strong for similar-diameter lines.",
            imageName: "gut_join.jpeg",
            attribution: credit
        ),
    ]
}
