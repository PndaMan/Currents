import SwiftUI

/// The secondary action: text colour at 8 percent behind a text-coloured
/// label. Same metrics as `PrimaryButtonStyle`.
struct TonalButtonStyle: ButtonStyle {
    var fullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        DSFilledButton(configuration: configuration, fullWidth: fullWidth,
                       fill: .dsTonal, foreground: .dsText)
    }
}

extension ButtonStyle where Self == TonalButtonStyle {
    /// `.buttonStyle(.dsTonal)`
    static var dsTonal: TonalButtonStyle { TonalButtonStyle() }
}
