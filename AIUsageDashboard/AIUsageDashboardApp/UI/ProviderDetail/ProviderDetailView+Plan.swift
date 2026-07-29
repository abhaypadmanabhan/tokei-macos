import SwiftUI
import AIUsageDashboardCore

// The plan-only half of the drill-in: plan cost, credits, and the value comparison a
// metered provider shows in place of quota windows. Its own file for the same reason the
// Accounts and Metrics sections have theirs — `ProviderDetailView.swift` is the surface.

extension ProviderDetailView {
    // MARK: - 5 · Plan & credits (plan-only)

    var planCreditsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionLabel("Plan & credits")

            if let credits = creditsWindow, let display = creditsDisplay(credits) {
                HStack(spacing: 16) {
                    Text(display.barLabel)
                        .font(.sans(size: 13))
                        .foregroundColor(PadzyTheme.ink2)
                        .frame(minWidth: 100, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(PadzyTheme.hairline)
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(PadzyTheme.quotaColor(display.fraction * 100))
                                .frame(width: geo.size.width * CGFloat(display.fraction))
                        }
                    }
                    .frame(height: 6)
                    .frame(minWidth: 140, maxWidth: .infinity)
                    Text(display.readout)
                        .font(.mono(size: 13))
                        .monospacedDigit()
                        .foregroundColor(PadzyTheme.ink)
                }

                FlowLayout(hSpacing: 40, vSpacing: 20) {
                    ForEach(display.stats, id: \.kicker) { stat in
                        planStatBlock(kicker: stat.kicker, value: stat.value)
                    }
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\u{2014}")
                    .font(.mono(size: 13))
                    .foregroundColor(PadzyTheme.ink4)
                Text("Token-level usage isn't measured locally for \(snapshot.displayName). The quota above is what Tokei reads honestly.")
                    .font(.sans(size: 13))
                    .foregroundColor(PadzyTheme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: 560, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: PadzyRadius.cell, style: .continuous)
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundColor(PadzyTheme.border2)
            )

            Button(action: onEnableOnline) {
                Text(enableOnlineLabel)
                    .font(.mono(size: 12.5, weight: .semibold))
                    .foregroundColor(PadzyTheme.ground)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                            .fill(PadzyTheme.accent)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var enableOnlineLabel: String {
        snapshot.providerID == .cursor ? "Enable online in Settings" : "Enable online sync \u{2192}"
    }

    private func planStatBlock(kicker: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(kicker.uppercased())
                .font(.mono(size: 9.5))
                .tracking(1.0)
                .foregroundColor(PadzyTheme.ink5)
            Text(value)
                .font(.mono(size: 22, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(PadzyTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .fixedSize()
    }

    private struct CreditsDisplay {
        let barLabel: String
        let readout: String
        let fraction: Double
        let stats: [(kicker: String, value: String)]
    }

    /// Preserves the capabilityPane "used" vs "left" nuance: a window reporting
    /// `used` reads as "Credits used"; a balance-style window (only `remaining`)
    /// reads as "Credits left".
    private func creditsDisplay(_ window: QuotaWindow) -> CreditsDisplay? {
        func fmt(_ value: Double) -> String { TokenFormatter.format(Int(value.rounded())) }

        if let used = window.used {
            if let limit = window.limit, limit > 0 {
                return CreditsDisplay(
                    barLabel: "Credits used",
                    readout: "\(fmt(used)) / \(fmt(limit))",
                    fraction: min(1, max(0, used / limit)),
                    stats: [("Credits left", fmt(max(0, limit - used))),
                            ("Credits total", fmt(limit))]
                )
            }
            return CreditsDisplay(
                barLabel: "Credits used",
                readout: fmt(used),
                fraction: min(1, max(0, used / 100)),
                stats: [("Credits used", fmt(used))]
            )
        }

        if let remaining = window.remaining {
            if let limit = window.limit, limit > 0 {
                let used = max(0, limit - remaining)
                return CreditsDisplay(
                    barLabel: "Credits used",
                    readout: "\(fmt(used)) / \(fmt(limit))",
                    fraction: min(1, max(0, used / limit)),
                    stats: [("Credits left", fmt(remaining)),
                            ("Credits total", fmt(limit))]
                )
            }
            return CreditsDisplay(
                barLabel: "Credits left",
                readout: fmt(remaining),
                fraction: 0,
                stats: [("Credits left", fmt(remaining))]
            )
        }

        return nil
    }
}
