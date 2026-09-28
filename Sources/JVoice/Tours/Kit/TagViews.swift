import AppKit

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
        if let dim {
            NSGraphicsContext.saveGraphicsState()
            let windowShape = NSBezierPath(roundedRect: dim.rect, xRadius: dim.radius, yRadius: dim.radius)
            windowShape.addClip()   // the part of the hole outside the window must stay clear, not flip to dim
            let path = NSBezierPath(roundedRect: dim.rect, xRadius: dim.radius, yRadius: dim.radius)
            let outerRadius = TagStyle.boxRadius + TagStyle.boxStroke
            path.append(NSBezierPath(roundedRect: outer, xRadius: outerRadius, yRadius: outerRadius))
            path.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(dimAlpha).setFill()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        TagStyle.tourRed.setStroke()
        let half = TagStyle.boxStroke / 2
        let radius = TagStyle.boxRadius + half
        let outline = NSBezierPath(roundedRect: box.insetBy(dx: -half, dy: -half), xRadius: radius, yRadius: radius)
        outline.lineWidth = TagStyle.boxStroke
        outline.stroke()

        if let leader {
            let line = NSBezierPath()
            line.move(to: leader.from)
            line.line(to: leader.to)
            line.lineWidth = TagStyle.leaderWidth
            line.lineCapStyle = .round
            line.stroke()
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

    private func restyle() {
        layer?.cornerRadius = TagStyle.buttonHeight / 2
        layer?.backgroundColor = style == .filled ? TagStyle.filledButtonFill.cgColor : NSColor.clear.cgColor
        layer?.borderWidth = style == .outline ? 1 : 0
        layer?.borderColor = TagStyle.textColour.cgColor
        setLabel(attributedTitle.string)
    }
}

/// The red tag bubble: title, body (≤ 2 lines), footer "2 of 7 · Skip tour · Next".
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

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = TagStyle.tourRed.cgColor
        layer?.cornerRadius = TagStyle.tagRadius
        setAccessibilityElement(true)
        setAccessibilityRole(.group)

        titleLabel.font = TagStyle.titleFont
        titleLabel.textColor = TagStyle.textColour
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1

        bodyLabel.font = TagStyle.bodyFont
        bodyLabel.textColor = TagStyle.textColour
        bodyLabel.maximumNumberOfLines = TagStyle.bodyMaxLines
        bodyLabel.cell?.truncatesLastVisibleLine = true
        bodyLabel.lineBreakMode = .byWordWrapping

        counterLabel.font = TagStyle.footerFont
        counterLabel.textColor = TagStyle.secondaryTextColour

        doneIcon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        doneIcon.contentTintColor = TagStyle.textColour
        doneLabel.font = TagStyle.buttonFont
        doneLabel.textColor = TagStyle.textColour

        skipTourButton.setLabel(TagStyle.skipTourTitle)
        skipTourButton.target = self
        skipTourButton.action = #selector(skipTourClicked)
        primaryButton.target = self
        primaryButton.action = #selector(primaryClicked)

        for v in [titleLabel, bodyLabel, counterLabel, skipTourButton, primaryButton, doneIcon, doneLabel] as [NSView] {
            addSubview(v)
        }
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
