# App / AIPolish — the Windows half of AI Polish

- `AIPolishServices.cs` — `HttpPolishTransport` (one shared HttpClient: no cookies, no credentials, no
  redirects — a redirect would re-send `x-api-key` — no cache; infinite HttpClient timeout, the Core
  client's deadline rules) and `DpapiKeyProtector` (`ProtectedData`, CurrentUser + `ApiKeyStore.Entropy`;
  the key file is `PlatformPaths.ApiKeyFile` = `%LOCALAPPDATA%\JVoice\anthropic-api-key.bin`).
- `PolishEvalCli.cs` — hidden `JVoice.exe --polish-eval <cases.json> [--model …] [--thinking off|low]
  [--prompt-file <t.txt>] [--out <r.md>]`. GUI-subsystem exe: pipe it (`| Out-Host`). Key from
  `ANTHROPIC_API_KEY`, else the saved key; never printed.

The coordinator side is `../VoiceCoordinator.AIPolish.cs` (partial class): Settings state, key/balance
actions, `PolishAsync` (called from `FinishTranscriptionAsync` after maths + the empty check, before
paste), the context append after each paste, and the one "balance used up" pill (kept pending if its
paste fails). Pure logic and its brief: `../../JVoice.Core/AIPolish/`.
