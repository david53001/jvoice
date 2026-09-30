import AppKit
import Combine
import SwiftUI

/// The live Opacity value (`UIOpacity`), persisted under `UIOpacity.defaultsKey`. One shared instance:
/// the Settings slider writes it and every surface observes it, so a change applies at once to every
/// open window and pill. (Not `@AppStorage`: it observes UserDefaults by KVO, which reads the dots in the key as a key path — and AppKit views need a publisher anyway.)
@MainActor
final class UIOpacityStore: ObservableObject {
    static let shared = UIOpacityStore()

    @Published var value: Double {
        didSet { if persists { defaults.set(value, forKey: UIOpacity.defaultsKey) } }
    }

    private let defaults: UserDefaults
    /// False in `--ui-preview`, which shows other values without ever writing a setting.
    var persists = true

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        value = UIOpacity.stored(in: defaults)
    }

    func backingAlpha(on surface: UIOpacity.Surface) -> Double {
        UIOpacity.backingAlpha(value, on: surface)
    }
}

/// The solid backing laid over a window's material (`WindowMaterial`) or the tour tag's: the window
/// background colour at the Opacity's alpha, following the setting live and the view's Light/Dark.
final class OpacityBackingView: NSView {
    private let surface: UIOpacity.Surface
    private var alpha: CGFloat = 0
    private var subscription: AnyCancellable?

    /// `cornerRadius`: continuous corners for a shaped surface (the tour tag); 0 for a window, whose
    /// frame already rounds it.
    @MainActor
    init(surface: UIOpacity.Surface, cornerRadius: CGFloat = 0) {
        self.surface = surface
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        subscription = UIOpacityStore.shared.$value.sink { [weak self] value in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.alpha = CGFloat(UIOpacity.backingAlpha(value, on: self.surface))
                self.updateColour()
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isOpaque: Bool { false }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { updateColour() }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColour()
    }
    /// Clicks and drags go to whatever is under it (it only paints).
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func updateColour() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(alpha).cgColor
        }
    }
}

/// The same backing for SwiftUI surfaces (the HUD pill), in the environment's Light/Dark.
struct OpacityBacking<S: Shape>: View {
    let surface: UIOpacity.Surface
    let shape: S
    @ObservedObject private var store = UIOpacityStore.shared

    var body: some View {
        shape.fill(Color(nsColor: .windowBackgroundColor).opacity(store.backingAlpha(on: surface)))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
