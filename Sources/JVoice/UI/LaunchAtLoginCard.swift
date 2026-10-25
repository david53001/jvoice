import AppKit
import SwiftUI

/// A small floating question card in a screen corner, like a macOS notification banner: the app icon,
/// a title, a line of text and up to two buttons. Used once, for "Open JVoice at login?"
/// (`LaunchAtLoginPromptController`). Same card as BetterScreenshot's and MacStats', in JVoice's own
/// native look (`UI/CLAUDE.md`, MacStats `docs/design-language/README.md`).
///
/// It never takes focus: a borderless `.nonactivatingPanel` that can't become key, whose buttons take
/// the first click — so typing in the frontmost app is never interrupted. That also means no keyboard
/// path (Return/Escape have no focus to reach); VoiceOver announces it and can reach the buttons, and
/// the menu's Launch at Login item is the full keyboard alternative. It joins every Space but, per
/// AppKit, not full-screen ones (no `.fullScreenAuxiliary`); the app also waits while anything
/// full-screen is in front, so it isn't put over a presentation.
///
/// Surface: the `.popover` behind-window material (light or dark with the appearance) under a
/// `windowBackgroundColor` tint (`LaunchAtLoginCardColors.tintAlpha`), continuous 16 pt corners, a
/// 0.5 pt hairline and the one system shadow. Slightly transparent, and the tint keeps all text at
/// ≥ 4.5:1 even over a pure black or white desktop (`LaunchAtLoginCardColors`, checked by
/// `scripts/run-logic-tests.sh`). Calling `show` again while it's up replaces the content.
@MainActor
final class LaunchAtLoginCard {
    struct Action {
        var title: String
        var isPrimary: Bool
        var handler: () -> Void

        init(_ title: String, primary: Bool = false, handler: @escaping () -> Void) {
            self.title = title
            self.isPrimary = primary
            self.handler = handler
        }
    }

    static let width: CGFloat = 360
    static let cornerRadius: CGFloat = 16
    /// Distance from the screen's visible frame (below the menu bar, beside the Dock).
    static let screenMargin: CGFloat = 12

    let window: NSPanel
    private let hosting: FirstClickHostingView<LaunchAtLoginCardView>

    init() {
        let panel = LaunchAtLoginCardPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 100),
                                           styleMask: [.nonactivatingPanel, .borderless],
                                           backing: .buffered, defer: false)
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true   // the one soft system shadow of a floating element
        panel.hidesOnDeactivate = false
        panel.canHide = false   // shown while JVoice is in the background — also when it's hidden
        panel.isExcludedFromWindowsMenu = true
        panel.isReleasedWhenClosed = false
        // Not `.fullScreenAuxiliary`: not on full-screen Spaces (a presentation, a shared screen).
        panel.collectionBehavior = [.canJoinAllSpaces]
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .utilityWindow
        hosting = FirstClickHostingView(rootView: LaunchAtLoginCardView(title: "", message: nil, actions: []))
        panel.contentView = hosting
        window = panel
    }

    var isVisible: Bool { window.isVisible }

    /// Shows (or updates in place) the card in the top-right corner of `screen`'s visible frame. No
    /// actions = a confirmation line only. `appearance`: JVoice's System / Light / Dark choice.
    func show(title: String, message: String?, actions: [Action], on screen: NSScreen,
              appearance: NSAppearance?) {
        if window.appearance?.name != appearance?.name { window.appearance = appearance }
        hosting.rootView = LaunchAtLoginCardView(title: title, message: message, actions: actions)
        let size = hosting.fittingSize
        let vf = screen.visibleFrame
        window.setFrame(NSRect(x: vf.maxX - size.width - Self.screenMargin,
                               y: vf.maxY - size.height - Self.screenMargin,
                               width: size.width, height: size.height), display: true)
        window.setAccessibilityLabel(title)
        window.orderFrontRegardless()
        window.invalidateShadow()
        NSAccessibility.post(element: window, notification: .announcementRequested, userInfo: [
            .announcement: [title, message].compactMap { $0 }.joined(separator: " "),
            .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    func hide() {
        window.orderOut(nil)
    }
}

/// Its own class so it is never key: the card must not take focus.
final class LaunchAtLoginCardPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The window is never key, so its buttons must react to the first click.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct LaunchAtLoginCardView: View {
    let title: String
    let message: String?
    let actions: [LaunchAtLoginCard.Action]

    private static let padding: CGFloat = 14
    private static let iconSize: CGFloat = 36

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: message == nil ? .center : .top, spacing: 12) {   // a lone line sits level with the icon
                Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                    .resizable()
                    .frame(width: Self.iconSize, height: Self.iconSize)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                    if let message {
                        // `.primary`, not `.secondary`: the secondary label colour is below 4.5:1 here.
                        Text(message)
                            .font(.callout)
                    }
                }
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !actions.isEmpty {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                        if action.isPrimary {
                            Button(action.title, action: action.handler)
                                .buttonStyle(CardPrimaryButtonStyle())
                        } else {
                            Button(action.title, action: action.handler)
                                .buttonStyle(SubtleButtonStyle())
                        }
                    }
                }
            }
        }
        .padding(Self.padding)
        .frame(width: LaunchAtLoginCard.width)
        .background(CardSurface())
    }
}

/// Behind-window material + the contrast tint + hairline, on a continuous rounded rectangle. (A
/// behind-window effect view ignores clip shapes, so its rounding is a stretchable mask image.)
private struct CardSurface: View {
    private static let mask = VisualEffectBackground.roundedMask(radius: LaunchAtLoginCard.cornerRadius)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: LaunchAtLoginCard.cornerRadius, style: .continuous)
        ZStack {
            VisualEffectBackground(material: .popover, maskImage: Self.mask)
            shape.fill(Color(nsColor: .windowBackgroundColor).opacity(LaunchAtLoginCardColors.tintAlpha))
            shape.strokeBorder(Color.primary.opacity(Design.cardHairline), lineWidth: Design.hairlineWidth)
        }
    }
}

/// The card's primary button: the label colour as the fill, the window background as the text
/// (≈ 14:1 in both appearances), 24 pt tall, continuous radius 6 — the small-button geometry. Not
/// `.borderedProminent`: in a window that is never key, AppKit draws that as an inactive grey button.
private struct CardPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Label(configuration: configuration)
    }

    private struct Label: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: Design.smallButtonHeight)
                .background(
                    RoundedRectangle(cornerRadius: Design.smallButtonRadius, style: .continuous)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.7 : hovering ? 0.85 : 1))
                )
                .contentShape(RoundedRectangle(cornerRadius: Design.smallButtonRadius, style: .continuous))
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
                .onHover { hovering = $0 }
        }
    }
}
