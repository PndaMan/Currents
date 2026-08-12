import SwiftUI
import PhotosUI

// MARK: - Segmented pills

/// Segment switcher for a screen's two-or-three peer views: plain labels
/// with icons over a hairline, and an accent underline that slides to the
/// selection — the same underline language as every filter row, no pills.
struct SegmentedPills<T: Hashable & Identifiable>: View {
    let options: [T]
    @Binding var selection: T
    let title: (T) -> String
    let icon: (T) -> String

    @Namespace private var ns
    // Observed so the underline re-tints the moment the theme changes.
    @AppStorage("selectedTheme") private var selectedTheme = ThemeOption.ocean.rawValue
    private var accent: Color { (ThemeOption(rawValue: selectedTheme) ?? .ocean).primary }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                let isSelected = option == selection
                Button {
                    withAnimation(.snappy(duration: 0.22)) { selection = option }
                } label: {
                    VStack(spacing: 7) {
                        HStack(spacing: 5) {
                            Image(systemName: icon(option))
                                .font(.caption.weight(.semibold))
                            Text(title(option))
                                .font(.subheadline.weight(isSelected ? .bold : .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(isSelected ? accent : Color.secondary)
                        ZStack {
                            Capsule().fill(Color.clear).frame(height: 3)
                            if isSelected {
                                Capsule().fill(accent).frame(height: 3)
                                    .matchedGeometryEffect(id: "segment-underline", in: ns)
                            }
                        }
                        .padding(.horizontal, 22)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        // A hairline base the underline sits on, so the row reads as tabs.
        .background(alignment: .bottom) {
            Rectangle().fill(Color.secondary.opacity(0.18)).frame(height: 1)
        }
    }
}

// MARK: - Score ring

/// A 0–100 bite score as a ring. Readable at arm's length on a boat, and the
/// arc carries the value even before you read the number.
struct ScoreRing: View {
    let score: Int
    var size: CGFloat = 62
    var caption: String? = nil

    var body: some View {
        ZStack {
            Circle()
                .stroke(.primary.opacity(0.08), lineWidth: size * 0.11)
            Circle()
                .trim(from: 0, to: CGFloat(min(100, max(0, score))) / 100)
                .stroke(CurrentsTheme.scoreColor(score).gradient,
                        style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: -1) {
                Text("\(score)")
                    .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(CurrentsTheme.scoreColor(score))
                if let caption {
                    Text(caption)
                        .font(.system(size: size * 0.13))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .animation(.snappy(duration: 0.3), value: score)
    }
}

// MARK: - Water clarity

/// Three cards showing what the water actually looks like, rather than a
/// segmented control of words. Clarity is the biggest single lever on lure
/// colour and only the angler can see it, so it's worth the space — and
/// showing the water teaches the rule while they pick.
struct ClarityPicker: View {
    @Binding var selection: WaterClarity?
    /// When true a second tap clears the choice (used on the catch form,
    /// where "not recorded" is a legitimate state).
    var allowsDeselect: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach(WaterClarity.allCases) { clarity in
                let isSelected = selection == clarity
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        selection = (allowsDeselect && isSelected) ? nil : clarity
                    }
                } label: {
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(clarity.waterGradient)
                            .frame(height: 34)
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(isSelected ? CurrentsTheme.accent : .clear,
                                                  lineWidth: 2)
                            }
                        Text(clarity.label)
                            .font(.caption.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? CurrentsTheme.accent : .secondary)
                        Text(clarity.detail)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

extension WaterClarity {
    /// Roughly what you'd see looking down into this water.
    var waterGradient: LinearGradient {
        let colors: [Color]
        switch self {
        case .clear:
            colors = [Color(red: 0.42, green: 0.75, blue: 0.87),
                      Color(red: 0.16, green: 0.47, blue: 0.68)]
        case .stained:
            colors = [Color(red: 0.45, green: 0.55, blue: 0.32),
                      Color(red: 0.24, green: 0.35, blue: 0.20)]
        case .muddy:
            colors = [Color(red: 0.60, green: 0.47, blue: 0.29),
                      Color(red: 0.36, green: 0.26, blue: 0.15)]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Lure colour swatch

/// Renders a lure colour *as that colour*. "Chartreuse / White" means nothing
/// as text at a glance; two stripes of the actual colours read instantly.
struct LureColorSwatch: View {
    let name: String
    var size: CGFloat = 18

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(LinearGradient(colors: Self.colors(for: name),
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(.primary.opacity(0.15), lineWidth: 0.5)
            }
    }

    /// Split on "/" and map each token to a real colour, so combination
    /// names render as the combination.
    static func colors(for name: String) -> [Color] {
        let parts = name.split(separator: "/").map {
            $0.trimmingCharacters(in: .whitespaces).lowercased()
        }
        let mapped = parts.compactMap(token)
        if mapped.isEmpty { return [.gray, .gray.opacity(0.6)] }
        return mapped.count == 1 ? [mapped[0], mapped[0].opacity(0.7)] : mapped
    }

    private static func token(_ t: String) -> Color? {
        switch true {
        case t.contains("chartreuse"):    return Color(red: 0.76, green: 0.94, blue: 0.13)
        case t.contains("firetiger"):     return Color(red: 0.95, green: 0.62, blue: 0.05)
        case t.contains("green pumpkin"): return Color(red: 0.35, green: 0.36, blue: 0.19)
        case t.contains("watermelon"):    return Color(red: 0.36, green: 0.45, blue: 0.24)
        case t.contains("pearl"):         return Color(red: 0.95, green: 0.94, blue: 0.90)
        case t.contains("shad"),
             t.contains("natural"):       return Color(red: 0.72, green: 0.76, blue: 0.78)
        case t.contains("chrome"),
             t.contains("silver"):        return Color(red: 0.80, green: 0.83, blue: 0.86)
        case t.contains("gold"):          return Color(red: 0.85, green: 0.68, blue: 0.24)
        case t.contains("white"):         return Color(red: 0.97, green: 0.97, blue: 0.97)
        case t.contains("black"):         return Color(red: 0.12, green: 0.12, blue: 0.13)
        case t.contains("blue"):          return Color(red: 0.18, green: 0.32, blue: 0.72)
        case t.contains("orange"):        return Color(red: 0.96, green: 0.52, blue: 0.11)
        case t.contains("red"):           return Color(red: 0.80, green: 0.16, blue: 0.16)
        case t.contains("green"):         return Color(red: 0.24, green: 0.60, blue: 0.30)
        default:                          return nil
        }
    }
}

// MARK: - Photo well

/// The capture surface for a piece of gear. Deliberately a wide rounded
/// rectangle, not a circle — lures and rods are long and thin, and a circular
/// crop cuts the ends off exactly the parts you photographed them for.
struct PhotoWell: View {
    let image: UIImage?
    var height: CGFloat = 150
    let onTake: () -> Void
    let onChoose: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Menu {
            // Offering the camera where there isn't one (simulator, iPads
            // without a rear camera) presents a picker that can't work.
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { onTake() } label: { Label("Take Photo", systemImage: "camera") }
            }
            Button { onChoose() } label: { Label("Choose Photo", systemImage: "photo.on.rectangle") }
            if image != nil {
                Divider()
                Button(role: .destructive) { onRemove() } label: {
                    Label("Remove Photo", systemImage: "trash")
                }
            }
        } label: {
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: height)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.5))
                                .padding(8)
                        }
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.gray.opacity(0.10))
                        .frame(height: height)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                                .foregroundStyle(.gray.opacity(0.4))
                        }
                        .overlay {
                            VStack(spacing: 6) {
                                Image(systemName: "camera.fill")
                                    .font(.title2)
                                    .foregroundStyle(CurrentsTheme.accent)
                                Text("Add a photo")
                                    .font(.subheadline.weight(.medium))
                                Text("So you can see the colour, not just the name")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.horizontal)
                        }
                }
            }
            .frame(maxWidth: .infinity)
            .clipped()
        }
        .buttonStyle(.plain)
    }
}

