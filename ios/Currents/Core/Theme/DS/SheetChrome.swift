import SwiftUI

extension View {
    /// Standard sheet chrome: the app background behind the sheet, a visible
    /// grabber and the detents. Every sheet's root view ends with this.
    func dsSheet(_ detents: Set<PresentationDetent> = [.large]) -> some View {
        presentationDetents(detents)
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.dsBackground)
    }
}

/// "Done" for a sheet that has nothing to save. Put it in
/// `ToolbarItem(placement: .confirmationAction)`.
struct SheetDoneButton: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Button("Done") { dismiss() }
    }
}
