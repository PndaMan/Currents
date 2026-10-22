import SwiftUI
import PhotosUI
import AVFoundation
import UIKit
import Combine

// MARK: - Capture session

/// A small still-photo camera for the log catch composer. The session runs on
/// its own queue; published state is only touched on the main queue.
final class LogCatchCaptureModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    enum Status { case starting, running, denied, unavailable }

    @Published private(set) var status: Status = .starting
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "currents.logcatch.camera")
    private var configured = false
    private var onPhoto: ((UIImage) -> Void)?

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.configureAndRun() } else { self?.status = .denied }
                }
            }
        default:
            status = .denied
        }
    }

    func stop() {
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configureAndRun() {
        queue.async { [weak self] in
            guard let self else { return }
            if !self.configured {
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                      let input = try? AVCaptureDeviceInput(device: device) else {
                    DispatchQueue.main.async { self.status = .unavailable }
                    return
                }
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo
                if self.session.canAddInput(input) { self.session.addInput(input) }
                if self.session.canAddOutput(self.output) { self.session.addOutput(self.output) }
                self.session.commitConfiguration()
                self.configured = true
            }
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async { self.status = .running }
        }
    }

    func capture(_ completion: @escaping (UIImage) -> Void) {
        guard status == .running else { return }
        onPhoto = completion
        let settings = AVCapturePhotoSettings()
        queue.async { [output] in
            output.capturePhoto(with: settings, delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onPhoto?(image)
            self?.onPhoto = nil
        }
    }
}

/// The live preview layer.
private struct LogCatchPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

// MARK: - Camera screen

/// The camera that opens first when logging a catch: shutter, library and
/// "No photo" (or "Done" when adding more photos). Always dark, like the
/// system camera. The captured frame is handed back to the composer, which
/// animates it down into the cover photo.
struct LogCatchCameraView: View {
    /// True when the catch already has photos and this adds another.
    let adding: Bool
    let photoCount: Int
    @Binding var libraryItems: [PhotosPickerItem]
    let librarySlots: Int
    var onCapture: (UIImage) -> Void
    var onClose: () -> Void
    var onSkip: () -> Void

    @StateObject private var camera = LogCatchCaptureModel()
    @State private var flash = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                viewfinder
                controls
            }
        }
        .environment(\.colorScheme, .dark)
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }

    private var topBar: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: adding ? "chevron.down" : "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.16), in: Circle())
            }
            .buttonStyle(.dim)
            .accessibilityLabel(adding ? "Back to the catch" : "Close")
            Spacer()
            Text(adding ? "Photo \(photoCount + 1) of 10" : "Photo")
                .font(.headline)
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
    }

    private var viewfinder: some View {
        ZStack {
            switch camera.status {
            case .running, .starting:
                LogCatchPreview(session: camera.session)
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.7), lineWidth: 2)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 70)
                    .accessibilityHidden(true)
            case .denied:
                cameraMessage("Camera is off for Currents",
                              detail: "Turn it on in Settings, or choose photos from your library.",
                              showsSettings: true)
            case .unavailable:
                cameraMessage("No camera here",
                              detail: "Choose photos from your library instead.",
                              showsSettings: false)
            }
            if flash {
                Color.white.allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            if camera.status == .running {
                Text(adding ? "Add the spot, the lure or the release" : "Fill the frame with the fish")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, DS.Space.s3)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.55), in: Capsule())
                    .padding(.bottom, DS.Space.s4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private func cameraMessage(_ title: String, detail: String, showsSettings: Bool) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "camera")
        } description: {
            Text(detail)
        } actions: {
            if showsSettings, let url = URL(string: UIApplication.openSettingsURLString) {
                Button("Open Settings") { UIApplication.shared.open(url) }
                    .buttonStyle(TonalButtonStyle(fullWidth: false))
            }
        }
        .foregroundStyle(.white)
    }

    private var controls: some View {
        VStack(spacing: DS.Space.s6) {
            HStack {
                PhotosPicker(selection: $libraryItems,
                             maxSelectionCount: max(1, librarySlots),
                             matching: .images) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.title3)
                        .frame(width: 52, height: 52)
                        .background(Color.white.opacity(0.16),
                                    in: RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous))
                }
                .accessibilityLabel("Choose photos")
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: shoot) {
                    ZStack {
                        Circle().strokeBorder(Color.white, lineWidth: 4).frame(width: 76, height: 76)
                        Circle().fill(Color.white).frame(width: 60, height: 60)
                    }
                }
                .buttonStyle(.dim)
                // On press-down, so the tap is over before the photo is taken.
                .buttonHaptic(.press)
                .disabled(camera.status != .running)
                .opacity(camera.status == .running ? 1 : 0.4)
                .accessibilityLabel("Take photo")

                Button(action: onSkip) {
                    Text(adding ? "Done" : "No photo")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, DS.Space.s4)
                        .frame(height: 40)
                        .background(Color.white.opacity(0.16), in: Capsule())
                }
                .buttonStyle(.dim)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 30)

            Label(adding ? "Location is removed from every photo." : "Species ID runs on your phone. No signal needed.",
                  systemImage: "checkmark.shield")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white)
        .padding(.top, DS.Space.s6)
        .padding(.bottom, DS.Space.s4)
    }

    private func shoot() {
        camera.capture { image in
            onCapture(image)
        }
        if reduceMotion { return }
        flash = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(40))
            withAnimation(.easeOut(duration: 0.24)) { flash = false }
        }
    }
}
