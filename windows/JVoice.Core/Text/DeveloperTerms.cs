namespace JVoice.Core.Text;

/// A curated, opt-out "Developer terms" vocabulary pack: canonical spellings of
/// common programming terms, keyed by how Whisper tends to MIS-render them
/// (spacing/casing drift plus a few dev-specific homophones).
///
/// It feeds the UNBOUNDED post-processing correction channel — folded into the
/// "extra dictionary" that <see cref="TextProcessor.Process"/> consumes, via
/// <see cref="Augment"/> at the transcription call site — NOT the 40-word decoder
/// prompt (<see cref="VocabularyPrompt"/>), which stays reserved for the user's own
/// genuinely-unusual vocabulary. Routing here means the pack scales to hundreds of
/// terms with zero decoder cost and no prompt-regurgitation risk.
///
/// Keys are lower-cased "heard" forms. <see cref="TextProcessor.ApplyCorrections"/>
/// matches them case-insensitively and treats internal spaces as <c>\s+</c> between
/// <c>\b</c> word boundaries, so <c>"node js"</c> also catches "Node JS"; values are
/// the literal canonical replacement.
///
/// Curation is deliberately CONSERVATIVE — only unambiguous spacing/casing fixes and
/// clearly dev-specific homophones. Ambiguous single English words are intentionally
/// EXCLUDED (casing "go"/"rust"/"swift"/"react"/"java"/"pandas", or "sequel"→"SQL",
/// or bare "dotnet"→".NET" which would wreck the lowercase `dotnet` CLI) so the pack
/// never corrupts ordinary dictation. One homophone has a known name collision —
/// "jason"→"JSON" — kept because in coding dictation it's overwhelmingly JSON; the
/// user can remove it with a correction rule if they dictate to a person named Jason.
///
/// This list is intended to be ported 1:1 to the macOS app later, exactly like the
/// rest of the brain (cf. <see cref="TextProcessor.CorrectionDictionary"/>).
public static class DeveloperTerms
{
    /// Heard form (lower-cased) → canonical replacement.
    public static readonly IReadOnlyDictionary<string, string> Map = new Dictionary<string, string>
    {
        // ---- JavaScript / web ecosystem ----
        ["java script"] = "JavaScript",
        ["javascript"] = "JavaScript",
        ["type script"] = "TypeScript",
        ["typescript"] = "TypeScript",
        ["node js"] = "Node.js",
        ["nodejs"] = "Node.js",
        ["next js"] = "Next.js",
        ["nextjs"] = "Next.js",
        ["nuxt js"] = "Nuxt.js",
        ["vue js"] = "Vue.js",
        ["react js"] = "React",
        ["reactjs"] = "React",
        ["express js"] = "Express",
        ["nest js"] = "NestJS",
        ["web pack"] = "webpack",
        ["es lint"] = "ESLint",
        ["eslint"] = "ESLint",
        ["tail wind"] = "Tailwind",
        ["graph ql"] = "GraphQL",
        ["graphql"] = "GraphQL",
        ["web socket"] = "WebSocket",
        ["web sockets"] = "WebSockets",
        ["web assembly"] = "WebAssembly",
        ["local host"] = "localhost",
        ["rest api"] = "REST API",
        ["restful"] = "RESTful",

        // ---- Python ecosystem ----
        ["num py"] = "NumPy",
        ["num pie"] = "NumPy",
        ["numpy"] = "NumPy",
        ["py torch"] = "PyTorch",
        ["pie torch"] = "PyTorch",
        ["pytorch"] = "PyTorch",
        ["tensor flow"] = "TensorFlow",
        ["tensorflow"] = "TensorFlow",
        ["fast api"] = "FastAPI",
        ["fastapi"] = "FastAPI",
        ["py pi"] = "PyPI",
        ["pypi"] = "PyPI",
        ["pydantic"] = "Pydantic",
        ["jupyter"] = "Jupyter",
        ["django"] = "Django",

        // ---- Languages / runtimes / frameworks ----
        ["c sharp"] = "C#",
        ["c plus plus"] = "C++",
        ["objective c"] = "Objective-C",
        ["dot net"] = ".NET",
        ["asp net"] = "ASP.NET",
        ["asp dot net"] = "ASP.NET",
        ["power shell"] = "PowerShell",
        ["powershell"] = "PowerShell",

        // ---- Data stores / infra ----
        ["post gres"] = "Postgres",
        ["postgres"] = "Postgres",
        ["postgre sql"] = "PostgreSQL",
        ["postgresql"] = "PostgreSQL",
        ["my sql"] = "MySQL",
        ["mysql"] = "MySQL",
        ["no sql"] = "NoSQL",
        ["nosql"] = "NoSQL",
        ["sqlite"] = "SQLite",
        ["mongo db"] = "MongoDB",
        ["mongodb"] = "MongoDB",
        ["redis"] = "Redis",
        ["kubernetes"] = "Kubernetes",

        // ---- Tooling / hosts ----
        ["git hub"] = "GitHub",
        ["github"] = "GitHub",
        ["git lab"] = "GitLab",
        ["gitlab"] = "GitLab",
        ["bit bucket"] = "Bitbucket",
        ["bitbucket"] = "Bitbucket",
        ["vs code"] = "VS Code",
        ["vscode"] = "VS Code",
        ["intellij"] = "IntelliJ",

        // ---- AI / ML ----
        ["open ai"] = "OpenAI",
        ["openai"] = "OpenAI",
        ["hugging face"] = "Hugging Face",
        ["lang chain"] = "LangChain",
        ["langchain"] = "LangChain",
        ["chat gpt"] = "ChatGPT",
        ["chatgpt"] = "ChatGPT",
        ["anthropic"] = "Anthropic",
        ["claude"] = "Claude",

        // ---- Acronym casing (distinctly technical; safe to uppercase) ----
        ["api"] = "API",
        ["apis"] = "APIs",
        ["url"] = "URL",
        ["urls"] = "URLs",
        ["uri"] = "URI",
        ["sdk"] = "SDK",
        ["cli"] = "CLI",
        ["gui"] = "GUI",
        ["ide"] = "IDE",
        ["ui"] = "UI",
        ["ux"] = "UX",
        ["html"] = "HTML",
        ["css"] = "CSS",
        ["sql"] = "SQL",
        ["http"] = "HTTP",
        ["https"] = "HTTPS",
        ["ssh"] = "SSH",
        ["json"] = "JSON",
        ["jason"] = "JSON",
        ["yaml"] = "YAML",
        ["xml"] = "XML",
        ["csv"] = "CSV",
        ["jwt"] = "JWT",
        ["llm"] = "LLM",
        ["o auth"] = "OAuth",
        ["oauth"] = "OAuth",
        ["npm"] = "npm",
    };

    /// Returns <paramref name="baseDict"/> with the pack laid in UNDERNEATH it: every
    /// pack entry is added, but a key already present in <paramref name="baseDict"/>
    /// keeps the base value (the user's own custom-word variants win over the generic
    /// pack). Folded in between <see cref="TextProcessor.BuildUserDictionary"/> and
    /// <see cref="UserCorrections.Merge"/> so the precedence is
    /// dev pack &lt; custom-word variants &lt; user correction rules, with the builtin
    /// <see cref="TextProcessor.CorrectionDictionary"/> still overriding everything
    /// inside <see cref="TextProcessor.ApplyCorrections"/>.
    public static IReadOnlyDictionary<string, string> Augment(IReadOnlyDictionary<string, string> baseDict)
    {
        var dict = new Dictionary<string, string>(Map);          // pack is the floor
        foreach (var kv in baseDict) dict[kv.Key] = kv.Value;    // the user's own entries win
        return dict;
    }
}
