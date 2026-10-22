import SwiftUI
import MapKit

// MARK: - Features and clustering

/// Anything Explore draws as a pin.
enum ExploreFeature: Identifiable {
    case spot(Spot)
    case water(Waterbody)
    case catchPin(CatchDetail)
    case ramp(BoatRamp)

    var id: String {
        switch self {
        case .spot(let s): "spot:\(s.id)"
        case .water(let w): "water:\(w.id ?? 0):\(w.name)"
        case .catchPin(let c): "catch:\(c.catchRecord.id)"
        case .ramp(let r): "ramp:\(r.id)"
        }
    }

    var coordinate: CLLocationCoordinate2D {
        switch self {
        case .spot(let s): CLLocationCoordinate2D(latitude: s.latitude, longitude: s.longitude)
        case .water(let w): CLLocationCoordinate2D(latitude: w.latitude, longitude: w.longitude)
        case .catchPin(let c): CLLocationCoordinate2D(latitude: c.catchRecord.latitude, longitude: c.catchRecord.longitude)
        case .ramp(let r): r.coordinate
        }
    }

    /// Spots lead a cluster, then water, catches and ramps.
    var priority: Int {
        switch self {
        case .spot: 0
        case .water: 1
        case .catchPin: 2
        case .ramp: 3
        }
    }

    var name: String {
        switch self {
        case .spot(let s): s.name
        case .water(let w): w.name
        case .catchPin(let c): c.species?.commonName ?? "Catch"
        case .ramp(let r): r.name
        }
    }

    var isCatch: Bool {
        if case .catchPin = self { return true }
        return false
    }

    /// Spots and catches draw as square art; water and places as round dots.
    var isSquare: Bool {
        switch self {
        case .spot, .catchPin: true
        case .water, .ramp: false
        }
    }
}

struct PinCluster: Identifiable {
    let members: [ExploreFeature]
    /// A cluster keeps its id while its count changes, so a photo stack stays
    /// the same view as the map zooms and its count can roll.
    var id: String { members.count == 1 ? members[0].id : "cluster:\(members[0].id)" }
    var coordinate: CLLocationCoordinate2D { members[0].coordinate }
    var lead: ExploreFeature { members[0] }

    /// The catches, when every member is one: the cluster draws as a photo
    /// stack.
    var catches: [CatchDetail]? {
        var out: [CatchDetail] = []
        for member in members {
            guard case .catchPin(let c) = member else { return nil }
            out.append(c)
        }
        return out
    }
}

/// Luma's map clustering: pins closer than about 64 points on screen merge
/// into a fanned stack, led by the most important pin. Below street level
/// every pin stands on its own.
///
/// Catches cluster only with catches, newest first, so a catch photo never
/// hides inside a spot's cluster and each stack shows its latest catch on
/// top. Spots, water and ramps merge together, led by spots. Catches logged
/// within `stackMetres` of each other stay stacked even at street level,
/// since zooming can never pull them apart; tapping that stack lists them.
enum PinClustering {
    /// Catches this close to a stack's lead never split by zooming.
    static let stackMetres: CLLocationDistance = 15

    /// Distance from the first catch to the farthest one.
    static func spread(_ catches: [CatchDetail]) -> CLLocationDistance {
        guard let first = catches.first else { return 0 }
        let origin = CLLocation(latitude: first.catchRecord.latitude, longitude: first.catchRecord.longitude)
        return catches.map {
            CLLocation(latitude: $0.catchRecord.latitude, longitude: $0.catchRecord.longitude).distance(from: origin)
        }.max() ?? 0
    }

    /// The catches of a stack that zooming cannot split, newest first, for
    /// a tap to list. Nil for any other cluster, which zooms in on tap.
    static func inseparableCatches(_ cluster: PinCluster) -> [CatchDetail]? {
        guard let catches = cluster.catches, catches.count > 1, spread(catches) < stackMetres else { return nil }
        return catches.sorted { $0.catchRecord.caughtAt > $1.catchRecord.caughtAt }
    }

