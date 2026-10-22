import SwiftUI
import UIKit

/// One screen for the app's whole look: light or dark, the colour theme and the
/// home-screen icon. By default the icon follows the theme: pick Forest and
/// both the accent and the icon turn green. Choosing an icon that differs from
/// the theme decouples them; re-picking the matching icon (or turning Match the
/// colour theme back on) links them again.
struct AppearanceSettingsView: View {
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.dark.rawValue
    @AppStorage("selectedTheme") private var selectedTheme = ThemeOption.ocean.rawValue
    @AppStorage("selectedAppIcon") private var selectedAppIcon = "ocean"
    /// When true the app icon automatically tracks the colour theme.
    @AppStorage("appIconFollowsTheme") private var iconFollowsTheme = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var titleShown = false

    private let themeColumns = [GridItem(.adaptive(minimum: 68), spacing: 12)]
    private let iconColumns = [GridItem(.adaptive(minimum: 76), spacing: 12)]

    private var theme: ThemeOption { ThemeOption(rawValue: selectedTheme) ?? .ocean }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                DetailHeader(title: "Appearance", subtitle: "Dark is easier on the eyes at dawn and dusk.")

                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    SectionTitle("Mode")
                    HStack(spacing: 12) {
                        ForEach(AppearanceMode.allCases) { mode in
                            modeCard(mode)
                        }
                    }
                    .padding(.horizontal, DS.gutter)
                }

                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    SectionTitle("Colour theme")
                    LazyVGrid(columns: themeColumns, spacing: 16) {
                        ForEach(ThemeOption.allCases) { theme in
                            themeCircle(theme)
                        }
                    }
                    .padding(.horizontal, DS.gutter)
                    PFFootnote("Tints buttons, highlights and the logo. \(theme.displayName) is on.")
                }

                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    SectionTitle("App icon")
                    PFToggleRow(title: "Match the colour theme", detail: "The icon follows your theme",
                                isOn: Binding(get: { iconFollowsTheme },
                                              set: { on in
                                                  if on { relinkIconToTheme() } else { iconFollowsTheme = false }
                                              }))
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.vertical, 12)
                        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                        .padding(.horizontal, DS.gutter)
                    LazyVGrid(columns: iconColumns, spacing: 16) {
                        ForEach(AppIconOption.all) { option in
                            iconCell(for: option)
                        }
                    }
                    .padding(.horizontal, DS.gutter)
                    PFFootnote(iconFollowsTheme
                               ? "Pick a different icon to set it on its own."
                               : "Your icon is set on its own. Turn on Match the colour theme to link them again.")
                }
            }
            .padding(.bottom, DS.Space.s8)
        }
        .detailTint(theme.primary)
        .pfTrackScroll($titleShown, threshold: 60)
        .pfScrollTitle("Appearance", shown: titleShown)
        .sensoryFeedback(.selection, trigger: selectedTheme)
        .sensoryFeedback(.selection, trigger: selectedAppIcon)
        .sensoryFeedback(.selection, trigger: appearanceMode)
    }

    // MARK: - Mode cards

    private func modeCard(_ mode: AppearanceMode) -> some View {
        let isActive = appearanceMode == mode.rawValue
        return Button {
            appearanceMode = mode.rawValue
        } label: {
            VStack(spacing: DS.Space.s2) {
                modeArt(mode)
                    .frame(height: 96)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous)
                            .strokeBorder(isActive ? theme.primary : Color.dsSeparator, lineWidth: isActive ? 2.5 : 1)
                    )
                Label(mode.title, systemImage: mode.systemImage)
                    .font(.subheadline.weight(isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? Color.dsText : Color.dsText2)
            }
        }
        .buttonStyle(.dim)
        .accessibilityLabel(mode.title)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    /// A tiny page sketch in the mode's colours. System shows both halves.
    @ViewBuilder
    private func modeArt(_ mode: AppearanceMode) -> some View {
        switch mode {
        case .light: modeSketch(dark: false)
        case .dark: modeSketch(dark: true)
        case .system:
            HStack(spacing: 0) {
                modeSketch(dark: false)
                modeSketch(dark: true)
            }
        }
    }

    private func modeSketch(dark: Bool) -> some View {
        let bg = dark ? Color.black : Color.white
        let fill = dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08)
        return ZStack(alignment: .topLeading) {
            bg
            VStack(alignment: .leading, spacing: 6) {
                Capsule().fill(fill).frame(width: 34, height: 7)
                Capsule().fill(theme.primary.opacity(0.8)).frame(height: 18)
                Capsule().fill(fill).frame(height: 10)
                Capsule().fill(fill).frame(width: 40, height: 10)
            }
            .padding(10)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Theme grid

    private func themeCircle(_ theme: ThemeOption) -> some View {
        let isActive = selectedTheme == theme.rawValue
        return Button {
            selectTheme(theme)
        } label: {
            VStack(spacing: 8) {
                Circle()
                    .fill(theme.primary)
                    .frame(width: 44, height: 44)
                    .overlay {
                        if isActive {
                            Image(systemName: "checkmark")
                                .font(.body.bold())
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(4)
                    .overlay(Circle().strokeBorder(isActive ? theme.primary : Color.clear, lineWidth: 2.5))
                Text(theme.displayName)
                    .font(.caption)
                    .foregroundStyle(isActive ? Color.dsText : Color.dsText2)
            }
        }
        .buttonStyle(.dim)
        .accessibilityLabel(theme.displayName)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // MARK: - Icon grid

    private func iconCell(for option: AppIconOption) -> some View {
        let isSelected = selectedAppIcon == option.id
        let tint = (ThemeOption(rawValue: option.id) ?? .ocean).primary
        return Button {
            selectIcon(option)
        } label: {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
                    .fill(Color.black)
                    .frame(width: 64, height: 64)
                    .overlay(
                        CurrentsMark()
                            .stroke(tint, style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
                            .frame(width: 40, height: 40)
                    )
                    .padding(3)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.button + 3, style: .continuous)
                            .strokeBorder(isSelected ? tint : Color.dsSeparator, lineWidth: isSelected ? 2.5 : 1)
                    )
                Text(option.name)
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.dsText : Color.dsText2)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
        }
        .buttonStyle(.dim)
        .accessibilityLabel("\(option.name) icon")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Selection + sync

    private func selectTheme(_ theme: ThemeOption) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: DS.Motion.fast)) { selectedTheme = theme.rawValue }
        // Icon follows the theme unless the user has overridden it.
        guard iconFollowsTheme, selectedAppIcon != theme.rawValue else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: DS.Motion.fast)) { selectedAppIcon = theme.rawValue }
        setAppIcon(AppIconOption.option(for: theme.rawValue).alternateIconName)
    }

    private func selectIcon(_ option: AppIconOption) {
        if selectedAppIcon != option.id {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: DS.Motion.fast)) { selectedAppIcon = option.id }
            setAppIcon(option.alternateIconName)
        }
        // Linked only while the icon matches the active theme; otherwise it's a
        // deliberate override that survives future theme changes.
        iconFollowsTheme = (option.id == selectedTheme)
    }

    private func relinkIconToTheme() {
        iconFollowsTheme = true
        guard selectedAppIcon != selectedTheme else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: DS.Motion.fast)) { selectedAppIcon = selectedTheme }
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
