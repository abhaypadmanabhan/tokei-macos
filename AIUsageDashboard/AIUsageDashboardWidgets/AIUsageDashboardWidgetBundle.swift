import WidgetKit
import SwiftUI
import AIUsageDashboardCore

@main
struct AIUsageDashboardWidgetBundle: WidgetBundle {
    var body: some Widget {
        ProviderStatsWidget()
    }
}
