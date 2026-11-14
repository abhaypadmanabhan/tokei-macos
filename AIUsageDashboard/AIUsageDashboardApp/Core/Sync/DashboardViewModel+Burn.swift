import Foundation
import os

extension DashboardViewModel {
    /// Serializes evaluations with their state writes. The generation check prevents an
    /// older saved/live refresh from publishing after a newer one. Heavy work always runs
    /// off the main actor (92-day fixtures exceed the 5 ms budget).
    func recomputeBurn(saved: Bool) async {
        burnGeneration += 1
        let generation = burnGeneration
        let previous = burnTask
        let snapshots = visibleSnapshots
        let hiddenProviders = hiddenProviders
        let calendar = analyticsCalendar
        let now = now()
        let costs = MaxxerPlanCostStore(defaults: burnDefaults)
        let plans = Dictionary(uniqueKeysWithValues: ProviderID.allCases.compactMap { id in
            costs.monthlyUSD(for: id.rawValue).map { (id, $0) }
        })
        let task = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled, self.burnGeneration == generation else { return }
            let state = await self.burnStateStore.load()
            let samples = await self.burnQuotaSeriesStore.allSamples()
            let pricingSource = self.burnPricing
            let evaluation = await Task.detached(priority: .utility) {
                BurnEngine.evaluate(snapshots: snapshots, monthlyPlanUSD: plans, quotaSamples: samples,
                                    state: state, now: now, calendar: calendar, pricing: pricingSource(),
                                    hiddenProviders: hiddenProviders, emitMoments: !saved)
            }.value
            guard !Task.isCancelled, self.burnGeneration == generation else { return }
            if !self.burn.hasSameContent(as: evaluation.snapshot) {
                self.burn = evaluation.snapshot
            }
            // A saved snapshot is a preview, not new evidence. In particular it must not
            // lower the stored tier and then celebrate the same tier on the live refresh.
            guard !saved else { return }
            do { try await self.burnStateStore.save(evaluation.state) } catch {
                Logger(subsystem: "ai.padzy.tokei", category: "Burn")
                    .error("Could not save burn achievements; will retry on the next refresh.")
            }
            guard !Task.isCancelled, self.burnGeneration == generation else { return }
            let notifyBurn = self.notifyBurn
            Task { await notifyBurn(evaluation.snapshot, calendar) }
        }
        burnTask = task
        await task.value
    }
}
