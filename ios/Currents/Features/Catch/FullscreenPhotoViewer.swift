import SwiftUI
import UIKit

/// Fullscreen, pinch-zoomable photo viewer for catch photos.
///
/// Presented as a fullScreenCover from the catch detail carousel. Swipe
/// between photos, pinch or double-tap to zoom, drag to pan when zoomed.
struct FullscreenPhotoViewer: View {
    let photoPaths: [String]
    @State var currentIndex: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(photoPaths.enumerated()), id: \.offset) { index, path in
                    Group {
                        if let image = PhotoManager.load(path) {
                            ZoomableImage(image: image)
                        } else {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photoPaths.count > 1 ? .automatic : .never))
            .ignoresSafeArea()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.bold())
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.5), in: Circle())
            }
            .padding(.trailing, 16)
            .padding(.top, 8)
        }
        .statusBarHidden()
    }
}

/// A single image with pinch-to-zoom, double-tap zoom, and pan-when-zoomed,
/// backed by a native `UIScrollView`. UIKit handles the pinch/pan/momentum and
/// edge clamping, so panning a zoomed photo is buttery-smooth instead of the
/// stuttering you get when a SwiftUI `DragGesture` fights the paging TabView.
///
/// The image view is laid out at the photo's NATURAL size and the fitted scale
/// is used as `minimumZoomScale` (recomputed in `layoutSubviews`, so it's
/// correct regardless of when SwiftUI hands us real bounds). That's the fix for
/// the photo opening wildly zoomed-in with no way to zoom back out — a fixed
/// `minimumZoomScale = 1` against a large image meant "fit" was unreachable.
struct ZoomableImage: UIViewRepresentable {
    let image: UIImage

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

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: ZoomScrollView, context: Context) {
        if scrollView.imageView.image !== image {
            scrollView.imageView.image = image
            scrollView.needsRefit = true
            scrollView.setNeedsLayout()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? ZoomScrollView)?.centerContent()
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
    private var lastBounds: CGRect = .zero

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
        // Reset to a fitted layout whenever the bounds change or a new image
        // arrives. Runs here (not in updateUIView) so the timing is reliable —
        // that's what stops the photo opening pre-zoomed. Bounds don't change
        // during a pinch, so this never fights the user's zoom.
        if (needsRefit || bounds != lastBounds), bounds.width > 0, imageView.image != nil {
            lastBounds = bounds
            needsRefit = false
            zoomScale = 1
            imageView.frame = bounds
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
