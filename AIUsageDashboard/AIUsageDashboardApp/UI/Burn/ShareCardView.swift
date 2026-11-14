import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AIUsageDashboardCore

/// The 1200×630 card "Share my week" renders: the week's value, the month's multiple and tier,
/// the streak and the top agent. Only `ShareCardModel` reaches it, so it cannot show an account.
struct ShareCardView: View {
    let card: ShareCardModel

    static let size = CGSize(width: 1200, height: 630)

    var body: some View {
        ZStack(alignment: .topLeading) {
            PadzyTheme.ground
            // One ring motif in the accent, bleeding off the right edge: the ring from the app,
            // track first so the arc keeps its full colour.
            Circle()
                .stroke(PadzyTheme.border2, lineWidth: 46)
                .frame(width: 520, height: 520)
                .offset(x: 860, y: 150)
            Circle()
                .trim(from: 0, to: 0.82)
                .rotation(.degrees(-90))
                .stroke(PadzyTheme.accent, style: StrokeStyle(lineWidth: 46, lineCap: .round))
                .frame(width: 520, height: 520)
                .offset(x: 860, y: 150)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    TokeiMark(size: 44)
                    Text("Tokei")
                        .font(.sans(size: 30, weight: .semibold))
                        .foregroundColor(PadzyTheme.ink)
                    Spacer()
                    Text(card.dateLine())
                        .font(.mono(size: 24))
                        .foregroundColor(PadzyTheme.ink3)
                        .padding(.trailing, 380)
                }

                Spacer(minLength: 0)

                Text(card.headline)
                    .font(.mono(size: 128, weight: .semibold))
                    .foregroundColor(PadzyTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(card.headlineCaption)
                    .font(.sans(size: 32))
                    .foregroundColor(PadzyTheme.ink3)
                    .padding(.top, 2)

                HStack(alignment: .firstTextBaseline, spacing: 44) {
                    if let multiple = card.multipleLine {
                        stat(multiple, emphasis: card.tierLine)
                    }
                    stat(card.streakLine, emphasis: nil)
                }
                .padding(.top, 42)

                HStack(spacing: 28) {
                    if let top = card.topAgentLine {
                        Text(top)
                    }
                    if card.weekValueUSD != nil {
                        Text(card.tokensLine).font(.mono(size: 24))
                    }
                    Spacer()
                }
                .font(.sans(size: 24))
                .foregroundColor(PadzyTheme.ink3)
                .padding(.top, 18)

                Spacer(minLength: 0)

                Text(ShareCardModel.footer)
                    .font(.sans(size: 22))
                    .foregroundColor(BurnTone.caption)
            }
            .padding(64)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipped()
        .environment(\.colorScheme, .dark)
    }

    private func stat(_ text: String, emphasis: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(text)
                .font(.sans(size: 30, weight: .medium))
                .foregroundColor(PadzyTheme.ink)
            if let emphasis {
                Text(emphasis)
                    .font(.sans(size: 30, weight: .semibold))
                    .foregroundColor(PadzyTheme.good)
            }
        }
    }

    /// The card as PNG bytes at exactly 1200×630 pixels.
    @MainActor
    static func png(for card: ShareCardModel) -> Data? {
        let renderer = ImageRenderer(content: ShareCardView(card: card))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(size)
        guard let image = renderer.cgImage else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = size
        return rep.representation(using: .png, properties: [:])
    }
}

/// Preview of the card with Copy and Save…. Opens from the Burn tab's "Share my week".
struct ShareCardSheet: View {
    let card: ShareCardModel
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var png: Data?
    @State private var status: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Share my week")
                .font(.sans(size: 15, weight: .semibold))
                .foregroundColor(PadzyTheme.ink)
            ShareCardView(card: card)
                .scaleEffect(0.5, anchor: .topLeading)
                .frame(width: ShareCardView.size.width / 2, height: ShareCardView.size.height / 2, alignment: .topLeading)
                .overlay(Rectangle().stroke(PadzyTheme.border2, lineWidth: 1))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Card: " + card.lines().joined(separator: ", "))
            Text("Only totals and agent names. No accounts, emails or project names.")
                .font(.sans(size: 12.5))
                .foregroundColor(BurnTone.caption)
            HStack(spacing: 10) {
                Text(status ?? " ")
                    .font(.sans(size: 12.5))
                    .foregroundColor(PadzyTheme.ink3)
                    .animation(reduceMotion ? nil : PadzyMotion.quick, value: status)
                Spacer()
                Button("Copy", action: copy)
                    .keyboardShortcut("c", modifiers: .command)
                Button("Save…", action: save)
                    .keyboardShortcut("s", modifiers: .command)
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.regular)
        }
        .padding(20)
        .background(PadzyTheme.panel)
        .preferredColorScheme(.dark)
        .task {
            png = ShareCardView.png(for: card)
            #if DEBUG
            if let path = UserDefaults.standard.string(forKey: "TokeiShareCardOut"), let png {
                try? png.write(to: URL(fileURLWithPath: path))
            }
            #endif
        }
        .task(id: status) {
            // The confirmation clears itself; the task ends with it.
            guard status != nil else { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            status = nil
        }
    }

    private func copy() {
        guard let png = png ?? ShareCardView.png(for: card) else {
            status = "Could not render the card."
            return
        }
        let board = NSPasteboard.general
        board.clearContents()
        board.setData(png, forType: .png)
        status = "Copied. Paste it into a post."
    }

    private func save() {
        guard let png = png ?? ShareCardView.png(for: card) else {
            status = "Could not render the card."
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = card.fileName()
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try png.write(to: url, options: .atomic)
                status = "Saved \(url.lastPathComponent)."
            } catch {
                status = "Could not save: \(error.localizedDescription)"
            }
        }
    }
}

#Preview("Share card") {
    ShareCardView(card: ShareCardModel(snapshot: .sample(now: Date())))
        .scaleEffect(0.5)
        .frame(width: 600, height: 315)
}
