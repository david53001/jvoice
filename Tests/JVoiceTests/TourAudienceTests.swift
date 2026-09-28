// Who gets tours (Sources/JVoice/Tours/Kit/TourAudience.swift + TourCoordinator.classifyAudienceIfNeeded).
// The owner's key requirement: an EXISTING user must never get the tour — any sign the app ran before
// (a non-tour preference key, a granted permission, an unexpected bundle id) classifies as existing.
// This suite is the authority (CI); `scripts/run-logic-tests.sh` (the "Tours" section) mirrors the pure
// cases as the local smoke check — change both.
#if canImport(Testing)
import Foundation
import Testing
@testable import JVoice

private func signals(keys: Set<String> = [], granted: Bool = false,
                     bundle: String? = "com.jvoice.app") -> TourAudience.Signals {
    TourAudience.Signals(preferenceKeys: keys, permissionGranted: granted, bundleIdentifier: bundle)
}

/// Keys a real JVoice install writes (UserDefaults namespace `jvoice.app.*` + AppKit's own).
private let jvoiceKeys: Set<String> = [
    "jvoice.app.settings.state", "jvoice.app.stats", "jvoice.app.lastTranscript", "jvoice.app.transcriptHistory",
    "KeyboardShortcuts_toggleRecording", "NSStatusItem Visible Item-0", "NSStatusItem Preferred Position Item-0",
    "NSWindow Frame SettingsWindow",
]

@Suite struct TourAudienceTests {
    @Test func knownBundleIdIsJVoices() {
        #expect(TourAudience.knownBundleIdentifier == "com.jvoice.app")
    }

    @Test func emptyDomainNoPermissionKnownBundleIsNew() {
        #expect(TourAudience.classify(signals()) == .new)
    }

    @Test func onlyTourKeysIsNew() {
        #expect(TourAudience.classify(signals(keys: TourPreferenceKey.all)) == .new)
        #expect(TourAudience.classify(signals(keys: [TourPreferenceKey.audience])) == .new)
    }

    @Test func aRealInstallsKeysAreExisting() {
        #expect(TourAudience.classify(signals(keys: jvoiceKeys)) == .existing)
        #expect(TourAudience.classify(signals(keys: jvoiceKeys.union(TourPreferenceKey.all))) == .existing)
        #expect(TourAudience.classify(signals(keys: TourPreferenceKey.all.union(["jvoice.app.settings.state"]))) == .existing)
    }

    @Test(arguments: jvoiceKeys.union(["anythingElse"]).sorted())
    func anySingleNonTourKeyIsExisting(_ key: String) {
        #expect(TourAudience.classify(signals(keys: [key])) == .existing)
    }

    @Test func permissionAlreadyGrantedIsExisting() {
        #expect(TourAudience.classify(signals(granted: true)) == .existing)
        #expect(TourAudience.classify(signals(keys: TourPreferenceKey.all, granted: true)) == .existing)
    }

    @Test(arguments: [nil, "", "com.jvoice.JVoice", "com.JVoice.app"] as [String?])
    func unknownOrMissingBundleIdIsExisting(_ bundle: String?) {
        #expect(TourAudience.classify(signals(bundle: bundle)) == .existing)
    }

    @Test func storedValueRoundTripsAndJunkIsExisting() {
        #expect(TourAudience(stored: nil) == nil)
        for a in [TourAudience.new, .existing] { #expect(TourAudience(stored: a.rawValue) == a) }
        for junk in ["New", "NEW", "", " new", "yes", "true", "1"] {
            #expect(TourAudience(stored: junk) == .existing, "\(junk)")
        }
    }

    @Test func tourKeysAreExactlyTheFiveAndOnlyTheyAreIgnored() {
        #expect(TourPreferenceKey.all == ["tourAudience", "tourQuestionAnswered", "firstUseToursEnabled", "toursSeen", "toursPaused"])
        #expect(TourAudience.ignoredKeys == TourPreferenceKey.all)
        #expect(TourPreferenceKey.all.allSatisfy { !$0.hasPrefix("jvoice.app.") })
    }
}

/// `TourCoordinator.classifyAudienceIfNeeded` against a real (throwaway) UserDefaults domain: it reads
/// only that domain, stores the verdict once, and never re-classifies.
@MainActor
@Suite struct TourAudienceClassificationTests {
    private func withDomain(_ body: (UserDefaults, String) -> Void) {
        let name = "jvoice.test.tours.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        body(defaults, name)
    }

    @Test func aFreshDomainIsNewAndTheVerdictIsStored() {
        withDomain { d, name in
            let a = TourCoordinator.classifyAudienceIfNeeded(defaults: d, domainName: name,
                                                             bundleIdentifier: "com.jvoice.app", permissionGranted: false)
            #expect(a == .new)
            #expect(d.string(forKey: TourPreferenceKey.audience) == "new")
        }
    }

    @Test func anExistingInstallIsExisting() {
        withDomain { d, name in
            d.set(Data(), forKey: "jvoice.app.settings.state")
            let a = TourCoordinator.classifyAudienceIfNeeded(defaults: d, domainName: name,
                                                             bundleIdentifier: "com.jvoice.app", permissionGranted: false)
            #expect(a == .existing)
            #expect(d.string(forKey: TourPreferenceKey.audience) == "existing")
        }
    }

    @Test func aGrantedPermissionOrForeignBundleIsExisting() {
        withDomain { d, name in
            #expect(TourCoordinator.classifyAudienceIfNeeded(defaults: d, domainName: name,
                                                             bundleIdentifier: "com.jvoice.app", permissionGranted: true) == .existing)
        }
        withDomain { d, name in
            #expect(TourCoordinator.classifyAudienceIfNeeded(defaults: d, domainName: name,
                                                             bundleIdentifier: nil, permissionGranted: false) == .existing)
        }
    }

    @Test func theStoredVerdictWinsOnLaterLaunches() {
        withDomain { d, name in
            _ = TourCoordinator.classifyAudienceIfNeeded(defaults: d, domainName: name,
                                                         bundleIdentifier: "com.jvoice.app", permissionGranted: false)
            d.set(Data(), forKey: "jvoice.app.settings.state")   // the new user now uses the app
            #expect(TourCoordinator.classifyAudienceIfNeeded(defaults: d, domainName: name,
                                                             bundleIdentifier: "com.jvoice.app", permissionGranted: true) == .new)
        }
        withDomain { d, name in
            d.set("existing", forKey: TourPreferenceKey.audience)
            #expect(TourCoordinator.classifyAudienceIfNeeded(defaults: d, domainName: name,
                                                             bundleIdentifier: "com.jvoice.app", permissionGranted: false) == .existing)
        }
    }
}
#endif
