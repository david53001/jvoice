import AppKit

/// What the user sees of a borderless host window, when that's less than its frame.
public struct TourHostShape: Equatable, Sendable {
    /// The visible panel, in screen coordinates: the dim covers it (rounded by `cornerRadius`) and the
    /// tag keeps clear of it.
    public var frame: CGRect
    public var cornerRadius: CGFloat
    /// Room the tag also keeps clear of, around `frame` (the recording pill's hover-hint band); nil = none.
    public var keepOut: CGRect?

    public init(frame: CGRect, cornerRadius: CGFloat, keepOut: CGRect? = nil) {
        self.frame = frame
        self.cornerRadius = cornerRadius
        self.keepOut = keepOut
    }
}

/// A borderless host whose window is bigger than what the user sees of it — the recording pill grows its
/// window by 30 pt while a control is hovered, for its hint bubble. The tag dims and keeps out of
/// `tourHostShape` instead of the window frame, so hovering neither moves the tag nor dims the window's
/// transparent part as a square band (review 2026-09-26, T4). Nil = use the window frame.
@MainActor
public protocol TourHostShaping: AnyObject {
    var tourHostShape: TourHostShape? { get }
}
