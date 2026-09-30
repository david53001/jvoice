import SwiftUI

/// The inset card surface (MacStats' `CardBackground`): a faint `Color.primary` tint so the window's
/// material shows through, a 0.5 pt hairline, and continuous (squircle) corners.
struct CardBackground: View {
    var fill: Double = Design.cardFill
    var cornerRadius: CGFloat = Design.cardCornerRadius

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape.fill(Color.primary.opacity(fill))
            .overlay(shape.strokeBorder(Color.primary.opacity(Design.cardHairline), lineWidth: Design.hairlineWidth))
    }
}

/// A text field drawn on the card: a `Color.primary` tint, a hairline and 6 pt continuous corners.
struct InputFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Design.smallButtonRadius, style: .continuous)
        return content
            .textFieldStyle(.plain)
            .font(.callout)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(shape.fill(Color.primary.opacity(Design.inputFill)))
            .overlay(shape.strokeBorder(Color.primary.opacity(Design.cardHairline), lineWidth: Design.hairlineWidth))
    }
}

extension View {
    func inputFieldStyle() -> some View { modifier(InputFieldStyle()) }
}
