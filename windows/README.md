# JVoice for Windows

A native **Windows** port of JVoice — a hotkey-driven, on-device voice-dictation app.
Press **Ctrl+Shift+Space** anywhere → record → transcribe locally with Whisper
(whisper.cpp via Whisper.net, GPU-accelerated when available) → tone-styled,
custom-word-accurate text pasted into the focused app. Free, open-source (GPL-3.0),
privacy-first: **zero network calls at runtime except the one-time speech-model download**.

This is the Windows sibling of the macOS Swift app (under `../Sources/`), which remains the
read-only reference for the accuracy "brain" and its invariants.

## Status

All five port phases are implemented. `dotnet build windows/JVoice.sln -c Release` = **0 errors**,
`dotnet test` = **434/434**, on-device transcription is verified (Vulkan GPU + CPU), and **the full
dictation loop works** (hotkey → record → transcribe → paste). The UI is a **black-&-white redesign**:
a text-free black HUD pill of white voice-activity bars (errors are the only text; successful paste is
silent), fully monochrome Settings + tray. No-speech detection is **model-driven** (whisper decides;
quiet/short dictation transcribes, true silence shows "No speech detected." — see the HANDOFF). What's
left is David's interactive **dogfood** of the live loop + HUD/Settings visual fidelity
(`../docs/launch/windows-dogfood-checklist.md`), plus two optional extras (Inno installer, accuracy
harness). The authoritative, complete state — pinned versions, every deviation, and the gotchas a new
contributor must know — is in **`../docs/HANDOFF-WINDOWS.md`**.

## Solution layout (`windows/`)

| Project | Target | What it is |
| --- | --- | --- |
| `JVoice.Core` | `net9.0` | **Pure** brain — text processing, phonetic match, vocabulary prompt, repetition guard, regurgitation recovery, chunk planner, WAV tail reader, streaming session, plus pure platform/UI decision helpers. No UI, no native deps. |
| `JVoice.App` | `net9.0-windows` (WinExe, WPF) | The app: Whisper engine (`Whisper/`), Win32/WASAPI platform services (`Platform/`), WPF UI (`UI/`), `VoiceCoordinator`, `App.xaml`. |
| `JVoice.Tests` | `net9.0` | xUnit suite locking the Core invariants (434 tests). |
| `tools/whisper-smoke` | `net9.0` console | WPF-free end-to-end transcription harness. |
| `tools/nospeech-probe` | `net9.0-windows` console | Runs silence/hum/noise/quiet-speech clips through the real engine to lock no-speech behaviour (self-generates a SAPI clip; `--muffle` matches a low-ratio mic). |
| `tools/generate-icon` | `net9.0` console | SkiaSharp icon generator → `JVoice.App/Assets/JVoice.ico` + tray PNGs. |

## Build · test · run

```bash
dotnet build windows/JVoice.sln -c Release          # 0 errors expected
dotnet test  windows/JVoice.Tests/JVoice.Tests.csproj   # 434/434 expected
dotnet run   --project windows/JVoice.App            # launches to the tray (+ first-run Settings)
```

- **Transcribe a WAV without the GUI:** `dotnet run --project windows/tools/whisper-smoke -- <file.wav> --model tiny`
- **Hidden bench CLI** (also on the app exe): `JVoice.exe --bench <file.wav> [--model tiny|base|small|large] [--lang en|ro] [--vocab "A,B"] [--stream] [--no-prompt]`
- **Regenerate icons:** `dotnet run --project windows/tools/generate-icon`

The bench/smoke tools need a 16 kHz / mono / 16-bit PCM WAV. Generate one with Windows TTS:
```powershell
Add-Type -AssemblyName System.Speech
$fmt = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(16000,[System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen,[System.Speech.AudioFormat.AudioChannel]::Mono)
$s = New-Object System.Speech.Synthesis.SpeechSynthesizer
$s.SetOutputToWaveFile("$env:TEMP\jv.wav",$fmt); $s.Speak('Testing JVoice on Windows.'); $s.Dispose()
```

## Speech engine & models

Whisper.net (managed whisper.cpp bindings), GGML models from Hugging Face
`ggerganov/whisper.cpp`, downloaded on first use to `%LOCALAPPDATA%\JVoice\models\`:

| UI label | GGML file | ~size |
| --- | --- | --- |
| Tiny | `ggml-tiny.bin` | 74 MB |
| Base | `ggml-base.bin` | 141 MB |
| Small | `ggml-small.bin` | 465 MB |
| Large | `ggml-large-v3-turbo-q5_0.bin` | 547 MB |

Runtime selection is automatic (CUDA → Vulkan → CPU). The dev RTX 3060 Ti uses **Vulkan**
(the bundled CUDA runtime needs the CUDA toolkit DLLs to be installed; otherwise Vulkan is
the GPU path). CPU is the universal fallback.

## Publish (distribution)

Two flavors from the one project, selected by the `JVoiceFlavor` MSBuild property:

```bash
# GPU folder build (CUDA + Vulkan + CPU runtimes on disk) — zip the folder:
dotnet publish windows/JVoice.App -c Release -r win-x64 -p:JVoiceFlavor=gpu \
  -p:SelfContained=true -p:PublishTrimmed=false -p:PublishReadyToRun=true -o out/gpu

# CPU-only folder build (small; no GPU runtimes) — zip the folder:
dotnet publish windows/JVoice.App -c Release -r win-x64 -p:JVoiceFlavor=cpu \
  -p:PublishSingleFile=false -p:SelfContained=true -p:PublishTrimmed=false \
  -p:PublishReadyToRun=true -o out/cpu
```

> **Ship a zipped folder, not a single-file exe.** WPF can't be trimmed, and the CPU
> single-file build (`-p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true`)
> *builds* (~75 MB) but **fails to load the native whisper runtime** because Whisper.net 1.9.1
> resolves natives via `Assembly.Location`, which is empty for bundled single-file assemblies.
> The self-contained **folder** build is verified working (`runtime: whisper.cpp (Cpu)`,
> accurate transcription). Distribute it as a `.zip` (see `docs/launch/windows-distribution.md`
> for the unsigned/SmartScreen story).

## Constraints

- **.NET 9**, C# latest, nullable + implicit usings. Primary RID `win-x64` (CUDA is x64-only).
- **GPL-3.0**; all NuGet deps MIT-compatible (Whisper.net, NAudio, H.NotifyIcon.Wpf, SkiaSharp).
- **Privacy:** no runtime network except the one-time model download. No telemetry. WAVs deleted after use + swept on launch.
- **Default hotkey Ctrl+Shift+Space** (Alt+Space is the Windows window menu). Rebindable in Settings.
- **$0 / unsigned** — document the SmartScreen "More info → Run anyway" step. Do NOT push/publish without David's go-ahead.

See `../docs/HANDOFF-WINDOWS.md` for the full session-by-session status and the
phase plans under `../docs/superpowers/plans/2026-06-22-windows-port-0*.md`.