/// The photo well plus its camera and library plumbing, so the add and edit
/// gear sheets share one implementation rather than each growing their own.
struct GearPhotoField: View {
    @Binding var image: UIImage?

    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        PhotoWell(
            image: image,
            onTake: { showCamera = true },
            onChoose: { showLibrary = true },
            onRemove: { image = nil }
        )
        .photosPicker(isPresented: $showLibrary, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let ui = UIImage(data: data) {
                    image = ui
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { captured in image = captured }
                .ignoresSafeArea()
        }
    }
}

// MARK: - Gear glyphs

/// SF Symbols has no fishing hook, so the hook category was borrowing a
/// paperclip. Drawn here instead: eye, straight shank, the bend, and a barbed
/// point — stroked to sit alongside real symbols without looking foreign.
struct FishHookShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        let shankX = w * 0.60

        // Eye at the top of the shank.
        let eyeR = w * 0.11
        p.addEllipse(in: CGRect(x: shankX - eyeR, y: h * 0.06,
                                width: eyeR * 2, height: eyeR * 2))

        // Shank straight down, then the bend sweeping left and back up.
        p.move(to: CGPoint(x: shankX, y: h * 0.06 + eyeR * 2))
        p.addLine(to: CGPoint(x: shankX, y: h * 0.56))
        p.addCurve(to: CGPoint(x: w * 0.26, y: h * 0.60),
                   control1: CGPoint(x: shankX, y: h * 0.92),
                   control2: CGPoint(x: w * 0.24, y: h * 0.90))

        // Point, with a barb kicking off it.
        p.addLine(to: CGPoint(x: w * 0.33, y: h * 0.44))
        p.move(to: CGPoint(x: w * 0.295, y: h * 0.53))
        p.addLine(to: CGPoint(x: w * 0.44, y: h * 0.56))
        return p
    }
}

