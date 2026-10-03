import SwiftUI

/// Small secondary button (MacStats' `SubtleButtonStyle`): `.callout` medium label, 24 pt tall,
/// continuous radius 6, a `Color.primary` tint 0.08 → 0.12 hover → 0.16 pressed. `destructive` tints
/// the label red; disabled labels go tertiary.
struct SubtleButtonStyle: ButtonStyle {
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        SubtleButton(configuration: configuration, destructive: destructive)
    }

    private struct SubtleButton: View {
        let configuration: ButtonStyleConfiguration
        let destructive: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            let fill = configuration.isPressed ? Design.smallButtonPressedFill
                : (hovering && isEnabled) ? Design.smallButtonHoverFill : Design.smallButtonFill
            configuration.label
                .font(.callout.weight(.medium))
                .foregroundStyle(!isEnabled ? AnyShapeStyle(.tertiary)
                                 : destructive ? AnyShapeStyle(Color.red) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: Design.smallButtonHeight)
                .background(
                    RoundedRectangle(cornerRadius: Design.smallButtonRadius, style: .continuous)
                        .fill(Color.primary.opacity(fill))
                )
                .contentShape(RoundedRectangle(cornerRadius: Design.smallButtonRadius, style: .continuous))
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
                .onHover { hovering = $0 }
        }
    }
}
