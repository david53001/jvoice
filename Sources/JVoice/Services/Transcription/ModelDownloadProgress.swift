import Foundation

/// Byte accounting for a WhisperKit model download that is still in flight.
///
/// The HUD used to cover two very different waits with one static "Preparing
/// Model" pill: a several-hundred-megabyte download over the network, and the
/// CoreML/Neural-Engine compile that follows it. Those fail differently and take
/// wildly different amounts of time, so collapsing them reads as a hang — a lost
/// model folder turns into a silent 632 MB fetch with nothing on screen to say so.
///
/// WhisperKit's own `Progress` can't tell us: `HubApi.snapshot` builds it as
/// `Progress(totalUnitCount: filenames.count)` and gives every file the same
/// `pendingUnitCount: 1`, so the Large model's 402 MB `AudioEncoder` weight file
/// counts exactly as much as a 4 KB `config.json`. A bar driven off its
/// `fractionCompleted` would race to ~90% and then sit still for most of the real
/// wait. Measuring bytes on disk reports what is actually happening instead.
enum ModelDownloadProgress {
    /// Bytes of the model `folderName` currently on disk.
    ///
    /// Counts the model folder **and** the HuggingFace staging area
    /// (`.cache/huggingface/download/<folderName>`). Files stream into staging
    /// as `.incomplete` and are only moved into the model folder once whole, so
    /// mid-download most of the bytes live in staging and the model folder alone
    /// barely moves.
    static func downloadedBytes(folderName: String, documentsDirectory: URL) -> Int64 {
        let repo = documentsDirectory
            .appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml")
        return directorySize(repo.appendingPathComponent(folderName))
            + directorySize(repo.appendingPathComponent(".cache/huggingface/download/\(folderName)"))
    }

    /// Human-readable "284 MB of ~632 MB". The downloaded figure is measured;
    /// the total is the model's published size and only approximate, which is
    /// what the tilde is there to admit.
    static func label(downloaded: Int64, total: Int64) -> String {
        "\(megabytes(downloaded)) of ~\(megabytes(total))"
    }

    /// Download fraction in 0…1, clamped so an approximate `total` can never
    /// drive the bar past full (or below empty).
    static func fraction(downloaded: Int64, total: Int64) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(downloaded) / Double(total)))
    }

    /// Whole megabytes, decimal (MB not MiB) to match how model sizes are
    /// published — "632 MB" should read back as the 632 in the folder name.
    static func megabytes(_ bytes: Int64) -> String {
        "\(max(0, bytes) / 1_000_000) MB"
    }

    /// Total size of every regular file under `url`, or 0 if it doesn't exist.
    /// Called about once a second against a folder of ~20 files, so a plain
    /// enumeration is cheap enough.
    private static func directorySize(_ url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let size = values.fileSize
            else { continue }
            total += Int64(size)
        }
        return total
    }
}