/// Likewise no reel symbol — "record.circle" read as a camera control. A
/// spinning reel in profile: spool, stem, rod foot and handle.
struct FishingReelShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        let c = CGPoint(x: w * 0.46, y: h * 0.60)
        let r = min(w, h) * 0.29

        // Spool.
        p.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        let inner = r * 0.36
        p.addEllipse(in: CGRect(x: c.x - inner, y: c.y - inner,
                                width: inner * 2, height: inner * 2))

        // Stem up to the rod foot.
        p.move(to: CGPoint(x: c.x, y: c.y - r))
        p.addLine(to: CGPoint(x: c.x, y: h * 0.20))
        p.move(to: CGPoint(x: w * 0.20, y: h * 0.16))
        p.addLine(to: CGPoint(x: w * 0.78, y: h * 0.16))

        // Handle arm and knob.
        p.move(to: CGPoint(x: c.x + r, y: c.y))
        p.addLine(to: CGPoint(x: w * 0.90, y: c.y))
        p.addLine(to: CGPoint(x: w * 0.90, y: c.y + h * 0.16))
        return p
    }
}

/// One place that knows how to draw a gear category, so the custom hook and
/// reel appear everywhere the SF Symbol ones do.
struct GearGlyph: View {
    let category: OwnedGear.Category
    var size: CGFloat = 17

    var body: some View {
        switch category {
        case .hook:
            FishHookShape()
                .stroke(style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round, lineJoin: .round))
                .frame(width: size, height: size)
        case .reel:
            FishingReelShape()
                .stroke(style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round, lineJoin: .round))
                .frame(width: size, height: size)
        default:
            Image(systemName: category.icon)
                .font(.system(size: size * 0.82))
                .frame(width: size, height: size)
        }
    }
}

/// Label equivalent, for rows and menus that want glyph + text.
struct GearCategoryLabel: View {
    let category: OwnedGear.Category
    var text: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            GearGlyph(category: category, size: 17)
            Text(text ?? category.rawValue)
        }
    }
}

// MARK: - Gear thumbnail

