import SwiftUI

/// "Claude is working" text: a Claude-orange highlight sweeping through the letters plus a soft orange
/// glow — the look of David's session dashboard. The HUD's "AI refining" pill uses the full strength;
/// Settings' AI Polish card title uses `.subtle` (slower, fainter).
struct ClaudeGlowText: View {
    static let claudeOrange = Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255)

    struct Style {
        /// Seconds for one sweep across the text.
        var period: TimeInterval
        /// The glow's opacity breathes between these.
        var glow: ClosedRange<Double>
        var radius: CGFloat

        static let full = Style(period: 1.6, glow: 0.2...0.7, radius: 6)
        static let subtle = Style(period: 3.2, glow: 0.12...0.35, radius: 4)
    }

    let text: String
    var base: Color = .primary
    var style: Style = .full

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            // The highlight's centre runs from just before the first letter to just past the last.
            let centre = -0.3 + 1.6 * (t.truncatingRemainder(dividingBy: style.period) / style.period)
            let breath = 0.5 + 0.5 * sin(t * 2 * .pi / style.period)
            let glow = style.glow.lowerBound + (style.glow.upperBound - style.glow.lowerBound) * breath
            Text(text)
                .foregroundStyle(LinearGradient(
                    stops: [
                        .init(color: base, location: Self.clamp(centre - 0.3)),
                        .init(color: Self.claudeOrange, location: Self.clamp(centre)),
                        .init(color: base, location: Self.clamp(centre + 0.3)),
                    ],
                    startPoint: .leading, endPoint: .trailing))
                .shadow(color: Self.claudeOrange.opacity(glow), radius: style.radius)
        }
    }

    private static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
}
