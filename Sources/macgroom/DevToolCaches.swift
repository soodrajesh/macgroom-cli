import Foundation

/// Known global cache/model locations — the free "Dev Tool Caches" +
/// AI-model-cache categories from the MacGroom GUI app, reimplemented here
/// independently. Each is only reported if it actually exists.
enum DevToolCaches {
    static func find() -> [Finding] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var findings: [Finding] = []

        func add(_ relativePath: String, label: String, safe: Bool) {
            let url = home.appendingPathComponent(relativePath)
            guard fm.fileExists(atPath: url.path) else { return }
            findings.append(Finding(url: url, label: label, safe: safe, sizeBytes: nil))
        }

        add("Library/Developer/Xcode/DerivedData", label: "Xcode DerivedData", safe: true)
        add("Library/Developer/CoreSimulator/Caches", label: "Simulator Caches", safe: true)
        add(".npm", label: "npm Cache", safe: true)
        add("Library/Caches/Yarn", label: "Yarn Cache", safe: true)
        add("Library/pnpm/store", label: "pnpm Store", safe: true)
        add("Library/Caches/pip", label: "pip Cache", safe: true)
        add("Library/Caches/pypoetry", label: "Poetry Cache", safe: true)
        add(".cargo/registry", label: "Cargo Registry Cache", safe: true)
        add(".cache", label: "~/.cache (XDG, includes Hugging Face's model cache)", safe: true)

        // Local AI model weights — re-downloadable, but the user may still
        // be using a given model, so `safe: false`: never swept into a
        // plain `--yes` clean without `--include-review`.
        add(".ollama/models", label: "Ollama Models", safe: false)
        add(".lmstudio/models", label: "LM Studio Models", safe: false)

        return findings
    }
}
