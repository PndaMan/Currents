import SwiftUI
import VisionKit

/// A live barcode scanner (VisionKit) for quickly capturing a product barcode
/// when adding gear. There's no product database, so the scanned code is
/// captured as a reference on the gear item — handy for re-ordering line,
/// hooks and other consumables.
struct BarcodeScannerView: UIViewControllerRepresentable {
    var onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
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
