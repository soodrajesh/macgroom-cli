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

        // ~/.cache is safe:true by default (it's regenerable XDG junk) —
        // *unless* Hugging Face's model cache lives inside it, in which
        // case the whole directory is promoted to safe:false too. Marking
        // only the huggingface subfolder unsafe wouldn't actually protect
        // it: FileManager.trashItem operates on whole paths, so a plain
        // `--yes` sweep of the safe:true parent would trash the "review-
        // required" child right along with it. Same treatment as Ollama/
        // LM Studio otherwise — the point of --include-review is that you
        // have to mean it.
        let cacheURL = home.appendingPathComponent(".cache")
        let hfURL = cacheURL.appendingPathComponent("huggingface")
        let hasHuggingFace = fm.fileExists(atPath: hfURL.path)
        add(
            ".cache",
            label: hasHuggingFace
                ? "~/.cache (includes Hugging Face model weights — review before removing one you still use)"
                : "~/.cache (XDG cache directory)",
            safe: !hasHuggingFace
        )

        // Local AI model weights — re-downloadable, but the user may still
        // be using a given model, so `safe: false`: never swept into a
        // plain `--yes` clean without `--include-review`. Same treatment
        // for all three tools that keep their own separate copy of the
        // same checkpoint.
        add(".ollama/models", label: "Ollama Models", safe: false)
        add(".lmstudio/models", label: "LM Studio Models", safe: false)

        return findings
    }
}
