# Terms of Use

**Effective date:** 7 July 2026 · Applies to JVoice for macOS and Windows.

> **In one sentence:** JVoice is free, source-available software provided **as-is, with no
> warranty** — you may use it free of charge for noncommercial purposes, read the source,
> and build it yourself, but you may not sell or commercially redistribute it, and you use
> it at your own risk.

These Terms explain the expectations for using the official JVoice builds. They are
written in plain language. Where anything here appears to conflict with the software
license below, **the PolyForm Noncommercial License wins.**

---

## 1. Your licence to use JVoice

JVoice is licensed under the **[PolyForm Noncommercial License 1.0.0](LICENSE)** — a
source-available license. The full, controlling text is in [`LICENSE`](LICENSE); this
section is a plain-language guide, and the license itself governs. In short, it lets you:

- **use JVoice free of charge for any noncommercial purpose** — personal use, study,
  hobby and amateur projects, and use by nonprofits, schools, and government bodies;
- **read the source, build it yourself, and make changes** for those purposes;
- **share copies**, as long as you pass along this license and the copyright notice.

What it does **not** permit: **selling JVoice, or using or redistributing it for a
commercial purpose**, without a separate license from the copyright holder. If you'd like
to use JVoice commercially, ask — a commercial licence can be arranged.

## 2. No warranty

JVoice is provided **"as is" and "as available", without warranty of any kind**, express
or implied — including, without limitation, any implied warranties of merchantability,
fitness for a particular purpose, accuracy, or non-infringement.

We do **not** promise that:

- transcriptions will be accurate, complete, or correct;
- the app will run without errors, interruptions, or data loss;
- it will work on any particular hardware, operating-system version, or with any
  particular microphone or third-party app.

Speech recognition is imperfect by nature. **Always review transcribed text before you
rely on it**, especially for anything important (medical, legal, financial, code,
credentials, or messages you can't take back).

## 3. Limitation of liability

To the fullest extent permitted by law, the authors and contributors of JVoice will not
be liable for any damages of any kind arising from your use of, or inability to use,
JVoice — including direct, indirect, incidental, special, consequential, or exemplary
damages, loss of data, or loss of profits — even if advised of the possibility.

Some jurisdictions do not allow the exclusion of certain warranties or the limitation of
certain damages. **Nothing in these Terms removes any rights you have under mandatory
local law that cannot be waived.** In that case, the disclaimers above apply to the
maximum extent your law allows.

## 4. Your responsibilities

By using JVoice you agree that:

- **You are responsible for what you dictate and where it is pasted.** JVoice types the
  transcribed text into whatever application currently has focus. Point it at the right
  window, and don't dictate content you aren't allowed to enter somewhere.
- **You will comply with the law and with the rules of the apps you dictate into.** Don't
  use JVoice to record people without the consent your local law requires, or to violate
  another service's terms.
- **You grant the permissions knowingly.** JVoice needs your **microphone** (to hear you)
  and, to paste text, an OS accessibility/automation permission (macOS **Accessibility**;
  on Windows it sends keystrokes to the focused window). You can revoke these at any time
  in your operating-system settings; the app simply stops working until you restore them.
- **You understand the downloads are unsigned.** To keep JVoice free, the builds are not
  code-signed. macOS Gatekeeper and Windows SmartScreen will warn you the first time you
  open it. The [README](README.md) explains the one-time "Open Anyway" / "Run anyway"
  steps. If you'd rather not trust an unsigned binary, **build it yourself** from source.

## 5. Speech models and third-party components

JVoice runs OpenAI's **Whisper** speech-recognition models on your own device. On first
use, the app downloads a model file **once** from a public host (Hugging Face) — this is
the only setup that touches the network, and after that transcription is fully offline.
See [`PRIVACY.md`](PRIVACY.md) for exactly what leaves your machine and when.

The Whisper models and the open-source libraries JVoice is built on are covered by their
own licenses, listed in [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md). Your use of
those components is subject to those licenses.

## 6. Trademarks and affiliation

**JVoice is an independent, community project. It is not affiliated with, endorsed by, or
sponsored by** OpenAI, Apple, Microsoft, NVIDIA, Hugging Face, or any other company named
in this repository.

Product names and trademarks are the property of their respective owners and are used
only to describe what JVoice does or what it runs on. Without limiting that:

- **Whisper** and **OpenAI** are trademarks of OpenAI.
- **Apple**, **macOS**, and **Apple Silicon** are trademarks of Apple Inc.
- **Microsoft**, **Windows**, and **SmartScreen** are trademarks of Microsoft
  Corporation.
- **NVIDIA** and **CUDA** are trademarks of NVIDIA Corporation.
- **Hugging Face** is a trademark of Hugging Face, Inc.

"JVoice" is the name of this project.

## 7. Changes to these Terms

We may update these Terms as the project evolves. The current version always lives in this
file in the repository, with its effective date at the top. Continuing to use JVoice after
a change means you accept the updated Terms. Past versions are visible in the project's git
history.

## 8. Contact

JVoice is developed in the open. Questions, concerns, or notices about these Terms can be
raised as an issue on the project's GitHub repository:
<https://github.com/david53001/jvoice>.
