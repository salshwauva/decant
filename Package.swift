// swift-tools-version:5.9
import PackageDescription

// decant: cozy launcher for windows-only steam games on apple silicon.
// monorepo: engine/ (wine 11 + dxmt scripts) + this swiftui front end.
// does not emulate; built with swiftpm against the command line tools sdk.
let package = Package(
    name: "decant",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "decant",
            path: "Sources/decant"
        )
    ]
)
