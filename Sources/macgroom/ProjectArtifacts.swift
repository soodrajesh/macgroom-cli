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

    /// Scans a root (defaults to `$HOME` at the call site) — one
    /// `find … -prune` per root so a match's own descendants (nested
    /// `node_modules` inside `node_modules`) are never walked into once
    /// found, which matters for performance as much as correctness.
    ///
    /// `target` is the only entry with a marker requirement, and `-prune`
    /// fires on the bare name match *before* that marker check happens —
    /// so a folder named `target` with no `Cargo.toml`/`pom.xml` sibling
    /// gets excluded from findings, but `find` never descended into it
    /// either, meaning anything actually reclaimable nested inside (a
    /// `node_modules` under an unrelated `target/`, say) would otherwise
    /// be silently missed. Rejected marker-less dirs go back on a work
    /// queue and get re-scanned from inside, so nothing under them is lost.
    static func find(root: URL) -> [Finding] {
        let fm = FileManager.default
        var findings: [Finding] = []
        var seen = Set<String>()
        var pendingRoots = [root]

        while !pendingRoots.isEmpty {
            let scanRoot = pendingRoots.removeFirst()
            for path in matchingPaths(root: scanRoot) {
                guard !seen.contains(path) else { continue }
                seen.insert(path)

                let url = URL(fileURLWithPath: path)
                let folderName = url.lastPathComponent
                guard let target = targets.first(where: { $0.name == folderName }) else { continue }

                let parent = url.deletingLastPathComponent()
                if !target.markers.isEmpty {
                    let hasMarker = target.markers.contains { fm.fileExists(atPath: parent.appendingPathComponent($0).path) }
                    guard hasMarker else {
                        // Re-queuing `url` itself as the next scan root
                        // wouldn't work — `find` evaluates its own starting
                        // point against the expression too, so a root named
                        // "target" would immediately self-match-and-prune
                        // again without ever descending. Queue its
                        // immediate children instead.
                        let children = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
                        for child in children {
                            let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                            if isDir { pendingRoots.append(child) }
                        }
                        continue
                    }
                }

                let projectName = parent.lastPathComponent
                findings.append(Finding(url: url, label: "\(projectName) — \(target.label)", safe: true, sizeBytes: nil))
            }
        }
        return findings
    }

    private static func matchingPaths(root: URL) -> [String] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let libraryPath = home.appendingPathComponent("Library").standardizedFileURL.path

        var args = [root.path]
        // Exclude ~/Library from the walk — no real dev-project artifact
        // (node_modules, target/, .venv, ...) legitimately lives there (the
        // fixed locations that do, like Xcode DerivedData, are covered
        // separately by DevToolCaches), and it can contain cloud-sync
        // folders — iCloud Drive (~/Library/Mobile Documents), OneDrive/
        // Dropbox (~/Library/CloudStorage) — that are painfully slow to
        // enumerate and turn an unscoped `scan` into a multi-minute hang.
        // Skipped only when it's an *ancestor* of `root`, not when it IS
        // root or root is inside it — an explicit `--path ~/Library/...`
        // still scans normally.
        if root.standardizedFileURL.path != libraryPath {
            args += ["-path", libraryPath, "-prune", "-o"]
        }

        args += ["-type", "d", "("]
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
