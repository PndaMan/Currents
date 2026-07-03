import SwiftUI

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

/// A single image with pinch-to-zoom, double-tap zoom, and pan-when-zoomed.
/// Paging swipes still work at 1× because the drag gesture only engages
/// once zoomed in.
struct ZoomableImage: View {
    let image: UIImage

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        scale = min(6, max(1, lastScale * value))
                    }
                    .onEnded { _ in
                        lastScale = scale
                        if scale <= 1.01 { resetZoom() }
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        guard scale > 1 else { return }
                        offset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                    }
                    .onEnded { _ in
                        lastOffset = offset
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring(duration: 0.3)) {
                    if scale > 1 {
                        resetZoom()
                    } else {
                        scale = 2.5
                        lastScale = 2.5
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .clipped()
    }

    private func resetZoom() {
        withAnimation(.spring(duration: 0.3)) {
            scale = 1
            lastScale = 1
            offset = .zero
            lastOffset = .zero
        }
    }
}
