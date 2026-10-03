import CoreGraphics

/// Where the tag goes around the highlighted control (spec §14.3). Pure and unit-tested; screen
/// coordinates with AppKit's origin (bottom-left, y up) — "below" is lower on screen.
///
/// The outline box is the anchor grown by `boxPadding` (clipped to the screen, for a menu-bar icon);
/// its 2 pt stroke sits just outside that. In order:
/// 1. A step's own `placement` (left/right/above/below/insideCorner) if it fits; else as automatic.
/// 2. A **big** control — at least `bigAnchorFraction` of its host window's width *and* height (the editor
///    canvas, the video
///    preview, the Settings cards) — gets the tag beside the *whole window* if there's room on screen,
///    else inside its own top-right corner: "beside" it would mean over the window's other controls.
/// 3. The first side in the preference order where the tag fits inside the visible frame (minus
///    `screenMargin`) at `leaderLength` from the outline, slid along that side to stay on screen — and
///    within the host window's extent on that axis when it fits there, so it doesn't hang past the
///    window's edge (the ⓘ at a window's far right) — but still overlapping the box's span so the leader
///    line stays short. With a `keepOut` rect (a small
///    borderless host — the record strip, the pill) the tag first tries to sit outside all of it, so it
///    never covers that panel's other controls; if nothing fits there it may overlap it.
/// 4. Nothing fits at all → the tag sits *over* the control's top-left corner.
/// A straight leader line is slid along the tag's side to cross as few `obstacles` (the host's other
/// controls) as it can, staying as close to the box's middle as that allows.
enum TagLayout {
    enum Side: String, Equatable, Sendable {
        case left, right, below, above, over, insideCorner
    }

    struct Placement: Equatable, Sendable {
        var side: Side
        /// The outline's inner edge: the anchor grown by `boxPadding` (corner radius `boxRadius`).
        var box: CGRect
        /// The outline's outer edge (box grown by the stroke) — the dim's hole.
        var outer: CGRect
        var tag: CGRect
        /// From a point on the tag's edge to a point on the outline's outer edge; nil for `.over` and
        /// `.insideCorner`.
        var leader: (from: CGPoint, to: CGPoint)?

        static func == (a: Placement, b: Placement) -> Bool {
            a.side == b.side && a.box == b.box && a.outer == b.outer && a.tag == b.tag
                && a.leader?.from == b.leader?.from && a.leader?.to == b.leader?.to
        }
    }

    /// Left/right first (the mock puts the tag left of the box), then below/above; or below/above
    /// first for a control sitting in a horizontal bar (toolbar, record strip, pill) or in a title bar,
    /// so the tag doesn't cover the controls next to it.
    static func order(verticalFirst: Bool) -> [Side] {
        verticalFirst ? [.below, .above, .left, .right] : [.left, .right, .below, .above]
    }

    /// A control whose container is a wide, short bar (3:1 or wider) gets the tag above/below.
    static func prefersVertical(containerSize: CGSize) -> Bool {
        containerSize.height > 0 && containerSize.width >= 3 * containerSize.height
    }

    /// A control in the window's title bar (the ⓘ, the editor's Undo/Redo): entirely above the content
    /// layout rect. Such a control gets the tag below it, not over its neighbours in the bar (review E4).
    static func isInTitleBar(anchor: CGRect, contentLayout: CGRect) -> Bool {
        anchor.minY >= contentLayout.maxY - 1
    }

    /// A control spanning at least `TagStyle.bigAnchorFraction` of its host window's width and of its height
    /// (what's visible of it). Both, not the area: Settings' Keyboard Shortcuts card is half the window's
    /// area but a wide strip — beside it (above) is fine, and its top-right corner holds the wells to click.
    static func isBig(anchor: CGRect, host: CGRect) -> Bool {
        let visible = anchor.intersection(host)
        guard !visible.isNull, host.width > 0, host.height > 0 else { return false }
        let f = TagStyle.bigAnchorFraction
        return visible.width >= f * host.width && visible.height >= f * host.height
    }

