import SwiftUI

/// Custom Padzy switch (aitracker): hairline-stroked track on `surface`,
/// accent fill when on, crisp square-ish knob — deliberately NOT the native
/// macOS switch. Label leads, control trails (same layout contract as
/// `.switch`, so it drops into every Settings `Toggle` unchanged). Knob slide
/// animates unless Reduce Motion is on; state is never color-alone (knob
/// position carries it, and VoiceOver reads on/off).
struct PadzyToggleStyle: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    private static let trackSize = CGSize(width: 34, height: 18)
    private static let knobSize: CGFloat = 12

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
            RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                .fill(isOn ? PadzyTheme.accent : PadzyTheme.surface)
            RoundedRectangle(cornerRadius: PadzyRadius.control, style: .continuous)
                .stroke(isOn ? PadzyTheme.accent : PadzyTheme.muted.opacity(0.5), lineWidth: 1)
            RoundedRectangle(cornerRadius: PadzyRadius.control - 3, style: .continuous)
                .fill(isOn ? PadzyTheme.ground : PadzyTheme.muted)
                .frame(width: Self.knobSize, height: Self.knobSize)
                .padding(3)
        }
        .frame(width: Self.trackSize.width, height: Self.trackSize.height)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isOn)
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
