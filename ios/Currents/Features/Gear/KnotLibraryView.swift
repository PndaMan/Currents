import SwiftUI

/// Offline knot & rig reference. Each entry has clear numbered steps and a
/// simple diagram drawn in SwiftUI (no bundled third-party artwork, so it
/// works offline and carries no licensing baggage). Content is data-driven so
/// entries are easy to extend.
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
                    HStack(spacing: 8) {
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
                    VStack(alignment: .leading, spacing: 3) {
                        Text(knot.name).font(.subheadline.bold())
                        Text(knot.useCase)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        HStack(spacing: 6) {
                            Label(knot.category.rawValue, systemImage: knot.category.icon)
                            Text("· \(knot.strength)")
                        }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .navigationTitle("Knots & Rigs")
        .searchable(text: $search, prompt: "Search knots")
    }
}

struct KnotDetailView: View {
    let knot: KnotEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                KnotDiagram(kind: knot.diagram)
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

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

/// Lightweight schematic diagrams drawn with SwiftUI paths — enough to convey
/// the shape of the knot without bundling copyrighted artwork.
struct KnotDiagram: View {
    enum Kind { case loop, cinch, join, snell, generic }
    let kind: Kind

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let line = GraphicsContext.Shading.color(CurrentsTheme.accent)
            var main = Path()
            main.move(to: CGPoint(x: 12, y: h / 2))
            main.addLine(to: CGPoint(x: w * 0.55, y: h / 2))
            ctx.stroke(main, with: line, lineWidth: 4)

            switch kind {
            case .loop:
                var loop = Path()
                loop.addEllipse(in: CGRect(x: w * 0.55, y: h * 0.28, width: w * 0.32, height: h * 0.44))
                ctx.stroke(loop, with: line, lineWidth: 4)
            case .cinch, .snell:
                for i in 0..<4 {
                    var coil = Path()
                    let x = w * 0.55 + CGFloat(i) * (w * 0.07)
                    coil.addEllipse(in: CGRect(x: x, y: h * 0.34, width: w * 0.05, height: h * 0.32))
                    ctx.stroke(coil, with: line, lineWidth: 3)
                }
            case .join:
                var b = Path()
                b.move(to: CGPoint(x: w * 0.55, y: h / 2))
                b.addLine(to: CGPoint(x: w - 12, y: h / 2))
                ctx.stroke(b, with: .color(.orange), lineWidth: 4)
                for i in 0..<3 {
                    var coil = Path()
                    let x = w * 0.45 + CGFloat(i) * (w * 0.06)
                    coil.addEllipse(in: CGRect(x: x, y: h * 0.36, width: w * 0.05, height: h * 0.28))
                    ctx.stroke(coil, with: line, lineWidth: 3)
                }
            case .generic:
                var k = Path()
                k.addEllipse(in: CGRect(x: w * 0.5, y: h * 0.3, width: w * 0.24, height: h * 0.4))
                ctx.stroke(k, with: line, lineWidth: 4)
            }
        }
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
    let diagram: KnotDiagram.Kind

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

