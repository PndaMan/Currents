import SwiftUI
import MapKit

/// A square over the map, as in Apple Maps' offline download: pan and zoom
/// the map to move it, drag a corner to resize it. `area` follows what is
/// inside the square.
struct OfflineAreaPicker: View {
    @Binding var area: GeoRect?
    @State private var position: MapCameraPosition
    @State private var size: CGSize = .zero
    @State private var side: CGFloat = 0
    @State private var dragStart: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Smallest square on screen, and the gap kept round the largest.
    private let minSide: CGFloat = 120
    private let margin: CGFloat = 28

    init(area: Binding<GeoRect?>, initial: MKCoordinateRegion?) {
        _area = area
        _position = State(initialValue: initial.map { .region($0) } ?? .userLocation(fallback: .automatic))
    }

    var body: some View {
        MapReader { proxy in
            Map(position: $position, interactionModes: [.pan, .zoom]) {
                UserAnnotation()
            }
            .mapStyle(.hybrid(elevation: .flat))
            .onMapCameraChange(frequency: .onEnd) { _ in update(proxy) }
            .overlay { frame(proxy) }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { new in
                size = new
                if side == 0 { side = maxSide * 0.8 }
                side = min(max(side, minSide), maxSide)
                update(proxy)
            }
        }
    }

    private var maxSide: CGFloat {
        max(min(size.width, size.height) - margin * 2, minSide)
    }

    private var square: CGRect {
        CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
    }

    @ViewBuilder
    private func frame(_ proxy: MapProxy) -> some View {
        if size != .zero {
            ZStack {
                Path { p in
                    p.addRect(CGRect(origin: .zero, size: size))
                    p.addRoundedRect(in: square, cornerSize: CGSize(width: DS.Radius.thumb, height: DS.Radius.thumb),
                                     style: .continuous)
                }
                .fill(Color.dsScrim, style: FillStyle(eoFill: true))
                .allowsHitTesting(false)

                RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous)
                    .stroke(.white, lineWidth: 2.5)
                    .frame(width: side, height: side)
                    .position(x: square.midX, y: square.midY)
                    .allowsHitTesting(false)

                if let area {
                    Text(OfflineFormat.side(area))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.dsText)
                        .monospacedDigit()
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .glassEffect(.regular, in: Capsule())
                        .position(x: square.midX, y: max(square.minY - 22, 18))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                ForEach(Corner.allCases, id: \.self) { corner in
                    handle(corner, proxy: proxy)
                        // One resize control is enough for VoiceOver.
                        .accessibilityHidden(corner != .bottomTrailing)
                }
            }
            .coordinateSpace(.named("areaPicker"))
            .accessibilityElement(children: .contain)
        }
    }

    private enum Corner: CaseIterable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing
    }

    private func point(_ corner: Corner) -> CGPoint {
        switch corner {
        case .topLeading: CGPoint(x: square.minX, y: square.minY)
        case .topTrailing: CGPoint(x: square.maxX, y: square.minY)
        case .bottomLeading: CGPoint(x: square.minX, y: square.maxY)
        case .bottomTrailing: CGPoint(x: square.maxX, y: square.maxY)
        }
    }

    private func handle(_ corner: Corner, proxy: MapProxy) -> some View {
        Circle()
            .fill(.white)
            .frame(width: 20, height: 20)
            .overlay(Circle().stroke(DS.accent, lineWidth: 3))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .position(point(corner))
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("areaPicker"))
                    .onChanged { value in
                        let start = dragStart ?? side
                        if dragStart == nil { dragStart = side }
                        let center = CGPoint(x: size.width / 2, y: size.height / 2)
                        let reach = max(abs(value.location.x - center.x), abs(value.location.y - center.y))
                        let startReach = max(abs(value.startLocation.x - center.x), abs(value.startLocation.y - center.y))
                        side = min(max(start + (reach - startReach) * 2, minSide), maxSide)
                    }
                    .onEnded { _ in
                        dragStart = nil
                        Haptics.selection()
                        update(proxy)
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("Resize the area")
            .accessibilityValue(area.map(OfflineFormat.side) ?? "")
            .accessibilityAdjustableAction { direction in
                let step = maxSide / 8
                withAnimation(reduceMotion ? nil : DS.Motion.easeOut) {
                    side = min(max(side + (direction == .increment ? step : -step), minSide), maxSide)
                }
                update(proxy)
            }
    }

    /// The square's corners in map coordinates.
    private func update(_ proxy: MapProxy) {
        guard size != .zero,
              let nw = proxy.convert(CGPoint(x: square.minX, y: square.minY), from: .local),
              let se = proxy.convert(CGPoint(x: square.maxX, y: square.maxY), from: .local) else { return }
        var maxLon = se.longitude
        if maxLon < nw.longitude { maxLon += 360 }
        area = GeoRect(minLat: min(se.latitude, nw.latitude), minLon: nw.longitude,
                       maxLat: max(se.latitude, nw.latitude), maxLon: maxLon)
    }
}
