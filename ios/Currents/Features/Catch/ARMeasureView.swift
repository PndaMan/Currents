import SwiftUI
import ARKit
import SceneKit

/// Measure a fish's length in AR: point the camera at the fish on a flat
/// surface, tap the nose, then tap the tail. Uses LiDAR/plane raycasting to
/// get real-world 3D points and returns the distance in centimetres. Best on
/// LiDAR devices; works with estimated planes elsewhere (less precise).
struct ARMeasureView: View {
    var onMeasured: (Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var measuredCm: Double?
    @State private var pointCount = 0
    @State private var resetToken = 0

    static var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }

    var body: some View {
        ZStack {
            ARMeasureContainer(measuredCm: $measuredCm, pointCount: $pointCount, resetToken: resetToken)
                .ignoresSafeArea()

            VStack {
                Text(instruction)
                    .font(.subheadline.weight(.semibold))
                    .padding(10)
                    .background(.black.opacity(0.55), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(.top, 12)

                Spacer()

                if let cm = measuredCm {
                    Text(String(format: "%.1f cm", cm))
                        .font(.largeTitle.bold().monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
                }

                HStack(spacing: 12) {
                    Button {
                        measuredCm = nil; pointCount = 0; resetToken += 1
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    if let cm = measuredCm {
                        Button {
                            onMeasured((cm * 10).rounded() / 10)
                            dismiss()
                        } label: {
                            Label("Use \(String(format: "%.1f", cm)) cm", systemImage: "checkmark")
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(CurrentsTheme.accent, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body.bold()).foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.5), in: Circle())
            }
            .padding()
        }
    }

    private var instruction: String {
        switch pointCount {
        case 0: return "Tap the fish's nose"
        case 1: return "Now tap the tail"
        default: return "Tap Reset to measure again"
        }
    }
}

private struct ARMeasureContainer: UIViewRepresentable {
    @Binding var measuredCm: Double?
    @Binding var pointCount: Int
    var resetToken: Int

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.delegate = context.coordinator
        view.automaticallyUpdatesLighting = true
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        view.session.run(config)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        if context.coordinator.lastResetToken != resetToken {
            context.coordinator.lastResetToken = resetToken
            context.coordinator.reset()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, ARSCNViewDelegate {
        let parent: ARMeasureContainer
        weak var view: ARSCNView?
        var lastResetToken = 0
        private var points: [SIMD3<Float>] = []
        private var markers: [SCNNode] = []

        init(_ parent: ARMeasureContainer) { self.parent = parent }

        func reset() {
            points.removeAll()
            markers.forEach { $0.removeFromParentNode() }
            markers.removeAll()
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view else { return }
            let location = gesture.location(in: view)
            guard let query = view.raycastQuery(from: location, allowing: .estimatedPlane, alignment: .any),
                  let result = view.session.raycast(query).first else { return }

            let t = result.worldTransform
            let pos = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)

            if points.count >= 2 { reset() }
            points.append(pos)
            addMarker(at: pos, in: view)

            DispatchQueue.main.async {
                self.parent.pointCount = self.points.count
                if self.points.count == 2 {
                    let d = simd_distance(self.points[0], self.points[1])
                    self.parent.measuredCm = Double(d) * 100.0
                }
            }
        }

        private func addMarker(at pos: SIMD3<Float>, in view: ARSCNView) {
            let sphere = SCNSphere(radius: 0.006)
            sphere.firstMaterial?.diffuse.contents = UIColor.systemYellow
            let node = SCNNode(geometry: sphere)
            node.position = SCNVector3(pos.x, pos.y, pos.z)
            view.scene.rootNode.addChildNode(node)
            markers.append(node)
        }
    }
}
