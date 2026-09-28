import AppKit

/// Every size, colour and string of the tour tag (spec §14.3, the owner's mock
/// `docs/superpowers/specs/assets/2026-09-25-tour-tag-mock.png`). One place, so the Windows port
/// (`docs/MAC-TO-WINDOWS-PARITY-v3.md` §7.3) copies the numbers from here.
public enum TagStyle {
    // MARK: Colour
    /// The tour colour — red #C62D22 — for the outline box, the leader line and the tag. A deeper shade
    /// of the mock's #FF453A so the tag's white text clears WCAG AA: white on it is 5.5:1 (#FF453A was
    /// 3.4:1 — review 2026-09-26, T1). `TagContrastTests` checks every text/background pair below.
    public static let tourRed = NSColor(srgbRed: 198 / 255, green: 45 / 255, blue: 34 / 255, alpha: 1)
    /// The tag's text: title, body, the Try step's "Skip Step" outline button, the done state.
    public static let textColour = NSColor.white
    /// The primary (Next / Done) capsule: white fill, tour-red label.
    public static let filledButtonFill = NSColor.white
    public static var filledButtonText: NSColor { tourRed }
    /// The dim laid over the rest of the host window (black at this alpha)…
    public static let dimAlpha: CGFloat = 0.2
    /// …and over an always-dark host (the editor, video editor, record strip, pill, Settings), where 20%
    /// barely shows (review T7). Chosen by the host's effective appearance (`dimAlpha(hostIsDark:)`).
    public static let darkHostDimAlpha: CGFloat = 0.35

    public static func dimAlpha(hostIsDark: Bool) -> CGFloat { hostIsDark ? darkHostDimAlpha : dimAlpha }

    // MARK: Outline box + leader
    /// Gap between the highlighted control and the inner edge of the outline.
    public static let boxPadding: CGFloat = 4
    /// Outline thickness; drawn outside the padding (it covers 4–6 pt outside the control).
    public static let boxStroke: CGFloat = 2
    /// Corner radius of the outline's inner edge.
    public static let boxRadius: CGFloat = 6
    public static let leaderWidth: CGFloat = 2
    /// Gap between the outline's outer edge and the tag, spanned by the leader line.
    public static let leaderLength: CGFloat = 24
    /// The tag never comes closer than this to the edges of the screen's visible frame.
    public static let screenMargin: CGFloat = 8
    /// A control spanning at least this share of its host window's width **and** height is "big" (the
    /// editor canvas, the video preview, the Settings cards): its tag goes beside the whole window, or
    /// inside the control's top-right corner — never beside the control, over the window's other controls.
    public static let bigAnchorFraction: CGFloat = 0.6
    /// An inside-corner tag's distance from the control's top and right edges.
    public static let insideCornerInset: CGFloat = 16

    // MARK: Tag bubble
    public static let tagRadius: CGFloat = 12
    public static let tagMaxWidth: CGFloat = 260
    public static let tagMinWidth: CGFloat = 200
    public static let tagPaddingX: CGFloat = 12
    public static let tagPaddingTop: CGFloat = 10
    public static let tagPaddingBottom: CGFloat = 10
    public static let titleBodyGap: CGFloat = 2
    public static let bodyFooterGap: CGFloat = 8
    public static let titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    public static let bodyFont = NSFont.systemFont(ofSize: 12)
    public static let bodyMaxLines = 2
    public static let footerFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    public static let buttonFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
    public static let footerHeight: CGFloat = 20
    public static let buttonHeight: CGFloat = 20
    public static let buttonPaddingX: CGFloat = 8
    public static let buttonGap: CGFloat = 4
    /// White at this alpha: the step counter and the "Skip Tour" link (4.7:1 on the tag red).
    public static let secondaryTextAlpha: CGFloat = 0.9
    public static var secondaryTextColour: NSColor { textColour.withAlphaComponent(secondaryTextAlpha) }

    // MARK: Strings
    public static let nextTitle = "Next"
    public static let doneTitle = "Done"
    /// Title Case, like every macOS button (review T6).
    public static let skipStepTitle = "Skip Step"
    public static let skipTourTitle = "Skip Tour"
    public static let completedTitle = "Done"

    /// "2 of 7".
    public static func counter(_ number: Int, of total: Int) -> String { "\(number) of \(total)" }

    /// The Explain step's primary button: "Next", or "Done" on the last step.
    public static func nextButtonTitle(number: Int, total: Int) -> String {
        number >= total ? doneTitle : nextTitle
    }

    /// "Skip Tour" is left out next to the last step's "Done" (same result, one click — review T6). A last
    /// *Try* step keeps it: there the other button is "Skip Step", which also runs the tour's hand-over.
    public static func showsSkipTour(number: Int, total: Int, isExplain: Bool) -> Bool {
        !(isExplain && number >= total)
    }

    /// What VoiceOver reads when a tag appears.
    public static func announcement(title: String, body: String, number: Int, total: Int) -> String {
        "\(title). \(body) Step \(number) of \(total)."
    }
}
