// swift-tools-version: 6.2
import PackageDescription

// Deployment targets are substituted from --ios-target/--macos-target (bootstrap.sh),
// same as the app's xcconfig — a package floor above the app's deployment target is a
// link failure, and this package IS linked into the app target.
//
// Strict concurrency needs no opt-in here: it is the default under Swift 6 tools mode.
//
// Warnings-as-errors is NOT declared in this manifest, deliberately. Xcode compiles a
// package dependency with `-suppress-warnings` (warnings in a dependency are assumed
// unactionable), and `.treatAllWarnings(as: .error)` here produces:
//
//     error: Conflicting options '-warnings-as-errors' and '-suppress-warnings'
//
// which fails the app build outright — for every configuration, so an archive breaks
// too. Setting SWIFT_SUPPRESS_WARNINGS = NO at the project level does not help: Xcode
// applies the flag to package targets directly, so the project value never reaches it.
//
// The rule instead lives on the SwiftPM path, where it is enforceable: scripts/test.sh
// passes `-Xswiftc -warnings-as-errors`, and CI runs that script. The consequence worth
// knowing: a warning in this package fails ./scripts/test.sh and CI, but is silently
// suppressed when Xcode builds it as part of the app.
let package = Package(
    name: "FolioCore",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0"),
    ],
    products: [
        .library(name: "FolioCore", targets: ["FolioCore"])
    ],
    targets: [
        .target(name: "FolioCore"),
        .testTarget(
            name: "FolioCoreTests",
            dependencies: ["FolioCore"]
        ),
    ]
)