    static func cluster(_ features: [ExploreFeature], latSpan: Double) -> [PinCluster] {
        var places: [ExploreFeature] = []
        var catches: [(feature: ExploreFeature, caughtAt: Date)] = []
        for f in features {
            if case .catchPin(let c) = f {
                catches.append((feature: f, caughtAt: c.catchRecord.caughtAt))
            } else {
                places.append(f)
            }
        }
        let sortedPlaces = places.sorted { $0.priority < $1.priority }
        let sortedCatches = catches.sorted { $0.caughtAt > $1.caughtAt }.map { $0.feature }
        // About 111 km to a degree of latitude.
        let stackRadius = stackMetres / 111_320
        guard latSpan > 0.04 else {
            return sortedPlaces.map { PinCluster(members: [$0]) } + group(sortedCatches, radius: stackRadius)
        }
        let radius = latSpan * 0.075
        return group(sortedPlaces, radius: radius) + group(sortedCatches, radius: max(radius, stackRadius))
    }

    /// Greedy grouping: each feature joins the first anchor within `radius`
    /// degrees, else starts its own group. Input order decides the leads.
    private static func group(_ sorted: [ExploreFeature], radius: Double) -> [PinCluster] {
        var groups: [[ExploreFeature]] = []
        var anchors: [CLLocationCoordinate2D] = []
        for f in sorted {
            let c = f.coordinate
            let k = cos(c.latitude * .pi / 180)
            if let i = anchors.firstIndex(where: { a in
                let dLat = a.latitude - c.latitude
                let dLon = (a.longitude - c.longitude) * k
                return (dLat * dLat + dLon * dLon).squareRoot() < radius
            }) {
                groups[i].append(f)
            } else {
                groups.append([f])
                anchors.append(c)
            }
        }
        return groups.map { PinCluster(members: $0) }
    }

    /// The region that splits a cluster when the map zooms to it.
    static func region(for cluster: PinCluster, currentSpan: Double) -> MKCoordinateRegion {
        let lats = cluster.members.map(\.coordinate.latitude)
        let lons = cluster.members.map(\.coordinate.longitude)
        let center = CLLocationCoordinate2D(
            latitude: ((lats.min() ?? 0) + (lats.max() ?? 0)) / 2,
            longitude: ((lons.min() ?? 0) + (lons.max() ?? 0)) / 2
        )
        let spread = max((lats.max() ?? 0) - (lats.min() ?? 0), (lons.max() ?? 0) - (lons.min() ?? 0))
        let span = min(currentSpan / 2.5, max(spread * 3, 0.02))
        return MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span))
    }
}

// MARK: - Pin art

/// Explore's three pin shapes, so a glance tells them apart, like Apple Maps'
/// category glyphs: your spots are square cards with species art, water is a
/// round blue glyph, and public fishing access and ramps are small white dots.
struct PinArt: View {
    let feature: ExploreFeature
    var topSpecies: Species?
    var size: CGFloat = 46

    var body: some View {
        switch feature {
        case .spot(let spot):
            card {
                if let topSpecies {
                    ThumbView(species: topSpecies, size: size)
                } else {
                    ThumbView(systemImage: spot.type.icon, tint: DS.accent, size: size)
                }
            }
        case .catchPin(let c):
            card {
                CatchPinFace(detail: c, size: size, cornerRadius: cardRadius)
            }
        case .water(let w):
            WaterDot(type: w.type, size: size)
        case .ramp(let r):
            PlaceDot(kind: r.kind, size: size)
        }
    }

    /// The same corner ThumbView uses at this size.
    private var cardRadius: CGFloat { size < 48 ? size * 0.25 : DS.Radius.thumb }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .overlay(
                RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                    .stroke(Color.white, lineWidth: 2.5)
            )
            .mapPinShadow()
    }
}

/// Water's glyph: a blue disc with a white rim.
struct WaterDot: View {
    let type: Waterbody.WaterbodyType
    var size: CGFloat = ExploreMetrics.waterDot

    var body: some View {
        Circle()
            .fill(Color.exploreWater)
            .overlay {
                Image(systemName: ExploreFormat.waterIcon(type))
                    .font(size > 36 ? Font.body.weight(.bold) : Font.footnote.weight(.bold))
                    .foregroundStyle(.white)
            }
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .frame(width: size, height: size)
            .mapPinShadow()
    }
}

/// A public fishing access point or boat ramp: a small white disc.
struct PlaceDot: View {
    let kind: BoatRamp.Kind
    var size: CGFloat = ExploreMetrics.placeDot

    var body: some View {
        Circle()
            .fill(Color.white)
            .overlay {
                Image(systemName: kind.icon)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(kind == .access ? DS.accent : Color.black.opacity(0.75))
            }
            .frame(width: size, height: size)
            .mapPinShadow()
    }
}

