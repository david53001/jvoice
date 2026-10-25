#if canImport(Testing)
import CoreServices
import Testing
@testable import JVoice

/// Which window a launch / a Dock click opens since JVoice became a Dock app (1.4.0), and how a launch
/// at login is told apart. Mirrored locally by the "Launch-at-login prompt" section of
/// `scripts/run-logic-tests.sh` (this suite only runs in CI).
@Suite struct LaunchWindowPolicyTests {
    typealias Policy = LaunchWindowPolicy

    @Test func launchOpensSettingsUnlessAtLoginRestoredOrFirstRun() {
        #expect(Policy.atLaunch(showWelcome: false, launchedAsLoginItem: false, isDefaultLaunch: true) == .settings)
        #expect(Policy.atLaunch(showWelcome: false, launchedAsLoginItem: true, isDefaultLaunch: true) == .noWindow)
        #expect(Policy.atLaunch(showWelcome: false, launchedAsLoginItem: false, isDefaultLaunch: false) == .noWindow)
        #expect(Policy.atLaunch(showWelcome: false, launchedAsLoginItem: true, isDefaultLaunch: false) == .noWindow)
        #expect(Policy.atLaunch(showWelcome: true, launchedAsLoginItem: false, isDefaultLaunch: true) == .welcome)
        #expect(Policy.atLaunch(showWelcome: true, launchedAsLoginItem: true, isDefaultLaunch: true) == .welcome)
        #expect(Policy.atLaunch(showWelcome: true, launchedAsLoginItem: false, isDefaultLaunch: false) == .welcome)
    }

    @Test func dockClickOpensSettingsOrBringsWelcomeForward() {
        #expect(Policy.onReopen(welcomeVisible: false) == .settings)
        #expect(Policy.onReopen(welcomeVisible: true) == .welcome)
    }

    @Test func loginItemLaunchComesFromTheLaunchAppleEvent() {
        let oapp = UInt32(kAEOpenApplication), lgit = UInt32(keyAELaunchedAsLogInItem)
        #expect(Policy.openApplicationEvent == oapp)
        #expect(Policy.loginItemProperty == lgit)
        #expect(Policy.isLoginItemLaunch(eventID: oapp, launchProperty: lgit))
        #expect(!Policy.isLoginItemLaunch(eventID: oapp, launchProperty: nil))
        #expect(!Policy.isLoginItemLaunch(eventID: oapp, launchProperty: UInt32(keyAELaunchedAsServiceItem)))
        #expect(!Policy.isLoginItemLaunch(eventID: UInt32(kAEReopenApplication), launchProperty: lgit))
        #expect(!Policy.isLoginItemLaunch(eventID: nil, launchProperty: nil))
    }
}
#endif
