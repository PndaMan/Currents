import SwiftUI

// MARK: - Theme Options

/// Available color themes for the app.
enum ThemeOption: String, CaseIterable, Codable, Identifiable {
    case ocean = "ocean"
    case forest = "forest"
    case ember = "ember"
    case sunset = "sunset"
    case amethyst = "amethyst"
    case teal = "teal"
    case rose = "rose"
    case gold = "gold"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ocean: "Ocean"
        case .forest: "Forest"
        case .ember: "Ember"
        case .sunset: "Sunset"
        case .amethyst: "Amethyst"
        case .teal: "Teal"
        case .rose: "Rose"
        case .gold: "Gold"
        }
    }

    var primary: Color {
        switch self {
        case .ocean: .blue
        case .forest: .green
        case .ember: Color(red: 0.86, green: 0.15, blue: 0.15)
        case .sunset: .orange
        case .amethyst: .purple
        case .teal: .teal
        case .rose: .pink
        case .gold: Color(red: 0.85, green: 0.65, blue: 0.13)
        }
    }

    /// Two-color gradient for the wordmark.
    var gradient: (Color, Color) {
        switch self {
        case .ocean:
            (Color(red: 0.10, green: 0.55, blue: 0.95),
             Color(red: 0.15, green: 0.82, blue: 0.98))
        case .forest:
            (Color(red: 0.18, green: 0.62, blue: 0.34),
             Color(red: 0.30, green: 0.85, blue: 0.50))
        case .ember:
            (Color(red: 0.86, green: 0.15, blue: 0.15),
             Color(red: 0.95, green: 0.40, blue: 0.25))
        case .sunset:
            (Color(red: 0.95, green: 0.55, blue: 0.15),
             Color(red: 0.98, green: 0.75, blue: 0.25))
        case .amethyst:
            (Color(red: 0.55, green: 0.25, blue: 0.85),
             Color(red: 0.72, green: 0.45, blue: 0.95))
        case .teal:
            (Color(red: 0.15, green: 0.65, blue: 0.70),
             Color(red: 0.25, green: 0.85, blue: 0.85))
        case .rose:
            (Color(red: 0.88, green: 0.30, blue: 0.55),
             Color(red: 0.95, green: 0.50, blue: 0.70))
        case .gold:
            (Color(red: 0.85, green: 0.65, blue: 0.13),
             Color(red: 0.95, green: 0.80, blue: 0.30))
        }
    }

    /// The currently selected theme, read from UserDefaults.
    static var current: ThemeOption {
        guard let raw = UserDefaults.standard.string(forKey: "selectedTheme"),
              let theme = ThemeOption(rawValue: raw) else {
            return .ocean
        }
        return theme
    }
}

// MARK: - Liquid Glass Theme for iOS 26

/// Currents design system built on iOS 26 Liquid Glass.
/// Dark-mode first — anglers fish dawn/dusk.
enum CurrentsTheme {
    // MARK: Colors

    /// Dynamic accent color that follows the user's selected theme.
    static var accent: Color { ThemeOption.current.primary }
    static let danger = Color.red

    /// Score color ramp: red (0) → orange (40) → yellow (60) → green (80) → accent (100)
    static func scoreColor(_ score: Int) -> Color {
        switch score {
        case 0..<25: return .red
        case 25..<50: return .orange
        case 50..<75: return .yellow
        case 75..<90: return .green
        default: return accent
        }
    }

    // MARK: Spacing

    static let paddingS: CGFloat = 8
    static let paddingM: CGFloat = 16
    static let paddingL: CGFloat = 24
    static let cornerRadius: CGFloat = 16
}

// MARK: - Reusable Liquid Glass Modifiers

extension View {
    /// Apply a glass card background — uses iOS 26 .glassEffect when available.
    func glassCard() -> some View {
        self
            .padding(CurrentsTheme.paddingM)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: CurrentsTheme.cornerRadius))
    }

    /// Subtle glass pill for tags/badges.
    func glassPill() -> some View {
        self
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
    }
}

