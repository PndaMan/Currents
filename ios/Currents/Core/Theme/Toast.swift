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

    enum Style {
        case success, error, info

        var icon: String {
            switch self {
            case .success: "checkmark.circle.fill"
            case .error:   "exclamationmark.triangle.fill"
            case .info:    "info.circle.fill"
            }
        }
        var tint: Color {
            switch self {
            case .success: .green
            case .error:   .red
            case .info:    CurrentsTheme.accent
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

    func show(_ message: String, style: Toast.Style = .success, haptic: Bool = true) {
        withAnimation(.spring(duration: 0.35)) { current = Toast(message: message, style: style) }
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
            withAnimation(.spring(duration: 0.35)) { self?.current = nil }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        withAnimation(.spring(duration: 0.35)) { current = nil }
    }
}

private struct ToastView: View {
    let toast: Toast
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.style.icon)
                .font(.headline)
                .foregroundStyle(toast.style.tint)
            Text(toast.message)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(toast.style.tint.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .padding(.horizontal, 24)
    }
}

private struct ToastHost: ViewModifier {
    @ObservedObject private var center = ToastCenter.shared
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let toast = center.current {
                ToastView(toast: toast)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { center.dismiss() }
                    .allowsHitTesting(true)
            }
        }
    }
}

extension View {
    /// Attach once near the app root so `ToastCenter.shared.show(...)` surfaces.
    func toastHost() -> some View { modifier(ToastHost()) }
}