/// The name under a pin, with a halo so it reads on any map style.
struct PinLabel: View {
    let title: String
    var detail: String? = nil
    /// Water names take the water ink, as Apple Maps colours lakes and rivers.
    var isWater = false

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(isWater ? Font.caption.weight(.semibold).italic() : Font.caption.weight(.semibold))
                .foregroundStyle(isWater ? Color.exploreWaterInk : Color.dsText)
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.dsText2)
                    .lineLimit(1)
            }
        }
        .mapLabelHalo()
        .frame(maxWidth: 160)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A single pin: art, bite treatment, label.
struct ExplorePin: View {
    let feature: ExploreFeature
    var score: Int?
    var topSpecies: Species?
    var showsLabel = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        content
            // Pins grow in from their point as they land. They never start
            // hidden, so a pin whose appear event is skipped still shows.
            .scaleEffect(shown || reduceMotion ? 1 : 0.6, anchor: .bottom)
            .onAppear { withAnimation(DS.Motion.spring) { shown = true } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var content: some View {
        switch feature {
        case .water(let w):
            WaterPin(waterbody: w, score: score, showsLabel: showsLabel)
        case .ramp(let r):
            VStack(spacing: 3) {
                PlaceDot(kind: r.kind)
                if showsLabel { PinLabel(title: r.name) }
            }
        case .catchPin(let c):
            CatchPhotoPin(detail: c)
        case .spot:
            VStack(spacing: 4) {
                PinArt(feature: feature, topSpecies: topSpecies, size: 46)
                    .overlay(alignment: .topTrailing) {
                        if let score {
                            Text("\(score)")
                                .font(.caption2.weight(.heavy))
                                .monospacedDigit()
                                .foregroundStyle(.black)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(DS.scoreColor(score), in: Capsule())
                                .overlay(Capsule().stroke(Color.dsBackground, lineWidth: 1.5))
                                .offset(x: 10, y: -8)
                        }
                    }
                if showsLabel {
                    PinLabel(title: feature.name)
                }
            }
        }
    }

    private var accessibilityText: String {
        let kind: String
        switch feature {
        case .spot: kind = "Your spot"
        case .water(let w): kind = ExploreFormat.waterType(w.type)
        case .catchPin(let c): return CatchPinText.label(c)
        case .ramp(let r): kind = r.kind.label
        }
        let bite = score.map { ", bite \($0)" } ?? ""
        return "\(feature.name), \(kind)\(bite)"
    }
}

/// Water on the map: the round glyph inside a bite ring drawn in the score
/// colour, and the name in water ink once the map is close enough to read it.
struct WaterPin: View {
    let waterbody: Waterbody
    var score: Int?
    var showsLabel = false

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                if let score {
                    Circle()
                        .stroke(Color.dsBackground.opacity(0.55), lineWidth: 3.5)
                    Circle()
                        .trim(from: 0, to: CGFloat(max(4, min(score, 100))) / 100)
                        .stroke(DS.scoreColor(score), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                WaterDot(type: waterbody.type)
            }
            .frame(width: ExploreMetrics.waterRing, height: ExploreMetrics.waterRing)
            if showsLabel {
                PinLabel(title: waterbody.name, detail: score.map { "Bite \($0)" }, isWater: true)
            }
        }
    }
}

/// What a cluster holds, as glyph and count pairs: "2 spots, 5 water".
struct ClusterContents {
    struct Part: Identifiable {
        let id: Int
        let icon: String
        let count: Int
        let tint: Color
        let noun: (Int) -> String
    }

    let parts: [Part]

    init(_ members: [ExploreFeature]) {
        var spots = 0, water = 0, catches = 0, access = 0, ramps = 0
        for m in members {
            switch m {
            case .spot: spots += 1
            case .water: water += 1
            case .catchPin: catches += 1
            case .ramp(let r): if r.kind == .access { access += 1 } else { ramps += 1 }
            }
        }
        var list: [Part] = []
        if spots > 0 { list.append(Part(id: 0, icon: "mappin", count: spots, tint: DS.accent, noun: { $0 == 1 ? "spot" : "spots" })) }
        if water > 0 { list.append(Part(id: 1, icon: "drop.fill", count: water, tint: .exploreWaterInk, noun: { $0 == 1 ? "water" : "waters" })) }
        if catches > 0 { list.append(Part(id: 2, icon: "fish.fill", count: catches, tint: .dsText2, noun: { $0 == 1 ? "catch" : "catches" })) }
        if access > 0 { list.append(Part(id: 3, icon: BoatRamp.Kind.access.icon, count: access, tint: .dsText2, noun: { $0 == 1 ? "access point" : "access points" })) }
        if ramps > 0 { list.append(Part(id: 4, icon: BoatRamp.Kind.ramp.icon, count: ramps, tint: .dsText2, noun: { $0 == 1 ? "ramp" : "ramps" })) }
        parts = list
    }

