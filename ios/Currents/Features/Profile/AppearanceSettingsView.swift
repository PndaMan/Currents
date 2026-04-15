import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage("selectedTheme") private var selectedTheme = ThemeOption.ocean.rawValue

    private let columns = [
        GridItem(.adaptive(minimum: 80), spacing: 16)
    ]

    var body: some View {
        Form {
            Section {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(ThemeOption.allCases) { theme in
                        themeCircle(theme)
                    }
                }
                .padding(.vertical, 12)
            } header: {
                Text("Color Theme")
            } footer: {
                Text("Choose an accent color for the app. This changes buttons, highlights, and the wordmark gradient.")
            }
        }
        .navigationTitle("Appearance")
    }

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
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTheme = theme.rawValue
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
