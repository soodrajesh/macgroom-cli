import Foundation

let version = "0.1.0"

func printHelp() {
    print("""
    macgroom \(version) — free dev-cache cleanup, from the terminal.
    The CLI companion to the MacGroom Mac app (https://gogenops.com/mac-apps/macgroom/).

    USAGE:
      macgroom scan  [--path <dir>] [--json]
      macgroom clean [--path <dir>] [--yes] [--include-review] [--dry-run]
      macgroom --version
      macgroom --help

    Scans two categories, both free forever:
      • Dev Tool Caches      Xcode DerivedData, Simulator Caches, npm/Yarn/
                              pnpm/pip/Poetry/Cargo caches, ~/.cache, and
                              local Ollama/LM Studio model weights.
      • Dev Project Artifacts  node_modules, Python virtualenvs, target/,
                              Pods, .terraform, and Next.js/Nuxt build
                              caches, found recursively under --path
                              (default: $HOME).

    scan   Lists everything found, with sizes, and exits. Nothing is
           touched.
    clean  Lists the same findings, then asks about each one
           interactively (y/n/a to accept all remaining/q to quit) unless
           --yes is passed. Every deletion goes through macOS's own
           Trash — recoverable until you empty it, never `rm`.

    --yes             Skip the interactive prompt; move every *safe* item
                       to Trash without asking. AI model weights
                       (Ollama/LM Studio) are never included by --yes
                       alone — see --include-review.
    --include-review  Also include non-"safe" findings (AI model weights)
                       in --yes mode. Ignored without --yes.
    --dry-run         Show exactly what --yes would delete, without
                       deleting anything.
    --json            Machine-readable output for `scan` (ignored by
                       `clean`).

    Full MacGroom app (free tier + Pro): https://gogenops.com/mac-apps/macgroom/
    Issues & feature requests: https://github.com/soodrajesh/macgroom-support
    """)
}

struct Options {
    var path: URL
    var json = false
    var yes = false
    var includeReview = false
    var dryRun = false
}

func parseOptions(_ args: [String]) -> Options {
    var opts = Options(path: FileManager.default.homeDirectoryForCurrentUser)
    var i = 0
    while i < args.count {
        switch args[i] {
        case "--path":
            i += 1
            guard i < args.count else { fail("--path needs a directory argument") }
            opts.path = URL(fileURLWithPath: args[i]).standardizedFileURL
        case "--json": opts.json = true
        case "--yes": opts.yes = true
        case "--include-review": opts.includeReview = true
        case "--dry-run": opts.dryRun = true
        default: fail("Unrecognized option: \(args[i])")
        }
        i += 1
    }
    return opts
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("macgroom: \(message)\n".data(using: .utf8)!)
    exit(1)
}

func collectFindings(path: URL) -> [Finding] {
    var findings = DevToolCaches.find()
    findings += ProjectArtifacts.find(root: path)
    // Size everything up front, sequentially — `du` on a handful to a
    // few dozen paths is fast enough that the concurrency the GUI app
    // needs for a full disk-wide scan isn't worth the complexity here.
    for i in findings.indices {
        findings[i].sizeBytes = SizeCalculator.size(of: findings[i].url)
    }
    return findings.sorted { ($0.sizeBytes ?? 0) > ($1.sizeBytes ?? 0) }
}

func printTable(_ findings: [Finding]) {
    if findings.isEmpty {
        print("Nothing found.")
        return
    }
    for finding in findings {
        let flag = finding.safe ? "  " : "! "
        print("\(flag)\(finding.sizeDisplay.padding(toLength: 9, withPad: " ", startingAt: 0))  \(finding.label)")
        print("     \(finding.url.path)")
    }
    let total = findings.reduce(Int64(0)) { $0 + ($1.sizeBytes ?? 0) }
    print("")
    print("Total: \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file)) across \(findings.count) item\(findings.count == 1 ? "" : "s")")
    if findings.contains(where: { !$0.safe }) {
        print("! = review before removing (AI model weights — you may still be using it)")
    }
}

func printJSON(_ findings: [Finding]) {
    let items = findings.map { f -> [String: Any] in
        ["path": f.url.path, "label": f.label, "safe": f.safe, "sizeBytes": f.sizeBytes ?? NSNull()]
    }
    let data = try? JSONSerialization.data(withJSONObject: ["items": items], options: [.prettyPrinted, .sortedKeys])
    print(String(data: data ?? Data(), encoding: .utf8) ?? "{}")
}

/// Moves to Trash via `FileManager`, not `rm` — recoverable, matching the
/// GUI app's own safety model exactly.
func trash(_ finding: Finding) -> Bool {
    do {
        try FileManager.default.trashItem(at: finding.url, resultingItemURL: nil)
        return true
    } catch {
        FileHandle.standardError.write("  failed: \(error.localizedDescription)\n".data(using: .utf8)!)
        return false
    }
}

func runScan(_ opts: Options) {
    let findings = collectFindings(path: opts.path)
    if opts.json { printJSON(findings) } else { printTable(findings) }
}

func runClean(_ opts: Options) {
    let findings = collectFindings(path: opts.path)
    guard !findings.isEmpty else { print("Nothing found."); return }
    printTable(findings)
    print("")

    if opts.yes || opts.dryRun {
        let toDelete = findings.filter { $0.safe || opts.includeReview }
        if opts.dryRun {
            print("--dry-run: would move \(toDelete.count) item(s) to Trash:")
            for f in toDelete { print("  \(f.url.path)") }
            return
        }
        var freed: Int64 = 0
        for f in toDelete where trash(f) { freed += f.sizeBytes ?? 0 }
        print("Moved \(toDelete.count) item(s) to Trash — \(ByteCountFormatter.string(fromByteCount: freed, countStyle: .file)) freed.")
        return
    }

    print("Review each item — y = trash it, n = skip, a = trash this and all remaining, q = stop here.")
    var freed: Int64 = 0
    var trashedCount = 0
    var acceptRest = false
    for f in findings {
        if !acceptRest {
            print("\(f.sizeDisplay)  \(f.label)")
            print("  \(f.url.path)")
            print("  Trash this? [y/N/a/q] ", terminator: "")
            guard let line = readLine()?.lowercased() else { break }
            switch line {
            case "y": break
            case "a": acceptRest = true
            case "q": print("Stopped."); print("Moved \(trashedCount) item(s) to Trash — \(ByteCountFormatter.string(fromByteCount: freed, countStyle: .file)) freed."); return
            default: continue
            }
        }
        if trash(f) { freed += f.sizeBytes ?? 0; trashedCount += 1 }
    }
    print("")
    print("Moved \(trashedCount) item(s) to Trash — \(ByteCountFormatter.string(fromByteCount: freed, countStyle: .file)) freed.")
}

// MARK: - Entry point

let arguments = Array(CommandLine.arguments.dropFirst())

guard let command = arguments.first else {
    printHelp()
    exit(0)
}

switch command {
case "--help", "-h":
    printHelp()
case "--version", "-v":
    print("macgroom \(version)")
case "scan":
    runScan(parseOptions(Array(arguments.dropFirst())))
case "clean":
    runClean(parseOptions(Array(arguments.dropFirst())))
default:
    fail("Unknown command: \(command)\nRun `macgroom --help` for usage.")
}