    static let all: [KnotEntry] = [
        KnotEntry(
            name: "Improved Clinch Knot",
            category: .terminal,
            useCase: "The classic hook/lure/swivel tie for mono and fluoro.",
            strength: "~85% line strength",
            steps: [
                "Pass the tag end through the hook eye and make 5–7 wraps around the standing line.",
                "Pass the tag end through the small loop just above the eye.",
                "Then pass it back through the big loop you just created.",
                "Wet the knot and pull the standing line to seat the coils down to the eye.",
                "Trim the tag end close.",
            ],
            tip: "Always wet the knot before cinching — friction heat weakens the line.",
            diagram: .cinch
        ),
        KnotEntry(
            name: "Palomar Knot",
            category: .terminal,
            useCase: "Strongest, simplest tie for braid — hooks and swivels.",
            strength: "~95% line strength",
            steps: [
                "Double about 15 cm of line and pass the loop through the hook eye.",
                "Tie a loose overhand knot with the doubled line, leaving the loop hanging.",
                "Pass the hook completely through the loop.",
                "Wet it, then pull both the standing line and tag to seat the knot.",
                "Trim the tag.",
            ],
            tip: "Best knot for braided line — it barely slips.",
            diagram: .generic
        ),
        KnotEntry(
            name: "Uni Knot",
            category: .terminal,
            useCase: "Versatile all-rounder for terminal tackle in any line.",
            strength: "~90% line strength",
            steps: [
                "Run the line through the eye and double back parallel to itself.",
                "Make a loop and wrap the tag end through it and around both lines 5–6 times.",
                "Wet it and pull the tag to snug the wraps together.",
                "Slide the knot down to the eye and trim.",
            ],
            tip: "Two Uni knots tied facing each other make a great line-to-line join.",
            diagram: .cinch
        ),
        KnotEntry(
            name: "Loop Knot (Non-Slip)",
            category: .loop,
            useCase: "A free-swinging loop that lets lures move naturally.",
            strength: "~80% line strength",
            steps: [
                "Make an overhand knot ~15 cm from the tag; pass the tag through the hook eye.",
                "Pass the tag back through the overhand knot loop.",
                "Wrap the tag around the standing line 4–5 times.",
                "Pass the tag back through the overhand knot again.",
                "Wet and cinch slowly, keeping the loop size you want.",
            ],
            tip: "Ideal for suspending jerkbaits and streamers.",
            diagram: .loop
        ),
        KnotEntry(
            name: "Dropper Loop",
            category: .loop,
            useCase: "A standing loop in the middle of a line for a second hook or sinker.",
            strength: "Strong mid-line loop",
            steps: [
                "Form a loop in the line where you want the dropper.",
                "Make 5–6 twists through the loop's centre.",
                "Open a gap in the middle twists and pass the loop through it.",
                "Wet and pull both ends steadily so the twists gather and the loop stands out.",
            ],
            tip: "Great for a paternoster/two-hook bottom rig.",
            diagram: .loop
        ),
        KnotEntry(
            name: "Double Uni (Line Join)",
            category: .join,
            useCase: "Join two lines — mono to mono, or braid to leader.",
            strength: "~90% line strength",
            steps: [
                "Overlap the two lines by ~20 cm.",
                "With one tag, make a Uni knot around the other line (4 wraps for mono, 6 for braid).",
                "Repeat with the other tag around the first line.",
                "Wet both knots, then pull the standing lines so the two knots slide together.",
                "Trim both tags.",
            ],
            tip: "Use more wraps on the thinner/braided side.",
            diagram: .join
        ),
        KnotEntry(
            name: "FG Knot (Braid to Leader)",
            category: .join,
            useCase: "Slim, super-strong braid-to-fluoro leader join for casting.",
            strength: "~95% line strength",
            steps: [
                "Keep the braid under tension and lay the leader across it.",
                "Weave the braid over-and-under the leader ~20 times (10 each side).",
                "Lock with two half hitches around both lines, then several around the leader tag.",
                "Trim the leader tag, add more half hitches on the braid, and trim.",
            ],
            tip: "Fiddly but the thinnest, strongest connection — worth practising at home.",
            diagram: .join
        ),
        KnotEntry(
            name: "Snell Knot",
            category: .terminal,
            useCase: "Ties directly to a hook shank for a straight-line hookset (bait hooks).",
            strength: "Very strong on the shank",
            steps: [
                "Pass the tag through the hook eye from the point side and along the shank.",
                "Form a loop along the shank.",
                "Wrap the loop around the shank and line 6–8 times toward the eye.",
                "Hold the wraps and pull the standing line to tighten.",
            ],
            tip: "Best with octopus/bait-holder hooks for bottom fishing.",
            diagram: .snell
        ),
        KnotEntry(
            name: "Carolina Rig",
            category: .rig,
            useCase: "Bottom rig that lets a soft plastic drift naturally behind a sliding weight.",
            strength: "—",
            steps: [
                "Thread a bullet/egg sinker onto the main line, then a bead.",
                "Tie the main line to a swivel.",
                "Add a 30–90 cm fluoro leader to the other end of the swivel.",
                "Tie your hook to the leader and rig your soft plastic weedless.",
            ],
            tip: "Longer leader = more natural fall; shorter = more bottom contact.",
            diagram: .generic
        ),
        KnotEntry(
            name: "Paternoster (Bottom) Rig",
            category: .rig,
            useCase: "Surf/bottom rig presenting bait above the seabed with the sinker below.",
            strength: "—",
            steps: [
                "Tie a dropper loop 30–40 cm up the line for the hook snood.",
                "Attach a baited hook to the dropper loop.",
                "Tie the sinker to the bottom end of the line below the dropper.",
                "Add a swivel at the top to connect to the main line.",
            ],
            tip: "Keep the snood shorter than the drop to reduce tangles on the cast.",
            diagram: .generic
        ),
    ]
}
