import SwiftUI

// Parts the Crew pages share: a strip and a grid of stat tiles, the
// reaction tiles, the Crew colours and the art for wearable titles.

// MARK: - Stat strip

/// A horizontal strip of `StatTile`s in the gutter, as on the Logbook.
struct StatStrip<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) { content }
                .padding(.horizontal, DS.gutter)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }
}

/// A short, fixed set of `StatTile`s (pass `width: nil`) filling the row
/// in the gutter: up to three across, four as two by two, one column at
/// accessibility sizes. For a set that fits, where a strip would leave the
/// row half empty or cut the last tile off.
struct StatTileGrid<Content: View>: View {
    private let columns: Int
    private let content: Content

    @Environment(\.dynamicTypeSize) private var typeSize

    init(count: Int, @ViewBuilder content: () -> Content) {
        self.columns = count == 4 ? 2 : max(1, min(count, 3))
        self.content = content()
    }

    var body: some View {
        let count = typeSize.isAccessibilitySize ? 1 : columns
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s2, alignment: .top),
                                 count: count),
                  spacing: DS.Space.s2) {
            content
        }
        .padding(.horizontal, DS.gutter)
    }
}

// MARK: - Reaction tile

/// One reaction on a crew catch: the symbol in its own colour (inked, so
/// yellow reads on white) on a faint tile of the same colour, with the count
/// under it. Yours fills stronger and gets a ring in the colour.
struct CrewReactionTile: View {
    let emoji: String
    let count: Int
    let selected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    private var tint: Color { CrewReactionStyle.tint(emoji) }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous) }
    private var fillOpacity: Double {
        if selected { return scheme == .dark ? 0.34 : 0.26 }
        return DS.thumbTintOpacity(scheme) * 0.6
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: CrewReactionStyle.symbol(emoji))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(DS.ink(tint))
                    .symbolEffect(.bounce, value: selected)
                Text(count > 0 ? "\(count)" : " ")
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(selected ? Color.dsText : Color.dsText2)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(tint.opacity(fillOpacity), in: shape)
            .overlay {
                if selected { shape.strokeBorder(tint, lineWidth: 1.5) }
            }
            .contentShape(shape)
        }
        .buttonStyle(.dim)
        .buttonHaptic(.toggle)
        .accessibilityLabel("\(CrewReactionStyle.name(emoji)), \(count)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Palette

/// The symbol colours the Crew pages share, so a fish is always blue and a
/// spot always green wherever it appears.
enum CrewTint {
    static var fish: Color { .blue }
    static var spot: Color { .dsScoreGood }
    static var exact: Color { .teal }
    static var water: Color { .cyan }
    static var region: Color { .orange }
    static var calendar: Color { DS.accent }
    static var weight: Color { .purple }
    static var length: Color { .orange }
    static var species: Color { .teal }
    static var people: Color { DS.accent }
    static var trophy: Color { .dsScoreFair }
    static var lock: Color { .orange }
    /// Something happening right now: a live trip or tournament.
    static var live: Color { .dsScoreGood }
    /// Game Center, the same green the Profile tab's Game Center section uses.
    static var gameCenter: Color { .green }
}

// MARK: - Title badge art

/// The look of one wearable title: its own symbol in its own colour, drawn
/// multicolour where the symbol has colour layers (flames, sunrise), plus a
/// small second symbol pinned to the medallion.
struct TitleArt {
    let symbol: String
    let color: Color
    var multicolor = false
    let accent: String
    let accentColor: Color

    /// Art for a title by its worn name; falls back to the achievement's own
    /// symbol in the rarity colour.
    static func of(_ flair: TitleFlair) -> TitleArt {
        table[flair.name] ?? TitleArt(symbol: flair.icon, color: flair.rarity.color,
                                      accent: "star.fill", accentColor: .dsScoreFair)
    }

    private static let table: [String: TitleArt] = [
        // Common
        "First Hook": .init(symbol: "fish.fill", color: .blue, accent: "drop.fill", accentColor: .cyan),
        "Shutterbug": .init(symbol: "camera.fill", color: .teal, accent: "bolt.fill", accentColor: .yellow),
        "Pathfinder": .init(symbol: "map.fill", color: .green, accent: "mappin", accentColor: .red),
        "Good Sport": .init(symbol: "hand.thumbsup.fill", color: .orange, accent: "heart.fill", accentColor: .pink),
        "Keeper": .init(symbol: "scalemass.fill", color: .teal, accent: "checkmark.seal.fill", accentColor: .green),
        "Doubleheader": .init(symbol: "fish.fill", color: .blue, accent: "fish.fill", accentColor: .cyan),
        "Weekend Warrior": .init(symbol: "tent.fill", color: .green, accent: "flame.fill", accentColor: .orange),
        // Uncommon
        "Rising Angler": .init(symbol: "chart.line.uptrend.xyaxis", color: .green, accent: "arrow.up", accentColor: .green),
        "Regular": .init(symbol: "star.leadinghalf.filled", color: .yellow, accent: "calendar", accentColor: .red),
        "Species Scout": .init(symbol: "binoculars.fill", color: .teal, accent: "leaf.fill", accentColor: .green),
        "Explorer": .init(symbol: "safari.fill", color: .blue, accent: "location.north.fill", accentColor: .red),
        "Photographer": .init(symbol: "camera.aperture", color: .cyan, accent: "photo.fill", accentColor: .orange),
        "On a Roll": .init(symbol: "flame.fill", color: .orange, multicolor: true, accent: "bolt.fill", accentColor: .yellow),
        "Conservationist": .init(symbol: "leaf.arrow.triangle.circlepath", color: .green, accent: "drop.fill", accentColor: .blue),
        "Hat Trick": .init(symbol: "3.circle.fill", color: .orange, accent: "fish.fill", accentColor: .blue),
        "Rod Bender": .init(symbol: "figure.fishing", color: .orange, accent: "scalemass.fill", accentColor: .teal),
        "Four Seasons": .init(symbol: "leaf.fill", color: .orange, accent: "snowflake", accentColor: .cyan),
        // Rare
        "Seasoned Angler": .init(symbol: "star.fill", color: .yellow, accent: "figure.fishing", accentColor: .blue),
        "Night Owl": .init(symbol: "moon.stars.fill", color: .purple, accent: "bird.fill", accentColor: .brown),
        "Early Riser": .init(symbol: "sunrise.fill", color: .orange, multicolor: true, accent: "alarm.fill", accentColor: .red),
        "Heavy Hitter": .init(symbol: "dumbbell.fill", color: .red, accent: "scalemass.fill", accentColor: .teal),
        "Longliner": .init(symbol: "ruler.fill", color: .orange, accent: "arrow.left.and.right", accentColor: .blue),
        "Naturalist": .init(symbol: "leaf.fill", color: .green, accent: "ladybug.fill", accentColor: .red),
        "Firebrand": .init(symbol: "flame.fill", color: .orange, multicolor: true, accent: "flame.fill", accentColor: .red),
        "Full Stringer": .init(symbol: "fish.fill", color: .blue, accent: "link", accentColor: .gray),
        "Wanderer": .init(symbol: "map.fill", color: .brown, accent: "figure.walk", accentColor: .green),
        "Sharp Eye": .init(symbol: "eye.fill", color: .cyan, accent: "scope", accentColor: .red),
        "Release Artist": .init(symbol: "arrow.uturn.backward.circle.fill", color: .green, accent: "water.waves", accentColor: .blue),
        // Epic
        "Centurion": .init(symbol: "shield.fill", color: .red, accent: "crown.fill", accentColor: .yellow),
        "Nomad": .init(symbol: "globe.europe.africa.fill", color: .blue, accent: "airplane", accentColor: .orange),
        "Water Whisperer": .init(symbol: "water.waves", color: .cyan, accent: "ear.fill", accentColor: .pink),
        "All-Season Angler": .init(symbol: "calendar.badge.checkmark", color: .red, accent: "leaf.fill", accentColor: .green),
        "Monster Hunter": .init(symbol: "scope", color: .red, accent: "fish.fill", accentColor: .blue),
        "Curator": .init(symbol: "photo.stack.fill", color: .orange, accent: "star.fill", accentColor: .yellow),
        "Big Day Hero": .init(symbol: "sun.max.fill", color: .yellow, multicolor: true, accent: "trophy.fill", accentColor: .orange),
        "Relentless": .init(symbol: "bolt.fill", color: .yellow, accent: "flame.fill", accentColor: .orange),
        "Meter Class": .init(symbol: "ruler.fill", color: .teal, accent: "checkmark.seal.fill", accentColor: .green),
        "Collector": .init(symbol: "square.grid.3x3.fill", color: .teal, accent: "leaf.fill", accentColor: .green),
        // Legendary
        "Double Centurion": .init(symbol: "shield.lefthalf.filled", color: .red, accent: "crown.fill", accentColor: .yellow),
        "Old Salt": .init(symbol: "sailboat.fill", color: .blue, accent: "water.waves", accentColor: .cyan),
        "Master of Species": .init(symbol: "crown.fill", color: .yellow, accent: "fish.fill", accentColor: .blue),
        "Unstoppable": .init(symbol: "bolt.circle.fill", color: .orange, accent: "flame.fill", accentColor: .red),
        "Trophy Hunter": .init(symbol: "trophy.fill", color: .yellow, accent: "scalemass.fill", accentColor: .teal),
        "Meter Monster": .init(symbol: "ruler.fill", color: .red, accent: "fish.fill", accentColor: .blue),
        "Water Guardian": .init(symbol: "shield.checkered", color: .blue, accent: "drop.fill", accentColor: .cyan),
        "Shutter Legend": .init(symbol: "camera.fill", color: .pink, accent: "star.fill", accentColor: .yellow),
        "World Traveler": .init(symbol: "globe.americas.fill", color: .blue, accent: "airplane", accentColor: .orange),
        // Mythic
        "Thousand Legend": .init(symbol: "medal.fill", color: .yellow, accent: "star.fill", accentColor: .orange),
        "Leviathan": .init(symbol: "hurricane", color: .blue, accent: "fish.fill", accentColor: .cyan),
        "Master of All Waters": .init(symbol: "crown.fill", color: .yellow, accent: "water.waves", accentColor: .blue),
        "Eternal Flame": .init(symbol: "flame.fill", color: .orange, multicolor: true, accent: "infinity", accentColor: .pink),
        "Bass Daddy": .init(symbol: "fish.fill", color: .green, accent: "crown.fill", accentColor: .yellow),
        "Patron": .init(symbol: "heart.fill", color: .pink, accent: "star.fill", accentColor: .yellow),
    ]
}

extension TitleFlair {
    /// The title as people read it: sentence case and British spelling
    /// ("Metre class", "World traveller"). `name` stays the key that stored
    /// profile titles and the title art look it up by.
    var displayName: String { BadgeDefinition.displayName(for: name) }
}

extension BadgeRarity {
    /// The small symbol beside the rarity name on a title badge.
    var badgeSymbol: String {
        switch self {
        case .common: return "circle"
        case .uncommon: return "circle.fill"
        case .rare: return "diamond.fill"
        case .epic: return "hexagon.fill"
        case .legendary: return "crown.fill"
        case .mythic: return "star.fill"
        }
    }
}

// MARK: - Title medallion

/// A title's round medallion: its symbol on a faint tile of its own colour,
/// the second symbol pinned bottom right, a rarity ring from rare up, a
/// slowly turning dashed ring and stars for legendary and mythic. Bounces
/// once on appear; mythic titles breathe. Reduce Motion keeps it still.
/// Symbols and stars are inked, so yellow reads on a white disc.
struct TitleMedallion: View {
    let flair: TitleFlair
    var size: CGFloat = 56
    var locked = false

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bounce = false
    @State private var turn: Double = 0

    private var art: TitleArt { TitleArt.of(flair) }
    private var rarity: BadgeRarity { flair.rarity }
    private var tint: Color { locked ? .gray : art.color }
    private var isHigh: Bool { rarity.rawValue >= BadgeRarity.legendary.rawValue }

    var body: some View {
        ZStack {
            if isHigh && !locked { orbit }
            disc
            if rarity.rawValue >= BadgeRarity.rare.rawValue && !locked {
                Circle().strokeBorder(rarity.color, lineWidth: max(2, size / 22))
            }
            accent
        }
        .frame(width: size, height: size)
        .padding(isHigh ? size * 0.12 : 0)
        .onAppear(perform: start)
        .accessibilityHidden(true)
    }

    private var disc: some View {
        ZStack {
            Circle().fill(Color.dsBackground)
            Circle().fill(tint.opacity(DS.thumbTintOpacity(scheme)))
            symbol
        }
        .clipShape(Circle())
    }

    @ViewBuilder private var symbol: some View {
        let image = Image(systemName: locked ? "lock.fill" : art.symbol)
            .font(.system(size: size * 0.44, weight: .semibold)) // ui-lint: allow, symbol scales with the medallion, not with text
        if art.multicolor && !locked {
            image
                .symbolRenderingMode(.multicolor)
                .symbolEffect(.bounce, value: bounce)
                .symbolEffect(.breathe, options: .repeating, isActive: rarity == .mythic && !reduceMotion)
        } else {
            image
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(DS.ink(tint))
                .symbolEffect(.bounce, value: bounce)
                .symbolEffect(.breathe, options: .repeating, isActive: rarity == .mythic && !reduceMotion && !locked)
        }
    }

    @ViewBuilder private var accent: some View {
        if !locked {
            Image(systemName: art.accent)
                .font(.system(size: size * 0.17, weight: .bold)) // ui-lint: allow, symbol scales with the medallion, not with text
                .foregroundStyle(DS.ink(art.accentColor))
                .frame(width: size * 0.38, height: size * 0.38)
                .background(Color.dsBackground, in: Circle())
                .overlay(Circle().strokeBorder(DS.ink(art.accentColor).opacity(0.45), lineWidth: 1))
                .offset(x: size * 0.36, y: size * 0.36)
        }
    }

    /// The dashed ring and three small stars around a legendary or mythic
    /// medallion.
    private var orbit: some View {
        ZStack {
            Circle()
                .stroke(rarity.color.opacity(0.7),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2, 5]))
                .frame(width: size * 1.22, height: size * 1.22)
                .rotationEffect(.degrees(turn))
            ForEach([-140.0, -90.0, -40.0], id: \.self) { angle in
                Image(systemName: "star.fill")
                    .font(.system(size: size * (angle == -90 ? 0.16 : 0.11))) // ui-lint: allow, symbol scales with the medallion, not with text
                    .foregroundStyle(DS.ink(rarity.color))
                    .offset(x: cos(angle * .pi / 180) * size * 0.66,
                            y: sin(angle * .pi / 180) * size * 0.66)
            }
        }
    }

    private func start() {
        guard !reduceMotion, !locked else { return }
        if rarity.rawValue >= BadgeRarity.rare.rawValue { bounce.toggle() }
        if isHigh {
            withAnimation(.linear(duration: 24).repeatForever(autoreverses: false)) { turn = 360 }
        }
    }
}

