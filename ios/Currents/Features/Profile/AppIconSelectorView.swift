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
        VStack(spacing: 8) {
            ZStack {
                Image(option.logoAsset)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 72, height: 72)
                    .background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(isSelected ? CurrentsTheme.accent : Color.clear, lineWidth: 3)
                    )
                    .shadow(color: isSelected ? CurrentsTheme.accent.opacity(0.4) : .clear, radius: 6, y: 2)

                if isSelected {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.white, CurrentsTheme.accent)
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
