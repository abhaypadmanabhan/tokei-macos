import SwiftUI

/// Rounded surface card shell for the redesigned dashboard (design spec §3):
/// a plain sentence-case heading, optional trailing control, content on a
/// `PadzyRadius.card` surface panel with a 1px hairline stroke. No shadows,
/// no materials — the lift comes from surface-over-ground plus the hairline.
struct SectionCard<Content: View, Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    init(
        _ title: String,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .font(.sans(size: 15, weight: .semibold))
                    .foregroundColor(PadzyTheme.ink2)
                    .lineLimit(1)
                Spacer(minLength: 0)
                trailing
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PadzyRadius.card, style: .continuous)
                .fill(PadzyTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PadzyRadius.card, style: .continuous)
                .stroke(PadzyTheme.muted.opacity(0.22), lineWidth: 1)
        )
    }
}

// MARK: - Previews

#Preview("SectionCard") {
    SectionCard("Today") {
        Text("Local usage")
            .font(.sans(size: 15))
            .foregroundColor(PadzyTheme.ink)
    }
    .padding(24)
    .frame(width: 640)
    .background(PadzyTheme.ground)
}
