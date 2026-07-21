import SwiftUI

/// Custom Padzy switch (aitracker): a pill track (neutral off / accent on) with a
/// white circular knob — the Tokei Dashboard mockup toggle. Label leads, control
/// trails (same layout contract as `.switch`, so it drops into every `Toggle`
/// unchanged). Knob slide animates unless Reduce Motion is on; state is never
/// colour-alone (knob position carries it, and VoiceOver reads on/off).
struct PadzyToggleStyle: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    private static let trackSize = CGSize(width: 36, height: 21)
    private static let knobSize: CGFloat = 16
    private static let offTrack = Color(hex: "2A2A31")

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.label
            Spacer(minLength: 8)
            Button(action: { configuration.isOn.toggle() }) {
                track(isOn: configuration.isOn)
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isOn ? "on" : "off")
        }
        .opacity(isEnabled ? 1 : 0.45)
    }

    private func track(isOn: Bool) -> some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule(style: .continuous)
                .fill(isOn ? PadzyTheme.accent : Self.offTrack)
            Circle()
                .fill(Color.white)
                .frame(width: Self.knobSize, height: Self.knobSize)
                .padding(2.5)
        }
        .frame(width: Self.trackSize.width, height: Self.trackSize.height)
        .animation(reduceMotion ? nil : PadzyMotion.toggle, value: isOn)
        .contentShape(Rectangle())
    }
}

extension ToggleStyle where Self == PadzyToggleStyle {
    /// `Toggle(...).toggleStyle(.padzy)`
    static var padzy: PadzyToggleStyle { PadzyToggleStyle() }
}

// MARK: - Previews

#Preview("Padzy toggle · on/off/disabled") {
    struct Host: View {
        @State private var on = true
        @State private var off = false

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: $on) {
                    Text("QUOTA ALERTS")
                        .font(.mono(size: 12))
                        .foregroundColor(PadzyTheme.ink)
                }
                Toggle(isOn: $off) {
                    Text("SHOW CLAUDE CODE")
                        .font(.mono(size: 12))
                        .foregroundColor(PadzyTheme.ink)
                }
                Toggle(isOn: $on) {
                    Text("DISABLED · ON")
                        .font(.mono(size: 12))
                        .foregroundColor(PadzyTheme.ink)
                }
                .disabled(true)
                Toggle(isOn: $off) {
                    Text("DISABLED · OFF")
                        .font(.mono(size: 12))
                        .foregroundColor(PadzyTheme.ink)
                }
                .disabled(true)
            }
            .toggleStyle(.padzy)
            .padding(24)
            .frame(width: 320)
            .background(PadzyTheme.ground)
        }
    }
    return Host()
}
