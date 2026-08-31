import Foundation

/// Recursively finds regenerable build/dependency artifact folders —
/// `node_modules`, Python virtualenvs, Rust/Maven `target/`, CocoaPods'
/// `Pods/`, Terraform's `.terraform/`, Next.js/Nuxt build caches —
/// scattered across a project tree. Every one regenerates automatically
/// via the project's own tooling, so every match here is `safe: true`.
enum ProjectArtifacts {
    /// Folder name → human label → sibling marker file(s) required in the
    /// *parent* directory for the match to count. `target` is the one
    /// deliberate exception — generic enough that a bare name match would
    /// false-positive on unrelated folders, so it additionally requires a
    /// `Cargo.toml` or `pom.xml` next to it.
    private static let targets: [(name: String, label: String, markers: [String])] = [
        ("node_modules",  "node_modules (npm/yarn/pnpm)", []),
        (".venv",         "Python virtualenv", []),
        ("venv",          "Python virtualenv", []),
        ("__pycache__",   "Python bytecode cache", []),
        (".pytest_cache", "pytest cache", []),
        (".tox",          "tox environments", []),
        ("target",        "Rust/Maven build output", ["Cargo.toml", "pom.xml"]),
        ("Pods",          "CocoaPods", []),
        (".terraform",    "Terraform provider cache", []),
        (".next",         "Next.js build cache", []),
        (".nuxt",         "Nuxt build cache", []),
    ]

    /// Scans a single root (defaults to `$HOME` at the call site) — one
    /// `find … -prune` so a match's own descendants (nested
    /// `node_modules` inside `node_modules`) are never walked into once
    /// found, which matters for performance as much as correctness.
    static func find(root: URL) -> [Finding] {
        let fm = FileManager.default
        var findings: [Finding] = []
        var seen = Set<String>()

        for path in matchingPaths(root: root) {
            guard !seen.contains(path) else { continue }
            seen.insert(path)

            let url = URL(fileURLWithPath: path)
            let folderName = url.lastPathComponent
            guard let target = targets.first(where: { $0.name == folderName }) else { continue }

            let parent = url.deletingLastPathComponent()
            if !target.markers.isEmpty {
                let hasMarker = target.markers.contains { fm.fileExists(atPath: parent.appendingPathComponent($0).path) }
                guard hasMarker else { continue }
            }

            let projectName = parent.lastPathComponent
            findings.append(Finding(url: url, label: "\(projectName) — \(target.label)", safe: true, sizeBytes: nil))
        }
        return findings
    }

    private static func matchingPaths(root: URL) -> [String] {
        var args = [root.path, "-type", "d", "("]
        for (index, target) in targets.enumerated() {
            if index > 0 { args.append("-o") }
            args.append("-name")
            args.append(target.name)
        }
        args += [")", "-prune", "-print"]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/find")
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return [] }
        return output.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }
}
