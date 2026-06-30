// swift-tools-version:5.9
import PackageDescription

// hearth: a cozy launcher for windows-only steam games on apple silicon.
// it drives an existing wine + game porting toolkit stack, it does not
// emulate anything itself. built with swiftpm so it compiles against the
// command line tools sdk without needing a full xcode project.
let package = Package(
    name: "hearth",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "hearth",
            path: "Sources/hearth"
        )
    ]
)
