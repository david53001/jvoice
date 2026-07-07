# Privacy Policy

**Effective date:** 7 July 2026 · Applies to JVoice for macOS and Windows.

> **In one sentence:** JVoice does its speech recognition **entirely on your own device**,
> collects **no personal data**, has **no accounts, telemetry, or analytics**, and the only
> times it ever touches the network are a one-time model download and an optional update
> check — neither of which sends any of your data anywhere.

This is the whole policy. It's short because JVoice is built to keep your voice on your
machine.

---

## What JVoice does with your voice

When you press the dictation hotkey, JVoice records audio from your microphone, transcribes
it locally using an on-device [Whisper](https://github.com/openai/whisper) model, styles the
text, and pastes the result into whatever app has focus.

- **Your audio never leaves your device.** It is transcribed by a model running locally on
  your CPU or GPU. It is **not** uploaded, streamed, or sent to us or to any third party.
- **The recording is temporary.** JVoice writes the audio to a temporary WAV file only long
  enough to transcribe it, then deletes it. It sweeps up any leftover recordings on startup.
- **Transcripts stay on your machine.** On Windows, JVoice keeps a short **local history**
  of your recent transcripts (the last few dozen) so you can copy one back — this is stored
  only on your computer and you can clear it any time from Settings. It is never transmitted.

## What we collect

**Nothing.** JVoice has:

- no user accounts and no sign-in;
- no telemetry, analytics, crash reporting, or usage tracking;
- no advertising and no cookies;
- no server that receives your data — the project doesn't operate one.

We (the JVoice authors) never see your audio, your transcripts, your settings, your custom
words, or the fact that you used the app at all.

## The only times JVoice uses the network

JVoice is designed to run fully offline. There are exactly two exceptions, and neither sends
your personal data:

1. **One-time model download (required, first run).** The first time you pick a Whisper
   model, JVoice downloads that model file from **Hugging Face**, a public file host:
   - Windows: from `huggingface.co/ggerganov/whisper.cpp`
   - macOS: from `huggingface.co/argmaxinc/whisperkit-coreml`

   This is an ordinary file download. It sends no audio and no personal information — only
   the standard request needed to fetch a public file. Once the model is on disk,
   transcription is completely offline. Hugging Face's own privacy practices apply to that
   request; see <https://huggingface.co/privacy>.

2. **Update check (Windows only, optional, can be turned off).** If enabled, JVoice
   occasionally asks GitHub whether a newer release exists, by requesting the public
   "latest release" endpoint for the project
   (`api.github.com/repos/david53001/jvoice/releases/latest`). This is an anonymous read
   that sends **no user data** — just the request needed to read a public release listing.
   You can disable it in **Settings → Updates** ("Check for updates"); when off, JVoice
   makes this call **never**. GitHub's privacy statement applies to that request; see
   <https://docs.github.com/site-policy/privacy-policies/github-privacy-statement>.

That's it. There are no other outbound connections during normal use.

## Permissions JVoice asks for, and why

- **Microphone** — to hear you while you dictate. Audio is used only for local
  transcription.
- **Paste / accessibility** — to type the transcribed text into the app you're using
  (macOS **Accessibility**; on Windows, sending keystrokes to the focused window). JVoice
  does not read your screen or the contents of other apps.

You can revoke either permission at any time in your operating-system settings.

## Where your data is stored on your device

Everything JVoice keeps lives in your normal per-user app-data location and never leaves it:

- **macOS:** the app's preferences (system `UserDefaults`, namespace `jvoice.app.*`) and
  the downloaded Whisper model cache under `~/Documents/huggingface/`.
- **Windows:** settings, stats, and the recent-transcript history in `%APPDATA%\JVoice`;
  the downloaded model cache in `%LOCALAPPDATA%\JVoice\models`.

Deleting the app and these folders removes everything JVoice stored.

## Children's privacy

JVoice collects no personal information from anyone, including children. It is a local
utility with no accounts and no data collection.

## Changes to this policy

If this policy changes, the current version will always be in this file in the repository,
with its effective date at the top. Because JVoice collects nothing, changes will typically
just reflect new features. Past versions are visible in the project's git history.

## Contact

JVoice is developed in the open. Privacy questions can be raised as an issue on the project's
GitHub repository: <https://github.com/david53001/jvoice>.
