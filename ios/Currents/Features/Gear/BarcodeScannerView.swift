import SwiftUI
import VisionKit
import AVFoundation

/// A live barcode scanner (VisionKit) for quickly capturing a product barcode
/// when adding gear. The scanned code is kept on the gear item and looked up
/// in the product database to fill in the name and brand.
struct BarcodeScannerView: UIViewControllerRepresentable {
    var onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    /// The device can scan and the camera is allowed right now.
    static var isSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    /// The device has the hardware to scan, whether or not the camera has
    /// been allowed yet. Decides whether to offer scanning at all.
    static var isDeviceSupported: Bool {
        DataScannerViewController.isSupported
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .accurate,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        try? scanner.startScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let parent: BarcodeScannerView
        private var handled = false
        init(_ parent: BarcodeScannerView) { self.parent = parent }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            handle(addedItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            handle([item])
        }

        private func handle(_ items: [RecognizedItem]) {
            guard !handled else { return }
            for item in items {
                if case let .barcode(barcode) = item, let payload = barcode.payloadStringValue {
                    handled = true
                    parent.onScan(payload)
                    parent.dismiss()
                    return
                }
            }
        }
    }
}

/// The scanner in its own sheet: Cancel in the bar and a one-line hint under
/// the camera.
struct BarcodeScannerSheet: View {
    var onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            BarcodeScannerView(onScan: onScan)
                .ignoresSafeArea(edges: .top)
                .safeAreaInset(edge: .bottom) { hint }
                .navigationTitle("Scan barcode")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
    }

    private var hint: some View {
        Label("Point the camera at the barcode on the packet. It scans by itself.",
              systemImage: "barcode.viewfinder")
            .font(.subheadline)
            .foregroundStyle(.dsText2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.gutter)
            .padding(.vertical, DS.Space.s4)
            .background(Color.dsBackground)
    }
}

/// Camera permission for the gear photo and barcode scanner: asks the first
/// time, and reports false when the angler has turned the camera off.
enum CameraAccess {
    @MainActor
    static func request() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }
}