// MARK: - Title badge

/// A worn title as a badge: the medallion, the rarity in its colour, the
/// title in bold type and an optional line under it, on a card
/// tinted with the rarity colour. Rare and up get a rarity stroke; epic and
/// up a faint repeating pattern of the title's symbol behind it. At
/// accessibility sizes the medallion sits above the words, so the title gets
/// the card's full width, and the trailing mark moves to the top corner.
struct TitleBadge<Trailing: View>: View {
    let flair: TitleFlair
    var subtitle: String? = nil
    var medallionSize: CGFloat = 56
    var locked = false
    private let trailing: Trailing

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    init(flair: TitleFlair, subtitle: String? = nil, medallionSize: CGFloat = 56, locked: Bool = false,
         @ViewBuilder trailing: () -> Trailing) {
        self.flair = flair
        self.subtitle = subtitle
        self.medallionSize = medallionSize
        self.locked = locked
        self.trailing = trailing()
    }

    private var rarity: BadgeRarity { flair.rarity }
    private var tint: Color { locked ? .gray : rarity.color }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous) }

    /// Rarity colour for text: in light mode mixed toward the text colour so
    /// yellow and cyan stay readable on white.
    private var ink: Color {
        scheme == .dark ? tint : tint.mix(with: .dsText, by: 0.4)
    }

    var body: some View {
        layout
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background { backdrop }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(rarity.rawValue >= BadgeRarity.rare.rawValue && !locked
                                       ? ink.opacity(0.5) : tint.opacity(0.18),
                                   lineWidth: 1)
            }
            .opacity(locked ? 0.55 : 1)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(locked ? "\(flair.displayName), \(rarity.label) title, locked"
                                       : "\(flair.displayName), \(rarity.label) title")
    }

    @ViewBuilder private var layout: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                TitleMedallion(flair: flair, size: medallionSize, locked: locked)
                words
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay(alignment: .topTrailing) { trailing }
        } else {
            HStack(spacing: 14) {
                TitleMedallion(flair: flair, size: medallionSize, locked: locked)
                words
                    .frame(maxWidth: .infinity, alignment: .leading)
                trailing
            }
        }
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: locked ? "lock.fill" : rarity.badgeSymbol)
                    .font(.caption2.weight(.bold))
                Text(rarity.label)
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(ink)
            Text(flair.displayName)
                .font(.title3.weight(.bold))
                .foregroundStyle(.dsText)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.dsText2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var backdrop: some View {
        ZStack {
            Color.dsFill
            tint.opacity(scheme == .dark ? 0.14 : 0.10)
            if rarity.rawValue >= BadgeRarity.epic.rawValue && !locked {
                // Fainter in light, where a yellow pattern turns the card khaki.
                TitlePattern(symbol: TitleArt.of(flair).symbol, color: tint,
                             opacity: scheme == .dark ? 0.12 : 0.05)
            }
        }
    }
}

extension TitleBadge where Trailing == EmptyView {
    init(flair: TitleFlair, subtitle: String? = nil, medallionSize: CGFloat = 56, locked: Bool = false) {
        self.init(flair: flair, subtitle: subtitle, medallionSize: medallionSize, locked: locked) { EmptyView() }
    }
}

/// Rows of a small symbol at low opacity, offset and tilted, behind an epic
/// or better title.
private struct TitlePattern: View {
    let symbol: String
    let color: Color
    var opacity: Double = 0.12

    var body: some View {
        VStack(spacing: 14) {
            ForEach(0..<6, id: \.self) { row in
                HStack(spacing: 20) {
                    ForEach(0..<16, id: \.self) { _ in
                        Image(systemName: symbol).font(.footnote.weight(.semibold))
                    }
                }
                .offset(x: row.isMultiple(of: 2) ? 0 : 18)
            }
        }
        .foregroundStyle(color.opacity(opacity))
        .rotationEffect(.degrees(-14))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
