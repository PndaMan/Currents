import SwiftUI
import PhotosUI

// MARK: - Segmented pills

/// A segmented control that doesn't look like the system one: full-height
/// pills with icons, an accent fill that slides between them, and enough
/// tap target to use with cold hands. Used wherever a screen has two or
/// three peer views.
struct SegmentedPills<T: Hashable & Identifiable>: View {
    let options: [T]
    @Binding var selection: T
    let title: (T) -> String
    let icon: (T) -> String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                let isSelected = option == selection
                Button {
                    withAnimation(.snappy(duration: 0.22)) { selection = option }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: icon(option))
                            .font(.caption2.weight(.semibold))
                        Text(title(option))
                            .font(.subheadline.weight(isSelected ? .semibold : .regular))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .foregroundStyle(isSelected ? .white : Color.secondary)
                    .background {
                        if isSelected {
                            Capsule().fill(CurrentsTheme.accent)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(.gray.opacity(0.14), in: Capsule())
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
                Image(systemName: category.icon)
                    .font(.subheadline)
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
