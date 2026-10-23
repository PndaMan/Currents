import SwiftUI

/// The opening moment: the fish leaps out of a still surface in the theme
/// colour, two rings spread where it broke the water, the name settles in
/// under it, and the whole thing lifts away to the app. About a second and a
/// half; a tap skips it, and Reduce Motion gets a plain fade.
///
/// The launch screen is the plain page background, so the first frame here
/// matches it and nothing jumps.
struct LaunchAnimation: View {
    let onFinish: () -> Void

    @AppStorage("selectedTheme") private var selectedTheme = ThemeOption.ocean.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 1 is below the waterline, 0 is in place.
    @State private var rise: CGFloat = 1
    @State private var tilt: Double = -32
    @State private var ripples: [CGFloat] = [0, 0]
    @State private var showsName = false
    @State private var leaving = false

    private let size: CGFloat = 104

    private var tint: Color { (ThemeOption(rawValue: selectedTheme) ?? .ocean).primary }

    var body: some View {
        ZStack {
            Color.dsBackground.ignoresSafeArea()
            VStack(spacing: DS.Space.s5) {
                ZStack {
                    fish
                    ForEach(ripples.indices, id: \.self) { i in
                        RippleRing(progress: ripples[i], width: size * 1.9, tint: tint)
                            .offset(x: -size * 0.12, y: size / 2)
                    }
                }
                .frame(width: size * 2, height: size)
                Text("Currents")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.dsText)
                    .opacity(showsName ? 1 : 0)
                    .offset(y: showsName ? 0 : DS.Space.s3)
            }
            .scaleEffect(leaving ? 1.12 : 1)
        }
        .opacity(leaving ? 0 : 1)
        .contentShape(Rectangle())
        .onTapGesture { Task { await finish() } }
        .accessibilityElement()
        .accessibilityLabel("Currents")
        .accessibilityAddTraits(.isImage)
        .task { await play() }
    }

    /// The mark, clipped at the waterline (the bottom of its frame) so it
    /// comes up out of the surface rather than sliding in.
    private var fish: some View {
        CurrentsMark()
            .filled(tint)
            .frame(width: size, height: size)
            .rotationEffect(.degrees(tilt))
            .offset(x: -rise * size * 0.35, y: rise * size * 1.5)
            .frame(width: size * 2, height: size)
            .mask(alignment: .bottom) {
                Rectangle().frame(height: size * 3)
            }
    }

    private func play() async {
        if reduceMotion {
            rise = 0
            tilt = 0
            showsName = true
            try? await Task.sleep(for: .milliseconds(700))
            await finish()
            return
        }
        try? await Task.sleep(for: .milliseconds(120))
        withAnimation(.spring(duration: 0.62, bounce: 0.32)) {
            rise = 0
            tilt = 0
        }
        for i in ripples.indices {
            try? await Task.sleep(for: .milliseconds(i == 0 ? 110 : 150))
            withAnimation(.easeOut(duration: 0.95)) { ripples[i] = 1 }
        }
        try? await Task.sleep(for: .milliseconds(220))
        withAnimation(.easeOut(duration: DS.Motion.med)) { showsName = true }
        try? await Task.sleep(for: .milliseconds(620))
        await finish()
    }

    private func finish() async {
        guard !leaving else { return }
        withAnimation(.easeIn(duration: 0.3)) { leaving = true }
        try? await Task.sleep(for: .milliseconds(300))
        onFinish()
    }
}

/// One flattened ring spreading across the water and fading as it goes.
private struct RippleRing: View, Animatable {
    var progress: CGFloat
    let width: CGFloat
    let tint: Color

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let w = width * (0.18 + 0.82 * progress)
        Ellipse()
            .stroke(tint, lineWidth: 2)
            .frame(width: w, height: w * 0.16)
            .opacity(progress <= 0 || progress >= 1 ? 0 : Double(1 - progress) * 0.7)
    }
}

#Preview {
    LaunchAnimation {}
}