/// Row-sized gear image: the photo when there is one, the category glyph when
/// there isn't. Rounded rect for the same reason as the well above.
struct GearThumbnail: View {
    let photoPath: String?
    let category: OwnedGear.Category
    var size: CGFloat = 44

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                GearGlyph(category: category, size: size * 0.46)
                    .foregroundStyle(CurrentsTheme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(CurrentsTheme.accent.opacity(0.12))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .task(id: photoPath) {
            guard let photoPath else { image = nil; return }
            let px = size * 3
            image = await Task.detached(priority: .userInitiated) {
                PhotoManager.thumbnail(photoPath, maxPixel: px)
            }.value
        }
    }
}

// MARK: - Gear field picker

/// Gear field with an owned-gear picker plus a "Custom…" option that reveals a
/// free-text field. Custom mode is tracked separately from the value, so typing
/// a custom name no longer hides the field (the old code bound the field
/// directly to the "__custom__" sentinel, so the first keystroke dismissed it).
struct GearFieldPicker: View {
    let placeholder: String
    let items: [OwnedGear]
    @Binding var selection: String
    @State private var isCustom = false
    @State private var customText = ""

    var body: some View {
        Picker(placeholder, selection: Binding(
            get: { isCustom ? "__custom__" : selection },
            set: { newValue in
                if newValue == "__custom__" {
                    isCustom = true
                    selection = customText   // keep any text already typed
                } else {
                    isCustom = false
                    selection = newValue
                }
            }
        )) {
            Text("None").tag("")
            ForEach(items) { item in
                Text(item.displayName).tag(item.displayName)
            }
            Text("Custom…").tag("__custom__")
        }

        if isCustom {
            TextField("Custom \(placeholder.lowercased())", text: $customText)
                .onChange(of: customText) { _, newValue in selection = newValue }
        }
    }

    init(placeholder: String, items: [OwnedGear], selection: Binding<String>) {
        self.placeholder = placeholder
        self.items = items
        self._selection = selection
        // Resume in custom mode if the stored value isn't one of the owned items.
        let value = selection.wrappedValue
        let isKnown = value.isEmpty || items.contains { $0.displayName == value }
        _isCustom = State(initialValue: !isKnown)
        _customText = State(initialValue: isKnown ? "" : value)
    }
}

// MARK: - Prominent button labels

/// Label style for filled accent buttons. Inside a List or Form the default
/// label style tints SF-symbol icons with the accent colour — invisible on a
/// borderedProminent accent fill — so this pins both glyph and title white.
struct ProminentButtonLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
            configuration.title
        }
        .foregroundStyle(.white)
    }
}

extension LabelStyle where Self == ProminentButtonLabelStyle {
    static var prominentButton: ProminentButtonLabelStyle { ProminentButtonLabelStyle() }
}

// MARK: - Tap-to-fullscreen images

/// Tap-to-fullscreen for any already-loaded image — avatars, crew banners,
/// post photos. Tapping opens the pinch-zoomable viewer; no image, no-op.
/// A real Button (not onTapGesture): inside a List row a bare tap gesture
/// becomes the ROW's primary action, so tapping anywhere on the post —
/// the crew chip, the ⋯ menu — opened the photo. Buttons hit-test exactly.
private struct ZoomableOnTap: ViewModifier {
    let image: UIImage?
    @State private var showing = false

    func body(content: Content) -> some View {
        Button {
            if image != nil {
                Haptics.tap()
                showing = true
            }
        } label: {
            content
                // Clamp the tap target to the VISIBLE frame. scaledToFill
                // images are laid out far larger than their clipped frame and
                // .clipped() only clips drawing — without this, the button's
                // hit area silently covered neighbouring controls (the crew
                // chip, the author header, the ⋯ menu all opened the photo).
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $showing) {
            if let image { FullscreenImageViewer(image: image) }
        }
    }
}

extension View {
    func zoomableOnTap(_ image: UIImage?) -> some View {
        modifier(ZoomableOnTap(image: image))
    }
}
