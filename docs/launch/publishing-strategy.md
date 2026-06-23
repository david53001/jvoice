# Publishing & repo strategy — macOS + Windows (2026-06-24)

Zero-context decision doc: **how to publish JVoice now that there are two native apps**
(macOS Swift + Windows .NET). Written for David and the next Claude session. **Nothing in
here has been executed** — publishing is on hold until David's explicit go-ahead (see
`CLAUDE.md` hard rules). This is the runbook + the reasoning, not an action already taken.

---

## 1. The situation (facts, verified from the repo)

- **One GitHub remote is already configured:** `origin = https://github.com/david53001/jvoice.git`.
  Local `main` tracks `origin/main`.
- **`main` is the macOS app, frozen at commit `2b6d53c` (Tue Jun 9 2026)** — "Custom-word
  robustness, streaming transcription, Large turbo, demo video." It has had no commits since.
- **`windows-port` is `main` + 79 commits** that add the *entire* Windows port. It is
  **0 commits behind main** (i.e. `main` is a direct ancestor — `windows-port` contains
  everything on `main` plus the Windows work). It is **local-only — never pushed.**
- **The repo is already physically a cross-platform monorepo.** Top level:
  - `Sources/`, `Tests/`, `Package.swift`, `Package.resolved`, `Resources/`, `scripts/` — the **macOS Swift app** (63 `.swift` files: 37 app source, 21 tests, 5 tooling).
  - `windows/` — the **Windows .NET solution** (C# / .NET 9 / WPF / Whisper.net; `JVoice.Core` + `JVoice.App` + `JVoice.Tests` + `tools/`).
  - `docs/` — **shared** docs for both (HANDOFF.md = macOS, HANDOFF-WINDOWS.md = Windows, the `launch/` material, the `superpowers/plans/` design docs).
  - `.gitignore` already covers **both** toolchains (`.build/` for Swift; `windows/**/bin|obj|publish`, `*.bin` for .NET).
  - `.github/` — CI (currently the macOS test workflow only).
- **The two trees are independent.** The Windows .NET build references **zero** Swift files
  (verified across every `.sln`/`.csproj`/`.props`); the only mentions of `*.swift` under
  `windows/` are `// Faithful port of TextProcessor.swift`-style provenance comments. The
  Swift sources are the macOS product **and** the human-readable spec the port was written
  against — they are not a build input for Windows.
- **`README.md` is still macOS-only** and uses the literal placeholder `USER` for the GitHub
  username (to be replaced at publish time; the same placeholder is in `../Portfolio` and the
  launch drafts).

> ⚠️ **Reconcile before any push:** `CLAUDE.md` says "publishing is deliberately on hold; do
> not `git push` or add remotes," yet `origin` is already configured and `main` tracks it.
> Before pushing *anything*, confirm what actually lives at `github.com/david53001/jvoice`
> (is it public? does it already contain the Jun 9 macOS code, or is the remote configured but
> empty?). Check in a browser or with `git ls-remote origin` (read-only). Do not assume.

---

## 2. Are the Swift files needed? — Yes. Keep all of them.

The "are the Swift files needed" question has a clean answer:

- **They are the entire macOS product.** `Sources/JVoice/**` (37 files) is the shipping macOS
  app; `Tests/JVoiceTests/**` (21 files) is its test suite; `scripts/` + `docs/demo-video/scripts/`
  (4 files) + `Package.swift` are tooling. **None are dead/vestigial.** (The only borderline
  files are two tiny throwaway debug probes, `docs/demo-video/scripts/probe5.swift` and
  `probecursor.swift`, used once when writing the demo-asset extractor — harmless, ~10 lines
  each; not worth a special action.)
- **They are also the port's source-of-truth.** `JVoice.Core` ports the "brain"
  (TextProcessor / PhoneticMatcher / VocabularyPrompt / RepetitionGuard / RegurgitationRecovery /
  ChunkPlanner / WavTail / StreamingTranscriptionSession) **1:1 from the Swift**, with the Swift
  tests as the parity spec. Deleting the Swift would throw away both a real product and the
  reference that keeps the Windows brain honest.
- **They do not bloat or break the Windows build** — the .NET solution never compiles or links
  them. Shipping them in the same repo costs nothing at build time.

**So this is not a "remove the Swift files" decision. It's a "how do we present two apps in
one (or two) repos" decision** — section 3.

---

## 3. How to publish — three options, with a recommendation

### Option A — Single cross-platform monorepo *(RECOMMENDED)*

Promote `windows-port` to `main` so **one repo holds both apps**, and rewrite the README into a
cross-platform landing page with separate **macOS** and **Windows** download sections. GitHub
Releases carry both binaries; Issues / stars / discussions are unified.

- **Why it's the right fit:** it matches what the codebase already *is* — one product family with
  a shared brain and shared docs, where the Windows port literally cites the Swift sources as its
  spec. The repo is already laid out this way (`Sources/` + `windows/` + shared `docs/`,
  cross-toolchain `.gitignore`). One repo = one place for users to find either build, one star
  count, one issue tracker, half the release/CI plumbing. This is the standard shape for
  cross-platform open-source tools.
- **Cost:** a macOS user browsing the repo sees a `windows/` folder and vice-versa (cosmetic),
  and the repo is larger. A clear README that routes each OS to its own download + build steps
  fully mitigates this.
- **Releases note:** GitHub Releases are **repo-level**, so both platforms' artifacts live under
  the same Releases tab — normal and fine. Simplest: one tag `v1.0.0` carrying
  `JVoice.dmg` (macOS) + `JVoice-win-x64-gpu.zip` + `JVoice-win-x64-cpu.zip` (Windows). If the
  two platforms ever ship on different cadences, use suffixed tags (`v1.0.0-macos`, `v1.0.0-win`).

### Option B — Same repo, a long-lived `windows` branch *(David floated this — do NOT do it)*

Keep `main` = macOS and a permanent `windows` branch = Windows.

- **Why it's the weakest option:** GitHub branches are **development lines, not product homes.**
  - **Releases and Issues are repo-level, not branch-level** — a `windows` branch *cannot* have
    its own separate Release page or issue tracker. The separation you'd want from "a different
    branch" doesn't actually exist on GitHub; you'd get a shared repo (the monorepo downside)
    with none of the monorepo upside.
  - Visitors land on the **default branch** (macOS) and may never discover the Windows branch.
  - You'd have to keep merging every shared change (docs, brain-reference, README) across two
    permanently-divergent branches, forever.
  - It splits nothing cleanly and complicates everything. **Recommend against.**

### Option C — Separate repo `jvoice-windows` *(clean fallback if Windows wants its own identity)*

A second GitHub repo containing only the Windows port.

- **Pros:** fully independent README, releases, issues, stars, and brand for Windows; a Windows
  user sees only Windows code. Right *if* David wants to market/version the two products
  separately.
- **Cons:** duplicates README/LICENSE/launch material; splits the brand and star count; the
  Windows port loses in-repo access to the Swift reference it was ported from (cross-link or
  vendor a copy); double the CI/release plumbing; the shared `docs/superpowers/plans/` +
  HANDOFFs must be split or duplicated.
- **Note:** going monorepo-first (Option A) loses nothing here — a monorepo can be cleanly split
  into a separate Windows repo later with `git subtree split -P windows -b windows-only` if
  David ever decides Windows deserves its own home. The reverse (merging two repos back together
  with history) is harder. **So Option A is also the safe default even if C is the eventual end
  state.**

### Recommendation

**Option A (monorepo on `main`).** Lowest friction, matches the codebase's actual architecture
and the project's "one product family, shared brain" ethos, gives users a single place, and
keeps the Swift reference next to the C# port that depends on it. Keep every Swift file. If
Windows later needs its own identity/issue tracker, split to Option C with `git subtree` — no
information is lost by starting monorepo.

---

## 4. Publish-prep runbook (Option A) — **do NOT run without David's go-ahead**

These steps change the published `main`, so they are publishing actions gated on explicit
approval. Listed so they can be executed in one pass when David says go.

1. **Verify the remote first** (section 1 ⚠). Confirm what's actually at
   `github.com/david53001/jvoice` and whether it's public, before touching it.
2. **Fast-forward `main` to the Windows work** (no merge commit — `main` is an ancestor of
   `windows-port`, so this is clean):
   ```bash
   git checkout main
   git merge --ff-only windows-port      # main now contains both platforms
   ```
   (Optionally delete `windows-port` afterward — it's fully contained in `main`.)
3. **Rewrite `README.md`** into a cross-platform landing page:
   - tagline → then an **"On macOS"** section (DMG download + the Gatekeeper "Open Anyway" steps
     already written in the current README) and an **"On Windows"** section (ZIP/installer
     download + the SmartScreen "More info → Run anyway" steps from
     `docs/launch/windows-distribution.md`);
   - a shared **How it works / Privacy / Build from source** body (macOS: `swift build`; Windows:
     `dotnet build windows/JVoice.sln -c Release`);
   - replace the literal `USER` placeholder with `david53001` (also in `../Portfolio` and the
     launch drafts).
4. **Cut a GitHub Release** with both platforms' artifacts:
   - macOS `JVoice.dmg` (ad-hoc signed, per the existing macOS distribution plan);
   - Windows `JVoice-win-x64-gpu.zip` + `JVoice-win-x64-cpu.zip` (the self-contained folder zips
     from the publish commands in `docs/HANDOFF-WINDOWS.md` §2 — single-file does NOT work for the
     engine, §7 #4).
   - Simplest is one tag (`v1.0.0`) with all assets attached.
5. **(Optional, recommended) Add a Windows CI job** to `.github/workflows/` (`windows-latest`,
   `dotnet build` + `dotnet test windows/JVoice.Tests`) so both platforms show green checks. Not
   a blocker for publishing.
6. **Account note:** David has two gh accounts (`david53001` active, `da97d`). The remote already
   points at `david53001`. Confirm that's the intended publish account before pushing.

---

## 5. One-line answer

Keep all the Swift files (they are the macOS product *and* the port's reference spec — nothing is
dead). Publish **both platforms from one repo on `main`** (Option A), not from a per-platform
branch (Option B is illusory separation), with a cross-platform README and a single Releases tab.
Splitting Windows into its own repo (Option C) stays available later via `git subtree` if it ever
earns a separate identity. **No push/merge until David greenlights** — section 4 is the runbook.
