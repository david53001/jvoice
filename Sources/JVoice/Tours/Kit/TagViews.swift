import AppKit
import SwiftUI

/// A continuous-corner (squircle) rounded rect, as a `CGPath` — `NSBezierPath(roundedRect:)` and
/// `CGPath(roundedRect:)` are circular arcs, which the native look avoids.
func continuousRoundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    RoundedRectangle(cornerRadius: max(0, radius), style: .continuous).path(in: rect).cgPath
}

/// The overlay's windows: borderless, transparent, never key or main, never activate the app.
/// The decor panel also ignores the mouse, so clicks land on the real control underneath.
final class TagPanel: NSPanel {
    init(clickThrough: Bool) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = !clickThrough
        ignoresMouseEvents = clickThrough
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = true
        isMovable = false
        isExcludedFromWindowsMenu = true
        collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Draws the dim over the host window (with a hole at the box), the outline box and the
/// leader line. Local coordinates of the decor panel.
final class TagDecorView: NSView {
    /// The host window's outline (rounded rect) to dim, or nil for no dim.
    var dim: (rect: CGRect, radius: CGFloat)?
    /// 20 %, or 35 % over a dark host (`TagStyle.dimAlpha(hostIsDark:)`).
    var dimAlpha = TagStyle.dimAlpha
    /// Outline's inner edge (anchor + padding) and outer edge (inner + stroke).
    var box: CGRect = .zero
    var outer: CGRect = .zero
    var leader: (from: CGPoint, to: CGPoint)?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        if let dim {
            cg.saveGState()
            let windowShape = continuousRoundedPath(dim.rect, radius: dim.radius)
            cg.addPath(windowShape)
            cg.clip()   // the part of the hole outside the window must stay clear, not flip to dim
            cg.addPath(windowShape)
            cg.addPath(continuousRoundedPath(outer, radius: TagStyle.boxRadius + TagStyle.boxStroke))
            cg.setFillColor(NSColor.black.withAlphaComponent(dimAlpha).cgColor)
            cg.fillPath(using: .evenOdd)
            cg.restoreGState()
        }

        // `NSAppearance.current` is this view's during `draw`, so the accent resolves for the host.
        cg.setStrokeColor(TagStyle.accentColour.cgColor)
        let half = TagStyle.outlineWidth / 2
        cg.addPath(continuousRoundedPath(box.insetBy(dx: -half, dy: -half), radius: TagStyle.boxRadius + half))
        cg.setLineWidth(TagStyle.outlineWidth)
        cg.strokePath()

        if let leader {
            cg.move(to: leader.from)
            cg.addLine(to: leader.to)
            cg.setLineWidth(TagStyle.leaderWidth)
            cg.setLineCap(.round)
            cg.strokePath()
        }
    }
}

/// A small capsule button inside the tag. Takes the first click (the tag's window is never key)
/// and never becomes first responder.
final class TagButton: NSButton {
    enum Style { case filled, outline, link }

    var style: Style { didSet { restyle() } }

    init(style: Style) {
        self.style = style
        super.init(frame: .zero)
        isBordered = false
        setButtonType(.momentaryChange)
        refusesFirstResponder = true
        focusRingType = .none
        wantsLayer = true
        restyle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        alphaValue = flag ? 0.7 : 1
    }

    func setLabel(_ text: String) {
        let colour: NSColor
        switch style {
        case .filled: colour = TagStyle.filledButtonText
        case .outline: colour = TagStyle.textColour
        case .link: colour = TagStyle.secondaryTextColour
        }
        attributedTitle = NSAttributedString(string: text, attributes: [
            .font: TagStyle.buttonFont, .foregroundColor: colour,
        ])
        setAccessibilityLabel(text)
    }

    /// Width that fits the label plus the capsule's padding.
    var fittingWidth: CGFloat {
        let text = ceil(attributedTitle.size().width)
        return style == .link ? text + 4 : text + 2 * TagStyle.buttonPaddingX
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        restyle()
    }

