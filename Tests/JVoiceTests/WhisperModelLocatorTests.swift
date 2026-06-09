#if canImport(Testing)
import Testing
import Foundation
@testable import JVoice

/// Builds a throwaway `documents` directory containing a WhisperKit-style model
/// folder, so the completeness check can be exercised without a real download.
private struct ModelFixture {
    let documents: URL
    let folderName: String
    private let fileManager = FileManager.default

    init(folderName: String) throws {
        self.folderName = folderName
        documents = fileManager.temporaryDirectory
            .appendingPathComponent("whisper-locator-tests")
            .appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: modelFolder, withIntermediateDirectories: true)
    }

    var modelFolder: URL {
        documents.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml/\(folderName)")
    }

    /// Writes `<component>.mlmodelc/weights/weight.bin` — a downloaded component.
    func addComponentWithWeights(_ component: String) throws {
        let weights = modelFolder.appendingPathComponent("\(component).mlmodelc/weights")
        try fileManager.createDirectory(at: weights, withIntermediateDirectories: true)
        try Data([0x00]).write(to: weights.appendingPathComponent("weight.bin"))
    }

    /// Writes a `<component>.mlmodelc` directory with metadata but NO weights —
    /// the state an interrupted download leaves behind.
    func addComponentWithoutWeights(_ component: String) throws {
        let dir = modelFolder.appendingPathComponent("\(component).mlmodelc")
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data([0x00]).write(to: dir.appendingPathComponent("coremldata.bin"))
    }

    /// Writes the model's `config.json` — present in every complete download.
    func addConfig() throws {
        try Data("{}".utf8).write(to: modelFolder.appendingPathComponent("config.json"))
    }

    func cleanup() {
        try? fileManager.removeItem(at: documents)
    }
}

@Test func completeModelFolderReturnsPathWhenEncoderAndDecoderWeightsPresent() throws {
    let fixture = try ModelFixture(folderName: "openai_whisper-small")
    defer { fixture.cleanup() }
    try fixture.addComponentWithWeights("MelSpectrogram")
    try fixture.addComponentWithWeights("AudioEncoder")
    try fixture.addComponentWithWeights("TextDecoder")
    try fixture.addConfig()

    let resolved = WhisperModelLocator.completeModelFolder(
        named: fixture.folderName, documentsDirectory: fixture.documents)

    #expect(resolved == fixture.modelFolder.path)
}

@Test func completeModelFolderReturnsNilWhenConfigMissing() throws {
    // All component weights finished but config.json never landed — still an
    // interrupted download; WhisperKit needs the config to load the model.
    let fixture = try ModelFixture(folderName: "openai_whisper-small")
    defer { fixture.cleanup() }
    try fixture.addComponentWithWeights("MelSpectrogram")
    try fixture.addComponentWithWeights("AudioEncoder")
    try fixture.addComponentWithWeights("TextDecoder")

    let resolved = WhisperModelLocator.completeModelFolder(
        named: fixture.folderName, documentsDirectory: fixture.documents)

    #expect(resolved == nil)
}

@Test func completeModelFolderReturnsNilWhenDecoderWeightsMissing() throws {
    // Reproduces the "Large model hangs" bug: the decoder .mlmodelc dir exists
    // but its weights never finished downloading.
    let fixture = try ModelFixture(folderName: "openai_whisper-large-v3_turbo")
    defer { fixture.cleanup() }
    try fixture.addComponentWithWeights("MelSpectrogram")
    try fixture.addComponentWithWeights("AudioEncoder")
    try fixture.addComponentWithoutWeights("TextDecoder")
    try fixture.addConfig()

    let resolved = WhisperModelLocator.completeModelFolder(
        named: fixture.folderName, documentsDirectory: fixture.documents)

    #expect(resolved == nil)
}

@Test func completeModelFolderReturnsNilWhenEncoderWeightsMissing() throws {
    let fixture = try ModelFixture(folderName: "openai_whisper-large-v3_turbo")
    defer { fixture.cleanup() }
    try fixture.addComponentWithWeights("MelSpectrogram")
    try fixture.addComponentWithoutWeights("AudioEncoder")
    try fixture.addComponentWithWeights("TextDecoder")
    try fixture.addConfig()

    let resolved = WhisperModelLocator.completeModelFolder(
        named: fixture.folderName, documentsDirectory: fixture.documents)

    #expect(resolved == nil)
}

@Test func completeModelFolderReturnsNilWhenFolderAbsent() throws {
    let fixture = try ModelFixture(folderName: "openai_whisper-small")
    defer { fixture.cleanup() }
    // Nothing downloaded for this model name.

    let resolved = WhisperModelLocator.completeModelFolder(
        named: "openai_whisper-missing", documentsDirectory: fixture.documents)

    #expect(resolved == nil)
}
#endif
