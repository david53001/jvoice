import Foundation

/// A curated, opt-out "Developer terms" vocabulary pack: canonical spellings of
/// common programming terms, keyed by how Whisper tends to MIS-render them
/// (spacing/casing drift plus a few dev-specific homophones).
///
/// It feeds the UNBOUNDED post-processing correction channel — folded into the
/// "extra dictionary" that `TextProcessor.process` consumes, via `augment(_:)` at
/// the transcription call site — NOT the decoder prompt (`VocabularyPrompt`), which
/// stays reserved for the user's own genuinely-unusual vocabulary. Routing here
/// means the pack scales to hundreds of terms with zero decoder cost and no
/// prompt-regurgitation risk.
///
/// Keys are lower-cased "heard" forms. `TextProcessor.applyCorrections` matches
/// them case-insensitively and treats internal spaces as `\s+` between `\b` word
/// boundaries, so `"node js"` also catches "Node JS"; values are the literal
/// canonical replacement.
///
/// Curation is deliberately CONSERVATIVE — only unambiguous spacing/casing fixes
/// and clearly dev-specific homophones. Ambiguous single English words are
/// intentionally EXCLUDED (casing "go"/"rust"/"swift"/"react"/"java"/"pandas", or
/// "sequel"→"SQL", or bare "dotnet"→".NET" which would wreck the lowercase `dotnet`
/// CLI) so the pack never corrupts ordinary dictation. One homophone has a known
/// name collision — "jason"→"JSON" — kept because in coding dictation it's
/// overwhelmingly JSON.
///
/// The AI / "vibe coding" section follows the SAME rule. Many of the hottest tool
/// names ARE ordinary English, so they are deliberately EXCLUDED to protect normal
/// dictation: "cursor" (the text/mouse cursor — the single most dangerous one),
/// "bolt", "continue", "render", "railway", "remix", "warp", "astro", bare "svelte",
/// "bun", "pinecone", bare "chroma", "cohere", "perplexity", "grok", "drizzle",
/// "lovable", and bare "llama". Three homophones/near-collisions are KEPT, each the
/// same call as "jason": "groq"→"Groq" (NOT "grok"), "gemini"→"Gemini" (safe both
/// senses), and distinctive product tokens "mistral"/"firebase"/"windsurf".
///
/// Ported 1:1 from the Windows port's `DeveloperTerms`. NOTE: the C# source uses
/// indexer-init (`["supabase"] = ...`) which silently keeps the LAST duplicate; a
/// Swift dictionary literal traps on duplicate keys, so "supabase" appears once
/// here as its last-wins value ("Supabase").
public enum DeveloperTerms {
    /// Heard form (lower-cased) → canonical replacement.
    public static let map: [String: String] = [
        // ---- JavaScript / web ecosystem ----
        "java script": "JavaScript",
        "javascript": "JavaScript",
        "type script": "TypeScript",
        "typescript": "TypeScript",
        "node js": "Node.js",
        "nodejs": "Node.js",
        "next js": "Next.js",
        "nextjs": "Next.js",
        "nuxt js": "Nuxt.js",
        "vue js": "Vue.js",
        "react js": "React",
        "reactjs": "React",
        "express js": "Express",
        "nest js": "NestJS",
        "web pack": "webpack",
        "es lint": "ESLint",
        "eslint": "ESLint",
        "tail wind": "Tailwind",
        "graph ql": "GraphQL",
        "graphql": "GraphQL",
        "web socket": "WebSocket",
        "web sockets": "WebSockets",
        "web assembly": "WebAssembly",
        "local host": "localhost",
        "rest api": "REST API",
        "restful": "RESTful",

        // ---- Python ecosystem ----
        "num py": "NumPy",
        "num pie": "NumPy",
        "numpy": "NumPy",
        "py torch": "PyTorch",
        "pie torch": "PyTorch",
        "pytorch": "PyTorch",
        "tensor flow": "TensorFlow",
        "tensorflow": "TensorFlow",
        "fast api": "FastAPI",
        "fastapi": "FastAPI",
        "py pi": "PyPI",
        "pypi": "PyPI",
        "pydantic": "Pydantic",
        "jupyter": "Jupyter",
        "django": "Django",

        // ---- Languages / runtimes / frameworks ----
        "c sharp": "C#",
        "c plus plus": "C++",
        "objective c": "Objective-C",
        "dot net": ".NET",
        "asp net": "ASP.NET",
        "asp dot net": "ASP.NET",
        "power shell": "PowerShell",
        "powershell": "PowerShell",

        // ---- Data stores / infra ----
        "post gres": "Postgres",
        "postgres": "Postgres",
        "postgre sql": "PostgreSQL",
        "postgresql": "PostgreSQL",
        "my sql": "MySQL",
        "mysql": "MySQL",
        "no sql": "NoSQL",
        "nosql": "NoSQL",
        "sqlite": "SQLite",
        "mongo db": "MongoDB",
        "mongodb": "MongoDB",
        "redis": "Redis",
        "kubernetes": "Kubernetes",

        // ---- Tooling / hosts ----
        "git hub": "GitHub",
        "github": "GitHub",
        "git lab": "GitLab",
        "gitlab": "GitLab",
        "bit bucket": "Bitbucket",
        "bitbucket": "Bitbucket",
        "vs code": "VS Code",
        "vscode": "VS Code",
        "intellij": "IntelliJ",

        // ---- AI / ML ----
        "open ai": "OpenAI",
        "openai": "OpenAI",
        "hugging face": "Hugging Face",
        "lang chain": "LangChain",
        "langchain": "LangChain",
        "chat gpt": "ChatGPT",
        "chatgpt": "ChatGPT",
        "anthropic": "Anthropic",
        "claude": "Claude",

        // ---- Acronym casing (distinctly technical; safe to uppercase) ----
        "api": "API",
        "apis": "APIs",
        "url": "URL",
        "urls": "URLs",
        "uri": "URI",
        "sdk": "SDK",
        "cli": "CLI",
        "gui": "GUI",
        "ide": "IDE",
        "ui": "UI",
        "ux": "UX",
        "html": "HTML",
        "css": "CSS",
        "sql": "SQL",
        "http": "HTTP",
        "https": "HTTPS",
        "ssh": "SSH",
        "json": "JSON",
        "jason": "JSON",
        "yaml": "YAML",
        "xml": "XML",
        "csv": "CSV",
        "jwt": "JWT",
        "llm": "LLM",
        "o auth": "OAuth",
        "oauth": "OAuth",
        "npm": "npm",

        // ================================================================
        // AI / "vibe coding" — tools, agents, models, protocols, and the
        // modern deploy stack. SAME conservative rule: product names that
        // are ordinary English are EXCLUDED (see the class doc-comment).
        // ================================================================

        // ---- AI coding tools / agents ----
        "copilot": "Copilot",
        "github copilot": "GitHub Copilot",
        "claude code": "Claude Code",
        "codeium": "Codeium",
        "windsurf": "Windsurf",
        "ollama": "Ollama",
        "o llama": "Ollama",
        "replit": "Replit",
        "rep lit": "Replit",

        // ---- AI frameworks / orchestration / protocols ----
        "mcp": "MCP",
        "lang graph": "LangGraph",
        "langgraph": "LangGraph",
        "llama index": "LlamaIndex",
        "llamaindex": "LlamaIndex",
        "crew ai": "CrewAI",
        "crewai": "CrewAI",
        "auto gen": "AutoGen",
        "autogen": "AutoGen",
        "semantic kernel": "Semantic Kernel",
        "dspy": "DSPy",
        "vllm": "vLLM",

        // ---- Models / labs (numbered versions deliberately skipped) ----
        "gpt": "GPT",
        "deep seek": "DeepSeek",
        "deepseek": "DeepSeek",
        "mixtral": "Mixtral",
        "qwen": "Qwen",
        "gemini": "Gemini",    // safe: capitalized in BOTH the zodiac & Google-model senses
        "mistral": "Mistral",  // the Mediterranean wind is vanishingly rare in coding dictation
        "groq": "Groq",        // NOT "grok" (the everyday verb) — kept the same way as "jason"

        // ---- Vector databases ----
        "weaviate": "Weaviate",
        "chroma db": "ChromaDB",
        "chromadb": "ChromaDB",
        "qdrant": "Qdrant",
        "pg vector": "pgvector",
        "pgvector": "pgvector",
        "milvus": "Milvus",
        "faiss": "FAISS",

        // ---- Modern deploy / web stack (where vibe-coded apps ship) ----
        "vercel": "Vercel",
        "ver cell": "Vercel",
        "netlify": "Netlify",
        "supabase": "Supabase",  // C# had a duplicate "supabase" key; indexer-init keeps this last value
        "firebase": "Firebase",
        "fire base": "Firebase",
        "cloudflare": "Cloudflare",
        "cloud flare": "Cloudflare",
        "planetscale": "PlanetScale",
        "planet scale": "PlanetScale",
        "turborepo": "Turborepo",
        "turbo repo": "Turborepo",
        "trpc": "tRPC",
        "t rpc": "tRPC",
        "sveltekit": "SvelteKit",
        "svelte kit": "SvelteKit",
        "deno": "Deno",
        "pnpm": "pnpm",
        "zod": "Zod",
        "zustand": "Zustand",
        "prisma": "Prisma",
    ]

    /// Returns `base` with the pack laid in UNDERNEATH it: every pack entry is
    /// added, but a key already present in `base` keeps the base value (the user's
    /// own custom-word variants win over the generic pack). The built-in
    /// `TextProcessor.correctionDictionary` still overrides everything inside
    /// `applyCorrections`, so precedence is dev pack < custom-word variants < builtin.
    public static func augment(_ base: [String: String]) -> [String: String] {
        var dict = map                        // pack is the floor
        for (key, value) in base { dict[key] = value }   // the user's own entries win
        return dict
    }
}
