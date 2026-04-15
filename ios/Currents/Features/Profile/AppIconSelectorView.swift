import SwiftUI

// MARK: - Theme Icon Definition

struct ThemeIconOption: Identifiable {
    let id: String          // matches ThemeOption raw value
    let name: String
    let sfSymbol: String
    let gradient: [Color]

    static let all: [ThemeIconOption] = [
        ThemeIconOption(id: "ocean", name: "Ocean",
                        sfSymbol: "water.waves",
                        gradient: [Color(red: 0.10, green: 0.55, blue: 0.95),
                                   Color(red: 0.15, green: 0.82, blue: 0.98)]),
        ThemeIconOption(id: "forest", name: "Forest",
                        sfSymbol: "leaf.fill",
                        gradient: [Color(red: 0.13, green: 0.55, blue: 0.33),
                                   Color(red: 0.30, green: 0.78, blue: 0.47)]),
        ThemeIconOption(id: "ember", name: "Ember",
                        sfSymbol: "flame.fill",
                        gradient: [Color(red: 0.85, green: 0.20, blue: 0.15),
                                   Color(red: 0.95, green: 0.45, blue: 0.20)]),
        ThemeIconOption(id: "sunset", name: "Sunset",
                        sfSymbol: "sun.horizon.fill",
                        gradient: [Color(red: 0.95, green: 0.55, blue: 0.15),
                                   Color(red: 0.98, green: 0.75, blue: 0.25)]),
        ThemeIconOption(id: "amethyst", name: "Amethyst",
                        sfSymbol: "sparkles",
                        gradient: [Color(red: 0.55, green: 0.25, blue: 0.85),
                                   Color(red: 0.75, green: 0.45, blue: 0.95)]),
        ThemeIconOption(id: "teal", name: "Teal",
                        sfSymbol: "drop.fill",
                        gradient: [Color(red: 0.10, green: 0.60, blue: 0.65),
                                   Color(red: 0.20, green: 0.80, blue: 0.78)]),
        ThemeIconOption(id: "rose", name: "Rose",
                        sfSymbol: "heart.fill",
                        gradient: [Color(red: 0.85, green: 0.25, blue: 0.45),
                                   Color(red: 0.95, green: 0.50, blue: 0.60)]),
        ThemeIconOption(id: "gold", name: "Gold",
                        sfSymbol: "star.fill",
                        gradient: [Color(red: 0.80, green: 0.65, blue: 0.15),
                                   Color(red: 0.95, green: 0.82, blue: 0.30)]),
    ]

    static func option(for id: String) -> ThemeIconOption {
        all.first { $0.id == id } ?? all[0]
    }
}

// MARK: - App Icon Selector View

struct AppIconSelectorView: View {
    @AppStorage("selectedAppIcon") private var selectedAppIcon = "ocean"

    private let columns = [
        GridItem(.adaptive(minimum: 90, maximum: 120), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(ThemeIconOption.all) { option in
                    iconCell(for: option)
                }
            }
            .padding()

            Text("Custom logos coming soon!")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom, 24)
        }
        .navigationTitle("App Icon")
    }

    @ViewBuilder
    private func iconCell(for option: ThemeIconOption) -> some View {
        let isSelected = selectedAppIcon == option.id
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: option.gradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)

                Image(systemName: option.sfSymbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)

                if isSelected {
                    Circle()
                        .strokeBorder(.white, lineWidth: 3)
                        .frame(width: 64, height: 64)

                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.white, .green)
                                .background(Circle().fill(.green).frame(width: 16, height: 16))
                        }
                        Spacer()
                    }
                    .frame(width: 64, height: 64)
                }
            }

            Text(option.name)
                .font(.caption)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .fontWeight(isSelected ? .semibold : .regular)
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedAppIcon = option.id
            }
        }
    }
}

#Preview {
    NavigationStack {
        AppIconSelectorView()
    }
}
