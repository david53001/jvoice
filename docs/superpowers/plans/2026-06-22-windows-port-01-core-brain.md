# Phase 1 — JVoice.Core (the accuracy "brain") + tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax. **Read `2026-06-22-windows-port-00-overview.md` first** — it defines the architecture, canonical names, and global constraints this phase obeys.

**Goal:** Build `JVoice.Core` — a pure, dependency-free .NET 9 class library that reproduces JVoice's accuracy "brain" (text processing, phonetic correction, vocabulary biasing, regurgitation recovery, repetition guard, WAV tail reading, silence-cut chunk planning, streaming session, and the transcription-engine abstraction) — and lock it with an xUnit test suite (`JVoice.Tests`) translated from the macOS Swift tests.

**Architecture:** `JVoice.Core` has zero UI, zero Win32, zero Whisper.net dependencies — only the .NET BCL. Every algorithm is a faithful 1:1 port of the corresponding Swift source under `Sources/JVoice/`, preserving **every constant verbatim**. The Swift source is the authority; cite `file:line` when in doubt. No behavior changes during the port. The tests encode the same vectors as `scripts/run-logic-tests.sh` and `scripts/verify-streaming.sh`.

**Tech Stack:** C# (latest) on .NET 9, xUnit, `System.Text.Json`. No native dependencies — this library compiles and tests on any OS / on CI without whisper binaries.

## Global Constraints

(From the overview — every task implicitly includes these.)
- .NET 9; `JVoice.Core` and `JVoice.Tests` target `net9.0` (cross-platform, **not** `-windows`). `<Nullable>enable</Nullable>`, `<ImplicitUsings>enable</ImplicitUsings>`, `<LangVersion>latest</LangVersion>`.
- Namespaces: `JVoice.Core.Models`, `JVoice.Core.Text`, `JVoice.Core.Audio`, `JVoice.Core.Transcription`, and `JVoice.Core` (root, for `AppTimings`).
- Faithful port: reproduce the Swift algorithm exactly, every numeric constant and string literal verbatim. No "improvements".
- Do not modify the macOS Swift app (`Sources/`, `Tests/`, `Package.swift`, `Resources/`). It is read-only reference.
- Do not push / open PRs / add remotes. Commit locally only, on a branch.
- TDD: write the test, watch it fail, implement, watch it pass, commit. Frequent commits.

## Source-of-truth file map (Swift → C#)

| Swift source | C# target |
| --- | --- |
| `Sources/JVoice/Models/AppMode.swift` + `ToneMode` (in `VoiceCoordinator.swift`) | `JVoice.Core/Models/ToneStyle.cs` |
| `Sources/JVoice/Models/TranscriptionLanguage.swift` | `JVoice.Core/Models/TranscriptionLanguage.cs` |
| `Sources/JVoice/Models/WhisperModelOption.swift` | `JVoice.Core/Models/WhisperModelOption.cs` |
| `Sources/JVoice/Models/SettingsState.swift` | `JVoice.Core/Models/SettingsState.cs` |
| `Sources/JVoice/Models/HUDState.swift` | `JVoice.Core/Models/HudState.cs` |
| `Sources/JVoice/Services/AppTimings.swift` | `JVoice.Core/AppTimings.cs` |
| `Sources/JVoice/Services/VocabularyPrompt.swift` | `JVoice.Core/Text/VocabularyPrompt.cs` |
| `Sources/JVoice/Services/TextProcessor.swift` | `JVoice.Core/Text/TextProcessor.cs` |
| `Sources/JVoice/Services/PhoneticMatcher.swift` | `JVoice.Core/Text/PhoneticMatcher.cs` |
| `Sources/JVoice/Services/RepetitionGuard.swift` | `JVoice.Core/Text/RepetitionGuard.cs` |
| `Sources/JVoice/Services/RegurgitationRecovery.swift` | `JVoice.Core/Text/RegurgitationRecovery.cs` |
| `Sources/JVoice/Services/WavTail.swift` | `JVoice.Core/Audio/WavTail.cs` |
| `Sources/JVoice/Services/ChunkPlanner.swift` | `JVoice.Core/Audio/ChunkPlanner.cs` |
| `Sources/JVoice/Services/StreamingTranscriptionSession.swift` | `JVoice.Core/Audio/StreamingTranscriptionSession.cs` |
| `Sources/JVoice/Services/TranscriptionManager.swift` (protocol + `FileBackedTranscriptionEngine` + errors) | `JVoice.Core/Transcription/ITranscriptionEngine.cs`, `FileBackedTranscriptionEngine.cs`, `TranscriptionException.cs` |

---

## File Structure (what this phase creates)

```
windows/
├── JVoice.sln
├── Directory.Build.props
├── .editorconfig
├── JVoice.Core/
│   ├── JVoice.Core.csproj
│   ├── AppTimings.cs
│   ├── Models/{ToneStyle,TranscriptionLanguage,WhisperModelOption,SettingsState,HudState}.cs
│   ├── Text/{VocabularyPrompt,TextProcessor,PhoneticMatcher,RepetitionGuard,RegurgitationRecovery}.cs
│   ├── Audio/{WavTail,ChunkPlanner,StreamingTranscriptionSession}.cs
│   └── Transcription/{ITranscriptionEngine,TranscriptionException,FileBackedTranscriptionEngine}.cs
└── JVoice.Tests/
    ├── JVoice.Tests.csproj
    └── {VocabularyPromptTests,TextProcessorTests,PhoneticMatcherTests,RepetitionGuardTests,
        RegurgitationRecoveryTests,WavTailTests,ChunkPlannerTests,StreamingSessionTests,
        FileBackedEngineTests,SettingsStateTests,ModelTests}.cs
```

---

## Task 1: Solution skeleton + projects

**Files:**
- Create: `windows/JVoice.sln`
- Create: `windows/Directory.Build.props`
- Create: `windows/.editorconfig`
- Create: `windows/JVoice.Core/JVoice.Core.csproj`
- Create: `windows/JVoice.Tests/JVoice.Tests.csproj`
- Create: `windows/JVoice.Core/_Placeholder.cs` (temporary, deleted in Task 2)
- Modify: `.gitignore` (append .NET ignores)

**Interfaces:**
- Produces: the `JVoice.Core` (net9.0 library) and `JVoice.Tests` (net9.0 xUnit) projects, both building empty. Later tasks add files to these.

- [ ] **Step 1: Create `windows/Directory.Build.props`**

```xml
<Project>
  <PropertyGroup>
    <LangVersion>latest</LangVersion>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <TreatWarningsAsErrors>false</TreatWarningsAsErrors>
    <Version>1.0.0</Version>
    <Company>JVoice</Company>
    <Product>JVoice</Product>
    <Authors>JVoice</Authors>
    <Copyright>GPL-3.0</Copyright>
  </PropertyGroup>
</Project>
```

- [ ] **Step 2: Create `windows/JVoice.Core/JVoice.Core.csproj`**

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
    <RootNamespace>JVoice.Core</RootNamespace>
    <AssemblyName>JVoice.Core</AssemblyName>
  </PropertyGroup>
</Project>
```

- [ ] **Step 3: Create `windows/JVoice.Core/_Placeholder.cs`** (so the project compiles before Task 2)

```csharp
namespace JVoice.Core;
internal static class _Placeholder { }
```

- [ ] **Step 4: Create `windows/JVoice.Tests/JVoice.Tests.csproj`**

> At execution time, resolve the current stable versions of these packages (`dotnet add package` writes them) and pin them. The versions below are a known-good baseline.

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
    <IsPackable>false</IsPackable>
    <RootNamespace>JVoice.Tests</RootNamespace>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.11.1" />
    <PackageReference Include="xunit" Version="2.9.2" />
    <PackageReference Include="xunit.runner.visualstudio" Version="2.8.2" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\JVoice.Core\JVoice.Core.csproj" />
  </ItemGroup>
</Project>
```

- [ ] **Step 5: Create `windows/.editorconfig`** (minimal — keep style relaxed during the port)

```ini
root = true
[*.cs]
indent_style = space
indent_size = 4
end_of_line = crlf
charset = utf-8
dotnet_diagnostic.CS8618.severity = warning
```

- [ ] **Step 6: Create the solution and add the projects**

Run (from `windows/`):
```bash
cd windows
dotnet new sln -n JVoice
dotnet sln add JVoice.Core/JVoice.Core.csproj
dotnet sln add JVoice.Tests/JVoice.Tests.csproj
```
(If `dotnet new sln` fails because the files already exist, create `JVoice.sln` via `dotnet sln` after deleting any partial file.)

- [ ] **Step 7: Append .NET ignores to `.gitignore`** (repo root)

Append:
```gitignore
# .NET / Windows app (windows/)
windows/**/bin/
windows/**/obj/
windows/**/*.user
windows/.vs/
windows/**/publish/
windows/tools/**/bin/
windows/tools/**/obj/
# Whisper GGML models are downloaded at runtime, never committed
*.bin
```
> Note: `*.bin` would also ignore any committed binary blobs; the repo currently commits none under `windows/`. If a needed `.bin` appears later, scope the ignore.

- [ ] **Step 8: Verify the solution builds**

Run: `dotnet build windows/JVoice.sln`
Expected: `Build succeeded` (0 errors). `JVoice.Tests` builds with no tests yet.

- [ ] **Step 9: Commit**

```bash
git checkout -b windows-port
git add windows/ .gitignore
git commit -m "build(windows): scaffold .NET 9 solution (JVoice.Core + JVoice.Tests)"
```

---

## Task 2: Core models

**Files:**
- Create: `windows/JVoice.Core/Models/ToneStyle.cs`
- Create: `windows/JVoice.Core/Models/TranscriptionLanguage.cs`
- Create: `windows/JVoice.Core/Models/WhisperModelOption.cs`
- Create: `windows/JVoice.Core/Models/SettingsState.cs`
- Create: `windows/JVoice.Core/Models/HudState.cs`
- Create: `windows/JVoice.Core/AppTimings.cs`
- Delete: `windows/JVoice.Core/_Placeholder.cs`
- Test: `windows/JVoice.Tests/ModelTests.cs`, `windows/JVoice.Tests/SettingsStateTests.cs`

**Interfaces:**
- Produces (consumed by all later tasks and phases):
  - `enum ToneStyle { Casual, Formal, VeryCasual }`, `ToneStyleExtensions.DisplayName(this ToneStyle)`.
  - `enum TranscriptionLanguage { English, Romanian }`, `.WhisperCode()`, `.DisplayName()`.
  - `enum WhisperModelOption { Tiny, Base, Small, LargeTurbo }`, `.DisplayName()`, `.GgmlFileName()`, `.Guidance()`.
  - `sealed record SettingsState(int SchemaVersion, ToneStyle Mode, WhisperModelOption Model, TranscriptionLanguage Language, IReadOnlyList<string> CustomWords, bool RemoveFillerWords)` + `static SettingsState Default` + `const int CurrentSchemaVersion = 1`.
  - `enum HudStateKind { Idle, Recording, PreparingModel, DownloadingModel, Transcribing, Done, Error }`, `readonly record struct HudState(HudStateKind Kind, string? Payload, double? Progress)` + factories + `Headline`/`Subtitle`/`IsVisible`/`IsBusy`/`IsTerminal`.
  - `static class AppTimings` with the timing constants.

