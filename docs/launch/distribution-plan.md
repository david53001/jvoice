# JVoice / BetterScreenshot — Distribution & Launch Playbook

Researched 2026-06-06. Goal: maximum real users + GitHub traction at $0 budget, for free open-source macOS menu-bar apps. Audiences: developers AND non-technical users (schoolmates).

## TL;DR prioritization (effort vs impact)

| Priority | Channel | Effort | Impact | Why |
|---|---|---|---|---|
| 1 | r/macapps post (dev flair) | Low | Very high | 231k members, unusually permissive to self-promo, exact audience |
| 2 | Show HN (Hacker News) | Med | Very high (devs) | Best single-shot dev/OSS reach; spikes GitHub stars |
| 3 | Awesome-list PRs (awesome-mac, open-source-mac-os-apps, Mac-Menubar-Megalist) | Low | High (durable) | Permanent backlinks + steady star drip |
| 4 | r/LocalLLaMA (JVoice only) | Low | High | On-device WhisperKit angle is on-topic and loved there |
| 5 | AlternativeTo + OpenAlternative + MacUpdate + ToolFinder | Low | Med (durable SEO) | "Free alternative to superwhisper / CleanShot X" search intent |
| 6 | Product Hunt | Med-High | Med | Do after building a small X following; maker first-comment matters (70% of POTD winners) |
| 7 | Press tips (9to5Mac, MacStories, Lifehacker) | Low | Med-high if it lands | Lottery odds, huge if hit |
| 8 | TikTok/Reels/Shorts demos | High (recurring) | Med-high | ONLY channel that reaches non-tech high-schoolers at scale, $0 |
| 9 | Build-in-public on X | High (recurring) | Med (compounding) | Pays off over months; fuels PH/HN launch days |
| 10 | lobste.rs | Low | Low-med | Invite-only; only with a genuine technical writeup |

## Key rules per channel

**r/macapps** — top priority. Self-promo friendly; use dev flair; lead with "free and open source." Confirm current flair/frequency rules in sidebar before posting (couldn't verify live).

**Show HN** — guidelines: https://news.ycombinator.com/showhn.html
- Title format: `Show HN: JVoice – Free, open-source on-device voice dictation for macOS`
- Boring/factual titles only: no caps, no exclamation marks, no hype words.
- Must be hands-on tryable, no signup walls. You must be the creator and answer comments all day.
- NEVER ask anyone to upvote (kills the post). AI-generated comments banned — reply in your own voice.
- Timing: Tue–Thu ~7–10am Pacific; be online the first 2–3 hours.

**r/LocalLLaMA** — frame as technical/local-inference ("on-device WhisperKit, nothing leaves your Mac"), not a product pitch. Keep self-promo <10% of activity.

**r/MacOS / r/apple** — strict; naked self-promo gets removed. Frame as "free open-source tool I built to solve X" + demo, engage in comments.

**Awesome lists:**
- jaywcjlove/awesome-mac: one PR per app, alphabetical order in correct category, `[App Name](link)`, explain why in PR.
- serhii-londar/open-source-mac-os-apps: edit `applications.json` NOT README (bot regenerates). Required: title, short_description (ends in period), categories, repo_url, icon_url, screenshots, official_site, languages. Gates: recent commits, English README, LICENSE file.
- SKaplanOfficial/Mac-Menubar-Megalist: very low bar, issue or PR, guaranteed inclusion.
- Also: iCHAIT/awesome-macOS, appleboy/awesome-osx.

**Directories:**
- AlternativeTo: sign up → "Add new application" → price=Free, flag open-source → list as alternative to superwhisper/Wispr Flow (JVoice) and CleanShot X (BetterScreenshot). Approval 1–2 days.
- OpenAlternative: https://openalternative.co/submit (also PRable repo piotrkulpinski/openalternative). Dofollow backlink.
- MacUpdate: https://www.macupdate.com/content/submit — direct installer URL, non-promotional description.
- ToolFinder: free listing via https://toolfinder.co/contact

**Press:**
- 9to5Mac: tips@9to5mac.com — 2–3 sentences + demo GIF.
- MacStories: feedback@macstories.net (John Voorhees handles app coverage).
- Lifehacker: tips@lifehacker.com — "free tool that replaces a paid one" angle fits their voice.
- YouTubers: business email on About pages; target mid/small Mac channels (e.g., MORGONAUT); give them a ready 30-sec demo clip.

**Short-form video (the non-tech/schoolmate channel):**
- TikTok app-install share >25% of spend in 2026; utilities are cheap/easy categories; new accounts can go viral (algorithm is relevance-based).
- Wispr Flow already markets on TikTok — audience for "talk-to-type" demos exists.
- Format: 10–25 sec vertical screen capture, transformation hook in first 1.5s, captions, "100% free, no subscription" kicker. Post same file to TikTok + Reels + Shorts.

## Launch sequence

1. **Pre-launch:** LICENSE + strong English README + screenshots in repo. One good 20-sec demo clip per app.
2. **Week 1 listings (one-time):** AlternativeTo, OpenAlternative, MacUpdate, ToolFinder; PRs to the 3+ awesome lists.
3. **JVoice launch day:** Show HN (Tue–Thu ~8am PT) + r/macapps + r/LocalLLaMA same day; press tips same morning; answer everything all day.
4. **Product Hunt** later, with maker first-comment.
5. **Ongoing:** short-form demos; repeat playbook for BetterScreenshot.

## Gotchas
1. Never ask for upvotes on HN. 2. No hype words in HN titles. 3. Only r/macapps (+ r/opensource, r/LocalLLaMA with right framing) are safe for "I made this." 4. open-source-mac-os-apps requires LICENSE + recent commits or you get rejected/removed. 5. Verify r/macapps sidebar rules before first post.
