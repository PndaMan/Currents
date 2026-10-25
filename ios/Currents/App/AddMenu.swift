import SwiftUI

/// What the centre tab's Add menu starts. Each one runs a flow that already
/// exists elsewhere in the app; ContentView routes them.
enum AddMenuAction: Hashable, CaseIterable {
    case logCatch, addSpot, startSession, planSession

    /// The tile's title, which is also its accessibility label.
    func title(sessionIsLive: Bool) -> String {
        switch self {
        case .logCatch: "Log catch"
        case .addSpot: "Add spot"
        case .startSession: sessionIsLive ? "Open live session" : "Start session"
        case .planSession: "Plan a session"
        }
    }

    func subtitle(sessionIsLive: Bool) -> String {
        switch self {
        case .logCatch: "Start with a photo"
        case .addSpot: "Pin it on the map"
        case .startSession: sessionIsLive ? "Recording now" : "Record your track"
        case .planSession: "Pick the best day"
        }
    }

    func systemImage(sessionIsLive: Bool) -> String {
        switch self {
        case .logCatch: "camera.fill"
        case .addSpot: "mappin.and.ellipse"
        case .startSession: sessionIsLive ? "figure.fishing" : "play.fill"
        case .planSession: "calendar.badge.plus"
        }
    }

    /// The raw hue; TintIcon inks the glyph and tints the tile with it.
    /// Fixed hues rather than the theme accent, so no two tiles match
    /// whichever accent the angler picks.
    var tint: Color {
        switch self {
        case .logCatch: .blue
        case .addSpot: .dsScoreGood
        case .startSession: .orange
        case .planSession: .indigo
        }
    }

    /// For UI tests, which cannot tell these tiles from Today's buttons of
    /// the same name by label alone.
    var testID: String {
        switch self {
        case .logCatch: "add-menu-log-catch"
        case .addSpot: "add-menu-add-spot"
        case .startSession: "add-menu-session"
        case .planSession: "add-menu-plan"
        }
    }
}

extension View {
    /// The centre tab's menu, over the whole screen with the tab bar: a dimmed
    /// scrim that closes it and a panel of four actions that springs up out
    /// of the centre item. `bottomInset` is the tab bar's top edge measured
    /// from the bottom of the screen (a tab's bottom safe area), so the panel
    /// sits just above the bar. Attach at the app root, under the toast and
    /// celebration hosts.
    ///
    /// It also lies over the bar's Add item and takes the tap on it, calling
    /// `onOpen`, so the bar never selects the item and the page underneath
    /// stays on screen. While the menu is open it draws the item selected in
    /// that spot, where a tap closes the menu.
    func addMenuOverlay(isPresented: Binding<Bool>, sessionIsLive: Bool, bottomInset: CGFloat,
                        onOpen: @escaping () -> Void,
                        onSelect: @escaping (AddMenuAction) -> Void) -> some View {
        modifier(AddMenuHost(isPresented: isPresented, sessionIsLive: sessionIsLive,
                             bottomInset: bottomInset, onOpen: onOpen, onSelect: onSelect))
    }
}

/// iOS 26's floating tab bar, which the overlay lines the Add item up with.
/// Its glass is 62 points tall and hangs from the tabs' bottom safe area,
/// about 21 points in from the sides of the screen, with the five items in
/// equal slots 4 points inside it. The Add item is the middle slot, so it is
/// centred on the screen, and a selected item's capsule fills its slot.
private enum AddMenuBar {
    static let height: CGFloat = 62
    static let margin: CGFloat = 21
    static let inset: CGFloat = 4

    /// One slot's width on a screen this wide.
    static func itemWidth(across width: CGFloat) -> CGFloat {
        max(0, (width - 2 * (margin + inset)) / 5)
    }
}

private enum AddMenuMotion {
    /// Opening: a quick spring with a little bounce.
    static let opening = Animation.spring(duration: 0.4, bounce: 0.22)
    /// Closing: quicker and easing in, so it gets out of the way.
    static let closing = Animation.easeIn(duration: DS.Motion.fast)
    /// Reduce Motion: a plain fade both ways.
    static let fade = Animation.easeOut(duration: DS.Motion.fast)
    /// Seconds between one tile coming in and the next.
    static let stagger = 0.05
}

private struct AddMenuHost: ViewModifier {
    @Binding var isPresented: Bool
    let sessionIsLive: Bool
    let bottomInset: CGFloat
    let onOpen: () -> Void
    let onSelect: (AddMenuAction) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The keyboard covers the bar, so the patch over its Add item stands
    /// down until it goes.
    @State private var keyboardShown = false

