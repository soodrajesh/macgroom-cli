// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "macgroom",
    platforms: [.macOS(.v13)],
    targets: [
        // No dependencies — same "pure Swift, zero third-party
        // dependencies" stance as the rest of the MacGroom suite. SwiftPM
        // itself (rather than a raw `swiftc` build) is used here, not in
        // the GUI apps, because it's the expected packaging for a public
        // CLI tool distributed via Homebrew (`brew install --build-from-
        // source` runs `swift build`) — no Xcode project either way.
        .executableTarget(name: "macgroom", path: "Sources/macgroom")
    ]
)
