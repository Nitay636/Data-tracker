// swift-tools-version: 5.10
import PackageDescription

// Platform-independent logic shared by the app, the packet tunnel extension and the widget.
// Everything here is unit-tested with `swift test` (macOS).
let package = Package(
    name: "DataTrackerCore",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "DataTrackerCore", targets: ["DataTrackerCore"])
    ],
    targets: [
        .target(
            name: "DataTrackerCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "DataTrackerCoreTests",
            dependencies: ["DataTrackerCore"]
        )
    ],
    swiftLanguageVersions: [.v5]
)
