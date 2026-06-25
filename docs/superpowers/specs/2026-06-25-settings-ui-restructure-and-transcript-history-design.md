# Settings UI restructure + 30-transcript history — design

**Date:** 2026-06-25
**Status:** Approved (design decisions confirmed with David via Q&A on 2026-06-25)
**Area:** `Sources/JVoice/UI/` (SettingsView) + `Sources/JVoice/Services/Orchestration/` (transcript store) + `Sources/JVoice/VoiceCoordinator.swift`

## Background

JVoice is a macOS menu-bar voice-dictation app. Its Settings window (`Sources/JVoice/UI/SettingsView.swift`)
is a single vertically-scrolling column of styled "DarkSection" cards. The window is a fixed
`320 × 520` points, hosted by `SettingsWindow.swift` (an `NSWindow` whose `contentRect` is also
`320 × 520`).

Today the window keeps only **one** transcript: the most recent. It is held as the
`@Published var lastTranscript: String` on `VoiceCoordinator` and persisted as a single string in
`UserDefaults` (key `jvoice.app.lastTranscript`) via `LastTranscriptStore`. In the UI it is shown in
an **editable** `TextEditor` box with three buttons — **Fix** (extracts the user's edits and adds them
as custom words — the app's accuracy-teaching mechanism), **Revert**, **Clear**.

The transcript text is intentionally persisted across launches (loaded in `VoiceCoordinator.init`) and
is only erased by **explicit** user action — the "Restore Default Settings" button (which calls
`clearLastTranscript()`) and the "Clear" button. App termination (`cleanUpForTermination()`) does NOT
clear it; its privacy cleanup only removes orphaned recording WAVs. Statistics are separate and are
NOT affected by Restore Defaults.

## Goals (what David asked for)

1. **Window a little wider, same height.** → `380 × 520` (was `320 × 520`).
2. **Statistics moved to the top** of the window (just under the header).
3. **Last-transcript section becomes a list of up to the 30 most recent transcripts**, shown as a
   compact list of one-line rows — **not** a tall editable box (a box "would take too much space").
4. **Model, Processing (Remove Filler Words), Voice Style, and Language move *under* the transcript
   list**, in that order.
5. **Custom Words stays toward the bottom.**
6. **The Restore Defaults + Quit row stays pinned at the very bottom** (unchanged).
7. **Keyboard-shortcut control placed where it reads best**, keeping the existing card style.
8. **Persist the 30 transcripts efficiently** — low memory/disk footprint.

## Confirmed design decisions

- **Transcript list behavior:** *read-only* rows. Each row shows the transcript text on one line
  (truncated with `…`). Hovering a row reveals a **Copy** button (copies that transcript to the
  clipboard) and an **✕** to delete just that row. A **Clear all** affordance empties the list.
  The inline **Fix/Revert** editing is **removed from the UI** — the user can still teach custom words
  through the existing **Custom Words** box. (The coordinator's `fixLastTranscript`/`revertLastFix`
  methods are kept intact, just no longer surfaced, because they are covered by CI tests and removing
  them is out of scope.)
- **Window width:** `380` points.
- **Keyboard-shortcut placement:** its own compact "Keyboard Shortcut" card placed just **above** the
  Restore/Quit row (after Custom Words) — it is set-once config, so it sits naturally next to the
  app-level actions at the bottom.

## New top-to-bottom layout

1. Header (`JVoice` + subtitle) — unchanged.
2. **Stats** card (total words / avg WPM) — moved here from the bottom.
3. **Recent Transcripts** card — the new list (see below).
4. **Whisper Model** card.
5. **Processing** card (Remove Filler Words toggle).
6. **Voice Style** card (tone).
7. **Language** card.
8. **Custom Words** card.
9. **Keyboard Shortcut** card.
10. Restore Default Settings + Quit JVoice row (pinned bottom) — unchanged.

All cards keep the existing `DarkSection` styling, palette, and button styles. The whole column stays
inside the existing `ScrollView`.

## Data model & storage

A new value type and store, living in `Sources/JVoice/Services/Orchestration/`:

```swift
struct TranscriptEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let text: String
}
```

`TranscriptHistoryStore` (new file `TranscriptHistoryStore.swift`):

- Persists `[TranscriptEntry]` as JSON in `UserDefaults` under key `jvoice.app.transcriptHistory`.
- Caps the list at **30** entries (newest first; appending past 30 drops the oldest).
- API: `entries` (get), `add(_ text:)` → prepends a new entry and trims to 30, `remove(id:)`,
  `clear()`.

**Why this is memory/disk-efficient:** 30 short dictation snippets is on the order of a few kilobytes.
`UserDefaults` is disk-backed (a `plist` under `~/Library/Preferences`) and lazily loaded, so nothing
heavy is kept resident. This also matches the existing `LastTranscriptStore` pattern and inherits the
same privacy posture (plaintext in prefs, cleared by explicit user action). No new file/database
machinery is warranted (YAGNI).

## Coordinator wiring (`VoiceCoordinator`)

- Add `@Published private(set) var recentTranscripts: [TranscriptEntry] = []`, seeded from the store
  in `init`.
- On a successful transcription (the existing success path around line 544): in addition to today's
  `lastTranscript`/`LastTranscriptStore` update, call `transcriptHistoryStore.add(processed)` and
  refresh `recentTranscripts`.
- `clearLastTranscript()` (called by Restore Defaults) **also** clears the history store and
  `recentTranscripts`, keeping the privacy guarantee that "Restore Defaults wipes stored transcripts".
- New methods for the UI:
  - `deleteTranscript(_ id: UUID)` → store `remove` + refresh.
  - `clearTranscriptHistory()` → store `clear` + refresh.
  - `copyToClipboard(_ text: String)` → `NSPasteboard.general` set string.
- `lastTranscript` and the old `LastTranscriptStore`/Fix/Revert paths are left functionally intact to
  avoid touching tested behavior; they are simply no longer the UI's primary surface.

## Recent Transcripts card UI

- If empty: "No transcripts yet." placeholder (matches existing empty-state styling).
- Otherwise: a bounded `ScrollView` (≈140pt max height, like the Custom Words list's `maxHeight: 88`)
  of rows. Each row: `Text(entry.text)` with `.lineLimit(1)` + `.truncationMode(.tail)`, and on the
  trailing side a Copy button (`doc.on.doc`) and a delete button (`xmark`/`minus.circle.fill`) shown
  on hover. Newest first.
- A small **Clear all** text button in the card header area (or top-right of the card body), disabled
  when the list is empty.

## Error handling

No new failure modes. `UserDefaults` JSON decode failures fall back to an empty list (treated as "no
history"), exactly as a fresh install. Copy/delete are local, synchronous, and cannot fail in a way
the user needs to see.

## Testing / verification

- `swift build` must pass (primary gate on this machine).
- `./scripts/run-logic-tests.sh` and `./scripts/verify-streaming.sh` must still pass (no logic-path
  changes, but run them to confirm no regression).
- No automated visual test exists for the Settings window — verify layout by eye after building and
  launching the app (`./scripts/install.sh` builds release, signs, installs to /Applications, then
  launch and confirm it is the running JVoice).
- If a lightweight unit test fits the existing CI suite, add one for `TranscriptHistoryStore`
  (add/cap-at-30/remove/clear round-trip) — pure logic, no WhisperKit/mic.

## Out of scope

- Re-pasting an old transcript into the frontmost app (clipboard Copy only).
- Timestamps / search / per-row Fix editing.
- Removing the now-unsurfaced Fix/Revert coordinator methods.
