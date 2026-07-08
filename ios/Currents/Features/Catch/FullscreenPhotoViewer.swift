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
/// At 1× the scroll view's content fits exactly, so it yields horizontal
/// swipes back to the TabView for paging between photos.
struct ZoomableImage: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 6
        scrollView.bouncesZoom = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.decelerationRate = .fast

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = true
        context.coordinator.imageView = imageView
        scrollView.addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        if context.coordinator.imageView?.image !== image {
            context.coordinator.imageView?.image = image
        }
        context.coordinator.layoutImage(in: scrollView)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var imageView: UIImageView?
        private var lastBounds: CGRect = .zero

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        /// Size the image to fill the scroll view (aspect-fit) when the bounds
        /// are first known or change (rotation), keeping zoom reset.
        func layoutImage(in scrollView: UIScrollView) {
            guard let imageView, scrollView.bounds != lastBounds, scrollView.bounds.width > 0 else { return }
            lastBounds = scrollView.bounds
            scrollView.zoomScale = 1
            imageView.frame = scrollView.bounds
            scrollView.contentSize = scrollView.bounds.size
        }

        /// Keep the image centred while it's smaller than the viewport.
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let imageView else { return }
            let bounds = scrollView.bounds.size
            var frame = imageView.frame
            frame.origin.x = frame.width < bounds.width ? (bounds.width - frame.width) / 2 : 0
            frame.origin.y = frame.height < bounds.height ? (bounds.height - frame.height) / 2 : 0
            imageView.frame = frame
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let newScale: CGFloat = 2.5
                let size = scrollView.bounds.size
                let rect = CGRect(
                    x: point.x - (size.width / newScale) / 2,
                    y: point.y - (size.height / newScale) / 2,
                    width: size.width / newScale,
                    height: size.height / newScale
                )
                scrollView.zoom(to: rect, animated: true)
            }
        }
    }
}
