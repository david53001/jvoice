import AppKit

/// The ⓘ on every window (spec §14.3): a small borderless ⓘ that opens a menu —
/// **Replay Tour** (→ `TourEvents.replay(tour, in: window)`) · **Keyboard Shortcuts** (a popover
/// listing the window's shortcuts; the item is left out when there are none).
///
/// Titled windows: `InfoButton.install(in:tour:shortcuts:)` puts it in the title bar's top-right
/// corner as its own trailing accessory, right of any accessory already there (the editor's
/// Undo/Redo/panel toggle). Untitled panels (the record strip): `InfoButton(tour:shortcuts:)` and
/// add it like any view (26 × 22 pt; set `contentTintColor` to match a dark HUD).
@MainActor
public final class InfoButton: NSButton {
    public static let size = NSSize(width: 26, height: 22)
    public static let replayTitle = "Replay Tour"
    public static let shortcutsTitle = "Keyboard Shortcuts"
    public static let toolTipText = "Tour & Keyboard Shortcuts"

    public var tour: TourID
    public var shortcuts: [(keys: String, action: String)]

    private var popover: NSPopover?

    public init(tour: TourID, shortcuts: [(keys: String, action: String)] = []) {
        self.tour = tour
        self.shortcuts = shortcuts
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        isBordered = false
        bezelStyle = .shadowlessSquare
        imagePosition = .imageOnly
        image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: Self.toolTipText)
        toolTip = Self.toolTipText
        setAccessibilityLabel(Self.toolTipText)
        target = self
        action = #selector(openMenu)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override public var intrinsicContentSize: NSSize { Self.size }

    /// Adds the ⓘ to `window`'s title bar, top-right. Calling it again on the same window updates
    /// and returns the existing button.
    @discardableResult
    public static func install(in window: NSWindow, tour: TourID,
                               shortcuts: [(keys: String, action: String)]) -> InfoButton {
        if let existing = window.titlebarAccessoryViewControllers
            .lazy.compactMap({ $0.view.subviews.first as? InfoButton }).first {
            existing.tour = tour
            existing.shortcuts = shortcuts
            return existing
        }
        let button = InfoButton(tour: tour, shortcuts: shortcuts)
        // A trailing accessory takes its width from the view's frame: give it a real one (UI review
        // E1 — a zero-width accessory is clipped away). 6 pt from the window's right edge.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: size.width + 6, height: size.height))
        button.frame = NSRect(origin: .zero, size: size)
        button.autoresizingMask = [.minYMargin, .maxYMargin]   // stays centred when the title bar sizes it
        container.addSubview(button)
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .trailing
        accessory.view = container
        // Trailing accessories line up right-to-left in list order: index 0 is the rightmost.
        window.insertTitlebarAccessoryViewController(accessory, at: 0)
        return button
    }

    // MARK: - Menu

    /// Opens on press, like any menu button.
    override public func mouseDown(with event: NSEvent) {
        openMenu()
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let replay = NSMenuItem(title: Self.replayTitle, action: #selector(replayTour), keyEquivalent: "")
        replay.image = NSImage(systemSymbolName: "play.circle", accessibilityDescription: nil)
        replay.target = self
        menu.addItem(replay)
        if !shortcuts.isEmpty {
            let keys = NSMenuItem(title: Self.shortcutsTitle, action: #selector(showShortcuts), keyEquivalent: "")
            keys.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)
            keys.target = self
            menu.addItem(keys)
        }
        return menu
    }

    @objc private func openMenu() {
        highlight(true)
        makeMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: isFlipped ? bounds.maxY + 4 : -4), in: self)
        highlight(false)
    }

    @objc func replayTour() {
        TourEvents.replay(tour, in: window)
    }

    @objc func showShortcuts() {
        popover?.close()
        let p = NSPopover()
        p.behavior = .transient
        p.contentViewController = ShortcutsViewController(shortcuts: shortcuts)
        p.show(relativeTo: bounds, of: self, preferredEdge: isFlipped ? .maxY : .minY)
        popover = p
    }
}

/// "Keyboard Shortcuts": a title, then one row per shortcut — action on the left, keys on the right.
final class ShortcutsViewController: NSViewController {
    private let shortcuts: [(keys: String, action: String)]

    init(shortcuts: [(keys: String, action: String)]) {
        self.shortcuts = shortcuts
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() {
        let title = NSTextField(labelWithString: InfoButton.shortcutsTitle)
        title.font = .systemFont(ofSize: 13, weight: .semibold)

        let rows: [[NSView]] = shortcuts.map { item in
            let action = NSTextField(labelWithString: item.action)
            action.font = .systemFont(ofSize: 12)
            action.textColor = .secondaryLabelColor
            let keys = NSTextField(labelWithString: item.keys)
            keys.font = .systemFont(ofSize: 12, weight: .medium)
            keys.alignment = .right
            return [action, keys]
        }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 6
        grid.columnSpacing = 24
        if grid.numberOfColumns == 2 { grid.column(at: 1).xPlacement = .trailing }

        let stack = NSStackView(views: [title, grid])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        let root = NSView()
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
        ])
        root.setFrameSize(root.fittingSize)
        preferredContentSize = root.frame.size
        view = root
    }
}
