#if canImport(Testing)
import Testing
@testable import JVoice

@Test func startIsAllowedWhenIdle() {
    #expect(CoordinatorDecisions.canStartRecording(isStartingRecording: false, isTranscribing: false))
}

@Test func startIsRefusedWhileAStartIsAlreadyOpeningTheMic() {
    #expect(!CoordinatorDecisions.canStartRecording(isStartingRecording: true, isTranscribing: false))
}

/// Windows §7 #44: a press ~300 ms after the stop press must never cancel the
/// finished dictation that is still being transcribed.
@Test func pendingTranscriptOutranksANewStart() {
    #expect(!CoordinatorDecisions.canStartRecording(isStartingRecording: false, isTranscribing: true))
    #expect(!CoordinatorDecisions.canStartRecording(isStartingRecording: true, isTranscribing: true))
}

@Test func pressWhenIdleStarts() {
    #expect(CoordinatorDecisions.pressAction(isRecording: false, isStartingRecording: false,
                                             isStoppingRecording: false, isTranscribing: false) == .start)
}

@Test func pressWhileRecordingStops() {
    #expect(CoordinatorDecisions.pressAction(isRecording: true, isStartingRecording: false,
                                             isStoppingRecording: false, isTranscribing: false) == .stop)
    // Both flags are briefly true at the end of a start: the mic is open, so stop.
    #expect(CoordinatorDecisions.pressAction(isRecording: true, isStartingRecording: true,
                                             isStoppingRecording: false, isTranscribing: false) == .stop)
}

@Test func pressWhileAStopIsRunningIsIgnored() {
    #expect(CoordinatorDecisions.pressAction(isRecording: true, isStartingRecording: false,
                                             isStoppingRecording: true, isTranscribing: false) == .ignore)
}

/// A stop press while the mic is still opening used to be dropped, leaving the
/// user recording after they pressed stop.
@Test func pressWhileTheMicIsOpeningStopsOnceItOpens() {
    #expect(CoordinatorDecisions.pressAction(isRecording: false, isStartingRecording: true,
                                             isStoppingRecording: false, isTranscribing: false) == .stopOnceOpened)
}

@Test func pressWhileTranscribingIsIgnored() {
    #expect(CoordinatorDecisions.pressAction(isRecording: false, isStartingRecording: false,
                                             isStoppingRecording: false, isTranscribing: true) == .ignore)
}
#endif