// MARK: - Dividers & Section Headers

/// A soft, slightly inset divider that reads more gently than the default
/// full-contrast `Divider()` inside glass cards and lists.
struct SoftDivider: View {
    var inset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(.secondary.opacity(0.15))
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

extension View {
    /// Replace a raw `Divider()` with the softer app-standard rule.
    func softDivider(inset: CGFloat = 0) -> some View {
        overlay(alignment: .bottom) { SoftDivider(inset: inset) }
    }
}

/// A consistent card/section header: title + optional trailing accessory,
/// with an optional leading SF Symbol tinted to the accent.
struct SectionHeaderView<Trailing: View>: View {
    let title: String
    var systemImage: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.subheadline)
                    .foregroundStyle(CurrentsTheme.accent)
            }
            Text(title)
                .font(.headline)
            Spacer()
            trailing()
        }
    }
}

extension SectionHeaderView where Trailing == EmptyView {
    init(title: String, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.trailing = { EmptyView() }
    }
}

// MARK: - Score Gauge View

struct ScoreGauge: View {
    let score: Int
    let label: String
    var size: CGFloat = 64

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: size > 80 ? 8 : 6)
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(
                        CurrentsTheme.scoreColor(score),
                        style: StrokeStyle(lineWidth: size > 80 ? 8 : 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text("\(score)")
                    .font(size > 80 ? .largeTitle.bold() : .title2.bold())
                    .monospacedDigit()
            }
            .frame(width: size, height: size)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    var systemImage: String? = nil
    let action: () -> Void
    // Observed so selected chips re-tint the moment the theme changes.
    // The accent is derived FROM this value (not CurrentsTheme.accent, which
    // reads UserDefaults without creating a view dependency) so the body
    // actually depends on it and re-renders automatically on a theme switch.
    @AppStorage("selectedTheme") private var selectedTheme = ThemeOption.ocean.rawValue
    private var accent: Color { (ThemeOption(rawValue: selectedTheme) ?? .ocean).primary }

    var body: some View {
        Button {
            // Every filter row in the app ticks through this one control.
            if !isSelected { Haptics.selection() }
            action()
        } label: {
            // No capsules at all any more: filter rows are plain labels with
            // an accent underline on the selection — quiet, uniform, and the
            // active choice reads instantly across every screen.
            VStack(spacing: 6) {
                HStack(spacing: 5) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    Text(title)
                        .font(.subheadline.weight(isSelected ? .bold : .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(isSelected ? accent : Color.secondary)
                Capsule()
                    .fill(isSelected ? accent : Color.clear)
                    .frame(height: 3)
                    .padding(.horizontal, 2)
            }
            .padding(.horizontal, 6)
            .padding(.top, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: isSelected)
    }
}

/// A horizontal, scrollable row of underline tabs backed by any `CaseIterable`
/// enum-like collection. Keeps the tab UI identical across every screen.
struct FilterChipRow<Item: Hashable>: View {
    let items: [Item]
    let title: (Item) -> String
    @Binding var selection: Item

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    FilterChip(title: title(item), isSelected: selection == item) {
                        withAnimation(.easeInOut(duration: 0.15)) { selection = item }
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
        // Tabs are a fixed strip — no vertical rubber-banding.
        .scrollBounceBehavior(.basedOnSize, axes: [.vertical, .horizontal])
    }
}

// MARK: - Weather Condition Icon

struct WeatherIcon: View {
    let condition: String // "clear", "cloudy", "rain", "storm", "wind"

    var systemName: String {
        switch condition.lowercased() {
        case "clear": "sun.max.fill"
        case "cloudy", "overcast": "cloud.fill"
        case "rain": "cloud.rain.fill"
        case "storm", "thunder": "cloud.bolt.rain.fill"
        case "wind": "wind"
        case "snow": "cloud.snow.fill"
        case "fog": "cloud.fog.fill"
        default: "cloud.fill"
        }
    }

    var body: some View {
        Image(systemName: systemName)
            .symbolRenderingMode(.multicolor)
    }
}
