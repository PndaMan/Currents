import SwiftUI
import UIKit

/// Lightweight haptic helpers so success/error/selection feedback is consistent
/// everywhere instead of ad-hoc generators.
enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func error()   { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func tap()     { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
}

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
        if haptic {
            switch style {
            case .success: Haptics.success()
            case .error:   Haptics.error()
            case .info:    Haptics.tap()
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

/// A glass capsule that drops in from the top: tinted symbol, then the message.
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
        .shadow(color: .black.opacity(0.12), radius: 15, y: 8)
        .padding(.horizontal, DS.gutter)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

private struct ToastHost: ViewModifier {
    @ObservedObject private var center = ToastCenter.shared
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let toast = center.current {
                ToastView(toast: toast)
                    .id(toast.id)
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { center.dismiss() }
                    .onAppear {
                        AccessibilityNotification.Announcement(toast.message).post()
                    }
            }
        }
    }
}

extension View {
    /// Attach once near the app root so `ToastCenter.shared.show(...)` surfaces.
    func toastHost() -> some View { modifier(ToastHost()) }
}
