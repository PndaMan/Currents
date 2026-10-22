import SwiftUI

/// The main action: filled with the text colour (white in dark, near black in
/// light), label in the background colour. Full width and 52 pt tall by
/// default; `fullWidth: false` hugs the label.
struct PrimaryButtonStyle: ButtonStyle {
    var fullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        DSFilledButton(configuration: configuration, fullWidth: fullWidth,
                       fill: .dsPrimaryButton, foreground: .dsOnPrimary)
    }
}

/// Shared body for the primary and tonal styles. A view (not inline in the
/// style) so it can read `isEnabled`.
struct DSFilledButton: View {
    let configuration: ButtonStyleConfiguration
    let fullWidth: Bool
    let fill: Color
    let foreground: Color
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        configuration.label
            .font(.headline)
            .labelStyle(.titleAndIcon)
            .foregroundStyle(foreground)
            // Wrap rather than truncate at accessibility sizes.
            .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            .multilineTextAlignment(.center)
            .padding(.horizontal, fullWidth ? DS.Space.s4 : 18)
            .padding(.vertical, DS.Space.s2)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(minHeight: fullWidth ? 52 : 40)
            .background(fill, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
            .animation(DS.Motion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    /// `.buttonStyle(.dsPrimary)`
    static var dsPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}
