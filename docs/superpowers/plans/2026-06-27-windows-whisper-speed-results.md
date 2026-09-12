# Whisper Speed-Tuning — Measured Results (2026-06-27)

On-device measurements for the plan `2026-06-27-windows-whisper-speed.md`. All numbers are
**median decode seconds** from the instrumented `--bench` (warm-up excluded), on:

- **GPU:** NVIDIA RTX 3060 Ti — runtime selected = **whisper.cpp (Vulkan)** (CUDA falls back; see §CUDA).
- **CPU:** Intel i5-12400 (6 physical cores / 12 logical) — `whisper.cpp (Cpu)`.
- **Model:** `ggml-large-v3-turbo-q5_0.bin` on GPU; `tiny`/`base` on CPU (large is impractically slow on CPU).
- Clips: SAPI-generated `jv-3s` (2.3 s), `jv-12s` (9.1 s), `jv-20s` (18.8 s, varied sentences),
  `jv-35s` (31 s — **8× the same sentence**, a degenerate repetition case).

## Headline: shipped default vs the old no-op default

`jv-20s` (18.8 s), large, Vulkan — **same model, same clip**, default config before vs after:

| Config | median |
| --- | --- |
| old default (flash off, threads = whisper's `min(4,logical)`) | **0.565 s** |
| new default (flash **on**, threads **6**) | **0.348 s** |

→ **~38% faster** on the GPU path with the shipped defaults, transcript byte-identical.

## 1. Flash attention (ADOPTED for GPU) — `WhisperFactoryOptions.UseFlashAttention`

large, Vulkan, median seconds; transcripts compared:

| Clip | flash off | flash on | speedup | transcript |
| --- | --- | --- | --- | --- |
| jv-3s (2.3 s) | 0.425 | 0.268 | **−37%** | identical |
| jv-12s (9.1 s) | 0.456 | 0.317 | **−30%** | identical |
| jv-20s (18.8 s) | 0.538 | 0.360 | **−33%** | identical (full paragraph) |
| jv-35s (31 s, 8× repeat) | 0.686 → "…whisper. whisper." | → empty ("No speech") | n/a | **degenerate synthetic only** |

- Clean, low-variance win of **~30–37%** across realistic short/medium/long clips, **byte-identical
  transcripts**. The 3060 Ti's driver exposes the NVIDIA `coopmat2` fast path, so flash helps on
  Vulkan (it was a coin-flip per research — here it lands on the good side).
- The **only** divergence was the pathological `jv-35s` (8 identical sentences): flash's slightly
  different numerics flipped the regurgitation/no-speech guard from garbage output to empty. This is
  not a real-dictation case (no one dictates 8 identical sentences) — confirm on real mic in dogfood.
- **CPU:** flash is forced **OFF** in the `cpu` publish flavor (`JVOICE_CPU` compile constant →
  `EngineTuning.Default.UseFlashAttention = false`), because flash degrades CPU decode (whisper.cpp PR #2152).
  Verified: the CPU build's no-flag `--bench` reports `flash=off`.

## 2. Decode threads (ADOPTED) — `WithThreads(physicalCores)`

`tiny`, **CPU-only build**, jv-20s (18.8 s), median seconds:

| threads | median |
| --- | --- |
| 4 (whisper default) | 0.794 |
| **6 (physical cores)** | **0.624** (−21%) |
| 8 | 0.591 |
| 12 (logical) | 0.601 |

- 4 → 6 is a clear **~21%** win; past the physical core count there's no further gain (8 ≈ 6, 12 regresses
  slightly) — exactly the whisper.cpp guidance. Adopted `Threads = WhisperTuning.DecodeThreads(CpuInfo.PhysicalCoreCount)`
  (= 6 here). On the GPU path threads are ~irrelevant; this is purely a CPU-build (default download) win.

## 3. Per-clip `audio_ctx` (MEASURED, **NOT adopted**) — `WithAudioContextSize`

large, Vulkan, median seconds:

| Clip | full (1500) | floor 768 | 896 | 1024 | 1280 |
| --- | --- | --- | --- | --- | --- |
| jv-3s (2.3 s) | 0.43–0.46 | **0.278** ✓ | — | — | — |
| jv-12s (9.1 s) | 0.476–**1.278** (erratic) | **0.87–1.08** ✗ slow | 0.34 | 0.37 | 0.43 |
| jv-35s (31 s) | 0.695 | (policy → null = full) | — | — | — |

- **Non-monotonic and fragile.** The naive floor (768) makes the 2.3 s clip faster but **REGRESSES the
  9.1 s clip 2–3×** (likely a temperature-fallback re-decode triggered by the reduced context); yet
  896–1280 are *faster than full and stable*. The full path itself is erratic (0.476 ↔ 1.278).
- A floor of 1024 would dodge the 768 bad-spot, **but** this is tuned on SAPI clips, and this project's
  repeated hard lesson is that synthetic clips ≠ David's real low-SNR mic — a bad-spot could sit at a
  different `audio_ctx` on his audio and silently *slow* real dictation. With the GPU path already
  sub-second and streaming-while-recording hiding most latency, the risk outweighs the sub-second gain.
- **Decision:** left OFF by default. The lever stays available behind `--bench --audio-ctx off|auto|N`
  for future per-device experimentation.

## 4. CUDA backend (ASSESSED, **not enabled/shipped**)

- `--bench --runtime cuda --log-runtime` confirmed the root cause live: `ggml-cuda-whisper.dll` loads but
  *"CUDA runtime Cuda is not available"* — the CUDA 13 toolkit DLLs (`cublas64_13.dll`,
  `nvcudart_hybrid64.dll`) aren't installed, so Whisper.net silently falls back to Vulkan (whisper.net #509).
- Not pursued: enabling CUDA needs the CUDA Toolkit (~3 GB) or bundling large redist DLLs (~hundreds of MB),
  for a research-estimated ~20–30% encode gain over Vulkan — and David ships **CPU-default** distribution.
  Vulkan **+ flash** is already excellent (0.348 s for an 18.8 s clip). CUDA remains a documented **opt-in**:
  a user who installs the matching CUDA Toolkit + driver makes Whisper.net's auto-probe pick CUDA with no
  code change. The `Whisper.net.Runtime.Cuda12` package was **not** added (it would bloat the GPU build with
  a runtime that can't load without the toolkit).
- Caveat: forcing `--runtime cuda`/`cpu` in the all-runtimes dev build aborts in the native layer
  (GGML_ASSERT) rather than failing cleanly — a bench diagnostic edge; the product uses auto-probe, which
  falls back to Vulkan cleanly.

## 5. Temperature-fallback cap (ASSESSED, **not adopted**)

`WithTemperatureInc(0)` would cap whisper's up-to-6× re-decode on hard clips, but it diverges from the
macOS parity (`temperatureFallbackCount = 2`), the app already has its own `RegurgitationRecovery` layer,
and flash already made decode fast and low-variance. Marginal EV; left at the parity default `0.2`.

## Reproducing

Build: `dotnet build windows/JVoice.sln -c Release`. Bench exe:
`windows/JVoice.App/bin/x64/Release/net9.0-windows/JVoice.exe`.

```
# default (shipped) config:
JVoice.exe --bench <clip.wav> --model large --iters 5
# A/B a lever:
JVoice.exe --bench <clip.wav> --model large --flash off|on   --iters 5
JVoice.exe --bench <clip.wav> --model large --audio-ctx off|auto|896  --iters 5
JVoice.exe --bench <clip.wav> --model large --threads 4|6|8   --iters 5
JVoice.exe --bench <clip.wav> --model large --runtime cuda --log-runtime   # diagnose backend
```

**Gotchas for the next session:**
- JVoice is a **WinExe** — PowerShell `$out = & JVoice.exe …` captures **nothing**; you must pipe:
  `& JVoice.exe … 2>&1 | Select-String 'transcribe:'`. (This wasted a debugging cycle.)
- large-v3-turbo on **CPU** is impractically slow (>40 s/decode) — measure CPU threads with `tiny`/`base`.
  `base` may need a one-time download; `tiny` + `large` were already present in `%LOCALAPPDATA%\JVoice\models`.
- Don't run heavy bench sweeps while the desktop is in use — back-to-back large decodes peg the GPU and lag
  the machine; a timed-out bench can leave a detached `JVoice.exe` churning (kill strays, keep the tray PID).
