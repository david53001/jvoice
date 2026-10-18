## JVoice 1.3.0

**AI Polish is new, optional and off: nothing changes unless you turn it on.** Settings → **AI Polish** can send the text of each finished dictation (never the audio) to Anthropic's Claude to fix punctuation, run-on sentences and misheard words, using what you were just talking about to pick the right word. To use it you paste your own Anthropic API key, add a small budget (each polish costs a fraction of a cent, billed to your Anthropic account) and turn the switch on. With it on, your custom words and your last few dictations into the same app go along too, so Claude has context. If anything goes wrong (offline, a bad key, no answer within 3 seconds), JVoice pastes its own text as before. Details: [PRIVACY.md](https://github.com/david53001/jvoice/blob/main/PRIVACY.md).

**Launch at Login is now in Settings.** A new **Startup** card shows whether JVoice opens when you log in and lets you change it. It stays in step with the menu bar's **Launch at Login** item. JVoice still never turns it on by itself.

**Also new:**

- **Opacity:** Settings → **Appearance** sets how see-through JVoice's windows and recording pill are.
- **Settings can be resized**, and its cards rearrange into two or three columns to fit.
- **Smarter maths:** say "lambda" in a maths dictation and you get λ; in everyday speech it stays a word.

**Fixed:** no more empty "JVoice Settings" window; windows open on the display you're using; the recording tour's outline fits the pill.

Your settings, custom words and permissions are kept.
