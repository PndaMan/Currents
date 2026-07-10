import WidgetKit
import SwiftUI

@main
struct CurrentsWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BiteScoreWidget()
        NextSessionWidget()
        SessionLiveActivity()
    }
}
