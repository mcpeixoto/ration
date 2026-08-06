// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ration",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Ration", targets: ["Ration"]),
        .library(name: "RationKit", targets: ["RationKit"]),
    ],
    targets: [
        // Pure logic. No SwiftUI, no AppKit. Fully unit-testable.
        .target(name: "RationKit"),

        // SwiftUI views and view models.
        .target(name: "RationUI", dependencies: ["RationKit"]),

        // Thin executable that wires the two together.
        .executableTarget(name: "Ration", dependencies: ["RationKit", "RationUI"]),

        // Development tool: renders the UI to PNGs for review and for the
        // README. Not shipped in the app bundle.
        .executableTarget(name: "RationPreview", dependencies: ["RationKit", "RationUI"]),

        .testTarget(
            name: "RationKitTests",
            dependencies: ["RationKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