    /// Capsules: accent-filled (Next / Done), a faint tint ("Skip Step" — no 1 pt outline), or a bare
    /// link ("Skip Tour"). Layer colours are resolved in this view's appearance.
    private func restyle() {
        layer?.cornerRadius = TagStyle.buttonHeight / 2
        layer?.cornerCurve = .continuous
        effectiveAppearance.performAsCurrentDrawingAppearance {
            switch style {
            case .filled: layer?.backgroundColor = TagStyle.filledButtonFill.cgColor
            case .outline: layer?.backgroundColor = TagStyle.subtleButtonFill.cgColor
            case .link: layer?.backgroundColor = NSColor.clear.cgColor
            }
        }
        setLabel(attributedTitle.string)
    }
}

/// The tag bubble — a `.popover`-material squircle in the host's appearance: title, body (≤ 2 lines),
/// footer "2 of 7 · Skip tour · Next".
final class TagBubbleView: NSView {
    let titleLabel = NSTextField(labelWithString: "")
    let bodyLabel = NSTextField(wrappingLabelWithString: "")
    let counterLabel = NSTextField(labelWithString: "")
    let skipTourButton = TagButton(style: .link)
    /// "Next"/"Done" (filled) on Explain steps, "Skip step" (outline) on Try steps.
    let primaryButton = TagButton(style: .filled)
    let doneIcon = NSImageView()
    let doneLabel = NSTextField(labelWithString: TagStyle.completedTitle)

