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
/// The AI / "vibe coding" section (2026-07-01) follows the SAME rule. Many of the hottest
/// tool names ARE ordinary English, so they are deliberately EXCLUDED to protect normal
/// dictation: "cursor" (the text/mouse cursor — the single most dangerous one), "bolt",
/// "continue", "render", "railway", "remix", "warp", "astro", bare "svelte", "bun",
/// "pinecone"/"pine cone" (the botanical object), bare "chroma", "cohere" (the verb),
/// "perplexity" (also a real ML metric), "grok" (the everyday verb), "drizzle", "lovable",
/// and bare "llama" (the animal — versioned model names like "Llama 3" are skipped too,
/// since Whisper renders digits unpredictably). Those products stay reachable via the
/// user's own custom-words / correction rules, which outrank this pack by design.
/// Three homophones/near-collisions are KEPT, each the same call as "jason": "groq"→"Groq"
/// (NOT "grok", the everyday verb + xAI's model), "gemini"→"Gemini" (SAFE either way — it's
/// a proper noun capitalized in BOTH the zodiac and the Google-model sense, so it can never
/// corrupt), and distinctive product tokens "mistral"/"firebase"/"windsurf" whose non-tech
/// senses (the Mediterranean wind / a military firebase / the sport) are vanishingly rare in
/// coding dictation — the same judgment already made for "django"/"redis". Every exclusion
/// above is locked by the test `Map_ExcludesAmbiguousEnglishWords`.
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

        // ================================================================
        // AI / "vibe coding" — tools, agents, models, protocols, and the
        // modern deploy stack (added 2026-07-01). SAME conservative rule:
        // product names that are ordinary English (cursor/bolt/continue/
        // render/railway/remix/warp/astro/svelte/bun/pinecone/chroma/cohere/
        // perplexity/grok/drizzle/llama/lovable) are EXCLUDED — see the class
        // doc-comment and the Map_ExcludesAmbiguousEnglishWords test.
        // ================================================================

        // ---- AI coding tools / agents ----
        ["copilot"] = "Copilot",
        ["github copilot"] = "GitHub Copilot",
        ["claude code"] = "Claude Code",
        ["codeium"] = "Codeium",
        ["windsurf"] = "Windsurf",
        ["ollama"] = "Ollama",
        ["o llama"] = "Ollama",
        ["replit"] = "Replit",
        ["rep lit"] = "Replit",

        // ---- AI frameworks / orchestration / protocols ----
        ["mcp"] = "MCP",
        ["lang graph"] = "LangGraph",
        ["langgraph"] = "LangGraph",
        ["llama index"] = "LlamaIndex",
        ["llamaindex"] = "LlamaIndex",
        ["crew ai"] = "CrewAI",
        ["crewai"] = "CrewAI",
        ["auto gen"] = "AutoGen",
        ["autogen"] = "AutoGen",
        ["semantic kernel"] = "Semantic Kernel",
        ["dspy"] = "DSPy",
        ["vllm"] = "vLLM",

        // ---- Models / labs (numbered versions deliberately skipped) ----
        ["gpt"] = "GPT",
        ["deep seek"] = "DeepSeek",
        ["deepseek"] = "DeepSeek",
        ["mixtral"] = "Mixtral",
        ["qwen"] = "Qwen",
        ["gemini"] = "Gemini",    // safe: capitalized in BOTH the zodiac & Google-model senses
        ["mistral"] = "Mistral",  // the Mediterranean wind is vanishingly rare in coding dictation
        ["groq"] = "Groq",        // NOT "grok" (the everyday verb) — kept the same way as "jason"

        // ---- Vector databases ----
        ["weaviate"] = "Weaviate",
        ["chroma db"] = "ChromaDB",
        ["chromadb"] = "ChromaDB",
        ["qdrant"] = "Qdrant",
        ["pg vector"] = "pgvector",
        ["pgvector"] = "pgvector",
        ["milvus"] = "Milvus",
        ["faiss"] = "FAISS",

        // ---- Modern deploy / web stack (where vibe-coded apps ship) ----
        ["vercel"] = "Vercel",
        ["ver cell"] = "Vercel",
        ["netlify"] = "Netlify",
        ["supabase"] = "Supabase",
        ["firebase"] = "Firebase",
        ["fire base"] = "Firebase",
        ["cloudflare"] = "Cloudflare",
        ["cloud flare"] = "Cloudflare",
        ["planetscale"] = "PlanetScale",
        ["planet scale"] = "PlanetScale",
        ["turborepo"] = "Turborepo",
        ["turbo repo"] = "Turborepo",
        ["trpc"] = "tRPC",
        ["t rpc"] = "tRPC",
        ["sveltekit"] = "SvelteKit",
        ["svelte kit"] = "SvelteKit",
        ["deno"] = "Deno",
        ["pnpm"] = "pnpm",
        ["zod"] = "Zod",
        ["zustand"] = "Zustand",
        ["prisma"] = "Prisma",
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
