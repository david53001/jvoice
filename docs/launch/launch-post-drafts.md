# Launch Post Drafts (David posts these himself — never automate)

## Show HN (post Tue–Thu, ~8am Pacific; stay online 2–3h to reply; NEVER ask for upvotes)

**Title:**
`Show HN: JVoice – Free, open-source on-device voice dictation for macOS`

**Text:**
I got tired of dictation apps charging $10–15/month for something an M-series Mac can do locally, so I built JVoice: press Option+Space anywhere, talk, and tone-styled text is pasted at your cursor.

It runs WhisperKit (CoreML Whisper) fully on-device — zero network calls during use, no telemetry, no accounts. It can rewrite your rambling into casual or formal register, strips filler words, supports a custom dictionary, and keeps Bluetooth headphones on high-quality audio by recording from the built-in mic.

Honest caveat: I'm a student with no Apple Developer account, so the binary is unsigned — macOS makes you click "Open Anyway" once in System Settings (documented in the README), or you can build from source with just the command-line tools.

Code: https://github.com/USER/jvoice

## r/macapps (use the dev/self-promo flair; check sidebar rules first)

**Title:**
`I made a free, open-source superwhisper alternative — on-device voice dictation, no subscription [JVoice]`

**Body:**
Hey r/macapps — I built JVoice because I didn't want to pay monthly for dictation. Press ⌥Space, talk, and clean text appears in whatever app you're in.

- 100% on-device (WhisperKit/CoreML) — nothing leaves your Mac
- Tone styles: casual / formal / very casual
- Filler-word removal + custom dictionary + WPM stats
- English & Romanian
- Free and open source (GPL), macOS 14+

It's unsigned (no $99 dev account), so there's a one-time "Open Anyway" step — exact instructions in the README, or build it from source.

GitHub: https://github.com/USER/jvoice — feedback very welcome, especially feature requests.

## r/LocalLLaMA (technical framing, not a product pitch; <10% self-promo rule)

**Title:**
`Built a fully local dictation app for macOS on WhisperKit — hotkey → speech → styled text in any app (open source)`

**Body:**
Sharing a weekend-project-turned-daily-driver: JVoice, a menu-bar app that does push-to-talk dictation entirely on-device with WhisperKit (CoreML Whisper, tiny→large-v3-turbo selectable).

Pipeline: AVAudioRecorder capture (with explicit input routing so Bluetooth headphones stay on A2DP instead of degrading to HFP) → WhisperKit transcription → a local post-processing pass that strips fillers, applies a tone style, and applies a user dictionary → pasted into the frontmost app via Accessibility APIs.

No network calls at runtime; the only download is the model snapshot from HF on first use. Curious what models people would want next — and whether anyone's benchmarked WhisperKit large-turbo vs Parakeet for short-utterance latency.

Repo: https://github.com/USER/jvoice

## Press tip email (9to5Mac: tips@9to5mac.com / Lifehacker: tips@lifehacker.com / MacStories: feedback@macstories.net)

**Subject:** Free, open-source alternative to Wispr Flow — on-device dictation for Mac, built by a student

**Body:**
Hi — I'm David, a student developer. I built JVoice, a free open-source Mac dictation app that does what Wispr Flow/superwhisper charge $10+/month for, entirely on-device with Apple's Neural Engine (WhisperKit). Press a hotkey, talk, and tone-styled text appears in any app. No cloud, no accounts, no telemetry. Demo GIF + details: https://github.com/USER/jvoice — happy to answer anything.

---

### Reminders from research
- Replace USER with the real GitHub username everywhere.
- Same-week concentration: HN + r/macapps + r/LocalLLaMA + directory submissions in one window (trending = star velocity).
- Reply to every comment personally; AI-written replies are banned on HN.
- Product Hunt comes later, after some X following exists; maker first-comment matters.
