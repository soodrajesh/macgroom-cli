import Foundation

/// One reclaimable item — a cache folder, a project's build artifact, a
/// local AI model directory. Deliberately not shared with the GUI app's
/// own `ScanItem` (that lives in a private, closed-source repo) — this is
/// an independent reimplementation of the same underlying scan logic,
/// open source on its own.
struct Finding {
    let url: URL
    let label: String
    /// `true` = fully regenerable, safe to include in a non-interactive
    /// `--yes` clean. `false` = technically re-creatable but the user may
    /// still be actively using it (an AI model, say) — always requires
    /// either an explicit interactive "yes" or `--include-review`.
    let safe: Bool
    var sizeBytes: Int64?

    var sizeDisplay: String {
        guard let sizeBytes else { return "?" }
        return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

enum SizeCalculator {
    /// `du -sk`, same approach as the GUI app: a tuned C implementation
    /// beats walking the tree in Swift, especially for something like
    /// `node_modules`.
    static func size(of url: URL) -> Int64? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return nil }
        if !isDir.boolValue {
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            return (attrs?[.size] as? NSNumber)?.int64Value
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-sk", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let output = String(data: data, encoding: .utf8),
              let firstField = output.split(whereSeparator: { $0 == "\t" || $0 == " " }).first,
              let kilobytes = Int64(firstField) else { return nil }
        return kilobytes * 1024
    }
}
