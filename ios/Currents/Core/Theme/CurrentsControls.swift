import SwiftUI
import PhotosUI

// MARK: - Water clarity

/// Three tiles showing what the water looks like, rather than a segmented
/// control of words. Clarity is the biggest single lever on lure colour and
/// only the angler can see it, so it's worth the space, and showing the water
/// teaches the rule while they pick. The tiles stack as rows at accessibility
/// text sizes.
struct ClarityPicker: View {
    @Binding var selection: WaterClarity?
    /// When true a second tap clears the choice (used on the catch form,
    /// where "not recorded" is a legitimate state).
    var allowsDeselect: Bool = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: DS.Space.s2))
            : AnyLayout(HStackLayout(alignment: .top, spacing: DS.Space.s2))
        layout {
            ForEach(WaterClarity.allCases) { clarity in
                option(clarity)
            }
        }
    }

    private func option(_ clarity: WaterClarity) -> some View {
        let isSelected = selection == clarity
        return Button {
            Haptics.selection()
            withAnimation(.snappy(duration: 0.2)) {
                selection = (allowsDeselect && isSelected) ? nil : clarity
            }
        } label: {
            ClarityTile(clarity: clarity, isSelected: isSelected, stacked: typeSize.isAccessibilitySize)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(clarity.label)
        .accessibilityValue(clarity.detail)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// One clarity choice: a flat swatch of the water with its drop symbol, the
/// name and how far you can see.
private struct ClarityTile: View {
    let clarity: WaterClarity
    let isSelected: Bool
    /// Accessibility sizes: swatch beside the text instead of above it.
    let stacked: Bool

    var body: some View {
        if stacked {
            HStack(spacing: DS.Space.s3) {
                ClaritySwatch(clarity: clarity, isSelected: isSelected)
                    .frame(width: 64)
                labels(alignment: .leading)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        } else {
            VStack(spacing: 6) {
                ClaritySwatch(clarity: clarity, isSelected: isSelected)
                labels(alignment: .center)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
    }

    private func labels(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(clarity.label)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? DS.accent : Color.dsText2)
            Text(clarity.detail)
                .font(.caption2)
                .foregroundStyle(.dsText3)
                .multilineTextAlignment(alignment == .center ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The water colour as a flat tint behind the clarity's drop symbol, on the
/// same plate a thumbnail uses. Ringed in the accent when chosen.
private struct ClaritySwatch: View {
    let clarity: WaterClarity
    let isSelected: Bool
    @Environment(\.colorScheme) private var scheme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous)
    }

    var body: some View {
        ZStack {
            shape.fill(Color.dsBackground)
            shape.fill(clarity.swatch.opacity(DS.thumbTintOpacity(scheme)))
            Image(systemName: clarity.icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(clarity.swatch)
        }
        .frame(height: 44)
        .overlay {
            shape.strokeBorder(isSelected ? DS.accent : Color.clear, lineWidth: 2)
        }
    }
}

extension WaterClarity {
    /// Roughly the colour of this water, as one flat system colour that
    /// adapts to light and dark.
    var swatch: Color {
        switch self {
        case .clear: .cyan
        case .stained: .green
        case .muddy: .brown
        }
    }
}

// MARK: - Lure colour swatch

/// Renders a lure colour as that colour. "Chartreuse / White" means nothing
/// as text at a glance; the actual colours side by side read instantly.
/// Flat stripes in a circle, one per colour in the name.
struct LureColorSwatch: View {
    let name: String
    var size: CGFloat = 18

    var body: some View {
        let colors = Self.colors(for: name)
        HStack(spacing: 0) {
            ForEach(colors.indices, id: \.self) { i in
                colors[i]
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(Color.dsSeparator, lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }

    /// Split on "/" and map each token to a real colour, so combination
    /// names render as the combination. Grey when nothing is recognised.
    static func colors(for name: String) -> [Color] {
        let mapped = tokens(in: name).compactMap(color)
        return mapped.isEmpty ? [.gray] : mapped
    }

    /// True when at least one part of the name maps to a real colour.
    static func isKnown(_ name: String) -> Bool {
        tokens(in: name).contains { color(for: $0) != nil }
    }

    private static func tokens(in name: String) -> [String] {
        name.split(separator: "/").map {
            $0.trimmingCharacters(in: .whitespaces).lowercased()
        }
    }

    /// The colours lures are sold in. These are content (the swatch shows the
    /// paint itself), so they are fixed values rather than theme colours.
    private static func color(for t: String) -> Color? {
        switch true {
        case t.contains("chartreuse"):    return Color(red: 0.76, green: 0.94, blue: 0.13) // ui-lint: allow lure paint, content not chrome
        case t.contains("firetiger"):     return Color(red: 0.95, green: 0.62, blue: 0.05) // ui-lint: allow lure paint, content not chrome
        case t.contains("green pumpkin"): return Color(red: 0.35, green: 0.36, blue: 0.19) // ui-lint: allow lure paint, content not chrome
        case t.contains("watermelon"):    return Color(red: 0.36, green: 0.45, blue: 0.24) // ui-lint: allow lure paint, content not chrome
        case t.contains("pearl"):         return Color(red: 0.95, green: 0.94, blue: 0.90) // ui-lint: allow lure paint, content not chrome
        case t.contains("shad"),
             t.contains("natural"):       return Color(red: 0.72, green: 0.76, blue: 0.78) // ui-lint: allow lure paint, content not chrome
        case t.contains("chrome"),
             t.contains("silver"):        return Color(red: 0.80, green: 0.83, blue: 0.86) // ui-lint: allow lure paint, content not chrome
        case t.contains("gold"):          return Color(red: 0.85, green: 0.68, blue: 0.24) // ui-lint: allow lure paint, content not chrome
        case t.contains("white"):         return Color(red: 0.97, green: 0.97, blue: 0.97) // ui-lint: allow lure paint, content not chrome
        case t.contains("black"):         return Color(red: 0.12, green: 0.12, blue: 0.13) // ui-lint: allow lure paint, content not chrome
        case t.contains("blue"):          return Color(red: 0.18, green: 0.32, blue: 0.72) // ui-lint: allow lure paint, content not chrome
        case t.contains("orange"):        return Color(red: 0.96, green: 0.52, blue: 0.11) // ui-lint: allow lure paint, content not chrome
        case t.contains("red"):           return Color(red: 0.80, green: 0.16, blue: 0.16) // ui-lint: allow lure paint, content not chrome
        case t.contains("green"):         return Color(red: 0.24, green: 0.60, blue: 0.30) // ui-lint: allow lure paint, content not chrome
        default:                          return nil
        }
    }
}

// MARK: - Photo row

/// The photo row at the top of the gear forms, laid out like the photo in
/// Contacts: a rounded square preview, then a button that offers the camera,
/// the library and removal. Without a photo the preview shows what the item
/// will look like in the tackle box (lure art or the category glyph).
struct PhotoWell: View {
    let image: UIImage?
    /// Side of the square preview.
    var height: CGFloat = 96
    /// The draft's category and name, for the no-photo preview.
    var category: OwnedGear.Category? = nil
    var name: String = ""
    let onTake: () -> Void
    let onChoose: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: DS.Space.s3) {
            preview
                .accessibilityHidden(true)
            menu
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.s2)
    }

    @ViewBuilder
    private var preview: some View {
        if let image {
            ThumbView(image: image, size: height)
        } else if let category {
            GearDraftArt(category: category, name: name, size: height)
        } else {
            ThumbView(systemImage: "camera.fill", tint: .gray, size: height)
        }
    }

    private var menu: some View {
        Menu {
            // Offering the camera where there isn't one (simulator, iPads
            // without a rear camera) presents a picker that can't work.
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button(action: onTake) { Label("Take photo", systemImage: "camera") }
            }
            Button(action: onChoose) { Label("Choose photo", systemImage: "photo.on.rectangle") }
            if image != nil {
                Divider()
                Button(role: .destructive, action: onRemove) {
                    Label("Remove photo", systemImage: "trash")
                }
            }
        } label: {
            Label(image == nil ? "Add photo" : "Change photo",
                  systemImage: image == nil ? "camera" : "photo")
        }
        .buttonStyle(TonalButtonStyle(fullWidth: false))
    }
}

/// What a new item looks like before it has a photo: the lure art for lures
/// and bait with a name, otherwise the category glyph on its tint.
struct GearDraftArt: View {
    let category: OwnedGear.Category
    let name: String
    var size: CGFloat = 96

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        if (category == .lure || category == .bait) && !trimmed.isEmpty {
            LureArtView(name: trimmed, size: size)
        } else {
            GearThumbnail(photoPath: nil, category: category, size: size)
        }
    }
}

/// The photo row plus its camera and library plumbing, so the add and edit
/// gear sheets share one implementation. Asks for the camera the first time
/// and explains when access is off.
struct GearPhotoField: View {
    @Binding var image: UIImage?
    var category: OwnedGear.Category? = nil
    var name: String = ""

    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var cameraOff = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        PhotoWell(
            image: image,
            category: category,
            name: name,
            onTake: takePhoto,
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
                // Clear it so picking the same photo again still loads.
                pickerItem = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { captured in image = captured }
                .ignoresSafeArea()
        }
        .alert("Camera access is off", isPresented: $cameraOff) {
            Button("Open Settings", action: openSettings)
            Button("Choose photo") { showLibrary = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Allow camera access for Currents in Settings to photograph your gear, or choose a photo from your library.")
        }
    }

    private func takePhoto() {
        Task { @MainActor in
            if await CameraAccess.request() {
                showCamera = true
            } else {
                cameraOff = true
            }
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
}

// MARK: - Gear glyphs

/// SF Symbols has no fishing hook, so the hook category was borrowing a
/// paperclip. Drawn here instead: eye, straight shank, the bend, and a barbed
/// point, stroked to sit alongside real symbols without looking foreign.
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

/// Likewise no reel symbol: "record.circle" read as a camera control. A
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
/// reel appear everywhere the SF Symbol ones do. Fills a `size` square; the
/// symbol is scaled to the frame rather than given a point size.
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
                .resizable()
                .scaledToFit()
                .fontWeight(.medium)
                .frame(width: size * 0.82, height: size * 0.82)
                .frame(width: size, height: size)
        }
    }
}

// MARK: - Gear thumbnail

/// Row-sized gear image: the photo when there is one, the category glyph on
/// the category tint when there isn't. A `ThumbView`, so it has the same
/// plate and corner radius as every other thumbnail.
struct GearThumbnail: View {
    let photoPath: String?
    let category: OwnedGear.Category
    var size: CGFloat = 44

    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ThumbView(tint: category.tint, size: size) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                GearGlyph(category: category, size: size * 0.48)
                    .foregroundStyle(category.tint)
            }
        }
        .task(id: photoPath) {
            guard let photoPath else { image = nil; return }
            let px = size * displayScale
            let scale = displayScale
            image = await Task.detached(priority: .userInitiated) {
                PhotoManager.thumbnail(photoPath, maxPixel: px, scale: scale)
            }.value
        }
    }
}

// MARK: - Gear field picker

/// A gear field as a menu row: None, the owned items of that kind, and Custom,
/// which adds a text row underneath for anything not in the tackle box.
/// Custom mode is tracked apart from the value, so typing a custom name never
/// hides the field.
struct GearFieldPicker: View {
    let placeholder: String
    let items: [OwnedGear]
    @Binding var selection: String
    @State private var isCustom = false
    @State private var customText = ""

    static let customTag = "__custom__"

    var body: some View {
        Picker(placeholder, selection: choice) {
            Text("None").tag("")
            ForEach(items) { item in
                Text(item.displayName).tag(item.displayName)
            }
            Text("Custom").tag(Self.customTag)
        }
        .pickerStyle(.menu)

        if isCustom {
            TextField(placeholder, text: $customText,
                      prompt: Text("Type the \(placeholder.lowercased())"))
                .onChange(of: customText) { _, newValue in selection = newValue }
        }
    }

    private var choice: Binding<String> {
        Binding(
            get: { isCustom ? Self.customTag : selection },
            set: { newValue in
                Haptics.selection()
                if newValue == Self.customTag {
                    isCustom = true
                    selection = customText   // keep any text already typed
                } else {
                    isCustom = false
                    selection = newValue
                }
            }
        )
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
