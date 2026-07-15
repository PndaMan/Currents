import SwiftUI
import UIKit

/// One screen for the app's whole look: the colour theme and the home-screen
/// icon, kept in sync. By default the icon **follows the theme** — pick "Forest"
/// and both the accent and the icon turn green. Choosing an icon that differs
/// from the theme decouples them (an override); re-picking the matching icon (or
/// "Match theme") links them back.
struct AppearanceSettingsView: View {
    @AppStorage("selectedTheme") private var selectedTheme = ThemeOption.ocean.rawValue
    @AppStorage("selectedAppIcon") private var selectedAppIcon = "ocean"
    /// When true the app icon automatically tracks the colour theme.
    @AppStorage("appIconFollowsTheme") private var iconFollowsTheme = true

    private let themeColumns = [GridItem(.adaptive(minimum: 80), spacing: 16)]
    private let iconColumns = [GridItem(.adaptive(minimum: 100, maximum: 140), spacing: 16)]

    var body: some View {
        Form {
            Section {
                LazyVGrid(columns: themeColumns, spacing: 20) {
                    ForEach(ThemeOption.allCases) { theme in
                        themeCircle(theme)
                    }
                }
                .padding(.vertical, 12)
            } header: {
                Text("Color Theme")
            } footer: {
                Text("Sets the accent colour across buttons, highlights and the logo.")
            }

            Section {
                LazyVGrid(columns: iconColumns, spacing: 20) {
                    ForEach(AppIconOption.all) { option in
                        iconCell(for: option)
                    }
                }
                .padding(.vertical, 8)
            } header: {
                HStack {
                    Text("App Icon")
                    Spacer()
                    if !iconFollowsTheme {
                        Button("Match theme") { relinkIconToTheme() }
                            .font(.caption.bold())
                            .textCase(nil)
                    }
                }
            } footer: {
                Text(iconFollowsTheme
                     ? "Your app icon follows your colour theme. Pick a different icon to set it on its own."
                     : "Your app icon is set independently. Tap the icon matching your theme — or “Match theme” — to link them again.")
            }
        }
        .navigationTitle("Appearance")
        .sensoryFeedback(.selection, trigger: selectedTheme)
        .sensoryFeedback(.selection, trigger: selectedAppIcon)
    }

    // MARK: - Theme grid

    private func themeCircle(_ theme: ThemeOption) -> some View {
        let isActive = selectedTheme == theme.rawValue
        return VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [theme.gradient.0, theme.gradient.1],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)

                if isActive {
                    Image(systemName: "checkmark")
                        .font(.body.bold())
                        .foregroundStyle(.white)
                }
            }
            .overlay(
                Circle()
                    .stroke(isActive ? theme.primary : Color.clear, lineWidth: 3)
                    .frame(width: 60, height: 60)
            )

            Text(theme.displayName)
                .font(.caption)
                .foregroundStyle(isActive ? .primary : .secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { selectTheme(theme) }
    }

    // MARK: - Icon grid

    @ViewBuilder
    private func iconCell(for option: AppIconOption) -> some View {
        let isSelected = selectedAppIcon == option.id
        let tint = (ThemeOption(rawValue: option.id) ?? .ocean).primary
        VStack(spacing: 8) {
            ZStack {
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
        .contentShape(Rectangle())
        .onTapGesture { selectIcon(option) }
    }

    // MARK: - Selection + sync

    private func selectTheme(_ theme: ThemeOption) {
        withAnimation(.easeInOut(duration: 0.2)) { selectedTheme = theme.rawValue }
        // Icon follows the theme unless the user has overridden it.
        guard iconFollowsTheme, selectedAppIcon != theme.rawValue else { return }
        withAnimation(.easeInOut(duration: 0.2)) { selectedAppIcon = theme.rawValue }
        setAppIcon(AppIconOption.option(for: theme.rawValue).alternateIconName)
    }

    private func selectIcon(_ option: AppIconOption) {
        if selectedAppIcon != option.id {
            withAnimation(.easeInOut(duration: 0.2)) { selectedAppIcon = option.id }
            setAppIcon(option.alternateIconName)
        }
        // Linked only while the icon matches the active theme; otherwise it's a
        // deliberate override that survives future theme changes.
        iconFollowsTheme = (option.id == selectedTheme)
    }

    private func relinkIconToTheme() {
        iconFollowsTheme = true
        guard selectedAppIcon != selectedTheme else { return }
        withAnimation(.easeInOut(duration: 0.2)) { selectedAppIcon = selectedTheme }
        setAppIcon(AppIconOption.option(for: selectedTheme).alternateIconName)
    }

    private func setAppIcon(_ iconName: String?) {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        UIApplication.shared.setAlternateIconName(iconName) { error in
            if let error {
                print("[Currents] Failed to set app icon: \(error.localizedDescription)")
                Task { @MainActor in ToastCenter.shared.show("Couldn't change app icon", style: .error) }
            } else {
                Task { @MainActor in ToastCenter.shared.show("App icon changed", haptic: false) }
            }
        }
    }
}

#Preview {
    NavigationStack {
        AppearanceSettingsView()
    }
    .preferredColorScheme(.dark)
}