    /// - Parameters:
    ///   - preferred: the step's `TourStep.placement`.
    ///   - host: the host window's frame (the visible body, for a panel bigger than what it shows); nil
    ///     for no big-control rule (the menu-bar icon).
    ///   - obstacles: the host's other controls, for routing the leader line.
    static func place(anchor: CGRect, tagSize: CGSize, visible: CGRect,
                      order: [Side] = order(verticalFirst: false),
                      keepOut: CGRect? = nil, screen: CGRect? = nil,
                      preferred: TourStep.Placement = .automatic, host: CGRect? = nil,
                      obstacles: [CGRect] = []) -> Placement {
        var box = anchor.insetBy(dx: -TagStyle.boxPadding, dy: -TagStyle.boxPadding)
        if let screen {
            // A menu-bar icon fills the bar's height: keep the whole outline on the screen.
            let limit = screen.insetBy(dx: TagStyle.boxStroke, dy: TagStyle.boxStroke)
            if box.intersects(limit) { box = box.intersection(limit) }
        }
        let outer = box.insetBy(dx: -TagStyle.boxStroke, dy: -TagStyle.boxStroke)
        let area = visible.insetBy(dx: TagStyle.screenMargin, dy: TagStyle.screenMargin)
        func fit(_ sides: [Side], clear: CGRect) -> Placement? {
            firstFit(sides, clear: clear, box: box, outer: outer, size: tagSize, area: area, within: host,
                     obstacles: obstacles)
        }
        func corner() -> Placement? {
            insideCorner(anchor: anchor, host: host, box: box, outer: outer, size: tagSize, area: area)
        }

        // 1. The step's own choice, when it fits.
        switch preferred {
        case .automatic:
            break
        case .insideCorner:
            if let p = corner() { return p }
        case .left, .right, .above, .below:
            let side: Side = preferred == .left ? .left : preferred == .right ? .right
                : preferred == .above ? .above : .below
            if let keepOut, let p = fit([side], clear: outer.union(keepOut)) { return p }
            if let p = fit([side], clear: outer) { return p }
        }

        // 2. A control filling most of its window: beside the whole window, else in its own corner.
        if let host, isBig(anchor: anchor, host: host) {
            if let p = fit(order, clear: outer.union(host).union(keepOut ?? outer)) { return p }
            if let p = corner() { return p }
        }

        // 3. Beside the control (outside a small panel host first).
        if let keepOut, let p = fit(order, clear: outer.union(keepOut)) { return p }
        if let p = fit(order, clear: outer) { return p }

        // 4. Fallback: inside the control's top-left corner, kept on screen.
        let w = tagSize.width, h = tagSize.height, inset = TagStyle.tagRadius
        let tag = CGRect(x: clamp(box.minX + inset, area.minX, area.maxX - w),
                         y: clamp(box.maxY - inset - h, area.minY, area.maxY - h),
                         width: w, height: h)
        return Placement(side: .over, box: box, outer: outer, tag: tag, leader: nil)
    }

    /// Inside the top-right corner of what's visible of the control, `insideCornerInset` from its edges;
    /// nil when the tag doesn't fit in there.
    private static func insideCorner(anchor: CGRect, host: CGRect?, box: CGRect, outer: CGRect,
                                     size: CGSize, area: CGRect) -> Placement? {
        let inset = TagStyle.insideCornerInset
        var region = anchor.intersection(area)
        if let host { region = region.intersection(host) }
        guard !region.isNull, region.width >= size.width + 2 * inset,
              region.height >= size.height + 2 * inset else { return nil }
        let tag = CGRect(x: (region.maxX - inset - size.width).rounded(),
                         y: (region.maxY - inset - size.height).rounded(),
                         width: size.width, height: size.height)
        return Placement(side: .insideCorner, box: box, outer: outer, tag: tag, leader: nil)
    }

