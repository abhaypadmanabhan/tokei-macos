import SwiftUI
import AIUsageDashboardCore

/// Claude's extra usage as one row: the words from `ExtraUsageCopy` and a thin bar of the
/// limit spent. Deliberately unlike a quota gauge: no elapsed tick, no pace, no forecast,
/// because it is a dollar balance, not a window that refills.
struct ExtraUsageRow: View {
    let window: QuotaWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let line = ExtraUsageCopy.line(window), let amounts = ExtraUsageCopy.amounts(window) {
            VStack(alignment: .leading, spacing: 6) {
                // Words in the body font, the dollars in mono: the same sentence as `line`.
                (Text("\(window.label ?? "Extra usage") ").font(.sans(size: 15))
                    + Text(amounts).font(.mono(size: 13.5)).monospacedDigit()
                    + Text(ExtraUsageCopy.status(window).map { " · \($0)" } ?? "").font(.sans(size: 15)))
                    .foregroundColor(PadzyTheme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                if let fraction = ExtraUsageCopy.fraction(window) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(PadzyTheme.hairline)
                            Rectangle()
                                .fill(PadzyTheme.ink4)
                                .frame(width: geo.size.width * CGFloat(fraction))
                                .animation(LiveNumberMotion.animation(reduceMotion: reduceMotion), value: fraction)
                        }
                    }
                    .frame(height: 3)
                    .frame(maxWidth: 320)
                }
                Text("Billed on top of the plan; not counted as a quota limit.")
                    .font(.sans(size: 12))
                    .foregroundColor(PadzyTheme.ink4)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(line)
        }
    }
}
