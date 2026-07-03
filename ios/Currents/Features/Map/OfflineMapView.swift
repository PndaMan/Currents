import SwiftUI
import MapKit

/// Full-screen offline satellite map backed by the disk-caching tile overlay.
///
/// SwiftUI's `Map` can't host an `MKTileOverlay`, so this wraps a plain
/// `MKMapView`. Tiles already cached (from browsing or background prefetch)
/// render with no connectivity; new tiles are cached as they load.
struct OfflineMapView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let center: CLLocationCoordinate2D

    var body: some View {
        NavigationStack {
            OfflineMapRepresentable(
                overlay: appState.mapManager.offlineOverlay,
                center: center
            )
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Offline Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay(alignment: .bottom) {
                Text("Cached satellite imagery — works without signal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 12)
            }
        }
    }
}

private struct OfflineMapRepresentable: UIViewRepresentable {
    let overlay: OfflineTileOverlay
    let center: CLLocationCoordinate2D

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.addOverlay(overlay, level: .aboveLabels)
        map.setRegion(
            MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
            ),
            animated: false
        )
        return map
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tile = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tile)
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