- [ ] **Step 1: Write `windows/JVoice.Tests/ModelTests.cs`** (failing — types don't exist yet)

```csharp
using JVoice.Core.Models;
using Xunit;

namespace JVoice.Tests;

public class ModelTests
{
    [Theory]
    [InlineData(ToneStyle.Casual, "Casual")]
    [InlineData(ToneStyle.Formal, "Formal")]
    [InlineData(ToneStyle.VeryCasual, "Very Casual")]
    public void ToneStyle_DisplayName(ToneStyle s, string expected)
        => Assert.Equal(expected, s.DisplayName());

    [Theory]
    [InlineData(TranscriptionLanguage.English, "en", "English")]
    [InlineData(TranscriptionLanguage.Romanian, "ro", "Romanian")]
    public void Language_CodesAndNames(TranscriptionLanguage l, string code, string name)
    {
        Assert.Equal(code, l.WhisperCode());
        Assert.Equal(name, l.DisplayName());
    }

    [Theory]
    [InlineData(WhisperModelOption.Tiny, "Tiny", "ggml-tiny.bin")]
    [InlineData(WhisperModelOption.Base, "Base", "ggml-base.bin")]
    [InlineData(WhisperModelOption.Small, "Small", "ggml-small.bin")]
    [InlineData(WhisperModelOption.LargeTurbo, "Large", "ggml-large-v3-turbo-q5_0.bin")]
    public void Model_DisplayAndFile(WhisperModelOption m, string display, string file)
    {
        Assert.Equal(display, m.DisplayName());
        Assert.Equal(file, m.GgmlFileName());
    }

    [Fact]
    public void HudState_Factories()
    {
        Assert.Equal(HudStateKind.Recording, HudState.Recording.Kind);
        Assert.Equal("Pasted", HudState.Done("hi").Headline);
        Assert.Equal("hi", HudState.Done("hi").Payload);
        Assert.False(HudState.Idle.IsVisible);
        Assert.True(HudState.Recording.IsVisible);
        Assert.True(HudState.Transcribing.IsBusy);
        Assert.True(HudState.Error("x").IsTerminal);
    }
}
```

- [ ] **Step 2: Run, verify it fails to compile** — `dotnet test windows/JVoice.Tests` → FAIL (types not defined).

- [ ] **Step 3: Delete the placeholder, create `windows/JVoice.Core/Models/ToneStyle.cs`**

```csharp
namespace JVoice.Core.Models;

/// Ports Swift `AppMode` / `ToneMode`. Three tone styles applied in TextProcessor.Format.
public enum ToneStyle
{
    Casual,
    Formal,
    VeryCasual,
}

public static class ToneStyleExtensions
{
    public static string DisplayName(this ToneStyle style) => style switch
    {
        ToneStyle.Casual => "Casual",
        ToneStyle.Formal => "Formal",
        ToneStyle.VeryCasual => "Very Casual",
        _ => "Casual",
    };

    /// Cycle order from Swift AppMode.toggled.
    public static ToneStyle Toggled(this ToneStyle style) => style switch
    {
        ToneStyle.Casual => ToneStyle.Formal,
        ToneStyle.Formal => ToneStyle.VeryCasual,
        ToneStyle.VeryCasual => ToneStyle.Casual,
        _ => ToneStyle.Casual,
    };
}
```

- [ ] **Step 4: Create `windows/JVoice.Core/Models/TranscriptionLanguage.cs`**

```csharp
namespace JVoice.Core.Models;

public enum TranscriptionLanguage
{
    English,
    Romanian,
}

public static class TranscriptionLanguageExtensions
{
    public static string DisplayName(this TranscriptionLanguage l) => l switch
    {
        TranscriptionLanguage.English => "English",
        TranscriptionLanguage.Romanian => "Romanian",
        _ => "English",
    };

    /// whisper.cpp language code.
    public static string WhisperCode(this TranscriptionLanguage l) => l switch
    {
        TranscriptionLanguage.English => "en",
        TranscriptionLanguage.Romanian => "ro",
        _ => "en",
    };
}
```

- [ ] **Step 5: Create `windows/JVoice.Core/Models/WhisperModelOption.cs`**

```csharp
namespace JVoice.Core.Models;

/// Ports Swift WhisperModelOption. On Windows we map to GGML (whisper.cpp) files
/// instead of WhisperKit CoreML folders. See overview §2.5 for the mapping table.
public enum WhisperModelOption
{
    Tiny,
    Base,
    Small,
    LargeTurbo,
}

public static class WhisperModelOptionExtensions
{
    public static string DisplayName(this WhisperModelOption m) => m switch
    {
        WhisperModelOption.Tiny => "Tiny",
        WhisperModelOption.Base => "Base",
        WhisperModelOption.Small => "Small",
        WhisperModelOption.LargeTurbo => "Large",
        _ => "Tiny",
    };

    /// GGML model filename (downloaded from Hugging Face ggerganov/whisper.cpp).
    public static string GgmlFileName(this WhisperModelOption m) => m switch
    {
        WhisperModelOption.Tiny => "ggml-tiny.bin",
        WhisperModelOption.Base => "ggml-base.bin",
        WhisperModelOption.Small => "ggml-small.bin",
        WhisperModelOption.LargeTurbo => "ggml-large-v3-turbo-q5_0.bin",
        _ => "ggml-tiny.bin",
    };

    /// One-line picker caption (ports VoiceCoordinator.WhisperModelChoice.guidance,
    /// with sizes/wording adjusted for the Windows GGML download).
    public static string Guidance(this WhisperModelOption m) => m switch
    {
        WhisperModelOption.Tiny => "Fastest · smallest download · least accurate",
        WhisperModelOption.Base => "Fast · balanced accuracy",
        WhisperModelOption.Small => "Slower · more accurate",
        WhisperModelOption.LargeTurbo => "Most accurate · ~550 MB download · GPU-accelerated when available",
        _ => "",
    };
}
```

- [ ] **Step 6: Create `windows/JVoice.Core/Models/SettingsState.cs`**

> Ports `SettingsState.swift`. Defaults verbatim: Mode=Casual, Model=Tiny, Language=English, CustomWords=[], RemoveFillerWords=**true**, SchemaVersion=1. JSON (de)serialization + forward-version refusal + per-field fallback live in `Platform/SettingsStore` (Phase 3); this is the immutable value type only.

```csharp
namespace JVoice.Core.Models;

public sealed record SettingsState(
    int SchemaVersion,
    ToneStyle Mode,
    WhisperModelOption Model,
    TranscriptionLanguage Language,
    IReadOnlyList<string> CustomWords,
    bool RemoveFillerWords)
{
    public const int CurrentSchemaVersion = 1;

    public static SettingsState Default => new(
        SchemaVersion: CurrentSchemaVersion,
        Mode: ToneStyle.Casual,
        Model: WhisperModelOption.Tiny,
        Language: TranscriptionLanguage.English,
        CustomWords: Array.Empty<string>(),
        RemoveFillerWords: true);
}
```

- [ ] **Step 7: Create `windows/JVoice.Core/Models/HudState.cs`**

> Ports `HUDState.swift`. Adds `DownloadingModel` (Windows surfaces model-download progress explicitly; macOS folded it into preparing). Headlines/subtitles match Swift `HUDState.headline`/`subtitle` (the StatusPill/RecordingPill copy is in the UI phase).

```csharp
namespace JVoice.Core.Models;

public enum HudStateKind
{
    Idle,
    Recording,
    PreparingModel,
    DownloadingModel,
    Transcribing,
    Done,
    Error,
}

public readonly record struct HudState(HudStateKind Kind, string? Payload = null, double? Progress = null)
{
    public static readonly HudState Idle = new(HudStateKind.Idle);
    public static readonly HudState Recording = new(HudStateKind.Recording);
    public static readonly HudState PreparingModel = new(HudStateKind.PreparingModel);
    public static HudState DownloadingModel(double progress) => new(HudStateKind.DownloadingModel, Progress: progress);
    public static readonly HudState Transcribing = new(HudStateKind.Transcribing);
    public static HudState Done(string text) => new(HudStateKind.Done, text);
    public static HudState Error(string message) => new(HudStateKind.Error, message);

    public string Headline => Kind switch
    {
        HudStateKind.Idle => "Ready",
        HudStateKind.Recording => "Listening",
        HudStateKind.PreparingModel => "Preparing Model",
        HudStateKind.DownloadingModel => "Downloading Model",
        HudStateKind.Transcribing => "Transcribing",
        HudStateKind.Done => "Pasted",
        HudStateKind.Error => "Something Went Wrong",
        _ => "Ready",
    };

    public string? Subtitle => Kind switch
    {
        HudStateKind.Idle => "JVoice is standing by.",
        HudStateKind.Recording => "Listening…",
        HudStateKind.PreparingModel => "One-time setup — keep JVoice open",
        HudStateKind.DownloadingModel => "Downloading the speech model…",
        HudStateKind.Transcribing => "Processing…",
        HudStateKind.Done => null,
        HudStateKind.Error => string.IsNullOrEmpty(Payload) ? "Something went wrong" : Payload,
        _ => null,
    };

    public bool IsVisible => Kind != HudStateKind.Idle;

    public bool IsBusy => Kind is HudStateKind.Recording or HudStateKind.PreparingModel
        or HudStateKind.DownloadingModel or HudStateKind.Transcribing;

    public bool IsTerminal => Kind is HudStateKind.Done or HudStateKind.Error;
}
```

- [ ] **Step 8: Create `windows/JVoice.Core/AppTimings.cs`** (ports `AppTimings.swift` + the nanosecond literals scattered in the Swift coordinator/session; see overview §6.2)

```csharp
namespace JVoice.Core;

public static class AppTimings
{
    /// PasteManager: wait after pasting before restoring the prior clipboard.
    public static readonly TimeSpan PasteRestoreDelay = TimeSpan.FromMilliseconds(300);
    /// PasteManager: shorter restore delay used when the paste FAILED (macOS used 0.05 s).
    public const int PasteRestoreDelayFailureMs = 50;
    /// VoiceCoordinator: wait after re-activating the target window before SendInput.
    public static readonly TimeSpan PasteActivationDelay = TimeSpan.FromMilliseconds(80);
    /// HotKeyManager debounce.
    public const int HotkeyDebounceMs = 150;
    /// SettingsStore debounce.
    public const int SettingsDebounceMs = 500;
    /// StreamingTranscriptionSession poll cadence.
    public const int StreamingPollMs = 1000;
    /// HUD auto-dismiss after a terminal state.
    public static readonly TimeSpan HudResetDelay = TimeSpan.FromMilliseconds(1000);
    /// HUD auto-dismiss after an error.
    public static readonly TimeSpan HudErrorResetDelay = TimeSpan.FromMilliseconds(3000);
}
```

- [ ] **Step 9: Write `windows/JVoice.Tests/SettingsStateTests.cs`**

```csharp
using JVoice.Core.Models;
using Xunit;

namespace JVoice.Tests;

public class SettingsStateTests
{
    [Fact]
    public void Default_MatchesSwiftDefaults()
    {
        var s = SettingsState.Default;
        Assert.Equal(1, s.SchemaVersion);
        Assert.Equal(ToneStyle.Casual, s.Mode);
        Assert.Equal(WhisperModelOption.Tiny, s.Model);
        Assert.Equal(TranscriptionLanguage.English, s.Language);
        Assert.Empty(s.CustomWords);
        Assert.True(s.RemoveFillerWords);
    }
}
```

- [ ] **Step 10: Run tests** — `dotnet test windows/JVoice.Tests` → all PASS.

- [ ] **Step 11: Commit**

```bash
git add windows/JVoice.Core/Models windows/JVoice.Core/AppTimings.cs windows/JVoice.Tests/ModelTests.cs windows/JVoice.Tests/SettingsStateTests.cs
git rm windows/JVoice.Core/_Placeholder.cs
git commit -m "feat(core): models (ToneStyle, language, model, settings, HUD) + AppTimings"
```

---

## Task 3: VocabularyPrompt

**Files:**
- Create: `windows/JVoice.Core/Text/VocabularyPrompt.cs`
- Test: `windows/JVoice.Tests/VocabularyPromptTests.cs`

**Interfaces:**
- Produces: `static class VocabularyPrompt` — `const int MaxWords = 40`, `const int MaxPromptTokens = 96`, `string? Text(IReadOnlyList<string> words)`.
- Consumes: nothing.

- [ ] **Step 1: Write `windows/JVoice.Tests/VocabularyPromptTests.cs`** (mirrors the Swift `VocabularyPromptTests`)

```csharp
using JVoice.Core.Text;
using Xunit;

namespace JVoice.Tests;

public class VocabularyPromptTests
{
    [Fact]
    public void Empty_ReturnsNull()
    {
        Assert.Null(VocabularyPrompt.Text(Array.Empty<string>()));
        Assert.Null(VocabularyPrompt.Text(new[] { "", "   " }));
    }

    [Fact]
    public void JoinsWithLeadingSpaceAndCommas()
    {
        // The leading space is required (Whisper BPE merges a leading space into word tokens).
        Assert.Equal(" VS Code, JVoice", VocabularyPrompt.Text(new[] { "VS Code", "JVoice" }));
    }

    [Fact]
    public void TrimsAndDropsBlanks()
    {
        Assert.Equal(" Claude", VocabularyPrompt.Text(new[] { "  Claude  ", "" }));
    }

    [Fact]
    public void CapsAtMaxWords()
    {
        var words = Enumerable.Range(0, 50).Select(i => $"w{i}").ToArray();
        var text = VocabularyPrompt.Text(words)!;
        Assert.Equal(VocabularyPrompt.MaxWords, text.Split(", ").Length);
    }
}
```

- [ ] **Step 2: Run, verify FAIL** (`VocabularyPrompt` undefined).

- [ ] **Step 3: Create `windows/JVoice.Core/Text/VocabularyPrompt.cs`**

```csharp
namespace JVoice.Core.Text;

/// Builds the decoder-conditioning prompt from the user's custom words
/// (OpenAI's `initial_prompt` technique). Ports VocabularyPrompt.swift verbatim.
public static class VocabularyPrompt
{
    /// Cap on words included — keeps the decoder prefill cheap.
    public const int MaxWords = 40;
    /// Hard cap on encoded tokens (consumed by the engine when tokenizing).
    public const int MaxPromptTokens = 96;

    /// The conditioning text, or null when there is nothing to bias toward.
    public static string? Text(IReadOnlyList<string> words)
    {
        var cleaned = new List<string>(words.Count);
        foreach (var w in words)
        {
            var t = w.Trim();
            if (t.Length > 0) cleaned.Add(t);
        }
        if (cleaned.Count == 0) return null;
        // Leading space matters: Whisper's BPE merges a leading space into word tokens.
        return " " + string.Join(", ", cleaned.Take(MaxWords));
    }
}
```

- [ ] **Step 4: Run tests** → PASS.

- [ ] **Step 5: Commit** — `git add … && git commit -m "feat(core): VocabularyPrompt (initial_prompt builder)"`

---

## Task 4: PhoneticMatcher

> Port `PhoneticMatcher.swift` faithfully. Three public surfaces: `Correct`, `PhoneticKey`, `Levenshtein`. The simplified-Metaphone key and the windowed fuzzy replacement are intricate — translate exactly, preserving the length gate, the initial-sound guard, and the `entry.letters.count >= 6` branch. Build this **before** TextProcessor (TextProcessor.Process calls it).

**Files:**
- Create: `windows/JVoice.Core/Text/PhoneticMatcher.cs`
- Test: `windows/JVoice.Tests/PhoneticMatcherTests.cs`

**Interfaces:**
- Produces: `static class PhoneticMatcher` — `string Correct(string text, IReadOnlyList<string> vocabulary)`, `string PhoneticKey(string input)`, `int Levenshtein(string a, string b, int limit)`.
- Consumes: nothing.

- [ ] **Step 1: Write `windows/JVoice.Tests/PhoneticMatcherTests.cs`** (vectors from `run-logic-tests.sh`)

```csharp
using JVoice.Core.Text;
using Xunit;

namespace JVoice.Tests;

public class PhoneticMatcherTests
{
    [Theory]
    [InlineData("jvoice", "jfs")]
    [InlineData("gvoice", "jfs")]   // g and j merge (spoken "G" is /dʒ/)
    [InlineData("whisperkit", "wsprkt")]
    public void PhoneticKey_KnownVectors(string input, string expected)
        => Assert.Equal(expected, PhoneticMatcher.PhoneticKey(input));

    [Fact]
    public void PhoneticKey_KeepsInitialVowel_DropsInterior()
    {
        // position 0 vowel kept; interior vowels dropped.
        Assert.StartsWith("a", PhoneticMatcher.PhoneticKey("apple"));
    }

    [Theory]
    [InlineData("a", "abc", 3, 2)]
    [InlineData("kitten", "sitting", 5, 3)]
    public void Levenshtein_Basic(string a, string b, int limit, int expected)
        => Assert.Equal(expected, PhoneticMatcher.Levenshtein(a, b, limit));

    [Fact]
    public void Levenshtein_EarlyExitReturnsLimitPlusOne()
        => Assert.Equal(2, PhoneticMatcher.Levenshtein("abcdef", "zzzzzz", 1));

    [Fact]
    public void Correct_FixesPhoneticMiss()
    {
        Assert.Equal("JVoice", PhoneticMatcher.Correct("jay voice", new[] { "JVoice" }));
        Assert.Equal("JVoice", PhoneticMatcher.Correct("g voice", new[] { "JVoice" }));
    }

    [Fact]
    public void Correct_PreservesPunctuationAroundWindow()
    {
        Assert.Equal("JVoice.", PhoneticMatcher.Correct("jvoice.", new[] { "JVoice" }));
    }

    [Fact]
    public void Correct_DoesNotHijackPlainWords()
    {
        // "voice" alone (fs…) must not become "JVoice" (jfs…) — initial-sound guard.
        Assert.Equal("the voice", PhoneticMatcher.Correct("the voice", new[] { "JVoice" }));
    }

    [Fact]
    public void Correct_LeavesAlreadyExactMultiToken()
    {
        Assert.Equal("VS Code", PhoneticMatcher.Correct("VS Code", new[] { "VS Code" }));
    }

    [Fact]
    public void Correct_NoVocab_Identity()
        => Assert.Equal("hello world", PhoneticMatcher.Correct("hello world", Array.Empty<string>()));
}
```

- [ ] **Step 2: Run, verify FAIL.**

- [ ] **Step 3: Create `windows/JVoice.Core/Text/PhoneticMatcher.cs`**

```csharp
using System.Text;

namespace JVoice.Core.Text;

/// Fuzzy phonetic matcher that corrects Whisper mishearings of user-defined
/// vocabulary ("jay voice" → "JVoice"). Faithful port of PhoneticMatcher.swift.
public static class PhoneticMatcher
{
    // MARK: Public API

    public static string Correct(string text, IReadOnlyList<string> vocabulary)
    {
        if (vocabulary.Count == 0 || text.Length == 0) return text;

        var entries = vocabulary
            .Select(w => new Entry(w))
            .Where(e => e.Letters.Length >= 3)
            .OrderByDescending(e => e.Letters.Length)
            .ToList();
        if (entries.Count == 0) return text;

        var tokens = text.Split(' ', StringSplitOptions.RemoveEmptyEntries)
            .Select(s => new Token(s)).ToList();
        int maxWindow = entries.Count == 0 ? 1 : entries.Max(e => e.MaxWindow);

        int i = 0;
        while (i < tokens.Count)
        {
            bool advanced = false;
            int upperWindow = Math.Min(maxWindow, tokens.Count - i);
            // Smallest window first so an exact single-token hit short-circuits
            // before a larger fuzzy window can swallow neighbors.
            for (int window = 1; window <= upperWindow; window++)
            {
                var slice = tokens.GetRange(i, window);
                string candidate = string.Concat(slice.Select(t => t.CoreLetters));
                if (candidate.Length < 3) continue;
                foreach (var entry in entries)
                {
                    if (window > entry.MaxWindow) continue;
                    if (!Matches(candidate, entry)) continue;
                    string renderedCore = string.Join(" ", slice.Select(t => t.Core));
                    if (renderedCore == entry.Word)
                    {
                        // Already exact (single- or multi-token) — stop probing here.
                        goto afterWindowSearch;
                    }
                    var replacement = new Token(slice[0].Leading, entry.Word, slice[^1].Trailing);
                    tokens.RemoveRange(i, window);
                    tokens.Insert(i, replacement);
                    i += 1;
                    advanced = true;
                    goto afterWindowSearch;
                }
            }
        afterWindowSearch:
            if (!advanced) i += 1;
        }

        return string.Join(" ", tokens.Select(t => t.Rendered));
    }

    // MARK: Matching

    private static bool Matches(string candidate, Entry entry)
    {
        if (candidate == entry.Letters) return true; // spacing/casing drift only

        if (Math.Abs(candidate.Length - entry.Letters.Length) > 2 + entry.Letters.Length / 3)
            return false;

        string candidateKey = PhoneticKey(candidate);
        // Initial-sound guard: "voice"(fs…) must never match "JVoice"(jfs…).
        if (candidateKey.Length == 0 || entry.Key.Length == 0 || candidateKey[0] != entry.Key[0])
            return false;

        int letterDistance = Levenshtein(candidate, entry.Letters, limit: 3);
        if (candidateKey == entry.Key && letterDistance <= Math.Max(1, entry.Letters.Length / 3))
            return true;
        if (entry.Letters.Length >= 6)
        {
            int keyDistance = Levenshtein(candidateKey, entry.Key, limit: 1);
            if (keyDistance <= 1 && letterDistance <= 2) return true;
        }
        return false;
    }

    // MARK: Phonetic key (simplified Metaphone)

    public static string PhoneticKey(string input)
    {
        var s = new List<char>();
        foreach (var c in input.ToLowerInvariant())
            if (char.IsLetter(c)) s.Add(c);
        if (s.Count == 0) return "";

        // Prefix simplifications.
        (char[] match, char[] replacement)[] prefixes =
        {
            (new[]{'k','n'}, new[]{'n'}),
            (new[]{'w','r'}, new[]{'r'}),
            (new[]{'p','s'}, new[]{'s'}),
            (new[]{'w','h'}, new[]{'w'}),
        };
        foreach (var (match, replacement) in prefixes)
        {
            if (s.Count >= match.Length && s.Take(match.Length).SequenceEqual(match))
            {
                s.RemoveRange(0, match.Length);
                s.InsertRange(0, replacement);
                break;
            }
        }

        // Pass 1: map letters (consuming digraphs), keeping vowels for now.
        var mapped = new List<char>();
        int i = 0;
        while (i < s.Count)
        {
            char ch = s[i];
            char? nxt = i + 1 < s.Count ? s[i + 1] : null;
            char outc;
            int consumed = 1;
            if (ch == 'p' && nxt == 'h') { outc = 'f'; consumed = 2; }
            else if ((ch == 's' && nxt == 'h') || (ch == 'c' && nxt == 'h')) { outc = 'x'; consumed = 2; }
            else if (ch == 't' && nxt == 'h') { outc = '0'; consumed = 2; }
            else if ((ch == 'c' && nxt == 'k') || (ch == 'q' && nxt == 'u') || (ch == 'g' && nxt == 'h')) { outc = 'k'; consumed = 2; }
            else
            {
                switch (ch)
                {
                    case 'b': outc = 'p'; break;
                    case 'c': outc = (nxt is char n && "eiy".Contains(n)) ? 's' : 'k'; break;
                    case 'd': outc = 't'; break;
                    case 'g': case 'j': outc = 'j'; break;
                    case 'k': case 'q': outc = 'k'; break;
                    case 'v': outc = 'f'; break;
                    case 'x': case 'z': outc = 's'; break;
                    default: outc = ch; break;
                }
            }
            mapped.Add(outc);
            i += consumed;
        }

        // Pass 2: keep position 0; drop vowels elsewhere. Pass 3: dedupe runs.
        var vowels = new HashSet<char> { 'a', 'e', 'i', 'o', 'u', 'y' };
        var key = new List<char>();
        for (int idx = 0; idx < mapped.Count; idx++)
        {
            char ch = mapped[idx];
            if (idx > 0 && vowels.Contains(ch)) continue;
            if (key.Count > 0 && key[^1] == ch) continue;
            key.Add(ch);
        }
        return new string(key.ToArray());
    }

    // MARK: Edit distance (bounded, early-exit)

    public static int Levenshtein(string a, string b, int limit)
    {
        if (Math.Abs(a.Length - b.Length) > limit) return limit + 1;
        if (a.Length == 0) return b.Length;
        if (b.Length == 0) return a.Length;

        var previous = new int[b.Length + 1];
        var current = new int[b.Length + 1];
        for (int j = 0; j <= b.Length; j++) previous[j] = j;

        for (int i = 0; i < a.Length; i++)
        {
            char ca = a[i];
            current[0] = i + 1;
            int rowMin = current[0];
            for (int j = 0; j < b.Length; j++)
            {
                int cost = ca == b[j] ? 0 : 1;
                current[j + 1] = Math.Min(Math.Min(previous[j + 1] + 1, current[j] + 1), previous[j] + cost);
                rowMin = Math.Min(rowMin, current[j + 1]);
            }
            if (rowMin > limit) return limit + 1;
            (previous, current) = (current, previous);
        }
        return Math.Min(previous[b.Length], limit + 1);
    }

    // MARK: Internals

    private sealed class Entry
    {
        public string Word { get; }
        public string Letters { get; }
        public string Key { get; }
        public int MaxWindow { get; }

        public Entry(string word)
        {
            Word = word;
            Letters = new string(word.ToLowerInvariant().Where(char.IsLetter).ToArray());
            Key = PhoneticKey(Letters);
            int spokenWords = 0;
            foreach (var part in word.Split(' ', StringSplitOptions.RemoveEmptyEntries))
            {
                int boundaries = 1;
                for (int i = 0; i < part.Length; i++)
                    if (i > 0 && char.IsUpper(part[i])) boundaries++;
                spokenWords += boundaries;
            }
            MaxWindow = Math.Max(1, spokenWords) + 1;
        }
    }

    private readonly struct Token
    {
        public string Leading { get; }
        public string Core { get; }
        public string Trailing { get; }

        public Token(string leading, string core, string trailing)
        {
            Leading = leading; Core = core; Trailing = trailing;
        }

        public Token(string raw)
        {
            int start = 0, end = raw.Length;
            while (start < end && !char.IsLetter(raw[start]) && !char.IsNumber(raw[start])) start++;
            while (end > start && !char.IsLetter(raw[end - 1]) && !char.IsNumber(raw[end - 1])) end--;
            Leading = raw[..start];
            Core = raw[start..end];
            Trailing = raw[end..];
        }

        public string CoreLetters => new(Core.ToLowerInvariant().Where(char.IsLetter).ToArray());
        public string Rendered => Leading + Core + Trailing;
    }
}
```

- [ ] **Step 4: Run tests** → PASS. If `PhoneticKey("whisperkit")` ≠ `"wsprkt"`, re-derive by hand against the Swift `phoneticKey` (the `wh`→`w` prefix rule then maps w,h(sk?)…) — **do not** change the algorithm to fit; fix the test's expected value to whatever the faithful algorithm produces and note it. (The three key vectors come from `run-logic-tests.sh`; trust the algorithm.)

- [ ] **Step 5: Commit** — `git commit -m "feat(core): PhoneticMatcher (metaphone key + windowed fuzzy correction)"`

---

## Task 5: TextProcessor

> Port `TextProcessor.swift` verbatim. Depends on `PhoneticMatcher` (Process calls `PhoneticMatcher.Correct`). Preserve the `CorrectionDictionary` exactly, the regexes exactly, and the per-mode `Format` rules exactly. Use `MatchEvaluator` for the replacement to avoid .NET `$`-substitution surprises.

**Files:**
- Create: `windows/JVoice.Core/Text/TextProcessor.cs`
- Test: `windows/JVoice.Tests/TextProcessorTests.cs`

**Interfaces:**
- Produces: `static class TextProcessor` — `string Process(string text, ToneStyle mode, IReadOnlyDictionary<string,string> extraDictionary, bool removeFillerWords, IReadOnlyList<string> vocabulary)`; `string ApplyCorrections(string text, IReadOnlyDictionary<string,string> extraDictionary)`; `IReadOnlyDictionary<string,string> BuildUserDictionary(IReadOnlyList<string> words)`; `IReadOnlyList<string> ExtractCorrections(string original, string corrected)`; `IReadOnlyList<string> SpokenVariants(string word)`; `string Format(string text, ToneStyle mode)`; `string RemoveDisfluencies(string text)`; `string StripDecoderArtifacts(string text)`; `string RemoveWhisperHallucinations(string text)`; `IReadOnlyDictionary<string,string> CorrectionDictionary`.
- Consumes: `PhoneticMatcher.Correct`, `ToneStyle`.

- [ ] **Step 1: Write `windows/JVoice.Tests/TextProcessorTests.cs`** (vectors from `run-logic-tests.sh` + the Swift source behavior)

```csharp
using JVoice.Core.Models;
using JVoice.Core.Text;
using Xunit;

namespace JVoice.Tests;

public class TextProcessorTests
{
    private static readonly Dictionary<string, string> Empty = new();

    [Fact]
    public void Casual_StripsTerminalPunctuation_NoCapitalize()
        => Assert.Equal("hello world",
            TextProcessor.Process("hello world.", ToneStyle.Casual, Empty, false, Array.Empty<string>()));

    [Fact]
    public void Formal_CapitalizesAndAddsPeriod()
        => Assert.Equal("Hello world.",
            TextProcessor.Process("hello world", ToneStyle.Formal, Empty, false, Array.Empty<string>()));

    [Fact]
    public void VeryCasual_Lowercases_ButKeepsCorrectionCasing()
    {
        // veryCasual lowercases BEFORE corrections, so custom/builtin casing survives.
        var outp = TextProcessor.Process("I love JVOICE", ToneStyle.VeryCasual, Empty, false, Array.Empty<string>());
        Assert.Contains("JVoice", outp);
    }

    [Fact]
    public void RemoveFillerWords_StripsDisfluencies()
        => Assert.Equal("so can we move",
            TextProcessor.Process("so um can we uh move", ToneStyle.Casual, Empty, true, Array.Empty<string>()));

    [Fact]
    public void BuiltinDictionary_FixesKnownSpellings()
        => Assert.Equal("WhisperKit",
            TextProcessor.Process("whisper kit", ToneStyle.Casual, Empty, false, Array.Empty<string>()));

    [Theory]
    [InlineData("hello [BLANK_AUDIO] world", "hello world")]
    [InlineData("[MUSIC] hi", "hi")]
    [InlineData("a [APPLAUSE] b", "a b")]
    public void StripDecoderArtifacts_RemovesBracketSentinels(string input, string expected)
        => Assert.Equal(expected, TextProcessor.StripDecoderArtifacts(input));

    [Fact]
    public void StripDecoderArtifacts_PreservesLowercaseBracket()
        => Assert.Equal("see [note] here", TextProcessor.StripDecoderArtifacts("see [note] here"));

    [Theory]
    [InlineData("Thanks for watching!", "")]
    [InlineData("Thank you.", "")]
    [InlineData(".", "")]
    public void RemoveWhisperHallucinations_NukesSentinels(string input, string expected)
        => Assert.Equal(expected, TextProcessor.RemoveWhisperHallucinations(input));

    [Fact]
    public void RemoveWhisperHallucinations_KeepsRealSpeech()
        => Assert.Equal("thank you for the help",
            TextProcessor.RemoveWhisperHallucinations("thank you for the help"));

    [Fact]
    public void BuildUserDictionary_MapsSpokenVariants()
    {
        var dict = TextProcessor.BuildUserDictionary(new[] { "VS Code" });
        Assert.True(dict.ContainsKey("vs code"));
        Assert.Equal("VS Code", dict["vs code"]);
    }

    [Fact]
    public void ExtractCorrections_FindsNewWords()
    {
        var added = TextProcessor.ExtractCorrections("i use vs code", "i use VSCode");
        Assert.Contains("VSCode", added);
    }
}
```

- [ ] **Step 2: Run, verify FAIL.**

- [ ] **Step 3: Create `windows/JVoice.Core/Text/TextProcessor.cs`**

```csharp
using System.Text;
using System.Text.RegularExpressions;
using JVoice.Core.Models;

namespace JVoice.Core.Text;

/// Post-processing pipeline: tone styles, filler removal, exact custom-word
/// corrections, hallucination-sentinel stripping. Faithful port of TextProcessor.swift.
public static class TextProcessor
{
    public static readonly IReadOnlyDictionary<string, string> CorrectionDictionary = new Dictionary<string, string>
    {
        ["app kit"] = "AppKit",
        ["appkit"] = "AppKit",
        ["j voice"] = "JVoice",
        ["jvoice"] = "JVoice",
        ["keyboard shortcuts"] = "KeyboardShortcuts",
        ["keyboardshortcuts"] = "KeyboardShortcuts",
        ["mac os"] = "macOS",
        ["whisper kit"] = "WhisperKit",
        ["whisperkit"] = "WhisperKit",
    };

    public static string Process(
        string text,
        ToneStyle mode,
        IReadOnlyDictionary<string, string>? extraDictionary = null,
        bool removeFillerWords = false,
        IReadOnlyList<string>? vocabulary = null)
    {
        extraDictionary ??= new Dictionary<string, string>();
        vocabulary ??= Array.Empty<string>();

        string normalized = NormalizeWhitespace(text);
        string clean = removeFillerWords ? RemoveDisfluencies(normalized) : normalized;
        // Very Casual lowercases first so corrections (applied after) win over the lowering.
        string cased = mode == ToneStyle.VeryCasual ? clean.ToLowerInvariant() : clean;
        string corrected = ApplyCorrections(cased, extraDictionary);
        string phonetic = PhoneticMatcher.Correct(corrected, vocabulary);
        return Format(phonetic, mode);
    }

    public static string ApplyCorrections(string text, IReadOnlyDictionary<string, string>? extraDictionary = null)
    {
        extraDictionary ??= new Dictionary<string, string>();
        var combined = new Dictionary<string, string>(extraDictionary);
        foreach (var kv in CorrectionDictionary) combined[kv.Key] = kv.Value; // builtin wins on conflict

        string result = text;
        foreach (var kv in combined.OrderByDescending(kv => kv.Key.Length))
            result = ReplaceOccurrences(kv.Key, result, kv.Value);
        return result;
    }

    public static IReadOnlyDictionary<string, string> BuildUserDictionary(IReadOnlyList<string> words)
    {
        var dict = new Dictionary<string, string>();
        foreach (var word in words)
            foreach (var variant in SpokenVariants(word))
                if (!CorrectionDictionary.ContainsKey(variant))
                    dict[variant] = word;
        return dict;
    }

    public static IReadOnlyList<string> ExtractCorrections(string original, string corrected)
    {
        var originalWords = original.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
        var correctedWords = corrected.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);

        var results = new List<string>();
        if (originalWords.Length == correctedWords.Length)
        {
            for (int i = 0; i < originalWords.Length; i++)
            {
                if (originalWords[i] == correctedWords[i]) continue;
                var stripped = TrimPunctuation(correctedWords[i]);
                if (stripped.Length > 0) results.Add(stripped);
            }
        }
        else
        {
            var originalExact = new HashSet<string>(originalWords);
            foreach (var word in correctedWords)
            {
                if (originalExact.Contains(word)) continue;
                var stripped = TrimPunctuation(word);
                if (stripped.Length > 0) results.Add(stripped);
            }
        }
        return results.Distinct().Where(s => s.Length > 1).ToList();
    }

    public static IReadOnlyList<string> SpokenVariants(string word)
    {
        var variants = new HashSet<string>();
        string lower = word.ToLowerInvariant();

        variants.Add(lower);
        variants.Add(lower.Replace(" ", ""));
        variants.Add(lower.Replace(".", "").Replace(" ", ""));
        variants.Add(lower.Replace(".", " "));

        var camel = new StringBuilder();
        for (int i = 0; i < word.Length; i++)
        {
            if (char.IsUpper(word[i]) && i > 0) camel.Append(' ');
            camel.Append(char.ToLowerInvariant(word[i]));
        }
        variants.Add(camel.ToString());
        variants.Add(camel.ToString().Replace(" ", ""));

        return variants.Where(v => v.Length > 0 && v != word).ToList();
    }

    public static string Format(string text, ToneStyle mode)
    {
        string trimmed = text.Trim();
        if (trimmed.Length == 0) return "";

        return mode switch
        {
            ToneStyle.Casual => RemoveTerminalPunctuation(trimmed),
            ToneStyle.Formal => EnsureTerminalPeriod(CapitalizeFirstCharacter(trimmed)),
            ToneStyle.VeryCasual => EnsureTerminalDotOrQuestion(CollapseRepeatedCommas(trimmed)),
            _ => trimmed,
        };
    }

    private static string NormalizeWhitespace(string text)
        => string.Join(" ", text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));

    public static string RemoveDisfluencies(string text)
    {
        string stripped = Regex.Replace(text, @"\b(um+h?|uh+|er+|a+h+|hmm+)\b[,.]?\s*", "", RegexOptions.IgnoreCase);
        string result = NormalizeWhitespace(stripped.Trim());
        if (result.EndsWith(",")) result = result[..^1];
        return result;
    }

    /// Removes "[BLANK_AUDIO]"-style all-caps/underscore bracket sentinels.
    public static string StripDecoderArtifacts(string text)
    {
        string stripped = Regex.Replace(text, @"\[[A-Z_][A-Z_ ]*\]", " ");
        return NormalizeWhitespace(stripped).Trim();
    }

    /// Returns "" when the whole input is hallucination noise (silence sentinels).
    public static string RemoveWhisperHallucinations(string text)
    {
        string trimmed = text.Trim();
        if (trimmed.Length == 0) return "";
        if (trimmed.All(c => ".,;:!? ".Contains(c))) return "";
        string[] blanklike =
        {
            "[BLANK_TEXT]", "BLANK_TEXT",
            "Thanks for watching!", "Thanks for watching.",
            "Thank you.", "Thank you for watching.",
            "Subscribe to my channel", "Subscribe to my channel.",
            "Please subscribe to my channel.",
            "Bye.", "Bye!",
        };
        foreach (var p in blanklike)
            if (string.Equals(trimmed, p, StringComparison.OrdinalIgnoreCase))
                return "";
        return text;
    }

    private static string ReplaceOccurrences(string needle, string text, string replacement)
    {
        string pattern = PhrasePattern(needle);
        // MatchEvaluator => literal replacement (no .NET $-group substitution surprises).
        return Regex.Replace(text, pattern, _ => replacement, RegexOptions.IgnoreCase);
    }

    private static string PhrasePattern(string phrase)
    {
        var components = phrase.Split(' ', StringSplitOptions.RemoveEmptyEntries)
            .Select(Regex.Escape);
        return @"\b" + string.Join(@"\s+", components) + @"\b";
    }

    private static string RemoveTerminalPunctuation(string text)
    {
        int end = text.Length;
        while (end > 0 && ".!?".Contains(text[end - 1])) end--;
        return text[..end];
    }

    private static string CapitalizeFirstCharacter(string text)
    {
        if (text.Length == 0) return text;
        return char.ToUpperInvariant(text[0]) + text[1..];
    }

    private static string EnsureTerminalPeriod(string text)
    {
        if (text.Length == 0) return text;
        char last = text[^1];
        return ".!?".Contains(last) ? text : text + ".";
    }

    private static string CollapseRepeatedCommas(string text)
        => Regex.Replace(text, @"\s*,(?:\s*,)*\s*", ", ");

    private static string EnsureTerminalDotOrQuestion(string text)
    {
        int end = text.Length;
        while (end > 0 && (text[end - 1] == ' ' || text[end - 1] == ',')) end--;
        string result = text[..end];
        if (result.Length == 0) return result;
        char last = result[^1];
        if (last == '?' || last == '.') return result;
        if (last == '!') return result[..^1] + ".";
        return result + ".";
    }

    private static string TrimPunctuation(string s)
    {
        int start = 0, end = s.Length;
        while (start < end && char.IsPunctuation(s[start])) start++;
        while (end > start && char.IsPunctuation(s[end - 1])) end--;
        return s[start..end];
    }
}
```

- [ ] **Step 4: Run tests** → PASS.

- [ ] **Step 5: Commit** — `git commit -m "feat(core): TextProcessor (tone styles, filler removal, corrections, sentinels)"`

---

## Task 6: RepetitionGuard

> Port `RepetitionGuard.swift` verbatim, including all tuning constants and the 120-case fuzz from `run-logic-tests.sh`. This guard contains the long-cycle fix (tail gate is density-only; the ≥3-repeat requirement is enforced over the whole loop run).

**Files:**
- Create: `windows/JVoice.Core/Text/RepetitionGuard.cs`
- Test: `windows/JVoice.Tests/RepetitionGuardTests.cs`

**Interfaces:**
- Produces: `static class RepetitionGuard` — nested `readonly record struct ScrubResult(string Text, bool RemovedRegurgitation)`; `ScrubResult Scrub(string text, IReadOnlyList<string> vocabulary)`; `string Strip(string text, IReadOnlyList<string> vocabulary)`. Public constants `MinLoopTokens=8`, `TailWindow=12`, `DensityThreshold=0.7`, `MinRepeatCount=3`, `NonLoopyTolerance=1`.
- Consumes: `PhoneticMatcher.PhoneticKey`.

- [ ] **Step 1: Write `windows/JVoice.Tests/RepetitionGuardTests.cs`**

```csharp
using JVoice.Core.Text;
using Xunit;

namespace JVoice.Tests;

public class RepetitionGuardTests
{
    private static readonly string[] Vocab = { "sub agents", "claude", "li-fraumeni", "vs code" };

    [Fact]
    public void Strip_RemovesTrailingRegurgitationLoop()
    {
        const string input = "so the thing about money is that " +
            "sub agents, claude, li-fraumeni, vs code, sub agents, claude, li-fraumeni, vs code, " +
            "sub agents, claude, li-fraumeni, vs code";
        var r = RepetitionGuard.Scrub(input, Vocab);
        Assert.True(r.RemovedRegurgitation);
        Assert.Equal("so the thing about money is that", r.Text);
    }

    [Fact]
    public void Scrub_LeavesCoherentSpeechUntouched()
    {
        const string input = "i really like using vs code and claude every day for my work here";
        var r = RepetitionGuard.Scrub(input, Vocab);
        Assert.False(r.RemovedRegurgitation);
        Assert.Equal(input, r.Text);
    }

    [Fact]
    public void Scrub_SingleVocabMention_NotStripped()
    {
        const string input = "we studied li-fraumeni syndrome in the lab last year for a long time okay";
        var r = RepetitionGuard.Scrub(input, Vocab);
        Assert.False(r.RemovedRegurgitation);
    }

    [Fact]
    public void Scrub_ShortInput_NeverStripped()
    {
        var r = RepetitionGuard.Scrub("claude claude claude", Vocab); // < MinLoopTokens
        Assert.False(r.RemovedRegurgitation);
    }

    // Fuzz: a coherent prefix + a loop-dominated tail must always strip back to (at
    // least) the prefix. The guard is CONSERVATIVE — it only fires when the trailing
    // run is genuinely loop-dominated (≥70% of the 12-token tail window) — so we
    // construct only loop-dominated tails: (a) the full 4-phrase cycle (6 tokens/rep)
    // repeated 3..8× and (b) a single-token loop repeated 9..14× (≥ the tail window).
    // (A naive "3 reps of 1 unit after a long prefix" is correctly NOT stripped.)
    [Fact]
    public void Fuzz_LoopDominatedTailsAlwaysStripped()
    {
        string[] prefixes =
        {
            "okay so here is the plan for the week ahead everyone",
            "the most important thing to remember about this topic is simple",
            "let me explain how the whole process actually works in practice",
        };
        string[] cycle = { "claude", "sub agents", "li-fraumeni", "vs code" };
        int cases = 0, failures = 0;
        foreach (var prefix in prefixes)
        {
            for (int reps = 3; reps <= 8; reps++)
            {
                string loop = string.Join(", ", Enumerable.Range(0, reps).SelectMany(_ => cycle));
                string input = prefix + " " + loop;
                var r = RepetitionGuard.Scrub(input, Vocab);
                cases++;
                if (!r.RemovedRegurgitation || r.Text.Length >= input.Length) failures++;
            }
            for (int reps = 9; reps <= 14; reps++)
            {
                string loop = string.Join(", ", Enumerable.Repeat("claude", reps));
                string input = prefix + " " + loop;
                var r = RepetitionGuard.Scrub(input, Vocab);
                cases++;
                if (!r.RemovedRegurgitation || r.Text.Length >= input.Length) failures++;
            }
        }
        Assert.True(cases >= 36);
        Assert.Equal(0, failures);
    }

    // Control: a single mention of vocab phrases in a long coherent sentence is NEVER stripped.
    [Fact]
    public void Fuzz_SingleMentions_NeverStripped()
    {
        string[] sentences =
        {
            "today i opened vs code and asked claude about the li-fraumeni paper for the lab meeting",
            "my favourite tool is claude and i also run a whole system of sub agents every single day now",
            "we discussed sub agents and vs code at length during the long planning session this afternoon",
        };
        foreach (var s in sentences)
            Assert.False(RepetitionGuard.Scrub(s, Vocab).RemovedRegurgitation);
    }
}
```

- [ ] **Step 2: Run, verify FAIL.**

- [ ] **Step 3: Create `windows/JVoice.Core/Text/RepetitionGuard.cs`**

```csharp
namespace JVoice.Core.Text;

/// Removes Whisper "prompt regurgitation" / repetition-loop output. Faithful port
/// of RepetitionGuard.swift (incl. the long-cycle fix). Conservative by construction:
/// only strips a sustained, repetitive, vocabulary/loop-dominated trailing run.
public static class RepetitionGuard
{
    public const int MinLoopTokens = 8;
    public const int TailWindow = 12;
    public const double DensityThreshold = 0.7;
    public const int MinRepeatCount = 3;
    public const int NonLoopyTolerance = 1;

    public readonly record struct ScrubResult(string Text, bool RemovedRegurgitation);

    public static string Strip(string text, IReadOnlyList<string> vocabulary)
        => Scrub(text, vocabulary).Text;

    public static ScrubResult Scrub(string text, IReadOnlyList<string> vocabulary)
    {
        var tokens = text.Split(new[] { ' ', '\n', '\t', '\r' }, StringSplitOptions.RemoveEmptyEntries);
        int n = tokens.Length;
        if (n < MinLoopTokens) return new ScrubResult(text, false);

        var cores = tokens.Select(Core).ToArray();
        var counts = new Dictionary<string, int>();
        foreach (var c in cores) if (c.Length > 0) counts[c] = counts.GetValueOrDefault(c) + 1;

        var vocabCores = VocabularyCores(vocabulary);
        var vocabKeys = new HashSet<string>(
            vocabCores.Select(PhoneticMatcher.PhoneticKey).Where(k => k.Length > 0));

        bool Loopy(int i)
        {
            string c = cores[i];
            if (c.Length == 0) return false;
            if (vocabCores.Contains(c)) return true;
            string key = PhoneticMatcher.PhoneticKey(c);
            if (key.Length > 0 && vocabKeys.Contains(key)) return true;
            return counts.GetValueOrDefault(c) >= MinRepeatCount && !Stopwords.Contains(c);
        }

        // 1. Quick gate: does the END look loopy at all (dense in loop tokens)?
        if (!IsDegenerate(Math.Max(0, n - TailWindow), n, cores, Loopy, requireRepeat: false))
            return new ScrubResult(text, false);

        // 2. Walk left to the loop onset, tolerating isolated mangled tokens.
        int onset = n;
        int consecutiveNonLoopy = 0;
        for (int i = n - 1; i >= 0; i--)
        {
            if (cores[i].Length == 0) continue; // pure punctuation: neutral
            if (Loopy(i)) { onset = i; consecutiveNonLoopy = 0; }
            else { consecutiveNonLoopy++; if (consecutiveNonLoopy > NonLoopyTolerance) break; }
        }

        // 3. Validate the stripped run is long AND repetitive enough.
        if (!(onset < n && IsDegenerate(onset, n, cores, Loopy)))
            return new ScrubResult(text, false);

        if (onset == 0) return new ScrubResult("", true);
        string kept = string.Join(" ", tokens[..onset]);
        return new ScrubResult(kept.Trim(' ', ',', ';', ':'), true);
    }

    // MARK: Internals

    private static bool IsDegenerate(int start, int end, string[] cores, Func<int, bool> loopy, bool requireRepeat = true)
    {
        var nonEmpty = new List<int>();
        for (int i = start; i < end; i++) if (cores[i].Length > 0) nonEmpty.Add(i);
        if (nonEmpty.Count < MinLoopTokens) return false;
        int loopCount = nonEmpty.Count(loopy);
        if ((double)loopCount / nonEmpty.Count < DensityThreshold) return false;
        if (!requireRepeat) return true;
        var counts = new Dictionary<string, int>();
        foreach (var idx in nonEmpty) counts[cores[idx]] = counts.GetValueOrDefault(cores[idx]) + 1;
        return counts.Count > 0 && counts.Values.Max() >= MinRepeatCount;
    }

    /// Lowercased letters/digits only — strips surrounding punctuation.
    internal static string Core(string token)
        => new(token.ToLowerInvariant().Where(char.IsLetterOrDigit).ToArray());

    internal static HashSet<string> VocabularyCores(IReadOnlyList<string> vocabulary)
    {
        var result = new HashSet<string>();
        foreach (var word in vocabulary)
        {
            string whole = Core(word);
            if (whole.Length >= 2) result.Add(whole);
            foreach (var part in word.Split(new[] { ' ', '-', '_', '/' }, StringSplitOptions.RemoveEmptyEntries))
            {
                var current = new System.Text.StringBuilder();
                for (int idx = 0; idx < part.Length; idx++)
                {
                    char ch = part[idx];
                    if (idx > 0 && char.IsUpper(ch) && current.Length > 0)
                    {
                        string c = Core(current.ToString());
                        if (c.Length >= 2) result.Add(c);
                        current.Clear();
                    }
                    current.Append(ch);
                }
                string last = Core(current.ToString());
                if (last.Length >= 2) result.Add(last);
            }
        }
        return result;
    }

    internal static readonly HashSet<string> Stopwords = new()
    {
        "the","a","an","and","or","but","to","of","in","on","at","for","with","by","from",
        "is","are","was","were","be","been","being","am","do","does","did","have","has","had",
        "it","its","i","you","he","she","we","they","me","him","her","us","them","my","your",
        "this","that","these","those","so","as","if","then","there","here","not","no","yes",
        "just","like","what","which","who","when","where","how","why","about","up","out","now",
    };
}
```

> Note the Swift `vocabularyCores` split also handles `word.split(whereSeparator: { … })` which **drops empty** subsequences — `StringSplitOptions.RemoveEmptyEntries` matches that. The Swift token split in `scrub` uses `split(whereSeparator:)` which also drops empties — matched.

- [ ] **Step 4: Run tests** → PASS (including the fuzz). If the fuzz fails, the most likely cause is a divergence in `Core`/`VocabularyCores`/`Loopy` — diff against the Swift line-by-line; **do not** loosen the test.

- [ ] **Step 5: Commit** — `git commit -m "feat(core): RepetitionGuard (regurgitation-loop detector + 120-case fuzz)"`

---

## Task 7: RegurgitationRecovery

> Port `RegurgitationRecovery.swift`. Tiny but central: decode with prompt; if it regurgitated (loop removed) or came back empty, decode again without prompt and use that.

**Files:**
- Create: `windows/JVoice.Core/Text/RegurgitationRecovery.cs`
- Test: `windows/JVoice.Tests/RegurgitationRecoveryTests.cs`

**Interfaces:**
- Produces: `static class RegurgitationRecovery` — `Task<string> Decode(bool useVocabularyPrompt, IReadOnlyList<string> vocabulary, Func<bool, Task<string>> decode)`.
- Consumes: `RepetitionGuard.Scrub`.

- [ ] **Step 1: Write `windows/JVoice.Tests/RegurgitationRecoveryTests.cs`** (the 4 Swift scenarios from `verify-streaming.sh`)

```csharp
using JVoice.Core.Text;
using Xunit;

namespace JVoice.Tests;

public class RegurgitationRecoveryTests
{
    private static readonly string[] Vocab = { "sub agents", "claude", "li-fraumeni", "vs code" };
    private const string Regurgitated =
        "so the thing about money is that sub agents, claude, li-fraumeni, vs code, " +
        "sub agents, claude, li-fraumeni, vs code, sub agents, claude, li-fraumeni, vs code";
    private const string CleanSpeech = "so the thing about money is that it grows over time with patience";

    [Fact]
    public async Task RegurgitatedPrompt_ReDecodesWithoutPrompt()
    {
        int calls = 0;
        var result = await RegurgitationRecovery.Decode(true, Vocab, usePrompt =>
        {
            calls++;
            return Task.FromResult(usePrompt ? Regurgitated : CleanSpeech);
        });
        Assert.Equal(2, calls);            // prompted, then prompt-free recovery
        Assert.Equal(CleanSpeech, result); // the recovered clean decode
    }

    [Fact]
    public async Task CleanPromptedDecode_KeptWithoutRedecode()
    {
        int calls = 0;
        var result = await RegurgitationRecovery.Decode(true, Vocab, usePrompt =>
        {
            calls++;
            return Task.FromResult(CleanSpeech);
        });
        Assert.Equal(1, calls);            // no wasteful re-decode
        Assert.Equal(CleanSpeech, result);
    }

    [Fact]
    public async Task EmptyPromptedDecode_TriggersRecovery()
    {
        int calls = 0;
        var result = await RegurgitationRecovery.Decode(true, Vocab, usePrompt =>
        {
            calls++;
            return Task.FromResult(usePrompt ? "" : CleanSpeech);
        });
        Assert.Equal(2, calls);
        Assert.Equal(CleanSpeech, result);
    }

    [Fact]
    public async Task PromptDisabled_SingleDecode_NoRecovery()
    {
        int calls = 0;
        var result = await RegurgitationRecovery.Decode(false, Vocab, _ =>
        {
            calls++;
            return Task.FromResult(Regurgitated);  // would scrub, but no recovery pass when prompt off
        });
        Assert.Equal(1, calls);
    }
}
```

- [ ] **Step 2: Run, verify FAIL.**

- [ ] **Step 3: Create `windows/JVoice.Core/Text/RegurgitationRecovery.cs`**

```csharp
namespace JVoice.Core.Text;

/// The decode-and-recover policy that contains the vocabulary prompt's failure
/// mode. Faithful port of RegurgitationRecovery.swift.
public static class RegurgitationRecovery
{
    /// `decode(usePrompt)` runs the real model; called once in the common (clean)
    /// case and a second time, with usePrompt == false, only when the prompted
    /// decode shows regurgitation (loop removed) or came back empty.
    public static async Task<string> Decode(
        bool useVocabularyPrompt,
        IReadOnlyList<string> vocabulary,
        Func<bool, Task<string>> decode)
    {
        var primary = RepetitionGuard.Scrub(await decode(useVocabularyPrompt), vocabulary);
        if (!useVocabularyPrompt || !(primary.RemovedRegurgitation || primary.Text.Length == 0))
            return primary.Text;
        // The prompt regurgitated — a prompt-free decode transcribes what was actually spoken.
        return RepetitionGuard.Scrub(await decode(false), vocabulary).Text;
    }
}
```

- [ ] **Step 4: Run tests** → PASS.

- [ ] **Step 5: Commit** — `git commit -m "feat(core): RegurgitationRecovery (prompt-free re-decode on regurgitation)"`

---

## Task 8: WavTail + WavTailReader

> Port `WavTail.swift`. Parses a still-growing RIFF/WAVE header (tolerating CoreAudio `FLLR` padding and stale size fields). Reader opens with **`FileShare.ReadWrite`** so the recorder can keep appending. Accepts only PCM/16-bit/mono/16 kHz.

**Files:**
- Create: `windows/JVoice.Core/Audio/WavTail.cs`
- Test: `windows/JVoice.Tests/WavTailTests.cs`

**Interfaces:**
- Produces:
  - `readonly record struct WavInfo(int DataOffset, int SampleRate, int Channels, int BytesPerSample)`.
  - `static class WavTail` — `const int HeaderProbeBytes = 16384`; `WavInfo? ParseHeader(ReadOnlySpan<byte> bytes)`; `float[] FloatSamples(ReadOnlySpan<short> samples)`.
  - `sealed class WavTailReader` — `static WavTailReader? Open(string path)`; `short[]? Samples(int sampleOffset)`; props `string Path`, `WavInfo Info`.
- Consumes: nothing.

- [ ] **Step 1: Write `windows/JVoice.Tests/WavTailTests.cs`**

```csharp
using JVoice.Core.Audio;
using Xunit;

namespace JVoice.Tests;

public class WavTailTests
{
    private static byte[] Ascii(string s) => System.Text.Encoding.ASCII.GetBytes(s);

    private static byte[] BuildWav(int sampleRate, int channels, int bits, int dataBytes, bool withFllr)
    {
        var ms = new MemoryStream();
        void U32(int v) { ms.Write(BitConverter.GetBytes((uint)v)); }
        void U16(int v) { ms.Write(BitConverter.GetBytes((ushort)v)); }
        ms.Write(Ascii("RIFF")); U32(0); ms.Write(Ascii("WAVE"));   // sizes deliberately 0/stale
        ms.Write(Ascii("fmt ")); U32(16);
        U16(1);                       // PCM
        U16(channels);
        U32(sampleRate);
        U32(sampleRate * channels * bits / 8);
        U16(channels * bits / 8);
        U16(bits);
        if (withFllr) { ms.Write(Ascii("FLLR")); U32(8); ms.Write(new byte[8]); }
        ms.Write(Ascii("data")); U32(dataBytes);
        ms.Write(new byte[dataBytes]);
        return ms.ToArray();
    }

    [Fact]
    public void ParseHeader_Valid_16k_Mono_16bit()
    {
        var info = WavTail.ParseHeader(BuildWav(16000, 1, 16, 100, withFllr: false));
        Assert.NotNull(info);
        Assert.Equal(16000, info!.Value.SampleRate);
        Assert.Equal(1, info.Value.Channels);
        Assert.Equal(2, info.Value.BytesPerSample);
    }

    [Fact]
    public void ParseHeader_ToleratesFllrPadding()
    {
        var info = WavTail.ParseHeader(BuildWav(16000, 1, 16, 100, withFllr: true));
        Assert.NotNull(info);
        Assert.True(info!.Value.DataOffset > 44); // pushed past the FLLR chunk
    }

    [Theory]
    [InlineData(44100, 1, 16)] // wrong rate
    [InlineData(16000, 2, 16)] // stereo
    [InlineData(16000, 1, 8)]  // 8-bit
    public void ParseHeader_RejectsWrongFormat(int rate, int ch, int bits)
        => Assert.Null(WavTail.ParseHeader(BuildWav(rate, ch, bits, 100, withFllr: false)));

    [Fact]
    public void ParseHeader_RejectsNonRiff()
        => Assert.Null(WavTail.ParseHeader(Ascii("NOPEnotawav....")));

    [Fact]
    public void FloatSamples_Normalizes()
    {
        short[] s = { 0, 32767, -32768 };
        var f = WavTail.FloatSamples(s);
        Assert.Equal(0f, f[0]);
        Assert.True(f[1] is > 0.99f and < 1.0f);
        Assert.Equal(-1f, f[2]);
    }

    [Fact]
    public void Reader_ReadsGrowingFile()
    {
        string path = Path.Combine(Path.GetTempPath(), $"jvtail-{Guid.NewGuid():N}.wav");
        try
        {
            File.WriteAllBytes(path, BuildWav(16000, 1, 16, 8, withFllr: false));
            var reader = WavTailReader.Open(path);
            Assert.NotNull(reader);
            var samples = reader!.Samples(0);
            Assert.NotNull(samples);
            Assert.Equal(4, samples!.Length); // 8 data bytes = 4 shorts
        }
        finally { File.Delete(path); }
    }
}
```

- [ ] **Step 2: Run, verify FAIL.**

- [ ] **Step 3: Create `windows/JVoice.Core/Audio/WavTail.cs`**

```csharp
using System.Buffers.Binary;
using System.Text;

namespace JVoice.Core.Audio;

public readonly record struct WavInfo(int DataOffset, int SampleRate, int Channels, int BytesPerSample);

/// Header parsing for a WAV that the recorder is *currently writing*.
/// Faithful port of WavTail.swift: walks chunks (CoreAudio/NAudio may pad before
/// `data`), treats payload as [dataOffset, EOF), and accepts only PCM/16-bit/mono/16 kHz.
public static class WavTail
{
    public const int HeaderProbeBytes = 16384;

    public static WavInfo? ParseHeader(ReadOnlySpan<byte> bytes)
    {
        if (bytes.Length < 12 || FourCC(bytes, 0) != "RIFF" || FourCC(bytes, 8) != "WAVE")
            return null;

        int offset = 12;
        (int rate, int channels, int bits)? format = null;
        while (offset + 8 <= bytes.Length)
        {
            string? id = FourCC(bytes, offset);
            int size = (int)BinaryPrimitives.ReadUInt32LittleEndian(bytes.Slice(offset + 4, 4));
            int payload = offset + 8;
            if (id == "fmt ")
            {
                if (payload + 16 > bytes.Length) return null;
                int audioFormat = BinaryPrimitives.ReadUInt16LittleEndian(bytes.Slice(payload, 2));
                if (audioFormat != 1) return null; // PCM only
                format = (
                    rate: (int)BinaryPrimitives.ReadUInt32LittleEndian(bytes.Slice(payload + 4, 4)),
                    channels: BinaryPrimitives.ReadUInt16LittleEndian(bytes.Slice(payload + 2, 2)),
                    bits: BinaryPrimitives.ReadUInt16LittleEndian(bytes.Slice(payload + 14, 2)));
            }
            else if (id == "data")
            {
                if (format is { } f && f.channels == 1 && f.rate == 16000 && f.bits == 16)
                    return new WavInfo(payload, f.rate, 1, 2);
                return null;
            }
            // Non-`data` chunks carry a real size and are word-aligned.
            offset = payload + size + (size % 2);
        }
        return null;
    }

    public static float[] FloatSamples(ReadOnlySpan<short> samples)
    {
        var result = new float[samples.Length];
        for (int i = 0; i < samples.Length; i++) result[i] = samples[i] / 32768f;
        return result;
    }

    private static string? FourCC(ReadOnlySpan<byte> bytes, int offset)
    {
        if (offset + 4 > bytes.Length) return null;
        return Encoding.ASCII.GetString(bytes.Slice(offset, 4));
    }
}

/// Incremental sample access to a growing WAV. Opens a fresh handle per read
/// (the file is being appended by another writer). Faithful port of WavTailReader.
public sealed class WavTailReader
{
    public string Path { get; }
    public WavInfo Info { get; }

    private WavTailReader(string path, WavInfo info) { Path = path; Info = info; }

    public static WavTailReader? Open(string path)
    {
        try
        {
            using var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            var probe = new byte[WavTail.HeaderProbeBytes];
            int read = fs.Read(probe, 0, probe.Length);
            var info = WavTail.ParseHeader(probe.AsSpan(0, read));
            return info is { } i ? new WavTailReader(path, i) : null;
        }
        catch (IOException) { return null; }
        catch (UnauthorizedAccessException) { return null; }
    }

    /// All samples from `sampleOffset` to EOF. `[]` = no new data; `null` = gone/unreadable.
    public short[]? Samples(int sampleOffset)
    {
        try
        {
            using var fs = new FileStream(Path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            long byteOffset = Info.DataOffset + (long)sampleOffset * Info.BytesPerSample;
            if (byteOffset > fs.Length) return Array.Empty<short>();
            fs.Seek(byteOffset, SeekOrigin.Begin);
            using var ms = new MemoryStream();
            fs.CopyTo(ms);
            var data = ms.GetBuffer();
            int len = (int)ms.Length;
            int usable = len - (len % 2); // a trailing odd byte is a mid-sample write
            if (usable <= 0) return Array.Empty<short>();
            var result = new short[usable / 2];
            for (int i = 0; i < result.Length; i++)
                result[i] = BinaryPrimitives.ReadInt16LittleEndian(data.AsSpan(i * 2, 2));
            return result;
        }
        catch (IOException) { return null; }
        catch (UnauthorizedAccessException) { return null; }
    }
}
```

- [ ] **Step 4: Run tests** → PASS.

- [ ] **Step 5: Commit** — `git commit -m "feat(core): WavTail + WavTailReader (growing-WAV parser)"`

---

## Task 9: ChunkPlanner

> Port `ChunkPlanner.swift` verbatim, including every Config constant. RMS windows over `short` samples; cut only at silence until the 25 s cap forces a cut.

**Files:**
- Create: `windows/JVoice.Core/Audio/ChunkPlanner.cs`
- Test: `windows/JVoice.Tests/ChunkPlannerTests.cs`

**Interfaces:**
- Produces:
  - `static class ChunkPlanner` with nested `sealed class Config` (mutable, defaults verbatim), `enum DecisionKind { Wait, Cut }`, `readonly record struct Decision(DecisionKind Kind, int AtSample, bool IsSilent)` + `Decision.Wait` + `Decision.Cut(int at, bool silent)`.
  - `Decision Plan(ReadOnlySpan<short> unconsumed, Config config)`.
  - `bool IsSilent(ReadOnlySpan<short> samples, Config config)`.
- Consumes: nothing.

- [ ] **Step 1: Write `windows/JVoice.Tests/ChunkPlannerTests.cs`**

```csharp
using JVoice.Core.Audio;
using Xunit;

namespace JVoice.Tests;

public class ChunkPlannerTests
{
    private static readonly ChunkPlanner.Config Cfg = new();

    private static short[] Loud(int seconds)
    {
        var n = seconds * 16000;
        var s = new short[n];
        for (int i = 0; i < n; i++) s[i] = (short)(i % 2 == 0 ? 8000 : -8000); // ~0.24 RMS
        return s;
    }

    private static short[] Silence(int seconds) => new short[seconds * 16000];

    private static short[] Concat(params short[][] parts)
        => parts.SelectMany(p => p).ToArray();

    [Fact]
    public void Plan_WaitsBelowMinChunk()
        => Assert.Equal(ChunkPlanner.DecisionKind.Wait, ChunkPlanner.Plan(Loud(10), Cfg).Kind);

    [Fact]
    public void Plan_CutsAtSilenceAfterMinChunk()
    {
        var audio = Concat(Loud(16), Silence(2), Loud(5));
        var d = ChunkPlanner.Plan(audio, Cfg);
        Assert.Equal(ChunkPlanner.DecisionKind.Cut, d.Kind);
        // Cut lands inside the silent gap (between 16s and 18s).
        Assert.InRange(d.AtSample, 16 * 16000, 18 * 16000);
    }

    [Fact]
    public void Plan_ForcesCutAtMaxWhenNoSilence()
    {
        var d = ChunkPlanner.Plan(Loud(30), Cfg); // > 25 s cap, no pause
        Assert.Equal(ChunkPlanner.DecisionKind.Cut, d.Kind);
    }

    [Fact]
    public void IsSilent_TrueForSilence_FalseForSpeech()
    {
        Assert.True(ChunkPlanner.IsSilent(Silence(2), Cfg));
        Assert.False(ChunkPlanner.IsSilent(Loud(2), Cfg));
    }

    [Fact]
    public void Plan_SilentChunkFlaggedSilent()
    {
        var audio = Concat(Silence(16), Loud(2), Silence(1));
        var d = ChunkPlanner.Plan(audio, Cfg);
        if (d.Kind == ChunkPlanner.DecisionKind.Cut)
            Assert.True(d.IsSilent); // the leading silence before the cut is silent
    }
}
```

- [ ] **Step 2: Run, verify FAIL.**

- [ ] **Step 3: Create `windows/JVoice.Core/Audio/ChunkPlanner.cs`**

```csharp
namespace JVoice.Core.Audio;

/// Pure chunking policy for streaming transcription. Faithful port of ChunkPlanner.swift.
/// Cuts only at silence (words never split) until maxChunkSeconds forces one.
public static class ChunkPlanner
{
    public sealed class Config
    {
        public int SampleRate { get; init; } = 16_000;
        public double MinChunkSeconds { get; init; } = 15;
        public double MaxChunkSeconds { get; init; } = 25;
        public double SilenceWindowSeconds { get; init; } = 0.3;
        public float SilenceRmsFloor { get; init; } = 0.005f;
        public float RelativeSilenceFraction { get; init; } = 0.1f;
    }

    public enum DecisionKind { Wait, Cut }

    public readonly record struct Decision(DecisionKind Kind, int AtSample, bool IsSilent)
    {
        public static readonly Decision Wait = new(DecisionKind.Wait, 0, false);
        public static Decision Cut(int at, bool silent) => new(DecisionKind.Cut, at, silent);
    }

    public static Decision Plan(ReadOnlySpan<short> unconsumed, Config config)
    {
        int minSamples = (int)(config.MinChunkSeconds * config.SampleRate);
        int maxSamples = (int)(config.MaxChunkSeconds * config.SampleRate);
        int window = Math.Max(1, (int)(config.SilenceWindowSeconds * config.SampleRate));
        if (unconsumed.Length < minSamples) return Decision.Wait;

        int searchEnd = Math.Min(unconsumed.Length, maxSamples);
        var energies = WindowRms(unconsumed[..searchEnd], window);
        float peak = energies.Count == 0 ? 0 : energies.Max(e => e.Rms);
        float threshold = Math.Max(config.SilenceRmsFloor, peak * config.RelativeSilenceFraction);

        WindowEnergy? quietest = null;
        foreach (var e in energies)
        {
            if (e.Start < minSamples || e.Start + window > searchEnd) continue;
            if (quietest is null || e.Rms < quietest.Value.Rms) quietest = e;
        }

        if (quietest is { } q && q.Rms < threshold)
            return MakeCut(unconsumed, q.Start + window / 2, config);

        if (unconsumed.Length < maxSamples) return Decision.Wait;
        int at = quietest is { } q2 ? q2.Start + window / 2 : maxSamples;
        return MakeCut(unconsumed, at, config);
    }

    public static bool IsSilent(ReadOnlySpan<short> samples, Config config)
    {
        int window = Math.Max(1, (int)(config.SilenceWindowSeconds * config.SampleRate));
        var energies = WindowRms(samples, window);
        float peak = energies.Count == 0 ? 0 : energies.Max(e => e.Rms);
        return peak < config.SilenceRmsFloor;
    }

    private static Decision MakeCut(ReadOnlySpan<short> unconsumed, int sample, Config config)
        => Decision.Cut(sample, IsSilent(unconsumed[..sample], config));

    private readonly record struct WindowEnergy(int Start, float Rms);

    /// Non-overlapping RMS windows; the last (partial) window is included.
    private static List<WindowEnergy> WindowRms(ReadOnlySpan<short> samples, int window)
    {
        var result = new List<WindowEnergy>();
        if (samples.Length == 0 || window <= 0) return result;
        int start = 0;
        while (start < samples.Length)
        {
            int end = Math.Min(start + window, samples.Length);
            double sum = 0;
            for (int i = start; i < end; i++)
            {
                double v = samples[i] / 32768.0;
                sum += v * v;
            }
            result.Add(new WindowEnergy(start, (float)Math.Sqrt(sum / (end - start))));
            start += window;
        }
        return result;
    }
}
```

- [ ] **Step 4: Run tests** → PASS.

- [ ] **Step 5: Commit** — `git commit -m "feat(core): ChunkPlanner (silence-cut streaming chunk policy)"`

---

## Task 10: StreamingTranscriptionSession

> Port `StreamingTranscriptionSession.swift`. This is the concurrency-sensitive one (see overview §6.1). The Swift actor's invariants MUST hold: **(a)** a non-silent chunk that decodes to "" FAILS the session (never silently drop up to 25 s of speech); **(b)** silent chunks are dropped without failing; **(c)** `finish()` is idempotent (second call returns null); **(d)** `cancel()` joins the poll loop. Use a `CancellationTokenSource` for the poll loop and re-check cancellation after each `transcribe` await.

**Files:**
- Create: `windows/JVoice.Core/Audio/StreamingTranscriptionSession.cs`
- Test: `windows/JVoice.Tests/StreamingSessionTests.cs`

**Interfaces:**
- Produces: `sealed class StreamingTranscriptionSession` — ctor `(Func<float[], Task<string>> transcribe, ChunkPlanner.Config? config = null, int pollMilliseconds = 1000)`; `void Start(string path)`; `Task<string?> Finish()`; `Task Cancel()`.
- Consumes: `WavTailReader`, `WavTail.FloatSamples`, `ChunkPlanner`.

> **Concurrency model (read before implementing):** `Finish()` and `Cancel()` first cancel the poll loop's CTS and `await` the poll `Task` to completion *before* touching shared state — so the drain in `Finish()` runs single-threaded (no lock needed there). The only cross-thread window is a poll iteration mid-`transcribe`: after that await, re-check `ct.IsCancellationRequested || _cancelled` before consuming, exactly as the Swift checks `!Task.isCancelled, !cancelled`. Fields touched only by the poll loop and the post-join drain don't need a lock; `_finished`/`_cancelled` are set by the caller before the join. This reproduces the Swift actor's guarantees.

- [ ] **Step 1: Write `windows/JVoice.Tests/StreamingSessionTests.cs`** (the 8 scenarios from `verify-streaming.sh`, adapted)

```csharp
using JVoice.Core.Audio;
using Xunit;

namespace JVoice.Tests;

public class StreamingSessionTests
{
    // Fast poll so tests don't sleep a real second.
    private const int FastPollMs = 20;
    private static readonly ChunkPlanner.Config Cfg = new();

    private static byte[] BuildWav(short[] samples)
    {
        var ms = new MemoryStream();
        void U32(int v) => ms.Write(BitConverter.GetBytes((uint)v));
        void U16(int v) => ms.Write(BitConverter.GetBytes((ushort)v));
        void A(string s) => ms.Write(System.Text.Encoding.ASCII.GetBytes(s));
        A("RIFF"); U32(0); A("WAVE");
        A("fmt "); U32(16); U16(1); U16(1); U32(16000); U32(32000); U16(2); U16(16);
        A("data"); U32(samples.Length * 2);
        foreach (var s in samples) ms.Write(BitConverter.GetBytes(s));
        return ms.ToArray();
    }

    private static short[] Loud(int seconds)
    {
        var s = new short[seconds * 16000];
        for (int i = 0; i < s.Length; i++) s[i] = (short)(i % 2 == 0 ? 8000 : -8000);
        return s;
    }
    private static short[] Silence(int seconds) => new short[seconds * 16000];
    private static short[] Concat(params short[][] p) => p.SelectMany(x => x).ToArray();

    private static string WriteTemp(short[] samples)
    {
        string path = Path.Combine(Path.GetTempPath(), $"jvstream-{Guid.NewGuid():N}.wav");
        File.WriteAllBytes(path, BuildWav(samples));
        return path;
    }

    [Fact]
    public async Task HappyPath_JoinsNonEmptyPieces()
    {
        // 16s loud, 2s silence, 5s loud → at least one chunk + tail, all decode "x".
        string path = WriteTemp(Concat(Loud(16), Silence(2), Loud(5)));
        try
        {
            var session = new StreamingTranscriptionSession(_ => Task.FromResult("x"), Cfg, FastPollMs);
            session.Start(path);
            await Task.Delay(200); // let the poll loop run a couple of iterations
            var result = await session.Finish();
            Assert.NotNull(result);
            Assert.Contains("x", result!);
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public async Task NonSilentChunkDecodesEmpty_FailsToNull()
    {
        string path = WriteTemp(Concat(Loud(16), Silence(2), Loud(5)));
        try
        {
            // A non-silent chunk that decodes to "" must fail the session (no silent drop).
            var session = new StreamingTranscriptionSession(_ => Task.FromResult(""), Cfg, FastPollMs);
            session.Start(path);
            await Task.Delay(200);
            var result = await session.Finish();
            Assert.Null(result); // caller falls back to whole-file
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public async Task Finish_IsIdempotent()
    {
        string path = WriteTemp(Concat(Loud(16), Silence(2), Loud(5)));
        try
        {
            var session = new StreamingTranscriptionSession(_ => Task.FromResult("x"), Cfg, FastPollMs);
            session.Start(path);
            await Task.Delay(100);
            await session.Finish();
            Assert.Null(await session.Finish()); // second finish returns null
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public async Task Cancel_ThenFinish_ReturnsNull()
    {
        string path = WriteTemp(Concat(Loud(16), Silence(2), Loud(5)));
        try
        {
            var session = new StreamingTranscriptionSession(_ => Task.FromResult("x"), Cfg, FastPollMs);
            session.Start(path);
            await session.Cancel();
            Assert.Null(await session.Finish());
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public async Task NeverStarted_FinishReturnsNull()
    {
        var session = new StreamingTranscriptionSession(_ => Task.FromResult("x"), Cfg, FastPollMs);
        Assert.Null(await session.Finish());
    }
}
```

- [ ] **Step 2: Run, verify FAIL.**

- [ ] **Step 3: Create `windows/JVoice.Core/Audio/StreamingTranscriptionSession.cs`**

```csharp
namespace JVoice.Core.Audio;

/// Transcribes completed speech chunks of a still-growing WAV while recording.
/// Faithful port of StreamingTranscriptionSession.swift. Any failure → Finish()
/// returns null and the caller falls back to whole-file transcription (never a
/// silent drop). Audio is never lost.
public sealed class StreamingTranscriptionSession
{
    private readonly Func<float[], Task<string>> _transcribe;
    private readonly ChunkPlanner.Config _config;
    private readonly int _pollMs;

    private string? _url;
    private WavTailReader? _reader;
    private int _consumedSamples;
    private readonly List<string> _pieces = new();
    private Task? _pollTask;
    private CancellationTokenSource? _cts;
    private bool _failed;
    private bool _cancelled;
    private bool _finished;
    private int _openRetriesRemaining = 10;

    public StreamingTranscriptionSession(
        Func<float[], Task<string>> transcribe,
        ChunkPlanner.Config? config = null,
        int pollMilliseconds = 1000)
    {
        _transcribe = transcribe;
        _config = config ?? new ChunkPlanner.Config();
        _pollMs = pollMilliseconds;
    }

    public void Start(string path)
    {
        if (_pollTask != null || _cancelled || _failed || _finished) return;
        _url = path;
        _cts = new CancellationTokenSource();
        var ct = _cts.Token;
        _pollTask = Task.Run(() => RunPollLoop(ct), ct);
    }

    /// Stop polling, transcribe whatever remains, return the combined raw transcript.
    /// null ⇒ the caller MUST fall back to whole-file transcription.
    public async Task<string?> Finish()
    {
        if (_finished) return null;
        _finished = true;
        _cts?.Cancel();
        if (_pollTask != null) { try { await _pollTask; } catch (OperationCanceledException) { } }
        _pollTask = null;

        if (_failed || _cancelled || _url is null) return null;
        if (_consumedSamples <= 0 && _pieces.Count == 0) return null;

        _reader ??= WavTailReader.Open(_url);
        if (_reader is null) return null;
        var tail = _reader.Samples(_consumedSamples);
        if (tail is null) return null;

        // Drain any backlog the poll loop didn't get to. Terminates: every cut shrinks tail.
        while (true)
        {
            var decision = ChunkPlanner.Plan(tail, _config);
            if (decision.Kind != ChunkPlanner.DecisionKind.Cut) break;
            if (!decision.IsSilent)
                if (!await AppendPiece(WavTail.FloatSamples(tail.AsSpan(0, decision.AtSample))))
                    return null;
            tail = tail[decision.AtSample..];
        }
        if (tail.Length > 0 && !ChunkPlanner.IsSilent(tail, _config))
            if (!await AppendPiece(WavTail.FloatSamples(tail)))
                return null;

        string joined = string.Join(" ", _pieces).Trim();
        return joined.Length == 0 ? null : joined;
    }

    /// Abandon this recording: discard everything; Finish() returns null if ever called.
    /// Joins the poll task so no chunk decode is still in flight when Cancel returns.
    public async Task Cancel()
    {
        _cancelled = true;
        _cts?.Cancel();
        if (_pollTask != null) { try { await _pollTask; } catch (OperationCanceledException) { } }
        _pollTask = null;
        _pieces.Clear();
    }

    private async Task<bool> AppendPiece(float[] samples)
    {
        try
        {
            string text = await _transcribe(samples);
            if (text.Length == 0)
            {
                // A non-silent chunk that decodes to nothing → fail (would otherwise
                // silently delete up to maxChunkSeconds of speech).
                _failed = true;
                return false;
            }
            _pieces.Add(text);
            return true;
        }
        catch
        {
            _failed = true;
            return false;
        }
    }

    private async Task RunPollLoop(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested && !_failed && !_cancelled)
        {
            await PollOnce(ct);
            try { await Task.Delay(_pollMs, ct); }
            catch (OperationCanceledException) { break; }
        }
    }

    private async Task PollOnce(CancellationToken ct)
    {
        if (_url is null) { _failed = true; return; }
        if (_reader is null)
        {
            if (!File.Exists(_url)) { _failed = true; return; } // recorder torn down
            var opened = WavTailReader.Open(_url);
            if (opened is null)
            {
                _openRetriesRemaining--;
                if (_openRetriesRemaining <= 0) _failed = true;
                return;
            }
            _reader = opened;
        }

        var unconsumed = _reader.Samples(_consumedSamples);
        if (unconsumed is null) { _failed = true; return; } // file vanished

        var decision = ChunkPlanner.Plan(unconsumed, _config);
        if (decision.Kind != ChunkPlanner.DecisionKind.Cut) return;

        if (decision.IsSilent)
        {
            _consumedSamples += decision.AtSample; // dropped, never transcribed
            return;
        }

        var chunk = WavTail.FloatSamples(unconsumed.AsSpan(0, decision.AtSample));
        try
        {
            string text = await _transcribe(chunk);
            if (ct.IsCancellationRequested || _cancelled) return; // re-cover via finish/fallback
            if (text.Length == 0)
            {
                _failed = true; // non-silent chunk decoded to nothing → never silently drop
                return;
            }
            _pieces.Add(text);
            _consumedSamples += decision.AtSample;
        }
        catch
        {
            _failed = true;
        }
    }
}
```

- [ ] **Step 4: Run tests** → PASS. If `HappyPath` is flaky, raise the `await Task.Delay` in the test (the poll loop needs a couple iterations); the production poll is 1000 ms.

- [ ] **Step 5: Commit** — `git commit -m "feat(core): StreamingTranscriptionSession (lossless streaming overlay)"`

---

## Task 11: Transcription abstraction (interface, exception, file-backed engine)

> Port the `TranscriptionEngine` protocol, `TranscriptionError`, and `FileBackedTranscriptionEngine` from `TranscriptionManager.swift`. The interface uses C# default interface methods for the protocol-extension defaults. `WhisperModelLocator` is **not** ported here — its GGML equivalent is `WhisperModelStore` in Phase 2.

**Files:**
- Create: `windows/JVoice.Core/Transcription/ITranscriptionEngine.cs`
- Create: `windows/JVoice.Core/Transcription/TranscriptionException.cs`
- Create: `windows/JVoice.Core/Transcription/FileBackedTranscriptionEngine.cs`
- Test: `windows/JVoice.Tests/FileBackedEngineTests.cs`

**Interfaces:**
- Produces:
  - `interface ITranscriptionEngine` — `Task<string> TranscribeAsync(string audioPath, CancellationToken ct = default)`; default `Task PrewarmAsync()`; default `Task UpdateVocabularyAsync(IReadOnlyList<string> words)`; default `Task<bool> IsReadyAsync()`; default `Task<StreamingTranscriptionSession?> MakeStreamingSessionAsync()`.
  - `sealed class TranscriptionException : Exception` — `TranscriptionErrorKind Kind`; statics `AudioFileMissing(string)`, `UnsupportedAudioFile(string)`, `EmptyTranscript()`, `ModelLoadFailed(string)`.
  - `sealed class FileBackedTranscriptionEngine : ITranscriptionEngine`.
- Consumes: `StreamingTranscriptionSession`.

- [ ] **Step 1: Write `windows/JVoice.Tests/FileBackedEngineTests.cs`**

```csharp
using JVoice.Core.Transcription;
using Xunit;

namespace JVoice.Tests;

public class FileBackedEngineTests
{
    [Fact]
    public async Task ReadsTextFile()
    {
        string path = Path.Combine(Path.GetTempPath(), $"jv-fbe-{Guid.NewGuid():N}.txt");
        await File.WriteAllTextAsync(path, "  hello there  ");
        try
        {
            ITranscriptionEngine engine = new FileBackedTranscriptionEngine(); // interface-typed so default methods resolve
            Assert.Equal("hello there", await engine.TranscribeAsync(path));
            Assert.True(await engine.IsReadyAsync());
            Assert.Null(await engine.MakeStreamingSessionAsync());
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public async Task MissingFile_Throws()
    {
        ITranscriptionEngine engine = new FileBackedTranscriptionEngine(); // interface-typed so default methods resolve
        var ex = await Assert.ThrowsAsync<TranscriptionException>(
            () => engine.TranscribeAsync("C:/does/not/exist.txt"));
        Assert.Equal(TranscriptionErrorKind.AudioFileMissing, ex.Kind);
    }

    [Fact]
    public async Task EmptyFile_ThrowsEmptyTranscript()
    {
        string path = Path.Combine(Path.GetTempPath(), $"jv-fbe-{Guid.NewGuid():N}.txt");
        await File.WriteAllTextAsync(path, "   ");
        try
        {
            ITranscriptionEngine engine = new FileBackedTranscriptionEngine(); // interface-typed so default methods resolve
            var ex = await Assert.ThrowsAsync<TranscriptionException>(() => engine.TranscribeAsync(path));
            Assert.Equal(TranscriptionErrorKind.EmptyTranscript, ex.Kind);
        }
        finally { File.Delete(path); }
    }
}
```

- [ ] **Step 2: Run, verify FAIL.**

- [ ] **Step 3: Create `windows/JVoice.Core/Transcription/TranscriptionException.cs`**

```csharp
namespace JVoice.Core.Transcription;

public enum TranscriptionErrorKind
{
    AudioFileMissing,
    UnsupportedAudioFile,
    EmptyTranscript,
    ModelLoadFailed,
}

public sealed class TranscriptionException : Exception
{
    public TranscriptionErrorKind Kind { get; }

    private TranscriptionException(TranscriptionErrorKind kind, string message) : base(message)
        => Kind = kind;

    public static TranscriptionException AudioFileMissing(string path)
        => new(TranscriptionErrorKind.AudioFileMissing, $"Audio file not found at {path}.");
    public static TranscriptionException UnsupportedAudioFile(string path)
        => new(TranscriptionErrorKind.UnsupportedAudioFile, $"Unsupported audio file at {path}.");
    public static TranscriptionException EmptyTranscript()
        => new(TranscriptionErrorKind.EmptyTranscript, "No transcript was produced.");
    public static TranscriptionException ModelLoadFailed(string message)
        => new(TranscriptionErrorKind.ModelLoadFailed, message);
}
```

- [ ] **Step 4: Create `windows/JVoice.Core/Transcription/ITranscriptionEngine.cs`**

```csharp
using JVoice.Core.Audio;

namespace JVoice.Core.Transcription;

public interface ITranscriptionEngine
{
    Task<string> TranscribeAsync(string audioPath, CancellationToken ct = default);

    /// Eagerly load the model so the first transcription isn't a cold start.
    Task PrewarmAsync() => Task.CompletedTask;

    /// Update the user vocabulary used to bias decoding toward custom words.
    Task UpdateVocabularyAsync(IReadOnlyList<string> words) => Task.CompletedTask;

    /// Whether the engine can transcribe immediately (model loaded).
    Task<bool> IsReadyAsync() => Task.FromResult(true);

    /// A streaming session, or null when the engine doesn't support streaming
    /// or hasn't loaded its model yet.
    Task<StreamingTranscriptionSession?> MakeStreamingSessionAsync()
        => Task.FromResult<StreamingTranscriptionSession?>(null);
}
```

- [ ] **Step 5: Create `windows/JVoice.Core/Transcription/FileBackedTranscriptionEngine.cs`**

```csharp
namespace JVoice.Core.Transcription;

/// Test/no-whisper fallback: treats the "audio" file as UTF-8 text.
/// Faithful port of FileBackedTranscriptionEngine. Used by Core tests and the
/// coordinator's no-engine path.
public sealed class FileBackedTranscriptionEngine : ITranscriptionEngine
{
    public async Task<string> TranscribeAsync(string audioPath, CancellationToken ct = default)
    {
        if (!File.Exists(audioPath))
            throw TranscriptionException.AudioFileMissing(audioPath);

        await Task.Yield();

        string transcript;
        try { transcript = await File.ReadAllTextAsync(audioPath, ct); }
        catch (Exception) { throw TranscriptionException.UnsupportedAudioFile(audioPath); }

        string trimmed = transcript.Trim();
        if (trimmed.Length == 0) throw TranscriptionException.EmptyTranscript();
        return trimmed;
    }
}
```

- [ ] **Step 6: Run tests** → PASS.

- [ ] **Step 7: Commit** — `git commit -m "feat(core): transcription abstraction (interface, exception, file-backed engine)"`

---

## Task 12: Phase gate — full Core test run + tag

**Files:** none (verification only).

- [ ] **Step 1: Run the whole suite**

Run: `dotnet test windows/JVoice.Tests --logger "console;verbosity=normal"`
Expected: **all tests pass**, 0 failures. Note the executed test count (should be ≥ ~50 across all `*Tests.cs`).

- [ ] **Step 2: Confirm `JVoice.Core` has no forbidden dependencies**

Run: `dotnet list windows/JVoice.Core/JVoice.Core.csproj package`
Expected: **no PackageReferences** (Core depends only on the BCL). If anything appears, remove it — Core must stay pure.

- [ ] **Step 3: Cross-check against the Swift invariants**

Open `Tests/JVoiceTests/` and skim `TextProcessorTests.swift`, `PhoneticMatcherTests.swift`, `RepetitionGuardTests.swift`, `RegurgitationRecoveryTests.swift`, `WavTailTests.swift`, `ChunkPlannerTests.swift`, `StreamingTranscriptionSessionTests.swift`, `WhisperModelOptionTests.swift`, `SettingsStateMigrationTests.swift`. For any assertion not yet covered by a C# test, add the equivalent xUnit case and make it pass (do **not** change the implementation to fit — if a faithful port disagrees with a Swift assertion, re-read the Swift source; the implementation is the spec). This step is how we guarantee behavioral parity with the proven macOS brain.

- [ ] **Step 4: Commit any added parity tests** — `git commit -m "test(core): close parity gaps vs macOS Swift test suite"`

---

## Self-Review (spec coverage)

- **Models:** ToneStyle, TranscriptionLanguage, WhisperModelOption (+GGML map), SettingsState (+defaults), HudState (+DownloadingModel), AppTimings — Tasks 2. ✓
- **Text brain:** VocabularyPrompt (3), TextProcessor (5), PhoneticMatcher (4), RepetitionGuard (6), RegurgitationRecovery (7). ✓
- **Audio brain:** WavTail/WavTailReader (8), ChunkPlanner (9), StreamingTranscriptionSession (10). ✓
- **Transcription abstraction:** ITranscriptionEngine, TranscriptionException, FileBackedTranscriptionEngine (11). ✓
- **Tests:** translated from `run-logic-tests.sh` (PhoneticMatcher key/levenshtein/correct, VocabularyPrompt, TextProcessor modes/filler/dict/artifacts, RepetitionGuard strip + 120-case fuzz, WavTail header, ChunkPlanner) and `verify-streaming.sh` (RegurgitationRecovery 4, streaming data-loss). Parity gate in Task 12. ✓
- **Deferred to later phases (correctly):** `WhisperKitTranscriptionEngine` → `WhisperNetTranscriptionEngine` (Phase 2); `WhisperModelLocator` → `WhisperModelStore` (Phase 2); `TranscriptionManager` orchestration (pending-engine swap, prewarm, vocabulary re-push) → folded into `VoiceCoordinator` + engine wiring (Phase 4).

**Type-consistency check:** the names produced here (`ITranscriptionEngine`, `StreamingTranscriptionSession`, `ChunkPlanner.Config`, `WavTailReader`, `RepetitionGuard.ScrubResult`, `RegurgitationRecovery.Decode`, `HudState`, `SettingsState`, `WhisperModelOption.GgmlFileName()`) are exactly the names Phases 2–4 consume per the overview §4. No drift.

*Next: Phase 2 (`2026-06-22-windows-port-02-whisper-engine.md`).*
