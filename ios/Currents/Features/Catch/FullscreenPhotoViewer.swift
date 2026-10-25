import SwiftUI
import UIKit

/// Fullscreen, pinch-zoomable photo viewer for catch photos.
///
/// Presented as a fullScreenCover from the catch detail carousel. Swipe
/// between photos, pinch or double-tap to zoom, drag to pan when zoomed, and
/// swipe down to close when the photo is not zoomed, as in Photos. The page
/// index is the catch page's own, so the hero and Share follow it.
struct FullscreenPhotoViewer: View {
    let photoPaths: [String]
    @Binding var currentIndex: Int
    @Environment(\.dismiss) private var dismiss
    /// Pages zoomed past their fitted size; a swipe down pans those instead.
    @State private var zoomedPages: Set<Int> = []
    @State private var dragOffset: CGFloat = 0
    /// Decided on the first movement, so a sideways page swipe never closes.
    @State private var dragIsVertical: Bool?

    private var isZoomed: Bool { zoomedPages.contains(currentIndex) }

    /// The black fades as the photo is pulled down.
    private var backdropOpacity: Double {
        1 - min(0.7, Double(max(0, dragOffset)) / 500)
    }

    var body: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(photoPaths.enumerated()), id: \.offset) { index, path in
                PhotoPage(path: path) { zoomed in
                    zoomedPages = zoomed ? zoomedPages.union([index]) : zoomedPages.subtracting([index])
                }
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: photoPaths.count > 1 ? .automatic : .never))
        .offset(y: dragOffset)
        .simultaneousGesture(dismissDrag, including: isZoomed ? .subviews : .all)
        .background(Color.black.opacity(backdropOpacity))
        .ignoresSafeArea()
        .viewerChrome(title: photoPaths.count > 1 ? "\(currentIndex + 1) of \(photoPaths.count)" : nil) {
            dismiss()
        }
        .presentationBackground(Color.clear)
        .environment(\.colorScheme, .dark)
    }

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if dragIsVertical == nil {
                    let t = value.translation
                    dragIsVertical = t.height > 0 && abs(t.height) > abs(t.width)
                }
                guard dragIsVertical == true else { return }
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                let vertical = dragIsVertical == true
                dragIsVertical = nil
                guard vertical else { return }
                if value.translation.height > 120 || value.predictedEndTranslation.height > 320 {
                    dismiss()
                } else {
                    withAnimation(DS.Motion.softSpring) { dragOffset = 0 }
                }
            }
    }
}

extension View {
    /// The viewer's close button and photo count, in a system toolbar over
    /// the photo. The toolbar is its own bar above the content, so a zoomed
    /// photo's scroll view can never take the close button's taps, which it
    /// did when the button was a SwiftUI overlay on top of the zoom view.
    func viewerChrome(title: String?, close: @escaping () -> Void) -> some View {
        NavigationStack {
            self
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if let title {
                        ToolbarItem(placement: .principal) {
                            Text(title)
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .contentTransition(.numericText())
                                .animation(DS.Motion.press, value: title)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close", systemImage: "xmark", action: close)
                            .tint(.white)
                    }
                }
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

/// One page of the viewer: decodes the full-size photo off the main thread,
/// with a spinner until it arrives.
private struct PhotoPage: View {
    let path: String
    var onZoomChange: ((Bool) -> Void)? = nil
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                ZoomableImage(image: image, onZoomChange: onZoomChange)
            } else if failed {
                InlineEmpty(systemImage: "photo", text: "This photo could not be found on the phone.")
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: path) {
            let path = path
            let loaded = await Task.detached { PhotoManager.load(path) }.value
            image = loaded
            failed = loaded == nil
        }
    }
}

/// Fullscreen, pinch-zoomable viewer for a single already-loaded `UIImage`
/// (e.g. a community catch photo that was downloaded from CloudKit rather than
/// stored locally). Same zoom/pan behaviour as `FullscreenPhotoViewer`.
struct FullscreenImageViewer: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZoomableImage(image: image)
            .background(Color.black)
            .ignoresSafeArea()
            .viewerChrome(title: nil) { dismiss() }
    }
}

