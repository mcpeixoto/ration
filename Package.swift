// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ration",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Ration", targets: ["Ration"]),
        .library(name: "RationKit", targets: ["RationKit"]),
    ],
    dependencies: [
        // Auto-update. Widely audited, and the EdDSA signature check on every
        // downloaded update is the part worth not writing ourselves.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        // Pure logic. No SwiftUI, no AppKit. Fully unit-testable.
        .target(
            name: "RationKit",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),

        // SwiftUI views and view models.
        .target(name: "RationUI", dependencies: ["RationKit"]),

        // Thin executable that wires the two together.
        .executableTarget(
            name: "Ration",
            dependencies: [
                "RationKit", "RationUI",
                .product(name: "Sparkle", package: "Sparkle"),
            ]
        ),

        // Development tool: renders the UI to PNGs for review and for the
        // README. Not shipped in the app bundle.
        .executableTarget(name: "RationPreview", dependencies: ["RationKit", "RationUI"]),

        .testTarget(
            name: "RationKitTests",
            dependencies: ["RationKit"],
            resources: [.copy("Fixtures")],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),

        .testTarget(
            name: "RationUITests",
            dependencies: ["RationUI"]
        ),
    ]
)
