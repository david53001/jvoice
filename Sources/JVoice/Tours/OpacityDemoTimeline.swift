import Foundation

/// The Opacity tour step's demo motion (`OpacityTourDemo`), as a pure function of time (logic-tested in `scripts/run-logic-tests.sh`): from
/// the user's value `start` down to 0, a pause, up to 1, a pause, back to `start`, a longer pause, then
/// again. Every move eases in and out, so the thumb visibly slows into each end.
enum OpacityDemoTimeline {
    /// The Settings tour step that plays the demo (the Appearance card).
    static let anchor = "settings.appearance"

    struct Frame: Equatable {
        var value: Double
        var readout: String
    }

    /// (target, seconds to get there, seconds to hold it). The first move starts at `start`.
    private static let legs: [(target: Double?, move: Double, hold: Double)] = [
        (0, 2.0, 0.9),      // fade to Transparent
        (1, 2.6, 0.9),      // rise to Opaque
        (nil, 1.3, 1.8),    // back to the user's value (nil = `start`)
    ]

    static var loopDuration: Double { legs.reduce(0) { $0 + $1.move + $1.hold } }

    static func frame(at time: TimeInterval, from start: Double) -> Frame {
        let start = UIOpacity.clamped(start)
        var t = max(0, time).truncatingRemainder(dividingBy: loopDuration)
        var from = start
        for leg in legs {
            let to = leg.target ?? start
            if t < leg.move {
                let p = t / leg.move
                let eased = p * p * (3 - 2 * p)   // smoothstep
                let value = from + (to - from) * eased
                let arrow = to < from ? " ↓" : to > from ? " ↑" : ""
                return Frame(value: value, readout: "Watch: \(percent(value)) %\(arrow)")
            }
            t -= leg.move
            if t < leg.hold { return Frame(value: to, readout: holdReadout(to, isYours: leg.target == nil)) }
            t -= leg.hold
            from = to
        }
        return Frame(value: start, readout: holdReadout(start, isYours: true))
    }

    static func percent(_ value: Double) -> Int { Int((UIOpacity.clamped(value) * 100).rounded()) }

    private static func holdReadout(_ value: Double, isYours: Bool) -> String {
        if isYours { return "Yours: \(percent(value)) %" }
        return value <= 0 ? "Watch: 0 % Transparent" : "Watch: 100 % Opaque"
    }
}
