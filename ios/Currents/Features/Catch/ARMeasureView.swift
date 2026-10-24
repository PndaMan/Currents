import SwiftUI
import ARKit
import AVFoundation
import SceneKit

/// Measure a fish's length in AR: point the camera at the fish on a flat
/// surface, tap the nose, then tap the tail. Uses LiDAR/plane raycasting to
/// get real-world 3D points and returns the distance in centimetres. Best on
/// LiDAR devices; works with estimated planes elsewhere (less precise).
struct ARMeasureView: View {
    var onMeasured: (Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("units") private var units = "metric"
    @ScaledMetric(relativeTo: .largeTitle) private var numeralSize: CGFloat = 52
    @State private var measuredCm: Double?
    @State private var pointCount = 0
    @State private var resetToken = 0
    /// The last tap hit no surface.
    @State private var missedTap = false
    @State private var cameraAccess = AVCaptureDevice.authorizationStatus(for: .video)

    static var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }

    private var imperial: Bool { units == "imperial" }

    var body: some View {
        ZStack {
            switch cameraAccess {
            case .authorized:
                ARMeasureContainer(measuredCm: $measuredCm, pointCount: $pointCount, missedTap: $missedTap,
                                   resetToken: resetToken)
                    .ignoresSafeArea()
            case .notDetermined:
                Color.black.ignoresSafeArea()
            default:
                Color.black.ignoresSafeArea()
                cameraDenied
            }

            VStack(spacing: DS.Space.s3) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.black.opacity(0.5), in: Circle())
                    }
                    .buttonStyle(.dim)
                    .accessibilityLabel("Close")
                    Spacer()
                    Text("Measure")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer()
                    Color.clear.frame(width: 40, height: 40)
                }
                .padding(.horizontal, DS.Space.s4)

                if cameraAccess == .authorized {
                    Text(instruction)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, DS.Space.s3)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.55), in: Capsule())
                        .contentTransition(.opacity)
                        .animation(reduceMotion ? nil : DS.Motion.easeOut, value: instruction)
                }

                Spacer()

                if cameraAccess == .authorized {
                    measurePanel
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .task {
            // ARKit would ask on its own; asking first lets a refusal show
            // the way to Settings instead of a black screen.
            guard cameraAccess == .notDetermined else { return }
            _ = await AVCaptureDevice.requestAccess(for: .video)
            cameraAccess = AVCaptureDevice.authorizationStatus(for: .video)
        }
        // The first point ticks, the second lands the measurement. Clear
        // (back to zero) already played its button's press.
        .haptic(.selection, trigger: pointCount) { _, new in new == 1 }
        .haptic(.success, trigger: measuredCm) { _, new in new != nil }
    }

    /// The LogCatch camera's denied state, with the way back to Settings.
    private var cameraDenied: some View {
        ContentUnavailableView {
            Label("Camera is off for Currents", systemImage: "camera")
        } description: {
            Text("Turn it on in Settings to measure, or type the length instead.")
        } actions: {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Button("Open Settings") { UIApplication.shared.open(url) }
                    .buttonStyle(TonalButtonStyle(fullWidth: false))
            }
        }
        .foregroundStyle(.white)
    }

    private var measurePanel: some View {
        VStack(spacing: DS.Space.s3) {
            if let cm = measuredCm {
                let parts = Units.lengthParts(cm: cm, imperial: imperial)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(parts.0)
                        .font(.system(size: numeralSize, weight: .bold, design: .rounded)) // ui-lint: allow, measurement numeral scaled with @ScaledMetric
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(parts.1)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.dsText2)
                }
                .foregroundStyle(Color.dsText)
                .accessibilityElement(children: .combine)

                Button {
                    onMeasured((cm * 10).rounded() / 10)
                    dismiss()
                } label: {
                    Label("Use \(Units.length(cm: cm, imperial: imperial))", systemImage: "checkmark")
                }
                .buttonStyle(.dsPrimary)
            } else {
                Label("Lay the fish flat and point the camera straight down", systemImage: "camera.metering.center.weighted")
                    .font(.subheadline)
                    .foregroundStyle(Color.dsText2)
                    .multilineTextAlignment(.center)
            }
            Button {
                measuredCm = nil; pointCount = 0; missedTap = false; resetToken += 1
            } label: {
                Label("Start again", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.dsTonal)
            .disabled(pointCount == 0)
        }
        .padding(DS.Space.s4)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DS.Radius.sheet, style: .continuous))
        .padding(.horizontal, DS.Space.s3)
        .padding(.bottom, DS.Space.s2)
    }

    private var instruction: String {
        if missedTap { return "Point at a flat surface" }
        switch pointCount {
        case 0: return "Tap the nose"
        case 1: return "Now tap the tail"
        default: return "Measured. Tap again to start over."
        }
    }
}

private struct ARMeasureContainer: UIViewRepresentable {
    @Binding var measuredCm: Double?
    @Binding var pointCount: Int
    @Binding var missedTap: Bool
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
                  let result = view.session.raycast(query).first else {
                DispatchQueue.main.async { self.parent.missedTap = true }
                return
            }

            let t = result.worldTransform
            let pos = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)

            if points.count >= 2 { reset() }
            points.append(pos)
            addMarker(at: pos, in: view)

            DispatchQueue.main.async {
                self.parent.missedTap = false
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
