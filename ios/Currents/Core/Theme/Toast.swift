import Combine
import SwiftUI
import UIKit

/// A transient status message shown at the top of the screen.
struct Toast: Equatable, Identifiable {
    let id = UUID()
    var message: String
    var style: Style = .success
    /// Overrides the style's symbol (for example "play.fill" for a started session).
    var icon: String? = nil

    enum Style {
        case success, error, info

        var icon: String {
            switch self {
            case .success: "checkmark"
            case .error:   "exclamationmark.triangle.fill"
            case .info:    "info.circle.fill"
            }
        }
        var tint: Color {
            switch self {
            case .success: .dsScoreGood
            case .error:   .dsScoreSlow
            case .info:    DS.accent
            }
        }
    }

    static func == (lhs: Toast, rhs: Toast) -> Bool { lhs.id == rhs.id }
}

/// App-wide toast queue. Call `ToastCenter.shared.show(...)` from anywhere on the
/// main actor to confirm a success or surface a failure.
@MainActor
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()
    @Published var current: Toast?
    private var dismissTask: Task<Void, Never>?

    func show(_ message: String, style: Toast.Style = .success, haptic: Bool = true, icon: String? = nil) {
        withAnimation(DS.Motion.spring) {
            current = Toast(message: Self.strippingEmoji(message), style: style, icon: icon)
        }
        // A success haptic the caller already played is not repeated (Haptics
        // drops the same feedback asked for twice in a moment).
        if haptic {
            switch style {
            case .success: Haptics.success()
            case .error:   Haptics.error()
            case .info:    Haptics.softPress()
            }
        }
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            withAnimation(DS.Motion.softSpring) { self?.current = nil }
        }
    }

    /// The redesign has no emoji in UI copy; older call sites still append
    /// them ("Catch logged 🎣"), so they are dropped here as a safety net.
    static func strippingEmoji(_ text: String) -> String {
        let kept = text.unicodeScalars.filter { scalar in
            if scalar.properties.isEmojiPresentation { return false }
            // Variation selector 16 and zero-width joiner glue emoji sequences.
            if scalar.value == 0xFE0F || scalar.value == 0x200D { return false }
            // Text-default pictographs (☀ ⚓ ✓) that render as emoji with FE0F.
            if scalar.properties.isEmoji && scalar.value > 0x2100 { return false }
            return true
        }
        return String(String.UnicodeScalarView(kept))
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func dismiss() {
        dismissTask?.cancel()
        withAnimation(DS.Motion.softSpring) { current = nil }
    }
}

/// A glass capsule that floats in from the top over the content, like the
/// other floating controls: tinted symbol, then the message.
private struct ToastView: View {
    let toast: Toast
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.icon ?? toast.style.icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(toast.style.tint)
            Text(toast.message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.dsText)
                .lineLimit(2)
        }
        .padding(.leading, 14)
        .padding(.trailing, 18)
        .padding(.vertical, 11)
        .glassEffect(.regular, in: Capsule())
        .padding(.horizontal, DS.gutter)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

/// The toast layer: the current toast at the top of an otherwise clear,
/// full-screen view. It lives in `ToastWindow`, above every sheet and cover.
private struct ToastOverlay: View {
    @ObservedObject private var center = ToastCenter.shared
    // The same keys and defaults as CurrentsApp, so the toast window follows
    // the app's appearance and theme colour.
    @AppStorage("selectedTheme") private var selectedTheme = ThemeOption.ocean.rawValue
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.dark.rawValue

    var body: some View {
        Color.clear
            .overlay(alignment: .top) {
                if let toast = center.current {
                    ToastView(toast: toast)
                        .id(toast.id)
                        .padding(.top, 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onAppear {
                            AccessibilityNotification.Announcement(toast.message).post()
                        }
                }
            }
            .preferredColorScheme((AppearanceMode(rawValue: appearanceMode) ?? .dark).colorScheme)
            .tint(ThemeOption(rawValue: selectedTheme)?.primary ?? .blue)
    }
}

/// Hosts the toast layer. While its window is visible it is the one the
/// system asks about the status bar, so it passes the question on to what the
/// app's own window is showing (a camera that hides the status bar keeps it
/// hidden).
private final class ToastHostingController: UIHostingController<ToastOverlay> {
    override var prefersStatusBarHidden: Bool {
        var top = appTopController
        while let child = top?.childForStatusBarHidden { top = child }
        return top?.prefersStatusBarHidden ?? false
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        var top = appTopController
        while let child = top?.childForStatusBarStyle { top = child }
        return top?.preferredStatusBarStyle ?? .default
    }

    /// The top-most controller presented in the app's main window: the
    /// scene's first window that is not this one.
    private var appTopController: UIViewController? {
        guard let toastWindow = view.window, let scene = toastWindow.windowScene,
              let main = scene.windows.first(where: { $0 !== toastWindow }) else { return nil }
        var top = main.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

/// A second window on the app's scene, one level above the app window, that
/// draws toasts over every presentation. It never takes touches (they fall
/// through to the app), never becomes the key window, and is hidden between
/// toasts so the app keeps control of the status bar.
@MainActor
final class ToastWindow {
    static let shared = ToastWindow()
    private var window: UIWindow?
    private var subscription: AnyCancellable?
    private var hideTask: Task<Void, Never>?

    func install() {
        guard window == nil else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else {
            return
        }
        let host = ToastHostingController(rootView: ToastOverlay())
        host.view.backgroundColor = .clear
        let window = UIWindow(windowScene: scene)
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 1)
        window.rootViewController = host
        window.isUserInteractionEnabled = false
        window.isHidden = true
        self.window = window
        subscription = ToastCenter.shared.$current.sink { [weak self] toast in
            self?.update(showing: toast != nil)
        }
    }

    /// Shows the window as a toast arrives. After the last one leaves, hides
    /// it once the exit animation (DS.Motion.softSpring, 0.56 s) has run, if
    /// no new toast came in meanwhile.
    private func update(showing: Bool) {
        hideTask?.cancel()
        hideTask = nil
        guard let window else { return }
        if showing {
            if window.isHidden {
                window.isHidden = false
                window.rootViewController?.setNeedsStatusBarAppearanceUpdate()
            }
            return
        }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(DS.Motion.slow + 0.1))
            guard !Task.isCancelled, ToastCenter.shared.current == nil else { return }
            self?.window?.isHidden = true
        }
    }
}

private struct ToastHost: ViewModifier {
    func body(content: Content) -> some View {
        content.onAppear { ToastWindow.shared.install() }
    }
}

extension View {
    /// Attach once near the app root so `ToastCenter.shared.show(...)` surfaces.
    func toastHost() -> some View { modifier(ToastHost()) }
}
