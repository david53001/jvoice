import Foundation

/// Which window JVoice opens when it starts and when its Dock icon is clicked (since 1.4.0, when
/// JVoice became a Dock app). Pure, so `scripts/run-logic-tests.sh` covers it; `AppDelegate` reads the
/// inputs and does the opening.
///
/// - At launch: a new user who hasn't answered "Want a quick tour?" gets the Welcome window (as
///   before, also when that launch was at login: quitting with it open asks again next launch).
///   Otherwise a launch at login opens nothing — the app just sits in the Dock with the shortcut
///   ready — and a launch the user started (Finder, Launchpad, Spotlight, `open`, a Sparkle relaunch)
///   shows Settings, so opening the app visibly does something.
/// - Dock click / launching it again while it runs: Settings, or the Welcome window while that is
///   still on screen (first run), so nothing opens on top of it.
enum LaunchWindowPolicy {
    enum Window: Equatable {
        case welcome
        case settings
        case none
    }

    static func atLaunch(showWelcome: Bool, launchedAsLoginItem: Bool) -> Window {
        if showWelcome { return .welcome }
        return launchedAsLoginItem ? .none : .settings
    }

    static func onReopen(welcomeVisible: Bool) -> Window {
        welcomeVisible ? .welcome : .settings
    }

    /// `kAEOpenApplication` ('oapp'), the event that launches an app.
    static let openApplicationEvent: UInt32 = 0x6F61_7070
    /// `keyAELaunchedAsLogInItem` ('lgit'): the open-application event's `keyAEPropData` when the
    /// system opened the app as a login item (also for `SMAppService.mainApp`, which can't pass
    /// launch arguments — this is the one signal there is).
    static let loginItemProperty: UInt32 = 0x6C67_6974

    /// Whether the launch Apple Event (`NSAppleEventManager.shared().currentAppleEvent` during
    /// `applicationDidFinishLaunching`) says "opened at login". No event or no property = the user.
    static func isLoginItemLaunch(eventID: UInt32?, launchProperty: UInt32?) -> Bool {
        eventID == openApplicationEvent && launchProperty == loginItemProperty
    }
}