    private var panelTransition: AnyTransition {
        reduceMotion
            ? AnyTransition.opacity
            : AnyTransition.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity)
    }

    private var itemTransition: AnyTransition {
        reduceMotion
            ? AnyTransition.opacity
            : AnyTransition.scale(scale: 0.85).combined(with: .opacity)
    }

    private var currentAnimation: Animation {
        if reduceMotion { return AddMenuMotion.fade }
        return isPresented ? AddMenuMotion.opening : AddMenuMotion.closing
    }

    func body(content: Content) -> some View {
        content.overlay {
            ZStack(alignment: .bottom) {
                if isPresented {
                    Color.dsScrim
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { close() }
                        .accessibilityHidden(true)
                        .transition(.opacity)

                    AddMenuPanel(sessionIsLive: sessionIsLive, onSelect: select, onClose: close)
                        .padding(.horizontal, DS.gutter)
                        .padding(.top, DS.Space.s4)
                        .padding(.bottom, bottomInset + DS.Space.s3)
                        .transition(panelTransition)
                }
            }
            // Measured from the screen's bottom edge, as `bottomInset` is.
            .ignoresSafeArea(.container, edges: .bottom)
            .animation(currentAnimation, value: isPresented)
        }
        // Above the scrim, so the selected item is not dimmed with the bar.
        .overlay { barItem }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardShown = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
            keyboardShown = false
        }
    }

    /// A patch over the bar's Add item. Closed, it is clear and takes the tap
    /// before the bar can, since the bar would switch to the item's empty
    /// page. Open, it draws the item selected and a tap on it closes the
    /// menu. Hidden from VoiceOver, which reads the bar's own item; when the
    /// bar selects that item, ContentView's `tabSelection` opens the menu.
    private var barItem: some View {
        GeometryReader { proxy in
            Color.clear
                .overlay {
                    if isPresented {
                        AddMenuBarItem()
                            .transition(itemTransition)
                    }
                }
                .frame(width: AddMenuBar.itemWidth(across: proxy.size.width), height: AddMenuBar.height)
                .contentShape(Rectangle())
                .onTapGesture {
                    if isPresented { close() } else { onOpen() }
                }
                .allowsHitTesting(isPresented || !keyboardShown)
                .accessibilityHidden(true)
                // The bar's glass hangs from the tabs' bottom safe area.
                .padding(.bottom, max(0, bottomInset - AddMenuBar.height))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        // Measured from the screen's bottom edge, as `bottomInset` is, and
        // left in place by the keyboard, which covers the bar.
        .ignoresSafeArea(edges: .bottom)
        .animation(currentAnimation, value: isPresented)
    }

    private func close() {
        isPresented = false
    }

    private func select(_ action: AddMenuAction) {
        isPresented = false
        onSelect(action)
    }
}

/// The bar's Add item as the bar draws a selected tab: the logo and its
/// title in the theme colour, on a glass capsule that fills its slot. The
/// same image and title as the item in ContentView's TabView.
private struct AddMenuBarItem: View {
    var body: some View {
        VStack(spacing: 2) {
            Image("TabCreate")
            Text("Add")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(.tint)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: Capsule())
        .padding(.vertical, AddMenuBar.inset)
    }
}

/// The panel: a 2 x 2 grid of Today-style tiles on the page background, one
/// column at accessibility text sizes (scrolling when it outgrows the
/// screen). Modal for VoiceOver, which starts on the first tile; the escape
/// gesture closes it.
private struct AddMenuPanel: View {
    let sessionIsLive: Bool
    let onSelect: (AddMenuAction) -> Void
    let onClose: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var focus: AddMenuAction?
    /// Flips on appear, so the tiles come in one after another.
    @State private var revealed = false

    private let rows: [[AddMenuAction]] = [[.logCatch, .addSpot], [.startSession, .planSession]]

    var body: some View {
        ViewThatFits(in: .vertical) {
            grid
            ScrollView { grid }
                .scrollBounceBehavior(.basedOnSize)
        }
        .padding(DS.Space.s3)
        // Concentric with the tiles: their card radius plus this padding.
        .background(Color.dsBackground, in: RoundedRectangle(cornerRadius: DS.Radius.sheet, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Add")
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { onClose() }
        .onAppear { revealed = true }
        .task {
            // Wait for the panel to land, then move VoiceOver to the first tile.
            try? await Task.sleep(for: .milliseconds(150))
            focus = .logCatch
        }
    }

    private var grid: some View {
        // Two to a row, one to a row at accessibility sizes, as on Today.
        let pair = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
        return VStack(spacing: 10) {
            ForEach(rows, id: \.self) { row in
                pair {
                    ForEach(row, id: \.self) { action in
                        tile(action)
                    }
                }
                // Tiles in a row share the taller one's height.
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func tile(_ action: AddMenuAction) -> some View {
        let order = Double(AddMenuAction.allCases.firstIndex(of: action) ?? 0)
        let shown = revealed || reduceMotion
        return Button { onSelect(action) } label: {
            AddMenuTile(title: action.title(sessionIsLive: sessionIsLive),
                        subtitle: action.subtitle(sessionIsLive: sessionIsLive),
                        systemImage: action.systemImage(sessionIsLive: sessionIsLive),
                        tint: action.tint)
        }
        .buttonStyle(.dim)
        .accessibilityLabel(action.title(sessionIsLive: sessionIsLive))
        .accessibilityHint(action.subtitle(sessionIsLive: sessionIsLive))
        .accessibilityIdentifier(action.testID)
        .accessibilityFocused($focus, equals: action)
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : DS.Space.s3)
        .animation(reduceMotion ? nil : AddMenuMotion.opening.delay(order * AddMenuMotion.stagger), value: revealed)
    }
}

/// One tile, in Today's card style: a coloured symbol tile, a short title and
/// one subtitle line on a `dsFill` card. At accessibility sizes the symbol
/// sits by the title and the text wraps.
private struct AddMenuTile: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(HStackLayout(alignment: .top, spacing: DS.Space.s3))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Space.s3))
        layout {
            TintIcon(systemImage: systemImage, tint: tint, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.dsText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.dsText2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }
}
