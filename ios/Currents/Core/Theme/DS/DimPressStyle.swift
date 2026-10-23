import SwiftUI

/// Luma's press feedback: the label dims to 60 percent while held, no scaling.
/// Use on rows, tiles, thumbnails and any custom tappable content.
struct DimPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(DS.Motion.press, value: configuration.isPressed)
            .pressHaptic(configuration.isPressed, .softPress)
    }
}

/// A list row press: the row's background fills with `dsFill` while held,
/// like a native cell highlight. Use for full-width rows in a ScrollView.
struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .background(configuration.isPressed ? Color.dsFill : Color.clear)
            .animation(DS.Motion.press, value: configuration.isPressed)
            .pressHaptic(configuration.isPressed, .softPress)
    }
}

extension ButtonStyle where Self == DimPressStyle {
    /// `.buttonStyle(.dim)`
    static var dim: DimPressStyle { DimPressStyle() }
}

extension ButtonStyle where Self == RowPressStyle {
    /// `.buttonStyle(.dsRow)`
    static var dsRow: RowPressStyle { RowPressStyle() }
}
