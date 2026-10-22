import SwiftUI

/// Luma's row of three equal action buttons under a detail header, icon over
/// label. Pass `ActionItem`s for plain buttons, or build the row yourself with
/// `ActionTileStyle` buttons and `ActionTileLabel` (for Menu or ShareLink).
struct ActionTriple<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: DS.Space.s2) { content }
            .padding(.horizontal, DS.gutter)
    }
}

extension ActionTriple where Content == ActionTripleItems {
    /// Up to three buttons; the first is filled when `firstIsPrimary`.
    init(_ items: [ActionItem], firstIsPrimary: Bool = false) {
        self.content = ActionTripleItems(items: items, firstIsPrimary: firstIsPrimary)
    }
}

/// One button in an `ActionTriple`.
struct ActionItem: Identifiable {
    let id = UUID()
    var title: String
    var systemImage: String
    /// Red tinted, for stop or end actions (End session).
    var isDestructive: Bool = false
    var action: () -> Void

    init(_ title: String, systemImage: String, isDestructive: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isDestructive = isDestructive
        self.action = action
    }
}

struct ActionTripleItems: View {
    let items: [ActionItem]
    let firstIsPrimary: Bool

    var body: some View {
        ForEach(Array(items.prefix(3).enumerated()), id: \.element.id) { index, item in
            let kind: ActionTileKind = item.isDestructive ? .destructive
                : (index == 0 && firstIsPrimary ? .primary : .tonal)
            Button(action: item.action) {
                Label(item.title, systemImage: item.systemImage)
            }
            .buttonStyle(ActionTileStyle(kind))
        }
    }
}

enum ActionTileKind {
    case primary, tonal, destructive
}

/// A 62 pt action tile: icon over a footnote label, filled per `kind`,
/// stretched to share its row equally. Dims on press.
struct ActionTileStyle: ButtonStyle {
    var kind: ActionTileKind

    init(_ kind: ActionTileKind = .tonal) { self.kind = kind }

    func makeBody(configuration: Configuration) -> some View {
        ActionTileBody(kind: kind) { configuration.label }
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(DS.Motion.press, value: configuration.isPressed)
    }
}

/// The tile itself, for labels of controls that ignore button styles
/// (`Menu { … } label: { ActionTileLabel("More", systemImage: "ellipsis") }`).
struct ActionTileLabel: View {
    let title: String
    let systemImage: String
    var kind: ActionTileKind = .tonal

    init(_ title: String, systemImage: String, kind: ActionTileKind = .tonal) {
        self.title = title
        self.systemImage = systemImage
        self.kind = kind
    }

    var body: some View {
        ActionTileBody(kind: kind) { Label(title, systemImage: systemImage) }
    }
}

private struct ActionTileBody<L: View>: View {
    let kind: ActionTileKind
    @ViewBuilder var label: () -> L
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        label()
            .labelStyle(ActionTileLabelStyle())
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(fill, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
            .opacity(isEnabled ? 1 : 0.4)
    }

    private var foreground: Color {
        switch kind {
        case .primary: .dsOnPrimary
        case .tonal: .dsText
        case .destructive: .dsScoreSlow
        }
    }

    private var fill: Color {
        switch kind {
        case .primary: .dsPrimaryButton
        case .tonal: .dsTonal
        case .destructive: Color.dsScoreSlow.opacity(scheme == .dark ? 0.18 : 0.12)
        }
    }
}

private struct ActionTileLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 4) {
            configuration.icon
                .font(.system(size: 19, weight: .medium))
                .imageScale(.medium)
            configuration.title
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 4)
    }
}
