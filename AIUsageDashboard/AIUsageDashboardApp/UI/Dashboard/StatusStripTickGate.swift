import Foundation

/// F6: a status-strip tick records a date only while the dashboard window is visible.
enum StatusStripTickGate {
    static func appliedDate(_ date: Date, dashboardVisible: Bool) -> Date? {
        dashboardVisible ? date : nil
    }
}
