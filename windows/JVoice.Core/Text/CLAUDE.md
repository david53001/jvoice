# Core / Text — custom-word accuracy & anti-hallucination pipeline

The layered defense that makes dictation get "Li-Fraumeni" / "VS Code" right **without** letting
the decoder hallucinate or loop. Ported 1:1 from macOS; every constant is test-locked.

## Key files
- `VocabularyPrompt.cs` — builds the decoder-conditioning prompt from the user's custom words
  (the main accuracy lever; kept ON by default).
- `RepetitionGuard.cs` — detects/strips "prompt regurgitation" (the decoder reciting the vocab
  list on pauses/silence); flags it via `scrub`.
- `RegurgitationRecovery.cs` — re-decodes the same audio *without* the prompt **only when** a
  decode regurgitated or returned empty. Keeps prompt accuracy in the common case while making
  the loop/insertion/drop failure mode unreachable.
- `NonSpeechAnnotation.cs` — maps whisper's `[BLANK_AUDIO]` / `(birds chirping)` annotations to
  empty ⇒ "No speech detected". **This replaced the old RMS pre-gate** — whisper itself decides.
  Do NOT re-add an RMS/energy gate (root `CLAUDE.md` §7 #21; memory `win-mic-low-capture-level`).
- `TextProcessor.cs` — tone styles, filler removal, exact custom-word corrections,
  hallucination-sentinel stripping.
- `PhoneticMatcher.cs` — fuzzy sound-alike correction ("jay voice" → "JVoice").
- `UserCorrections.cs`, `DeveloperTerms.cs` — correction-rule data.

## Invariants / traps
- Constants are ported verbatim from macOS and asserted by tests — don't tune them blind.
- Never re-introduce an RMS/spectral no-speech gate. No-speech is model-driven now.

## Verify
`dotnet test windows/JVoice.Tests` — TextProcessorTests, PhoneticMatcherTests,
VocabularyPromptTests, RepetitionGuardTests, RegurgitationRecoveryTests,
NonSpeechAnnotationTests, DeveloperTermsTests, UserCorrectionsTests.
