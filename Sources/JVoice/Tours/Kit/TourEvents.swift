import AppKit

/// The one-way line from the app's surfaces to the tour system. Surfaces call `post` /
/// `surfaceShown` at the moments tours care about; the app's `TourCoordinator` sets the handlers.
/// With no handler set (tests, probes, tours off) every call is a no-op, so posting is always safe.
@MainActor
public enum TourEvents {
    public static var onEvent: ((TourEvent) -> Void)?
    public static var onSurfaceShown: ((TourSurface, NSWindow) -> Void)?
    public static var onReplayRequested: ((TourID, NSWindow?) -> Void)?
    public static var onResetRequested: (() -> Void)?

    public static func post(_ event: TourEvent) { onEvent?(event) }

    /// Call right after a surface's window is on screen.
    public static func surfaceShown(_ surface: TourSurface, in window: NSWindow) {
        onSurfaceShown?(surface, window)
    }

    /// The ⓘ button's "Replay Tour" (or the Help & Tours menu): run `tour` again now, in `window`
    /// (nil from the menu bar — the coordinator then starts it when its surface next appears).
    public static func replay(_ tour: TourID, in window: NSWindow?) {
        onReplayRequested?(tour, window)
    }

    /// Help & Tours → Reset All Tours, or Settings → Tours & Tips → Reset All Tours. Clears
    /// `toursSeen` / `toursPaused` only (never the audience) and confirms in the HUD.
    public static func resetAll() { onResetRequested?() }
}

/// The one user-facing tour preference, for Settings → "Tours & Tips" (read/write straight to
/// UserDefaults; the coordinator reads the same key each time it decides).
@MainActor
public enum TourSettings {
    public static var defaults: UserDefaults = .standard

    /// "Show me around the first time I use each part". Absent = off (existing users never opted in).
    public static var firstUseToursEnabled: Bool {
        get { defaults.bool(forKey: TourPreferenceKey.firstUseToursEnabled) }
        set { defaults.set(newValue, forKey: TourPreferenceKey.firstUseToursEnabled) }
    }
}