    var onPrimary: (() -> Void)?
    var onSkipTour: (() -> Void)?
    /// False on the last Explain step ("Done" alone — `TagStyle.showsSkipTour`).
    private var offersSkipTour = true
    /// The bubble's backdrop: a behind-window material, masked to the continuous-cornered tag shape.
    private let backdrop = NSVisualEffectView()

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        backdrop.material = .popover
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.maskImage = Self.maskImage(radius: TagStyle.tagRadius)
        backdrop.autoresizingMask = [.width, .height]
        backdrop.frame = bounds
        addSubview(backdrop)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)

        titleLabel.font = TagStyle.titleFont
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1

        bodyLabel.font = TagStyle.bodyFont
        bodyLabel.maximumNumberOfLines = TagStyle.bodyMaxLines
        bodyLabel.cell?.truncatesLastVisibleLine = true
        bodyLabel.lineBreakMode = .byWordWrapping

        counterLabel.font = TagStyle.footerFont

        doneIcon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        doneLabel.font = TagStyle.buttonFont

        skipTourButton.setLabel(TagStyle.skipTourTitle)
        skipTourButton.target = self
        skipTourButton.action = #selector(skipTourClicked)
        primaryButton.target = self
        primaryButton.action = #selector(primaryClicked)

        for v in [titleLabel, bodyLabel, counterLabel, skipTourButton, primaryButton, doneIcon, doneLabel] as [NSView] {
            addSubview(v)
        }
        applyColours()
    }

    /// System label colours (they resolve in the bubble's appearance); the done tick is green.
    private func applyColours() {
        titleLabel.textColor = TagStyle.textColour
        bodyLabel.textColor = TagStyle.textColour
        counterLabel.textColor = TagStyle.secondaryTextColour
        doneIcon.contentTintColor = .systemGreen
        doneLabel.textColor = TagStyle.textColour
    }

    /// A stretchable continuous-corner mask. The cap insets cover the whole squircle transition
    /// (≈ 1.53 × the radius), so stretching never bends the curve.
    private static func maskImage(radius: CGFloat) -> NSImage {
        let cap = ceil(radius * 1.6)
        let side = cap * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            guard let cg = NSGraphicsContext.current?.cgContext else { return false }
            cg.addPath(continuousRoundedPath(rect, radius: radius))
            cg.setFillColor(NSColor.black.cgColor)
            cg.fillPath()
            return true
        }
        image.capInsets = NSEdgeInsets(top: cap, left: cap, bottom: cap, right: cap)
        image.resizingMode = .stretch
        return image
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func primaryClicked() { onPrimary?() }
    @objc private func skipTourClicked() { onSkipTour?() }

    /// Fills the tag for a step; returns its size.
    func configure(title: String, body: String, number: Int, total: Int, isExplain: Bool) -> NSSize {
        titleLabel.stringValue = title
        bodyLabel.stringValue = body
        counterLabel.stringValue = TagStyle.counter(number, of: total)
        primaryButton.style = isExplain ? .filled : .outline
        primaryButton.setLabel(isExplain ? TagStyle.nextButtonTitle(number: number, total: total)
                                         : TagStyle.skipStepTitle)
        offersSkipTour = TagStyle.showsSkipTour(number: number, total: total, isExplain: isExplain)
        setAccessibilityLabel("Tour: \(title)")
        setDone(false)
        return relayout()
    }

    /// The brief "done" state after a Try step: the footer becomes ✓ Done.
    func showDone() -> NSSize {
        setDone(true)
        return relayout()
    }

    private func setDone(_ done: Bool) {
        counterLabel.isHidden = done
        skipTourButton.isHidden = done || !offersSkipTour
        primaryButton.isHidden = done
        doneIcon.isHidden = !done
        doneLabel.isHidden = !done
    }

    private func relayout() -> NSSize {
        let padX = TagStyle.tagPaddingX
        let counterW = ceil(counterLabel.attributedStringValue.size().width) + 4
        let skipW = offersSkipTour ? skipTourButton.fittingWidth + TagStyle.buttonGap : 0
        let footerW = counterW + 12 + skipW + primaryButton.fittingWidth
        let titleW = ceil(titleLabel.attributedStringValue.size().width) + 4
        let bodyW = ceil(bodyLabel.attributedStringValue.size().width) + 4
        let width = min(max(max(titleW, bodyW, footerW) + 2 * padX, TagStyle.tagMinWidth), TagStyle.tagMaxWidth)
        let inner = width - 2 * padX

        var y = TagStyle.tagPaddingTop
        let titleH = ceil(titleLabel.sizeThatFits(NSSize(width: inner, height: 1000)).height)
        titleLabel.frame = NSRect(x: padX, y: y, width: inner, height: titleH)
        y += titleH
        if bodyLabel.stringValue.isEmpty {
            bodyLabel.frame = .zero
        } else {
            bodyLabel.preferredMaxLayoutWidth = inner
            let bodyH = ceil(bodyLabel.sizeThatFits(NSSize(width: inner, height: 1000)).height)
            y += TagStyle.titleBodyGap
            bodyLabel.frame = NSRect(x: padX, y: y, width: inner, height: bodyH)
            y += bodyH
        }
        y += TagStyle.bodyFooterGap

        let fh = TagStyle.footerHeight, bh = TagStyle.buttonHeight
        let counterH = ceil(counterLabel.intrinsicContentSize.height)
        counterLabel.frame = NSRect(x: padX, y: y + (fh - counterH) / 2, width: counterW, height: counterH)
        let pw = primaryButton.fittingWidth, sw = skipTourButton.fittingWidth
        primaryButton.frame = NSRect(x: width - padX - pw, y: y + (fh - bh) / 2, width: pw, height: bh)
        skipTourButton.frame = NSRect(x: primaryButton.frame.minX - TagStyle.buttonGap - sw,
                                      y: y + (fh - bh) / 2, width: sw, height: bh)
        doneIcon.frame = NSRect(x: padX, y: y + (fh - 16) / 2, width: 16, height: 16)
        let doneH = ceil(doneLabel.intrinsicContentSize.height)
        doneLabel.frame = NSRect(x: padX + 20, y: y + (fh - doneH) / 2,
                                 width: ceil(doneLabel.intrinsicContentSize.width) + 4, height: doneH)
        y += fh + TagStyle.tagPaddingBottom

        let size = NSSize(width: width, height: y)
        setFrameSize(size)
        return size
    }
}
