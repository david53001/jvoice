# Third-Party Notices

JVoice is licensed under the **GPL-3.0** (see [`LICENSE`](LICENSE)). It is built with, and
distributes, the open-source components listed below, each under its own license. We thank
their authors. Their copyright notices are preserved here as those licenses require.

All bundled components are under the permissive **MIT License**, which is compatible with
GPL-3.0. The MIT license text is reproduced once at the end; each component remains under
the copyright of its own authors.

The Whisper speech-recognition **models** are downloaded on first run (not bundled in the
installer) from the hosts noted below; they are also MIT-licensed.

---

## Components distributed with JVoice

### Windows build (.NET 9)

| Component | Author(s) | License | Home |
| --- | --- | --- | --- |
| Whisper.net `1.9.1` | Sandro Hanea & contributors | MIT | https://github.com/sandrohanea/whisper.net |
| Whisper.net.Runtime (+ CUDA, + Vulkan) `1.9.1` | Sandro Hanea & contributors | MIT | https://github.com/sandrohanea/whisper.net |
| whisper.cpp (native engine wrapped by the runtime) | Georgi Gerganov & contributors | MIT | https://github.com/ggerganov/whisper.cpp |
| NAudio `2.3.0` | Mark Heath & NAudio contributors | MIT | https://github.com/naudio/NAudio |
| H.NotifyIcon.Wpf `2.3.0` | Havendv & contributors (based on Hardcodet.NotifyIcon.Wpf) | MIT | https://github.com/HavenDV/H.NotifyIcon |
| .NET runtime & WPF `9.0` | .NET Foundation & contributors | MIT | https://github.com/dotnet/runtime |

### macOS build (Swift, macOS 14+)

| Component | Author(s) | License | Home |
| --- | --- | --- | --- |
| WhisperKit (≥ `1.0.0`) | Argmax, Inc. | MIT | https://github.com/argmaxinc/WhisperKit |
| KeyboardShortcuts (`1.10.0`) | Sindre Sorhus | MIT | https://github.com/sindresorhus/KeyboardShortcuts |

## Speech-recognition models (downloaded on first run, not bundled)

| Component | Author(s) | License | Source |
| --- | --- | --- | --- |
| Whisper (the underlying model architecture and weights) | OpenAI | MIT | https://github.com/openai/whisper |
| GGML Whisper conversions (Windows) | Georgi Gerganov & contributors | MIT | https://huggingface.co/ggerganov/whisper.cpp |
| WhisperKit Core ML conversions (macOS) | Argmax, Inc. | MIT | https://huggingface.co/argmaxinc/whisperkit-coreml |

## Build-time only (not distributed in the app)

| Component | Author(s) | License | Home |
| --- | --- | --- | --- |
| SkiaSharp | .NET Foundation & Microsoft | MIT | https://github.com/mono/SkiaSharp |

_SkiaSharp is used only by the developer tool that generates the app icon; it is not shipped
in the installer._

---

## The MIT License

Each MIT-licensed component above is provided under the following terms, with copyright held
by that component's respective author(s) as listed:

```
MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

For the exact, authoritative license text and copyright lines of any component, see its
linked repository. If you believe an attribution here is incomplete or incorrect, please
open an issue at <https://github.com/david53001/jvoice> and it will be corrected.
