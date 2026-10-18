# Privacy Policy

**Effective date:** 18 October 2026 · Applies to JVoice for macOS and Windows.

> **In one sentence:** JVoice does its speech recognition **entirely on your own device**,
> collects **no personal data**, has **no accounts, telemetry, or analytics**, and the only
> times it ever touches the network are a one-time model download and an optional update
> check — neither of which sends any of your data anywhere — plus **AI Polish** (macOS, from
> version 1.3.0), which is **off by default** and sends the text of your dictations to Anthropic
> only after you turn it on and add your own Anthropic API key.

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
- **Transcripts stay on your machine** — unless you turn on AI Polish (below), which sends the
  text of each dictation to Anthropic. JVoice keeps a short **local history** of your recent
  transcripts (the last few dozen) so you can copy one back — this is stored only on your
  computer and you can clear it any time from Settings. The history itself is never transmitted.

## What we collect

**Nothing.** JVoice has:

- no user accounts and no sign-in;
- no telemetry, analytics, crash reporting, or usage tracking;
- no advertising and no cookies;
- no server that receives your data — the project doesn't operate one.

We (the JVoice authors) never see your audio, your transcripts, your settings, your custom
words, or the fact that you used the app at all.

## The only times JVoice uses the network

JVoice is designed to run fully offline. There are exactly three exceptions. The first two
send none of your data; the third sends your dictated text, and only if you turn it on:

1. **One-time model download (required, first run).** The first time you pick a Whisper
   model, JVoice downloads that model file from **Hugging Face**, a public file host:
   - Windows: from `huggingface.co/ggerganov/whisper.cpp`
   - macOS: from `huggingface.co/argmaxinc/whisperkit-coreml`

   This is an ordinary file download. It sends no audio and no personal information — only
   the standard request needed to fetch a public file. Once the model is on disk,
   transcription is completely offline. Hugging Face's own privacy practices apply to that
   request; see <https://huggingface.co/privacy>.

2. **Update check (optional, can be turned off).** JVoice occasionally asks GitHub whether a
   newer release exists, and downloads it only when there is one:
   - Windows: requests the public release listing for the project
     (`api.github.com/repos/david53001/jvoice/releases`). Turn it off in **Settings → Updates**
     ("Check for updates").
   - macOS (from version 1.2.0): about once a day, the built-in updater (Sparkle) reads the public
     file `github.com/david53001/jvoice/releases/latest/download/appcast.xml`, which names the newest
     version. If there is a newer one and you choose to install it, the update is downloaded from the
     same GitHub release and checked against JVoice's signing key before it is installed. Turn the
     daily check off in **Settings → Updates** ("Check Automatically"); **Check for Updates…** in the
     menu then checks only when you click it.

   These are anonymous reads of public files. They send **no user data** — no audio, transcripts,
   settings or system profile; only the standard request (which, like any download, includes the
   app's name and version). When the check is off, JVoice makes this call **never** (on macOS:
   only when you click Check for Updates…). GitHub's privacy statement applies to these requests; see
   <https://docs.github.com/site-policy/privacy-policies/github-privacy-statement>.

3. **AI Polish (macOS only, from version 1.3.0; off by default; uses your own key).**
   - **When:** only while all of these are true: you turned on **Settings → AI Polish → Polish
     with Claude**, you saved your own Anthropic API key, and the AI Polish balance you set in
     Settings is above $0. Then it happens once per finished dictation of three words or more
     (shorter ones are never sent). Nothing is sent while it is off, which is how JVoice starts.
     **Test Key** in Settings sends one tiny test message ("Hi") with the key, and nothing else.
   - **What:** the dictation's **text** (never the audio), after JVoice's own clean-up, goes to
     **Anthropic's Claude API** (`api.anthropic.com`) to fix punctuation and misheard words,
     together with your tone setting, your custom words and up to three of your previous
     dictations into the same app from the last 10 minutes (kept only in memory, never saved,
     forgotten when you turn AI Polish off). Your API key travels in the request header, as
     Anthropic requires; like any web request, Anthropic also sees your IP address. Anthropic's
     privacy policy applies to that request; see <https://www.anthropic.com/legal/privacy>.
   - **Who sees it:** the request goes straight from your Mac to Anthropic with your key — the
     JVoice authors never see it. If anything goes wrong (offline, bad key, no reply within
     3 seconds) JVoice pastes its own local text instead.
   - **Your key** is stored in one file on your Mac that only your user account can open
     (`~/Library/Application Support/JVoice/anthropic-api-key`, left out of Time Machine backups,
     never synced), and is never written to settings, history, logs or the clipboard. Three honest
     limits: anyone using your unlocked Mac can open Settings and reveal the key with the eye
     button; other software running under your user account could read that file (the same way
     developer tools such as the `aws` and `anthropic` command-line tools keep their keys), so set
     a spend limit on the key in the Anthropic console; and while AI Polish is on, what you
     dictate is read by Anthropic. Turn it off and none of your dictations leave your Mac.

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
  the downloaded Whisper model cache under `~/Documents/huggingface/`. If you saved an
  Anthropic key for AI Polish, it is in `~/Library/Application Support/JVoice/anthropic-api-key`;
  **Settings → AI Polish → Remove Key** deletes it.
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
