import Foundation

extension BurnSnapshot {
    /// The refresh clock alone does not change anything a burn surface renders.
    func hasSameContent(as other: BurnSnapshot) -> Bool {
        today == other.today && streak == other.streak && expiring == other.expiring &&
            records == other.records && leaderboard == other.leaderboard && badges == other.badges &&
            recentWindows == other.recentWindows && tier == other.tier &&
            monthValueMultiple == other.monthValueMultiple && moments == other.moments
    }
}
