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
}

struct PinCluster: Identifiable {
    let members: [ExploreFeature]
    var id: String { members.count == 1 ? members[0].id : "cluster:\(members[0].id):\(members.count)" }
    var coordinate: CLLocationCoordinate2D { members[0].coordinate }
    var lead: ExploreFeature { members[0] }
}

/// Luma's map clustering: pins closer than about 64 points on screen merge
/// into a fanned stack, led by the most important pin. Below street level
/// every pin stands on its own.
enum PinClustering {
    static func cluster(_ features: [ExploreFeature], latSpan: Double) -> [PinCluster] {
        let sorted = features.sorted { $0.priority < $1.priority }
        guard latSpan > 0.04 else { return sorted.map { PinCluster(members: [$0]) } }
        let radius = latSpan * 0.075
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

/// The square art inside a pin: species art on its tint, or a symbol.
struct PinArt: View {
    let feature: ExploreFeature
    var topSpecies: Species?
    var size: CGFloat = 46

    var body: some View {
        Group {
            switch feature {
            case .spot(let spot):
                if let topSpecies {
                    ThumbView(species: topSpecies, size: size)
                } else {
                    ThumbView(systemImage: spot.type.icon, tint: DS.accent, size: size)
                }
            case .water(let w):
                ThumbView(systemImage: ExploreFormat.waterIcon(w.type), tint: Color.exploreWater, size: size)
            case .catchPin(let c):
                if let sp = c.species {
                    ThumbView(species: sp, size: size)
                } else {
                    ThumbView(systemImage: "fish.fill", tint: DS.accent, size: size)
                }
            case .ramp(let r):
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.25, style: .continuous).fill(Color.white)
                    Image(systemName: r.kind.icon)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.black.opacity(0.8))
                }
                .frame(width: size, height: size)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: size < 48 ? size * 0.25 : DS.Radius.thumb, style: .continuous)
                .stroke(Color.white, lineWidth: 2.5)
        )
        .mapPinShadow()
    }
}

/// The name under a pin, with a halo so it reads on any map style.
struct PinLabel: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.dsText2)
            }
        }
        .foregroundStyle(.dsText)
        .mapLabelHalo()
        .fixedSize()
    }
}

/// A single pin: art, optional score badge, label.
struct ExplorePin: View {
    let feature: ExploreFeature
    var score: Int?
    var topSpecies: Species?
    var showsLabel = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private var size: CGFloat {
        switch feature {
        case .spot, .water: 46
        case .catchPin: 36
        case .ramp: 28
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            PinArt(feature: feature, topSpecies: topSpecies, size: size)
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
        .scaleEffect(shown || reduceMotion ? 1 : 0.4)
        .opacity(shown || reduceMotion ? 1 : 0)
        .onAppear { withAnimation(DS.Motion.spring) { shown = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(score.map { "\(feature.name), bite \($0)" } ?? feature.name)
        .accessibilityAddTraits(.isButton)
    }
}

/// A fanned stack of up to three cards for a cluster, with "+n more".
struct ClusterPin: View {
    let cluster: PinCluster
    var topSpecies: (Spot) -> Species?

    private var allCatches: Bool { cluster.members.allSatisfy(\.isCatch) }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                ForEach(Array(cluster.members.prefix(3).enumerated().reversed()), id: \.offset) { index, member in
                    PinArt(feature: member, topSpecies: species(for: member), size: 46)
                        .rotationEffect(.degrees([0, -9, 8][index]))
                        .offset(x: CGFloat(index) * -3, y: CGFloat(index) * -2)
                }
            }
            if allCatches {
                PinLabel(title: "\(cluster.members.count) catches")
            } else {
                PinLabel(title: cluster.lead.name, detail: "+\(cluster.members.count - 1) more")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(cluster.lead.name) and \(cluster.members.count - 1) more")
        .accessibilityHint("Zooms in")
        .accessibilityAddTraits(.isButton)
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
