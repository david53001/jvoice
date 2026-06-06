# Unsigned Distribution & Case-Study Findings (researched 2026-06-06)

## Critical facts that shape the plan

1. **Right-click→Open is GONE** (since macOS Sequoia 15, still true on Tahoe 26). Unsigned-app install dance is now: open (fails) → System Settings → Privacy & Security → scroll to bottom → "Open Anyway" (within ~1h of failed launch) → admin password → relaunch → Open. One-time per app.
2. **Homebrew is closed to unsigned apps**: `--no-quarantine` deprecated in Homebrew 5.0.0 (Nov 2025); as of **Sept 1, 2026** all Gatekeeper-failing casks are removed/non-installable — likely including personal taps (enforced client-side). → **Skip Homebrew entirely until signed/notarized.** Distribute via **GitHub Releases only**.
3. **Package as ad-hoc-signed DMG, never bare zip**: `codesign --force --deep -s - App.app` + `create-dmg`. A plain `zip` can break the bundle signature → users get the unrecoverable "App is damaged" error instead of the recoverable "can't verify developer" one. If zipping, use `ditto -c -k --keepParent`. Damaged-case fallback: `xattr -dr com.apple.quarantine /Applications/App.app`.
4. **GitHub Actions macOS runners can build + ad-hoc sign + DMG for $0.** Only notarization needs the $99/yr account.
5. **Notarization is the real growth bottleneck** — every breakout app (Stats 39k★, Rectangle 29k★, Maccy 20k★, AltTab 16k★, VoiceInk 5k★) is notarized. Get the $99 account the moment there's any revenue.

## Homebrew main-repo notability (for later, once signed)
- Third-party submission: rejected under 30 forks / 30 watchers / 75 stars.
- Self-submission: rejected under 90 forks / 90 watchers / 225 stars.

## Direct comparable: VoiceInk (Beingpax/VoiceInk, GPL-3.0, ~5.2k★)
- Model: **source free & buildable; prebuilt notarized binary $39.99 one-time lifetime** (auto-updates, support). "Sell the convenience, give away the code." Market-validated price band $30–60 (MacWhisper €59, ~300k copies; AltTab Pro $9.99; Rectangle Pro).
- Whole niche rejects subscriptions; "no subscription" is itself a marketing line.
- Other comparables: Handy (cjpais/Handy, MIT, 100% free, HN-launched), MacWhisper (closed, free tier funnel + €59 lifetime).

## Free→paid without backlash (AltTab lesson)
- Add NEW paid features; never paywall what was free; announce before shipping; no harsh device limits.
- Maccy model also good: 100% free OSS + paid Mac App Store build purely for convenience.
- Turn on GitHub Sponsors / Buy Me a Coffee from day one (zero goodwill cost).

## GitHub repo optimization
- Trending = star **velocity**, not absolute count → concentrate launch (HN + r/macapps + listings same week).
- README: title → one-line value prop → **demo GIF at top** → 30-sec quick start → why-this-exists. 500–1500 words. Repos with screenshots ≈ 42% more stars; comprehensive READMEs ≈ 4× stars.
- Host GIFs on GitHub CDN (drag into an issue comment, copy URL) to keep repo slim.
- Set social-preview image; add topics: whisper, speech-to-text, macos, dictation, menubar, swift, on-device, privacy. Get into awesome-whisper / awesome-voice-typing too.
- Visible release cadence signals "alive."

## Trust strategy for an unsigned app asking for mic + accessibility
- Lead loudly with: **open source + 100% on-device + zero telemetry + no accounts**.
- README section "First launch on macOS" with exact Open-Anyway steps + visual.
- Build-from-source instructions so skeptics can verify (VoiceInk-style BUILDING.md).

## Install UX copy to reuse in README/site
1. Download `JVoice.dmg`, drag JVoice into Applications.
2. Double-click it. macOS will say it "can't verify the developer." Click **Done** (not "Move to Trash").
3. Open **System Settings → Privacy & Security**, scroll to the bottom, click **Open Anyway** next to JVoice.
4. Enter your password, launch JVoice again, click **Open**. You only do this once.
(If you see "App is damaged": run `xattr -dr com.apple.quarantine /Applications/JVoice.app` in Terminal once.)

## Caveat to re-verify near Sept 2026
Whether the Homebrew Gatekeeper enforcement hits personal taps exactly as announced.
