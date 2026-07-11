import SwiftUI

// MARK: - App Icon Option

struct AppIconOption: Identifiable {
    let id: String              // matches ThemeOption raw value
    let name: String
    let logoAsset: String       // image asset name for preview
    let alternateIconName: String? // nil = primary icon, string = CFBundleAlternateIcons key

    /// The 4 available logo variants, mapped to closest themes.
    static let all: [AppIconOption] = [
        AppIconOption(id: "ocean", name: "Ocean",
                      logoAsset: "Logo",
                      alternateIconName: nil), // Primary (default)
        AppIconOption(id: "forest", name: "Forest",
                      logoAsset: "LogoGreen",
                      alternateIconName: "AppIcon-Green"),
        AppIconOption(id: "amethyst", name: "Amethyst",
                      logoAsset: "LogoPurple",
                      alternateIconName: "AppIcon-Purple"),
        AppIconOption(id: "gold", name: "Gold",
                      logoAsset: "LogoGold",
                      alternateIconName: "AppIcon-Gold"),
    ]

    static func option(for id: String) -> AppIconOption {
        all.first { $0.id == id } ?? all[0]
    }
}

// MARK: - App Icon Selector View

struct AppIconSelectorView: View {
    @AppStorage("selectedAppIcon") private var selectedAppIcon = "ocean"

    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 140), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Choose your app icon")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(AppIconOption.all) { option in
                        iconCell(for: option)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("App Icon")
    }

    @ViewBuilder
    private func iconCell(for option: AppIconOption) -> some View {
        let isSelected = selectedAppIcon == option.id
        let tint = (ThemeOption(rawValue: option.id) ?? .ocean).primary
        VStack(spacing: 8) {
            ZStack {
                // Uniform, adaptive tile: transparent-feeling surface that follows
                // light/dark, with the single-colour current mark tinted per theme.
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 72, height: 72)
                    .overlay(
                        CurrentsMark()
                            .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                            .frame(width: 46, height: 46)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(isSelected ? tint : Color.primary.opacity(0.08), lineWidth: isSelected ? 3 : 1)
                    )
                    .shadow(color: isSelected ? tint.opacity(0.35) : .clear, radius: 6, y: 2)

                if isSelected {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.white, tint)
                        }
                        Spacer()
                    }
                    .frame(width: 72, height: 72)
                    .offset(x: 6, y: -6)
                }
            }

            Text(option.name)
                .font(.caption)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .fontWeight(isSelected ? .semibold : .regular)
        }
        .onTapGesture {
            guard selectedAppIcon != option.id else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedAppIcon = option.id
            }
            setAppIcon(option.alternateIconName)
        }
    }

    private func setAppIcon(_ iconName: String?) {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        UIApplication.shared.setAlternateIconName(iconName) { error in
            if let error {
                print("[Currents] Failed to set app icon: \(error.localizedDescription)")
            }
        }
    }
}

#Preview {
    NavigationStack {
        AppIconSelectorView()
    }
}
