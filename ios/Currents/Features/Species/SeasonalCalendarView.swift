import SwiftUI

/// The old Seasons segment. Seasons now live in the species guide (month
/// chips, in season and out of season groups), so this shows that guide.
/// Kept so existing call sites still compile.
struct SeasonalCalendarView: View {
    /// No longer used; the guide has its own header.
    var header: AnyView? = nil

    var body: some View {
        SpeciesBrowserView()
    }
}
