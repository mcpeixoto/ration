// swift-tools-version: 6.0
import PackageDescription

#if os(macOS)
let sparkleDependency: [Package.Dependency] = [
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
]
#else
let sparkleDependency: [Package.Dependency] = []
#endif

#if os(macOS)
let macOSProducts: [Product] = [
    .executable(name: "Ration", targets: ["Ration"]),
]
let macOSTargets: [Target] = [
    .target(name: "RationUI", dependencies: ["RationKit"]),
    .executableTarget(
        name: "Ration",
        dependencies: [
            "RationKit", "RationUI",
            .product(name: "Sparkle", package: "Sparkle"),
        ]
    ),
    .executableTarget(name: "RationPreview", dependencies: ["RationKit", "RationUI"]),
    .testTarget(name: "RationUITests", dependencies: ["RationUI"]),
]
#else
let macOSProducts: [Product] = []
let macOSTargets: [Target] = []
#endif

#if os(Linux)
// The tray is the Linux counterpart of the macOS menu bar extra: the same
// gauge and the same panel, drawn with Cairo and published through
// libayatana-appindicator3 instead of SwiftUI's MenuBarExtra.
let linuxProducts: [Product] = [
    .executable(name: "ration-tray", targets: ["RationTray"])
]
let linuxTargets: [Target] = [
    .systemLibrary(
        name: "CLinuxTray",
        path: "Sources/CLinuxTray",
        providers: [
            .apt(["libgtk-3-dev", "libayatana-appindicator3-dev"])
        ]
    ),
    .executableTarget(
        name: "RationTray",
        dependencies: ["RationKit", "CLinuxTray"],
        linkerSettings: [
            .linkedLibrary("m")
        ]
    ),
]
#else
let linuxProducts: [Product] = []
let linuxTargets: [Target] = []
#endif

let package = Package(
    name: "Ration",
    platforms: [.macOS(.v14)],
    products: macOSProducts + linuxProducts + [
        .executable(name: "ration", targets: ["RationCLI"]),
        .library(name: "RationKit", targets: ["RationKit"]),
    ],
    dependencies: sparkleDependency,
    targets: [
        .systemLibrary(
            name: "CSqlite3",
            path: "Sources/CSqlite3",
            providers: [
                .apt(["libsqlite3-dev"]),
                .brew(["sqlite"]),
            ]
        ),
        .target(
            name: "RationKit",
            dependencies: ["CSqlite3"],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedLibrary("FoundationNetworking", .when(platforms: [.linux])),
            ]
        ),
        .executableTarget(
            name: "RationCLI",
            dependencies: ["RationKit"]
        ),
        .testTarget(
            name: "RationKitTests",
            dependencies: ["RationKit", "CSqlite3"],
            resources: [.copy("Fixtures")],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedLibrary("FoundationNetworking", .when(platforms: [.linux])),
            ]
        ),
    ] + macOSTargets + linuxTargets
)
