import Foundation

/// Parsed layout of a (possibly still-growing) RIFF/WAVE file.
public struct WavInfo: Equatable, Sendable {
    public let dataOffset: Int
    public let sampleRate: Int
    public let channels: Int
    public let bytesPerSample: Int
}

/// Header parsing for the WAV that AVAudioRecorder is *currently writing*.
///
/// Two realities of a mid-recording WAV that a naive parser trips over:
/// - CoreAudio pads the header with a `FLLR` filler chunk (the PCM payload can
///   start ~4 KB in), so the payload offset must come from chunk-walking,
///   never a hardcoded 44.
/// - The `RIFF` and `data` size fields are 0/stale until the recorder stops
///   and patches them, so the payload is treated as [dataOffset, EOF) and the
///   declared data size is deliberately ignored.
public enum WavTail {
    /// More than enough to cover Apple's filler padding before `data`.
    public static let headerProbeBytes = 16_384

    /// nil unless the header is parseable AND the format is exactly what
    /// `RecordingManager` writes (PCM, 16-bit, mono, 16 kHz) — anything else
    /// refuses to stream and the caller falls back to whole-file transcription.
    public static func parseHeader(_ bytes: [UInt8]) -> WavInfo? {
        guard bytes.count >= 12,
              fourCC(bytes, at: 0) == "RIFF",
              fourCC(bytes, at: 8) == "WAVE" else { return nil }
        var offset = 12
        var format: (rate: Int, channels: Int, bits: Int)?
        while offset + 8 <= bytes.count {
            let id = fourCC(bytes, at: offset)
            let size = Int(uint32LE(bytes, at: offset + 4))
            let payload = offset + 8
            if id == "fmt " {
                guard payload + 16 <= bytes.count else { return nil }
                let audioFormat = Int(uint16LE(bytes, at: payload))
                guard audioFormat == 1 else { return nil } // PCM only
                format = (
                    rate: Int(uint32LE(bytes, at: payload + 4)),
                    channels: Int(uint16LE(bytes, at: payload + 2)),
                    bits: Int(uint16LE(bytes, at: payload + 14))
                )
            } else if id == "data" {
                guard let format,
                      format.channels == 1, format.rate == 16_000, format.bits == 16 else {
                    return nil
                }
                return WavInfo(dataOffset: payload, sampleRate: format.rate, channels: 1, bytesPerSample: 2)
            }
            // Non-`data` chunks always carry a real size (only `data` grows),
            // and chunks are word-aligned.
            offset = payload + size + (size % 2)
        }
        return nil
    }

    public static func floatSamples(_ samples: ArraySlice<Int16>) -> [Float] {
        samples.map { Float($0) / 32_768.0 }
    }

    private static func fourCC(_ bytes: [UInt8], at offset: Int) -> String? {
        guard offset + 4 <= bytes.count else { return nil }
        return String(bytes: bytes[offset..<offset + 4], encoding: .ascii)
    }

    private static func uint16LE(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func uint32LE(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }
}

/// Incremental sample access to a growing WAV. Opens a fresh FileHandle per
/// read — the file is being appended to by another writer and a long-lived
/// handle's EOF view is unreliable.
public struct WavTailReader: Sendable {
    public let url: URL
    public let info: WavInfo

    /// nil when the header can't be parsed yet (recorder may still be
    /// flushing its first buffer) — callers retry on the next poll.
    public static func open(url: URL) -> WavTailReader? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let probe = try? handle.read(upToCount: WavTail.headerProbeBytes),
              let info = WavTail.parseHeader([UInt8](probe)) else { return nil }
        return WavTailReader(url: url, info: info)
    }

    /// All samples from `sampleOffset` to the current EOF. `[]` = no new data
    /// yet; nil = file gone/unreadable (the session must abort and fall back).
    public func samples(from sampleOffset: Int) -> [Int16]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let byteOffset = UInt64(info.dataOffset + sampleOffset * info.bytesPerSample)
        guard (try? handle.seek(toOffset: byteOffset)) != nil else { return nil }
        let data: Data
        do {
            data = try handle.readToEnd() ?? Data() // nil == already at EOF
        } catch {
            return nil
        }
        let usable = data.count - (data.count % 2) // a trailing odd byte is a mid-sample write
        guard usable > 0 else { return [] }
        var result = [Int16](repeating: 0, count: usable / 2)
        data.prefix(usable).withUnsafeBytes { raw in
            for i in 0..<result.count {
                result[i] = Int16(littleEndian: raw.loadUnaligned(fromByteOffset: i * 2, as: Int16.self))
            }
        }
        return result
    }
}