    var spoken: String {
        parts.map { "\($0.count) \($0.noun($0.count))" }.joined(separator: ", ")
    }
}

/// A cluster: the lead pins fanned, and a capsule saying what is inside.
/// Water-only clusters stay round so they still read as water, and catches
/// draw as a stack of their photos.
struct ClusterPin: View {
    let cluster: PinCluster
    var topSpecies: (Spot) -> Species?

    private var contents: ClusterContents { ClusterContents(cluster.members) }

    private var allWater: Bool {
        cluster.members.allSatisfy { if case .water = $0 { return true } else { return false } }
    }

    var body: some View {
        if let catches = cluster.catches {
            CatchPhotoStack(catches: CatchPinPhotos.stackTop(catches), count: catches.count)
                .accessibilityHint(PinClustering.inseparableCatches(cluster) == nil ? "Zooms in" : "Lists these catches")
                .accessibilityAddTraits(.isButton)
        } else {
            placesCluster
        }
    }

    private var placesCluster: some View {
        VStack(spacing: 4) {
            if allWater {
                Circle()
                    .fill(Color.exploreWater)
                    .overlay {
                        Text("\(cluster.members.count)")
                            .font(.headline.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }
                    .overlay(Circle().stroke(Color.white, lineWidth: 2.5))
                    .frame(width: 40, height: 40)
                    .mapPinShadow()
                PinLabel(title: cluster.lead.name, detail: "and \(cluster.members.count - 1) more", isWater: true)
            } else {
                ZStack {
                    ForEach(Array(cluster.members.prefix(3).enumerated().reversed()), id: \.offset) { index, member in
                        PinArt(feature: member, topSpecies: species(for: member), size: member.isSquare ? 46 : 34)
                            .rotationEffect(.degrees([0, -9, 8][index]))
                            .offset(x: CGFloat(index) * -3, y: CGFloat(index) * -2)
                    }
                }
                contentsCapsule
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(contents.spoken)
        .accessibilityHint("Zooms in")
        .accessibilityAddTraits(.isButton)
    }

    private var contentsCapsule: some View {
        HStack(spacing: DS.Space.s2) {
            ForEach(contents.parts) { part in
                HStack(spacing: 3) {
                    Image(systemName: part.icon)
                        .foregroundStyle(part.tint)
                    Text("\(part.count)")
                        .foregroundStyle(.dsText)
                }
            }
        }
        .font(.caption2.weight(.bold))
        .monospacedDigit()
        .padding(.horizontal, DS.Space.s2)
        .padding(.vertical, 3)
        .background(Color.dsBackground, in: Capsule())
        .mapPinShadow()
        .fixedSize()
    }

    private func species(for f: ExploreFeature) -> Species? {
        if case .spot(let s) = f { return topSpecies(s) }
        return nil
    }
}

// MARK: - User location marker

/// Precise location dot with a heading cone showing which way the user is
/// facing (driven by the compass).
struct UserLocationMarker: View {
    let heading: Double
    var accent: Color = DS.accent

    var body: some View {
        ZStack {
            HeadingCone()
                .fill(accent.opacity(0.3))
                .frame(width: 72, height: 72)
                .rotationEffect(.degrees(heading))
                .animation(.easeOut(duration: 0.2), value: heading)

            Circle()
                .fill(accent)
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(.white, lineWidth: 3))
                .mapPinShadow()
        }
        .accessibilityLabel("Your location")
    }
}

/// A 56 degree wedge pointing north; rotate it by the device heading.
struct HeadingCone: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        p.move(to: center)
        p.addArc(center: center, radius: radius, startAngle: .degrees(-118), endAngle: .degrees(-62), clockwise: false)
        p.closeSubpath()
        return p
    }
}