    /// The first side where the tag fits `leaderLength` outside `clear`, inside `area`, overlapping
    /// the box's span.
    private static func firstFit(_ order: [Side], clear: CGRect, box: CGRect, outer: CGRect,
                                 size: CGSize, area: CGRect, within host: CGRect?,
                                 obstacles: [CGRect]) -> Placement? {
        let w = size.width, h = size.height, gap = TagStyle.leaderLength
        /// Where the tag's origin may slide on one axis: the screen, narrowed to the host when it fits.
        func slide(_ lo: CGFloat, _ hi: CGFloat, _ hostLo: CGFloat?, _ hostHi: CGFloat?, _ len: CGFloat)
            -> (CGFloat, CGFloat) {
            if let hostLo, let hostHi, min(hi, hostHi) - max(lo, hostLo) >= len {
                return (max(lo, hostLo), min(hi, hostHi) - len)
            }
            return (lo, hi - len)
        }
        let ys = slide(area.minY, area.maxY, host?.minY, host?.maxY, h)
        let xs = slide(area.minX, area.maxX, host?.minX, host?.maxX, w)
        for side in order {
            var tag: CGRect
            switch side {
            case .left, .right:
                let x = side == .left ? clear.minX - gap - w : clear.maxX + gap
                let y = clearestY(centred: clamp(box.midY - h / 2, ys.0, ys.1), x: x, size: size,
                                  box: box, range: ys, obstacles: obstacles)
                tag = CGRect(x: x, y: y, width: w, height: h)
                guard tag.minX >= area.minX, tag.maxX <= area.maxX, h <= area.height,
                      tag.minY < box.maxY, tag.maxY > box.minY else { continue }
            case .below, .above:
                let y = side == .below ? clear.minY - gap - h : clear.maxY + gap
                let x = clamp(box.midX - w / 2, xs.0, xs.1)
                tag = CGRect(x: x, y: y, width: w, height: h)
                guard tag.minY >= area.minY, tag.maxY <= area.maxY, w <= area.width,
                      tag.minX < box.maxX, tag.maxX > box.minX else { continue }
            case .over, .insideCorner:
                continue
            }
            tag.origin = CGPoint(x: tag.origin.x.rounded(), y: tag.origin.y.rounded())   // whole points
            return Placement(side: side, box: box, outer: outer, tag: tag,
                             leader: leader(side: side, tag: tag, box: box, outer: outer, obstacles: obstacles))
        }
        return nil
    }

    /// A side tag's y: centred on the box, unless sliding it along the box (keeping a straight leader —
    /// the tag's straight part still overlapping the box's) covers less of the host's other controls,
    /// e.g. the Welcome page's text line just above the ⇧⌘4 row (review W1). Ties stay nearest the centre.
    private static func clearestY(centred: CGFloat, x: CGFloat, size: CGSize, box: CGRect,
                                  range: (CGFloat, CGFloat), obstacles: [CGRect]) -> CGFloat {
        guard !obstacles.isEmpty else { return centred }
        let h = size.height, reach = TagStyle.tagRadius + TagStyle.boxRadius
        let lo = max(range.0, box.minY + reach - h), hi = min(range.1, box.maxY - reach)
        guard lo <= hi else { return centred }
        func covered(_ y: CGFloat) -> CGFloat {
            let tag = CGRect(x: x, y: y, width: size.width, height: h)
            return obstacles.reduce(0) { sum, o in
                let i = tag.intersection(o)
                return i.isNull ? sum : sum + i.width * i.height
            }
        }
        var candidates = [clamp(centred, lo, hi)]
        for o in obstacles {   // just clear of each control, above or below it
            candidates.append(clamp(o.maxY + 1, lo, hi))
            candidates.append(clamp(o.minY - 1 - h, lo, hi))
        }
        return candidates.min { a, b in
            let ca = covered(a), cb = covered(b)
            return ca != cb ? ca < cb : abs(a - centred) < abs(b - centred)
        }!
    }

