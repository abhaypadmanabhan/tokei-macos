import Foundation
import AIUsageDashboardCore

/// UI-side, disk-only agent detection + the "is this agent on my canvas" model.
///
/// "Added" a provider == it is **visible** (`!ProviderVisibility.isHidden`). Adding
/// un-hides it; removing hides it. Detection is a cheap `FileManager` existence check
/// over the exact read paths already centralised in `ProviderMetadata.localPaths`
/// — never a provider call, never a secret read (frozen contract §4).
enum AgentDetection {
    /// True iff any of this provider's declared local read-paths exists on disk.
    /// Tilde is expanded; a bare marker file or directory both count.
    static func isInstalled(_ providerID: ProviderID, fileManager: FileManager = .default) -> Bool {
        for raw in ProviderMetadata.localPaths(for: providerID) {
            let expanded = (raw as NSString).expandingTildeInPath
            if fileManager.fileExists(atPath: expanded) { return true }
        }
        return false
    }

    /// Every provider currently detected on this machine.
    static func installedProviders(fileManager: FileManager = .default) -> [ProviderID] {
        ProviderID.allCases.filter { isInstalled($0, fileManager: fileManager) }
    }
}

/// The set of providers on the user's canvas, expressed through the existing
/// per-provider visibility flag. One source of truth: a provider is "added" when
/// it is not hidden.
enum AddAgentModel {
    /// Run-once flag: seeds the very first launch so a brand-new user (no agents on
    /// disk) starts on a genuine blank canvas instead of a wall of empty rows.
    private static let seededKey = "tokei.onboarding.seeded.v1"

    static func isAdded(_ providerID: ProviderID, defaults: UserDefaults = .standard) -> Bool {
        !ProviderVisibility.isHidden(providerID, defaults: defaults)
    }

    static func add(_ providerID: ProviderID, defaults: UserDefaults = .standard) {
        ProviderVisibility.setHidden(false, for: providerID, defaults: defaults)
    }

    static func remove(_ providerID: ProviderID, defaults: UserDefaults = .standard) {
        ProviderVisibility.setHidden(true, for: providerID, defaults: defaults)
    }

    /// Providers detected on disk that the user has not added yet — the "we found
    /// these, add them?" candidates for the detected flow.
    static func detectedNotAdded(defaults: UserDefaults = .standard,
                                 fileManager: FileManager = .default) -> [ProviderID] {
        AgentDetection.installedProviders(fileManager: fileManager)
            .filter { !isAdded($0, defaults: defaults) }
    }

    /// Idempotent first-run seed. On a genuine **fresh install only**, hides every
    /// provider whose install marker is absent so the user leads with `+` instead of
    /// a wall of empty rows; detected providers stay visible. An **existing user**
    /// (the app has persisted data before, or they already set any provider's
    /// visibility) is left untouched — seeding would silently clobber their
    /// deliberate show/hide choices on upgrade. Runs at most once, gated by `seededKey`.
    static func seedOnFirstLaunchIfNeeded(defaults: UserDefaults = .standard,
                                          fileManager: FileManager = .default) {
        guard !defaults.bool(forKey: seededKey) else { return }
        // Run-once regardless of whether we actually seed below.
        defaults.set(true, forKey: seededKey)

        // Only a brand-new install gets seeded. If the app has run before — a
        // persisted usage store exists, or the user already chose any provider's
        // visibility — this is an upgrade; preserve their existing setup verbatim.
        guard !hasExistingInstall(fileManager: fileManager),
              !hasStoredVisibilityPreference(defaults: defaults) else { return }

        for providerID in ProviderID.allCases {
            let installed = AgentDetection.isInstalled(providerID, fileManager: fileManager)
            ProviderVisibility.setHidden(!installed, for: providerID, defaults: defaults)
        }
    }

    /// True once the app has persisted its usage store — i.e. it has run before.
    /// The blank-canvas seed must not fire for such an (upgrading) user. Mirrors
    /// `UsageStore`'s default path (`Application Support/AIUsageDashboard/usage-store.json`).
    private static func hasExistingInstall(fileManager: FileManager) -> Bool {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory,
                                                in: .userDomainMask).first else { return false }
        let store = appSupport
            .appendingPathComponent("AIUsageDashboard", isDirectory: true)
            .appendingPathComponent("usage-store.json")
        return fileManager.fileExists(atPath: store.path)
    }

    /// True if the user has ever explicitly stored any provider's visibility — a
    /// second "has configured before" signal so an upgrader is never re-seeded.
    private static func hasStoredVisibilityPreference(defaults: UserDefaults) -> Bool {
        ProviderID.allCases.contains { defaults.object(forKey: ProviderVisibility.key(for: $0)) != nil }
    }
}