/// A single image with pinch-to-zoom, double-tap zoom, and pan-when-zoomed,
/// backed by a native `UIScrollView`. UIKit handles the pinch/pan/momentum and
/// edge clamping, so panning a zoomed photo is buttery-smooth instead of the
/// stuttering you get when a SwiftUI `DragGesture` fights the paging TabView.
///
/// The image is aspect-fit to the viewport at `zoomScale == 1` with a fixed
/// 1…4× range, and the fit is applied in `layoutSubviews` (keyed on the
/// viewport SIZE) so it opens fitted, never pre-zoomed, and doesn't reset the
/// scale mid-pinch.
struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    /// Told when the photo zooms in past its fitted size or back out.
    var onZoomChange: ((Bool) -> Void)? = nil

    func makeUIView(context: Context) -> ZoomScrollView {
        let scrollView = ZoomScrollView()
        scrollView.delegate = context.coordinator
        scrollView.bouncesZoom = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.decelerationRate = .fast
        scrollView.imageView.image = image
        context.coordinator.imageView = scrollView.imageView
        context.coordinator.onZoomChange = onZoomChange

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: ZoomScrollView, context: Context) {
        context.coordinator.onZoomChange = onZoomChange
        if scrollView.imageView.image !== image {
            scrollView.imageView.image = image
            scrollView.needsRefit = true
            scrollView.setNeedsLayout()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        var onZoomChange: ((Bool) -> Void)?
        private var isZoomed = false

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? ZoomScrollView)?.centerContent()
            let zoomed = scrollView.zoomScale > scrollView.minimumZoomScale + 0.01
            guard zoomed != isZoomed else { return }
            isZoomed = zoomed
            // A refit can zoom during a SwiftUI layout pass; report after it.
            let report = onZoomChange
            DispatchQueue.main.async { report?(zoomed) }
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale + 0.001 {
                // Zoomed in → return to the fitted (minimum) scale.
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let target = min(scrollView.minimumZoomScale * 3, scrollView.maximumZoomScale)
                let point = gesture.location(in: imageView)
                let w = scrollView.bounds.width / target
                let h = scrollView.bounds.height / target
                scrollView.zoom(
                    to: CGRect(x: point.x - w / 2, y: point.y - h / 2, width: w, height: h),
                    animated: true
                )
            }
        }
    }
}

/// UIScrollView that fits its image (aspect-fit) to the viewport at zoomScale 1
/// with fixed 1…4× zoom. Fitting the image with an aspect-fit image view at
/// scale 1 — rather than laying the image out at its natural (huge) size and
/// using a fractional minimum zoom — keeps pinch behaviour sane: a large camera
/// photo previously produced a tiny min-zoom (~0.13) that made pinches jump
/// straight to max and refuse to zoom back out.
final class ZoomScrollView: UIScrollView {
    let imageView = UIImageView()
    var needsRefit = true
    // Track the viewport SIZE only. A scroll view's `bounds.origin` is its
    // contentOffset, so comparing the whole rect re-fired the refit (resetting
    // zoomScale to 1) on every scroll/zoom frame — which killed zooming.
    private var lastSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.clipsToBounds = true
        minimumZoomScale = 1
        maximumZoomScale = 4
        addSubview(imageView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Fit the image only when the viewport SIZE changes or a new image
        // arrives — never during a pinch/scroll, so it doesn't fight the zoom.
        if (needsRefit || bounds.size != lastSize), bounds.width > 0, imageView.image != nil {
            lastSize = bounds.size
            needsRefit = false
            zoomScale = 1
            imageView.frame = CGRect(origin: .zero, size: bounds.size)
            contentSize = bounds.size
        }
        centerContent()
    }

    /// Centre the image via contentInset when it's smaller than the viewport.
    func centerContent() {
        let ox = max(0, (bounds.width - imageView.frame.width) / 2)
        let oy = max(0, (bounds.height - imageView.frame.height) / 2)
        contentInset = UIEdgeInsets(top: oy, left: ox, bottom: oy, right: ox)
    }
}
