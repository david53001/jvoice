import SwiftUI

/// Default press-feedback style for panel-resident buttons. Use this
/// instead of .buttonStyle(.plain) anywhere an interactive control
/// should give visible feedback on press.
public struct PanelPressableButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(AppTimings.Motion.press, value: configuration.isPressed)
    }
}
