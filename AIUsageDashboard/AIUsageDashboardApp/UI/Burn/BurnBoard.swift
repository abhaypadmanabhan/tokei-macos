import Combine
import Foundation
import Observation
import AIUsageDashboardCore

/// The burn surfaces' own model: the latest `BurnSnapshot` and the celebration waiting to play.
///
/// Why a separate model instead of reading `DashboardViewModel` directly: the view model is one
/// `ObservableObject`, so every `@Published` change (loading flags, range, settings, snapshots)
/// re-renders every view that holds it. The burn strip and the Burn tab only care about `burn`,
/// so they observe this `@Observable` board, which changes only when the snapshot does.
@MainActor
@Observable
final class BurnBoard {
    /// What the burn surfaces render.
    private(set) var snapshot: BurnSnapshot
    /// The one celebration waiting for a burn surface to play it; `nil` when there is none.
    private(set) var celebration: BurnCelebration?

    @ObservationIgnored private var subscription: AnyCancellable?
    @ObservationIgnored private let now: () -> Date

    init(snapshot: BurnSnapshot, now: @escaping () -> Date = Date.init) {
        self.snapshot = snapshot
        self.now = now
    }

    /// Follows the view model's `burn`. `$burn` publishes on `willSet`, so the sink receives the
    /// new value; `removeDuplicates` drops re-publishes of an unchanged snapshot.
    convenience init(viewModel: DashboardViewModel) {
        self.init(snapshot: viewModel.burn)
        #if DEBUG
        if let fixed = BurnDebug.fixedSnapshot(now: Date()) {
            snapshot = fixed
            BurnDebug.scheduleMoment(on: self)
            return
        }
        #endif
        subscription = viewModel.$burn
            .removeDuplicates()
            .sink { [weak self] next in
                MainActor.assumeIsolated { self?.apply(next) }
            }
    }

    func apply(_ next: BurnSnapshot) {
        guard next != snapshot else { return }
        snapshot = next
        if let moment = BurnCopy.headlineMoment(next.moments) {
            celebration = BurnCelebration(moment: moment, createdAt: now())
        }
    }

    /// The celebration a surface may play: the pending one while that surface is exposed, `nil`
    /// while it is covered or closed, which leaves it pending for the next exposed surface.
    /// Playing ends in `finish`, so handing it to a hidden surface would use it up unseen
    /// (review r1 S1: Burn stays mounted under an opaque agent drill-in).
    func celebration(forSurfaceExposed exposed: Bool) -> BurnCelebration? {
        exposed ? celebration : nil
    }

    /// Queues a celebration directly (debug trigger and previews).
    func celebrate(_ moment: BurnMoment) {
        celebration = BurnCelebration(moment: moment, createdAt: now())
    }

    /// The surface that played `id` is done with it. A later celebration is left alone.
    func finish(_ id: UUID) {
        if celebration?.id == id { celebration = nil }
    }

}

/// One moment to celebrate, once.
struct BurnCelebration: Equatable, Identifiable {
    let id = UUID()
    let moment: BurnMoment
    let createdAt: Date

    /// A moment nobody saw within this long is not celebrated any more.
    static let maxWait: TimeInterval = 12 * 3_600

    /// Goblin mode is the biggest moment the game has; it gets the biggest celebration.
    var isGoblinMode: Bool { moment == .tierUp(.goblinMode) }

    /// A moment nobody saw for `maxWait` (Tokei sat closed) is dropped, not played hours late.
    func isStale(at date: Date) -> Bool { date.timeIntervalSince(createdAt) > Self.maxWait }

    /// Which part of the surface celebrates: the badge's own cell, or the ring.
    var badge: BurnBadge? {
        if case .badge(let badge) = moment { return badge }
        return nil
    }

    var title: String { BurnCopy.momentTitle(moment) }
}

#if DEBUG
/// Debug builds only: launch arguments that fix the burn state for previews and captures,
/// until the burn engine (WP-A) fills `DashboardViewModel.burn`.
///
///     Tokei -TokeiBurnSample YES                      # BurnSnapshot.sample(now:)
///     Tokei -TokeiBurnEmpty YES                       # BurnSnapshot.empty(now:), a fresh install
///     Tokei -TokeiBurnSample YES -TokeiBurnMoment tier.goblinMode   # celebrate 2 s after launch
///     Tokei … -TokeiBurnMomentDelay 5 -TokeiReduceMotion YES        # later; the static variant
///
/// Moments: `badge.<BurnBadge raw value>`, `record.<BurnRecordKind raw value>`,
/// `tier.<MaxxerTier raw value>`.
enum BurnDebug {
    static func fixedSnapshot(now: Date) -> BurnSnapshot? {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "TokeiBurnEmpty") { return .empty(now: now) }
        if defaults.bool(forKey: "TokeiBurnSample") { return .sample(now: now) }
        return nil
    }

    /// Captures the Reduce Motion celebration without changing the system setting.
    static var forceReduceMotion: Bool { UserDefaults.standard.bool(forKey: "TokeiReduceMotion") }

    static var requestedMoment: BurnMoment? {
        guard let raw = UserDefaults.standard.string(forKey: "TokeiBurnMoment") else { return nil }
        return moment(from: raw)
    }

    static func moment(from raw: String) -> BurnMoment? {
        let parts = raw.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "badge": return BurnBadge(rawValue: parts[1]).map(BurnMoment.badge)
        case "record": return BurnRecordKind(rawValue: parts[1]).map(BurnMoment.record)
        case "tier": return MaxxerTier(rawValue: parts[1]).map(BurnMoment.tierUp)
        default: return nil
        }
    }

    @MainActor
    static func scheduleMoment(on board: BurnBoard) {
        guard let moment = requestedMoment else { return }
        // `-TokeiBurnMomentDelay <seconds>` (default 2) leaves time to start a recording.
        let delay = UserDefaults.standard.object(forKey: "TokeiBurnMomentDelay") == nil
            ? 2 : UserDefaults.standard.double(forKey: "TokeiBurnMomentDelay")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
            board.celebrate(moment)
        }
    }
}
#endif