    /// Straight across when the tag and box overlap enough — at the point nearest the box's middle that
    /// crosses the fewest `obstacles` — and kept off both shapes' rounded corners; else diagonal.
    static func leader(side: Side, tag: CGRect, box: CGRect, outer: CGRect,
                       obstacles: [CGRect] = []) -> (CGPoint, CGPoint) {
        let tr = TagStyle.tagRadius, br = TagStyle.boxRadius
        switch side {
        case .left, .right:
            let x1 = side == .left ? tag.maxX : tag.minX
            let x2 = side == .left ? outer.minX : outer.maxX
            let lo = max(tag.minY + tr, box.minY + br), hi = min(tag.maxY - tr, box.maxY - br)
            if lo <= hi {
                let y = route(preferred: clamp(box.midY, lo, hi), lo: lo, hi: hi, obstacles: obstacles) { y in
                    CGRect(x: min(x1, x2), y: y - TagStyle.leaderWidth / 2, width: abs(x2 - x1), height: TagStyle.leaderWidth)
                }
                return (CGPoint(x: x1, y: y), CGPoint(x: x2, y: y))
            }
            let y = clamp(box.midY, tag.minY + tr, tag.maxY - tr)
            return (CGPoint(x: x1, y: y), CGPoint(x: x2, y: clamp(y, box.minY + br, box.maxY - br)))
        case .below, .above:
            let y1 = side == .below ? tag.maxY : tag.minY
            let y2 = side == .below ? outer.minY : outer.maxY
            let lo = max(tag.minX + tr, box.minX + br), hi = min(tag.maxX - tr, box.maxX - br)
            if lo <= hi {
                let x = route(preferred: clamp(box.midX, lo, hi), lo: lo, hi: hi, obstacles: obstacles) { x in
                    CGRect(x: x - TagStyle.leaderWidth / 2, y: min(y1, y2), width: TagStyle.leaderWidth, height: abs(y2 - y1))
                }
                return (CGPoint(x: x, y: y1), CGPoint(x: x, y: y2))
            }
            let x = clamp(box.midX, tag.minX + tr, tag.maxX - tr)
            return (CGPoint(x: x, y: y1), CGPoint(x: clamp(x, box.minX + br, box.maxX - br), y: y2))
        case .over, .insideCorner:
            return (.zero, .zero)
        }
    }

    /// The coordinate in `lo...hi` whose line (`segment`) crosses the fewest obstacles; ties go to the one
    /// nearest `preferred`. Candidates: `preferred`, and just past each obstacle's two edges.
    private static func route(preferred: CGFloat, lo: CGFloat, hi: CGFloat, obstacles: [CGRect],
                              segment: (CGFloat) -> CGRect) -> CGFloat {
        func crossings(_ v: CGFloat) -> Int { obstacles.filter { $0.intersects(segment(v)) }.count }
        let clearance = TagStyle.leaderWidth / 2 + 2
        let horizontal = segment(0).width > segment(0).height   // the line runs along x: candidates are ys
        var candidates = [preferred]
        for o in obstacles {
            let (a, b) = horizontal ? (o.minY, o.maxY) : (o.minX, o.maxX)
            candidates += [a - clearance, b + clearance].filter { $0 >= lo && $0 <= hi }
        }
        var best = preferred, bestCount = crossings(preferred)
        for c in candidates.dropFirst() {
            let n = crossings(c)
            if n < bestCount || (n == bestCount && abs(c - preferred) < abs(best - preferred)) {
                best = c
                bestCount = n
            }
        }
        return best
    }

    /// `lo...hi`, or the middle of the two when the range is empty (a tiny box or tag).
    static func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        lo > hi ? (lo + hi) / 2 : min(max(v, lo), hi)
    }
}
