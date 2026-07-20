# JVoice.Tests — the brain's lock

xUnit suite (865 tests) that pins `JVoice.Core` to the macOS Swift behavior. Each `*Tests.cs`
mirrors a Swift test file; the constants are asserted verbatim. White-box access to internal
helpers is granted via `InternalsVisibleTo("JVoice.Tests")` in `JVoice.Core.csproj` (mirrors
Swift's `@testable import`).

## Mapping (test → area)
- **Text brain** → TextProcessorTests, PhoneticMatcherTests, VocabularyPromptTests,
  RepetitionGuardTests, RegurgitationRecoveryTests, NonSpeechAnnotationTests, DeveloperTermsTests,
  UserCorrectionsTests.
- **Audio / streaming** → StreamingSessionTests, ChunkPlannerTests, WavTailTests,
  HighPassSilenceTests, BluetoothDevicePolicyTests.
- **Policy** → CoordinatorDecisionsTests, HotkeyGateTests, GameDetectionPolicyTests, StatsMathTests,
  WhisperTuningTests, SilenceHallucinationGateTests, TailCoverageGuardTests, PhraseLoopGuardTests,
  SparseTranscriptGuardTests, ReleaseVersionTests, UpdateCheckTests, UpdateProgressCurveTests.
- **Models / persistence** → ModelTests, SettingsStateTests, SettingsStoreJsonTests,
  HotkeyChordTests, HudStateTests, TranscriptHistoryTests.
- **Engine seam** → FileBackedEngineTests.

## Run
`dotnet test windows/JVoice.Tests/JVoice.Tests.csproj -c Release`. If you change a Core constant,
the matching test must change in the **same commit** — otherwise you've silently diverged from
macOS.
