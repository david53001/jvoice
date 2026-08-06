#if canImport(Testing)
import Testing
@testable import JVoice

@Test func developerTermsMapsCommonSpacingAndCasing() {
    #expect(DeveloperTerms.map["node js"] == "Node.js")
    #expect(DeveloperTerms.map["nodejs"] == "Node.js")
    #expect(DeveloperTerms.map["type script"] == "TypeScript")
    #expect(DeveloperTerms.map["c sharp"] == "C#")
    #expect(DeveloperTerms.map["vs code"] == "VS Code")
    #expect(DeveloperTerms.map["git hub"] == "GitHub")
    #expect(DeveloperTerms.map["json"] == "JSON")
}

@Test func developerTermsKeepsIntentionalHomophones() {
    // The same conservative call as "jason": distinctive product tokens whose
    // non-tech senses are vanishingly rare in coding dictation.
    #expect(DeveloperTerms.map["jason"] == "JSON")
    #expect(DeveloperTerms.map["groq"] == "Groq")     // NOT "grok" (the everyday verb)
    #expect(DeveloperTerms.map["gemini"] == "Gemini")
    #expect(DeveloperTerms.map["mistral"] == "Mistral")
}

@Test func developerTermsExcludesAmbiguousEnglishWords() {
    // Ambiguous single English words must NOT be keys — correcting them would
    // corrupt ordinary dictation. (Mirrors the Windows Map_ExcludesAmbiguousEnglishWords.)
    let excluded = ["cursor", "bolt", "continue", "render", "railway", "remix",
                    "warp", "astro", "svelte", "bun", "pinecone", "chroma",
                    "cohere", "perplexity", "grok", "drizzle", "lovable", "llama"]
    for word in excluded {
        #expect(DeveloperTerms.map[word] == nil, "\(word) must not be a key")
    }
}

@Test func developerTermsAugmentLaysPackUnderBase() {
    // Pack-only keys survive; a key present in base keeps the base value.
    #expect(DeveloperTerms.augment([:])["vs code"] == "VS Code")
    #expect(DeveloperTerms.augment(["node js": "CustomNode"])["node js"] == "CustomNode")
}

@Test func developerTermsAppliedThroughProcess() {
    let extra = DeveloperTerms.augment([:])
    #expect(TextProcessor.process("i use node js and type script daily", mode: .casual, extraDictionary: extra)
        == "i use Node.js and TypeScript daily")
    #expect(TextProcessor.process("send me the jason file", mode: .casual, extraDictionary: extra)
        == "send me the JSON file")
}
#endif
